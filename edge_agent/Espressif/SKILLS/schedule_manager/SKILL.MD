---
{
  "name": "schedule_manager",
  "description": "Manage a user's schedule: add one-off or recurring schedules, store them as JSON on device, show today's schedule on the e-paper, list/remove schedules, and auto-trigger a time announcement at the scheduled moment.",
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
(日程/提醒/安排/待办时间/定时), or wants today's schedule shown on the e-paper
display, or asks the device to remember to remind them at a specific time.

The device stores schedules as JSON on the writable storage partition and, for
each schedule, creates an on-device scheduler entry (via `scheduler_add`) that
fires at the scheduled moment and wakes the agent.

## When to use

- **Add** a schedule (one-off at a date/time, daily, or weekly) → `add_schedule.lua`
- **Show** today's schedule on the e-paper → `show_schedule.lua`
- **List** all schedules → `list_schedules.lua`
- **Remove** a schedule → `remove_schedule.lua`

Run exactly one bundled script per turn with `lua_run_script`. If the script
returns an error, report that error directly to the user; do not retry with
changed arguments in the same turn unless the user explicitly asks.

## Auto-trigger flow (important)

When a schedule fires, the on-device scheduler wakes you (the agent) with a
message that begins with `日程提醒：`. When you receive such a message:

1. Call `get_current_time` to obtain the current time.
2. Activate the `announce_time` skill and run its script with the current
   `hour` and `minute` so the speaker announces the time.
3. Send a Feishu message to the user: `您有日程提醒：{title}`.
4. Run `show_schedule.lua` (this skill) to refresh the e-paper with today's schedule.
5. Reply with a short text summary.

## Script 1: add_schedule.lua

Adds one or more schedules, stores them as JSON, and creates the matching
scheduler entries so the device auto-triggers at the right time.

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
          "title_ascii": {"type": "string", "description": "ASCII/pinyin label for e-paper (no Chinese font)."},
          "description": {"type": "string", "description": "Optional detail."},
          "recurrence": {"type": "string", "enum": ["once", "daily", "weekly"], "description": "Default once."},
          "weekday": {"type": "integer", "description": "For weekly: 0-6, 0=Sunday."}
        },
        "required": ["time", "title"]
      }
    },
    "chat_channel": {"type": "string", "description": "IM channel, e.g. feishu. From current conversation context."},
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

Draws today's schedule on the 184x384 e-paper. ASCII only.

### Script Args Schema

```json
{
  "type": "object",
  "properties": {
    "date": {"type": "string", "description": "Target date YYYY-MM-DD. Optional; defaults to today."}
  }
}
```

### Tool Call Inputs

```json
{"path":"{CUR_SKILL_DIR}/scripts/show_schedule.lua","args":{"date":"2026-09-16"},"timeout_ms":60000}
```

## Script 3: list_schedules.lua

Prints all stored schedules (one per line) to stdout. Read the script output and
summarize it for the user. Takes no arguments.

### Tool Call Inputs

```json
{"path":"{CUR_SKILL_DIR}/scripts/list_schedules.lua","args":{},"timeout_ms":60000}
```

## Script 4: remove_schedule.lua

Removes a schedule by id (also removes its scheduler entry).

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
