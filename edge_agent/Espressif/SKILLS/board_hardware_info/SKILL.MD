---
{
  "name": "board_hardware_info",
  "description": "Use this skill before operating hardware or writing Lua and board-specific code that depends on device inventory and occupied GPIOs.",
  "metadata": {
    "cap_groups": ["cap_boards"],
    "manage_mode": "readonly"
  }
}
---

# Current Board Hardware: esp32_p4_function_ev

Read this skill before operating hardware, assigning GPIOs, or writing Lua and board-specific code. **You cannot speculate or fabricate hardware information.**

## Rules
- Before operating any hardware, read this skill first.
- Before assigning a GPIO, check whether it is already occupied below.
- When writing Lua or board-specific code, use the listed device names instead of guessing hardware wiring.

## Board Summary
- Board: `esp32_p4_function_ev`
- Chip: `esp32p4`
- Version: `1`
- Manufacturer: `unknown`

## Device Inventory

The following devices are known to be present on this board:

### audio_dac
- Occupied IO:
  - `pin` -> `GPIO53`
  - `mclk` -> `GPIO13`
  - `bclk` -> `GPIO12`
  - `ws` -> `GPIO10`
  - `dout` -> `GPIO9`
  - `din` -> `GPIO11`
  - `sda` -> `GPIO7`
  - `scl` -> `GPIO8`

### audio_adc
- Occupied IO:
  - `mclk` -> `GPIO13`
  - `bclk` -> `GPIO12`
  - `ws` -> `GPIO10`
  - `dout` -> `GPIO9`
  - `din` -> `GPIO11`
  - `sda` -> `GPIO7`
  - `scl` -> `GPIO8`

### fs_sdcard
- Occupied IO:
  - `clk` -> `GPIO0`

### camera
- Occupied IO:
  - `sda` -> `GPIO7`
  - `scl` -> `GPIO8`

## Notes
- If a device has no explicit IO mapping here, treat it as unknown instead of guessing.
