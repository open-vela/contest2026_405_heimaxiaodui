---
{
  "name": "schedule_manager",
  "description": "Manage a user's schedule: add one-off or recurring schedules, store them as JSON on device, show today's schedule on the e-paper, list/remove schedules, and auto-trigger a reminder 5 minutes before the schedule and again at the scheduled moment, via the conversation channel (feishu/wechat/qq/telegram) and speaker.",
  "metadata": {
    "cap_groups": [
      "cap_lua",
      "cap_scheduler",
      "cap_router_mgr"
    ],
    "manage_mode": "readonly"
  }
}
---

# Schedule Manager

Use this skill when the user asks to add, view, list, or remove a schedule
(日程/提醒/安排/待办时间/定时), or wants today's and upcoming schedules shown on
the e-paper display, or asks the device to remember to remind them at a specific
time.

The device stores schedules as JSON on the writable storage partition and, for
each schedule, creates an on-device scheduler entry (via `scheduler_add`) that
fires at the scheduled moment and wakes the agent.

## When to use

- **Add** a schedule (one-off at a date/time, daily, or weekly) → `add_schedule.lua`
- **Show** today's and upcoming schedules on the e-paper → `show_schedule.lua`
- **List** all schedules → `list_schedules.lua`
- **Remove** a schedule → `remove_schedule.lua`

Run exactly one bundled script per turn with `lua_run_script`. If the script
returns an error, report that error directly to the user; do not retry with
changed arguments in the same turn unless the user explicitly asks.

## Auto-trigger flow (important)

Each schedule creates two on-device scheduler entries: a 5-minute-before warning
(`日程预警：…`) and an on-time reminder (`日程提醒：…`). Both wake you (the agent)
with a message. When you receive one:

1. Call `get_current_time` to obtain the current time.
2. Activate the `announce_time` skill and run its script with the current
   `hour` and `minute` so the speaker announces the time.
3. Reply to the user via the current conversation channel (feishu/wechat/qq/...):
   `您有日程提醒：{title}`. Do NOT hardcode a channel — your reply auto-routes
   back to the source channel (the channel the schedule was added from).
4. For the on-time (`日程提醒：`) message, run `show_schedule.lua` (this skill) to
   refresh the e-paper with today's schedule. Skip this step for the 5-minute
   warning (`日程预警：`) to avoid extra e-paper refreshes.
5. Reply with a short text summary.

## Script 1: add_schedule.lua

Adds one or more schedules, stores them as JSON, and creates the matching
scheduler entries so the device auto-triggers at the right time. After saving,
it also re-renders the e-paper 待办 screen cache (via `show_schedule.lua`), so
the 3rd screen reflects the new schedule without an extra step.

### Script Args Schema

```json
{
  "type": "object",
  "properties": {
    "schedules": {
      "type": "array",
      "description": "One or more schedule objects.",
      "items": {
        "type": "object",
        "properties": {
          "date": {"type": "string", "description": "Start date, YYYY-MM-DD."},
          "time": {"type": "string", "description": "Trigger time, HH:MM (24h)."},
          "title": {"type": "string", "description": "Schedule title in Chinese (for Feishu message)."},
          "title_ascii": {"type": "string", "description": "ASCII/pinyin label for e-paper (no Chinese font). Keep it <= 30 chars; longer labels auto-wrap to up to 3 lines and are truncated with an ellipsis."},
          "description": {"type": "string", "description": "Optional detail."},
          "recurrence": {"type": "string", "enum": ["once", "daily", "weekly"], "description": "Default once."},
          "weekday": {"type": "integer", "description": "For weekly: 0-6, 0=Sunday."}
        },
        "required": ["time", "title"]
      }
    },
    "chat_channel": {"type": "string", "description": "IM channel, e.g. feishu or wechat. From current conversation context. For wechat: requires personal-WeChat QR login on the device web config page (iLink bot bridge) and an explicit chat_id."},
    "chat_id": {"type": "string", "description": "Target chat id. From current conversation context."}
  },
  "required": ["schedules", "chat_channel", "chat_id"]
}
```

### Tool Call Inputs

Add a one-off schedule "早会" at 08:30 on 2026-09-16:

```json
{"path":"{CUR_SKILL_DIR}/scripts/add_schedule.lua","args":{"schedules":[{"date":"2026-09-16","time":"08:30","title":"早会","title_ascii":"Morning Meeting","recurrence":"once"}],"chat_channel":"feishu","chat_id":"ou_xxx"},"timeout_ms":60000}
```

Add a daily reminder "喝水" at 10:00:

```json
{"path":"{CUR_SKILL_DIR}/scripts/add_schedule.lua","args":{"schedules":[{"time":"10:00","title":"喝水","title_ascii":"Drink Water","recurrence":"daily"}],"chat_channel":"feishu","chat_id":"ou_xxx"},"timeout_ms":60000}
```

## Script 2: show_schedule.lua

Renders **today's plus the next 3 days'** schedules into the e-paper's schedule
cache (it does **not** immediately take over the screen); the BOOT-key switcher
shows the cached frame when the user switches to the 待办 screen (page 3). ASCII
only. Takes no arguments: it always renders the current date's schedules plus any
one-off (`once`) schedules falling within the next 3 days, grouped by date. Daily
and weekly schedules are shown under today's heading. Past items (today's time
already passed) are drawn entirely in red; upcoming items are drawn in black.

### Script Args Schema

```json
{ "type": "object", "properties": {} }
```

### Tool Call Inputs

```json
{"path":"{CUR_SKILL_DIR}/scripts/show_schedule.lua","args":{},"timeout_ms":60000}
```

## Script 3: list_schedules.lua

Prints all stored schedules (one per line) to stdout. Read the script output and
summarize it for the user. Takes no arguments.

### Tool Call Inputs

```json
{"path":"{CUR_SKILL_DIR}/scripts/list_schedules.lua","args":{},"timeout_ms":60000}
```

## Script 4: remove_schedule.lua

Removes a schedule by id (also removes its scheduler entry). After removal, it
re-renders the e-paper 待办 screen cache (via `show_schedule.lua`) so the 3rd
screen reflects the deletion.

### Script Args Schema

```json
{
  "type": "object",
  "properties": {
    "schedule_id": {"type": "string", "description": "The schedule id to remove."}
  },
  "required": ["schedule_id"]
}
```

### Tool Call Inputs

```json
{"path":"{CUR_SKILL_DIR}/scripts/remove_schedule.lua","args":{"schedule_id":"sched_20260916_0830"},"timeout_ms":60000}
```

## Recommended Flow

1. Determine the user's intent: add / show / list / remove.
2. For add: parse each schedule's date, time, title, and recurrence; produce an
   ASCII label for the e-paper (`title_ascii`). Resolve `chat_channel` and
   `chat_id` from the current conversation context.
3. Tell the user what you are going to schedule in concise terms.
4. Run exactly one bundled script with `lua_run_script`.
5. Report the result or error directly to the user.
