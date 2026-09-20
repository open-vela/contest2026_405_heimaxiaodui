---
{
  "name": "announce_morning",
  "description": "Morning briefing: announce today's to-do count through the speaker, complementing the detail message sent via Feishu.",
  "metadata": {
    "cap_groups": [
      "cap_lua"
    ],
    "manage_mode": "readonly"
  }
}
---

# Morning Briefing Through Speaker

Use this skill as the LAST step of the morning briefing flow, after the to-do
detail message has been sent to the user via Feishu. The speaker plays:
"早上好，您今天有 X 个代办，已通过飞书发送给您，可以打开飞书进一步查看".

Trigger phrases: 晨间播报 / 早安播报 / 播报今天的待办数量.

Typical flow (usually driven by a scheduled task at 08:00):
1. Recall to-do items for today from long-term memory (`memory_list` /
   `memory_recall`), e.g. memories labelled or describing 待办/代办/计划.
2. Send the to-do detail list to the user via Feishu
   (`feishu_send_message` with the user's chat_id from context).
3. Run this skill with the to-do count.
4. Reply with a short text summary.

If there are no to-do items today, still run this skill with count 0.

Run exactly one script with `lua_run_script`.

If `lua_run_script` returns an error, report that error directly to the user.
Do not retry with changed arguments in the same turn unless the user explicitly asks.

## Script Args Schema

```json
{
  "type": "object",
  "properties": {
    "count": {
      "type": "integer",
      "minimum": 0,
      "maximum": 99,
      "description": "Number of to-do items for today."
    },
    "skill_dir": {
      "type": "string",
      "description": "Skill directory path. Pass exactly the value shown in the example below."
    }
  },
  "required": ["count"]
}
```

## Tool Call Inputs

Announce 3 to-dos:

```json
{"path":"{CUR_SKILL_DIR}/scripts/announce_morning.lua","args":{"count":3,"skill_dir":"{CUR_SKILL_DIR}"}}
```

## Recommended Flow

1. Collect today's to-do count (from memory recall, as described above).
2. Send the detail message via Feishu first.
3. Run `{CUR_SKILL_DIR}/scripts/announce_morning.lua` with `count` and `skill_dir`.
4. Playback takes about 8 seconds; the clips announce the count exactly once.
