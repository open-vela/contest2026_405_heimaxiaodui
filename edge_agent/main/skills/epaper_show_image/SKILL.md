---
{
  "name": "epaper_show_image",
  "description": "Display a JPEG image on the 3.5-inch 4-color e-paper display (184x384, black/white/yellow/red).",
  "metadata": {
    "cap_groups": [
      "cap_lua"
    ],
    "manage_mode": "readonly"
  }
}
---

# Show Image on E-Paper

Use this skill when the user asks to display a picture, photo, logo, or
diagram on the e-paper screen (把图片/照片/图示显示到墨水屏/屏幕上).

The device decodes a JPEG, resizes it to the 184x384 panel, quantizes it to
the panel's 4 colors (black/white/yellow/red), and does a full refresh.
Refresh is slow (seconds), so it is for static images, not video.

## When to use

- The image is already a JPEG file on the device (e.g. under `/fatfs/images/`)
  → run `show_image.lua` with that `path`.
- The user provides an image URL → first download it with `http_request`
  (use `save_path`, e.g. `/ramfs/img.jpg`), then run `show_image.lua` with
  that path. Note the URL's domain must be in the `http_request` allowlist.

Run exactly one bundled script per turn with `lua_run_script`. If it returns
an error, report that error directly to the user; do not retry with changed
arguments in the same turn unless the user explicitly asks.

## Limitations

- **JPEG only** — `image.load_file` rejects any other format (no PNG/GIF/BMP).
- **Slow refresh** — a full e-paper update takes seconds.
- **4 colors only** — continuous-tone photos lose detail; enable `dither` to
  soften banding, or leave it off for crisp text/icon content.

## Script Args Schema

```json
{
  "type": "object",
  "properties": {
    "path": {
      "type": "string",
      "description": "Absolute path to a JPEG file on the device, e.g. /fatfs/images/logo.jpg or /ramfs/img.jpg."
    },
    "dither": {
      "type": "boolean",
      "description": "Enable Floyd-Steinberg dithering. true for photos, false (default) for text/line art."
    }
  },
  "required": ["path"]
}
```

## Tool Call Inputs

Show a pre-staged JPEG (no dithering):

```json
{"path":"{CUR_SKILL_DIR}/scripts/show_image.lua","args":{"path":"/fatfs/images/logo.jpg"},"timeout_ms":60000}
```

Show a downloaded photo (with dithering):

```json
{"path":"{CUR_SKILL_DIR}/scripts/show_image.lua","args":{"path":"/ramfs/img.jpg","dither":true},"timeout_ms":60000}
```

## Recommended Flow

1. Determine where the image comes from:
   - a JPEG already on the device → use its `path` directly;
   - a URL → call `http_request` with `{"url": "...", "save_path": "/ramfs/img.jpg"}`
     to download it first, then use `/ramfs/img.jpg`.
2. Choose `dither`: `true` for photos, omit/false for text and line art.
3. Tell the user briefly what you are about to show.
4. Run `show_image.lua` with `lua_run_script`.
5. Report the result or error directly to the user.
