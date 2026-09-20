# Lua EPAPER

Lua binding for the Waveshare 3.5" 4-color e-paper display (184×384), driven
via bit-bang SPI (no dedicated SPI peripheral).

## Pins

| Signal | GPIO |
|--------|------|
| SCK    | 21   |
| MOSI   | 22   |
| CS     | 33   |
| DC     | 32   |
| RST    | 5    |
| BUSY   | 20   |

These are the pins already validated by the `vela-esp32` project on the same
ESP32-P4 Function EV board. On ESP32-P4 the flash/PSRAM use dedicated internal
MSPI buses, so GPIO22~54 are free for ordinary GPIO use.

## How to call

```lua
local epaper = require("epaper")
epaper.init()               -- GPIO + panel init (idempotent)
epaper.clear(color)         -- fill the frame buffer with color (no refresh yet)
epaper.text("Hello", 0, 0, 24, 0)  -- draw text into the frame buffer
epaper.display()            -- flush the frame buffer to the panel (slow refresh)
epaper.sleep()              -- put the panel into deep sleep
```

Colors: `0` black, `1` white, `2` yellow, `3` red. Font sizes: `8`, `16`, `24`
(ASCII only). `text()` clips anything outside the 184×384 panel; `\n` moves to
the next line.

The panel is slow: a full refresh takes tens of seconds. Prefer composing the
whole screen into the buffer (clear + text) and flushing once with `display()`.
