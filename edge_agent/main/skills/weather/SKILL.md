---
{
  "name": "weather",
  "description": "Show today's weather and this week's calendar on the e-paper. Use when the user asks for weather/forecast (天气/天气预报), or when the hourly weather-refresh timer fires a message asking to refresh the weather screen.",
  "metadata": {
    "cap_groups": [
      "cap_lua",
      "cap_web_search"
    ],
    "manage_mode": "readonly"
  }
}
---

# Weather

Use this skill to refresh the e-paper's weather-and-calendar screen with
**real** weather data. The screen is generated in the background and stored to
the epaper module's weather cache (it does **not** immediately take over the
screen); the user sees it when they press BOOT to switch to the weather screen.

## When to use

- The user asks for the weather / forecast (天气 / 天气预报 / 今天天气).
- You receive a scheduled message that begins with `定时刷新天气屏：` (the hourly
  weather-refresh timer) — refresh the cache and reply briefly.

## Required flow (must follow, in order)

1. **Fetch real weather via `web_search`.** Call the `web_search` tool to query
   the current weather, e.g. query `今天 <城市> 天气`. Determine the city:
   - **Scheduled refresh** (message begins with `定时刷新天气屏：`): the city
     name is embedded in that text (the device's configured default city). Parse
     it from the text and search that city — do **not** guess a different city.
   - **User-initiated query:** parse the city from the user's message (e.g.
     "北京今天天气" → Beijing). If the message names no city, fall back to the
     city embedded in the scheduled-refresh text.
   **Never invent weather data.** If `web_search` is unavailable (no API key,
   offline, or no usable results), reply `天气暂不可用` and stop — do not draw,
   do not fabricate.
2. **Parse** from the search results: condition (sunny/cloudy/rain/snow…),
   temperature, temperature range (high/low), and wind (optional).
3. **Draw + cache (mandatory — do not skip).** Run `show_weather.lua` with
   `lua_run_script`, passing the parsed values in `args`. For a scheduled refresh
   (`定时刷新天气屏：`), running this script is **required to complete the task**:
   if you fetched weather but did not run the script, the screen stays on the
   "天气待配置" placeholder and the refresh has failed. Run it before replying;
   if a previous refresh did not complete, retry it this round.
4. **Reply** to the user with a one-line summary of what was refreshed.

Run exactly one bundled script per turn. If the script returns an error, report
that error directly; do not retry with changed arguments in the same turn unless
the user explicitly asks.

## Script: show_weather.lua

Draws today's date, weekday, city, condition, temperature and this week's
calendar onto the 184x384 e-paper, then stores the frame into the weather cache
via `epaper.save_weather_cache()`. It does **not** call `display()` — the BOOT
key switcher shows the cached frame when the user switches to the weather screen.

The e-paper module only has ASCII fonts (Font8/16/24, no Chinese), so all
text on this screen must be English or pinyin (e.g. `Sunny`, `Beijing`, `28C`).

### Script Args Schema

```json
{
  "type": "object",
  "properties": {
    "city": {"type": "string", "description": "City name, ASCII/pinyin, e.g. Beijing."},
    "cond": {"type": "string", "description": "Condition, ASCII, e.g. Sunny / Cloudy / Rain."},
    "temp": {"type": "string", "description": "Current temperature, e.g. 28C."},
    "range": {"type": "string", "description": "High/low range, e.g. 22~31C."},
    "wind": {"type": "string", "description": "Wind, ASCII, e.g. SW 3-4."}
  },
  "required": ["cond", "temp"]
}
```

### Tool Call Inputs

```json
{"path":"{CUR_SKILL_DIR}/scripts/show_weather.lua","args":{"city":"Beijing","cond":"Sunny","temp":"28C","range":"22~31C","wind":"SW 3"},"timeout_ms":60000}
```

## Notes

- All strings you pass in `args` must be ASCII. Convert any Chinese to pinyin or
  English, and any non-ASCII characters to a safe equivalent.
- The cached frame is only valid until the next reboot (RAM). On a fresh boot the
  static placeholder is shown until the first refresh completes.
- Keep `temp` short (e.g. `28C`) so it fits the large-font temperature line.
