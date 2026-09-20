---
{
  "name": "announce_time",
  "description": "Announce the given time through the device speaker using pre-recorded Chinese voice clips.",
  "metadata": {
    "cap_groups": [
      "cap_lua"
    ],
    "manage_mode": "readonly"
  }
}
---

# Announce Time Through Speaker

Use this skill when the user asks the device to announce, speak, or broadcast
the time out loud (报时 / 播报时间 / 语音报时 / 用喇叭报时). The speaker plays
short Chinese voice clips: "现在是北京时间" + hour + "点" + minute + "分".

**This skill needs the time as input.** Always call the `get_current_time`
capability FIRST, parse hour and minute (24-hour format) from its output, then
run this script. Also state the time in your text reply so the user gets both
voice and text.

If `get_current_time` reports an invalid clock, tell the user the device clock
is not synced yet and skip this skill.

Run exactly one script with `lua_run_script`.

If `lua_run_script` returns an error, report that error directly to the user.
Do not retry with changed arguments in the same turn unless the user explicitly asks.

## Script Args Schema

```json
{
  "type": "object",
  "properties": {
    "hour": {
      "type": "integer",
      "minimum": 0,
      "maximum": 23,
      "description": "Hour to announce, 24-hour format (14 means 下午两点)."
    },
    "minute": {
      "type": "integer",
      "minimum": 0,
      "maximum": 59,
      "description": "Minute to announce. 0 is announced as 整."
    },
    "skill_dir": {
      "type": "string",
      "description": "Skill directory path. Pass exactly the value shown in the example below."
    }
  },
  "required": ["hour", "minute"]
}
```

## Tool Call Inputs

Announce 14:30 (现在是北京时间 十四点三十分):

```json
{"path":"{CUR_SKILL_DIR}/scripts/announce_time.lua","args":{"hour":14,"minute":30,"skill_dir":"{CUR_SKILL_DIR}"}}
```

## Recommended Flow

1. Call `get_current_time` and parse hour and minute in 24-hour format.
2. Run `{CUR_SKILL_DIR}/scripts/announce_time.lua` with `hour`, `minute` and `skill_dir`.
3. Reply with the time in text. Playback takes about 3-5 seconds; the clips
   announce the time exactly once.
