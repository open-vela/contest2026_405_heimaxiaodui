---
{
  "name": "epaper_show_text",
  "description": "Display text (or a simple colored screen) on the 3.5-inch 4-color e-paper display.",
  "metadata": {
    "cap_groups": [
      "cap_lua"
    ],
    "manage_mode": "readonly"
  }
}
---

# Show Text on E-Paper

Use this skill when the user asks to show a message, text, note, or a solid
color on the e-paper (e-ink) display. The panel is 184×384 with 4 colors
(black / white / yellow / red) and refreshes slowly, so it is best for static
information left on screen.

Run exactly one script with `lua_run_script`.

If `lua_run_script` returns an error, report that error directly to the user.
Do not retry with changed arguments in the same turn unless the user explicitly asks.

## Script Args Schema

```json
{
  "type": "object",
  "properties": {
    "text": {
      "type": "string",
      "description": "The text to show. ASCII only. Use \\n for line breaks."
    },
    "size": {
      "type": "integer",
      "enum": [8, 16, 24],
      "default": 24,
      "description": "Font size in pixels. 24 is the largest and most readable."
    },
    "color": {
      "type": "integer",
      "enum": [0, 1, 2, 3],
      "default": 0,
      "description": "Text color: 0 black, 1 white, 2 yellow, 3 red."
    },
    "x": {
      "type": "integer",
      "default": 0,
      "description": "X offset of the first character in pixels (0..183)."
    },
    "y": {
      "type": "integer",
      "default": 0,
      "description": "Y offset of the first character in pixels (0..383)."
    },
    "background": {
      "type": "integer",
      "enum": [0, 1, 2, 3],
      "default": 1,
      "description": "Background fill color: 0 black, 1 white, 2 yellow, 3 red."
    }
  }
}
```

## Tool Call Inputs

Show "Hello AI" on a white background:

```json
{"path":"{CUR_SKILL_DIR}/scripts/show_text.lua","args":{"text":"Hello AI"}}
```

Show a multi-line note in red:

```json
{"path":"{CUR_SKILL_DIR}/scripts/show_text.lua","args":{"text":"Room: Lab\\nStatus: OK","color":3,"size":16}}
```

## Recommended Flow

1. Compose the full screen into `args` (text, size, color, x, y, background).
2. Run `{CUR_SKILL_DIR}/scripts/show_text.lua` with those args.
3. Report the outcome. Note that a full refresh can take tens of seconds.
