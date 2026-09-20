---
{
  "name": "sd_storage",
  "description": "Save camera stills and audio recordings to the SD card, and query SD card capacity/status. Use when the user asks to take a photo/picture (拍照/拍张照/照相), record audio (录音/录一段), or check SD card / storage space (SD卡还剩多少/存储空间/卡容量).",
  "metadata": {
    "cap_groups": [
      "cap_lua"
    ],
    "manage_mode": "readonly"
  }
}
---

# SD Card Storage

Use this skill when the user asks the device to take a photo / picture, record
audio, or check SD card / storage space.

The SD card is mounted automatically at boot by the board manager; the app's
writable storage root follows the SD card. Photos land under
`<root>/photo/P_*.jpg`, recordings under `<root>/rec/R_*.wav`. When the device
clock is not synced yet, files use a sequential number instead of a timestamp
(`P00001.jpg`), so they never overwrite each other.

## When to use

- **Take a photo** → `capture_photo.lua`
- **Record audio** → `record_audio.lua`
- **Query SD card status / capacity** → `sd_status.lua`

Run exactly one bundled script per turn with `lua_run_script`. If the script
returns an error, report that error directly to the user; do not retry with
changed arguments in the same turn unless the user explicitly asks.

## Script 1: capture_photo.lua

Captures one JPEG still from the camera and saves it to
`<root>/photo/P_<timestamp>.jpg` (or `P<NNNNN>.jpg` when the clock is not
synced). It skips the first few warm-up frames because some sensors produce
overexposed frames right after opening. If no SD card is mounted (storage root
is the flash fallback), it errors out immediately and writes nothing.

### Script Args Schema

```json
{
  "type": "object",
  "properties": {
    "timeout_ms": {"type": "integer", "description": "Frame capture timeout, default 3000."},
    "skip_frames": {"type": "integer", "description": "Warm-up frames to skip, default 3."},
    "dir": {"type": "string", "description": "Subdirectory under the storage root, default photo."},
    "prefix": {"type": "string", "description": "Filename prefix, default P. Use letters only."}
  }
}
```

### Tool Call Inputs

```json
{"path":"{CUR_SKILL_DIR}/scripts/capture_photo.lua","args":{},"timeout_ms":30000}
```

## Script 2: record_audio.lua

Records WAV audio from the microphone and saves it to
`<root>/rec/R_<timestamp>.wav` (or `R<NNNNN>.wav` when the clock is not synced).
Recording blocks for the requested duration. If no SD card is mounted (storage
root is the flash fallback), it errors out immediately and writes nothing.

### Script Args Schema

```json
{
  "type": "object",
  "properties": {
    "duration_ms": {"type": "integer", "minimum": 1000, "maximum": 60000, "description": "Recording duration in milliseconds, default 3000."},
    "volume": {"type": "integer", "minimum": 0, "maximum": 100, "description": "Input capture volume percentage, default 70."},
    "dir": {"type": "string", "description": "Subdirectory under the storage root, default rec."},
    "prefix": {"type": "string", "description": "Filename prefix, default R. Use letters only."}
  }
}
```

### Tool Call Inputs

Record 5 seconds:

```json
{"path":"{CUR_SKILL_DIR}/scripts/record_audio.lua","args":{"duration_ms":5000},"timeout_ms":70000}
```

## Script 3: sd_status.lua

Prints the storage root path, whether it is the SD card (vs the flash fallback),
total/used/free capacity in MB, and the number of saved photos and recordings.
Takes no arguments.

### Tool Call Inputs

```json
{"path":"{CUR_SKILL_DIR}/scripts/sd_status.lua","args":{},"timeout_ms":10000}
```

## Recommended Flow

1. Determine the user's intent: photo / recording / status.
2. Tell the user what you are going to do in concise terms.
3. Run exactly one bundled script with `lua_run_script`.
4. Read the script output and report the result (saved path, bytes, capacity) to
   the user.
