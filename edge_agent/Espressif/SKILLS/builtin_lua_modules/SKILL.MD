---
{
  "name": "builtin_lua_modules",
  "description": "Built-in Lua module documentation.",
  "metadata": {
    "cap_groups": [
      "cap_lua"
    ],
    "manage_mode": "readonly"
  }
}
---

# Builtin Lua Modules

To read documentation for a module, call `read_file("{CUR_SKILL_DIR}/scripts/docs/<Doc file path>")`.
To read a module test script, call `read_file("{CUR_SKILL_DIR}/scripts/builtin/test/<Test script path>")`.
Read all the files you need in one go as much as possible.
Do not fabricate functions that are not documented.

| Module | Doc file path | Test script path |
| --- | --- | --- |
| `lua_driver_adc` | `lua_driver_adc.md` | `adc_read.lua` |
| `lua_driver_gpio` | `lua_driver_gpio.md` | `gpio_basic.lua` |
| `lua_driver_i2c` | `lua_driver_i2c.md` | `i2c_scan_rw.lua`<br>`si12t_touch_read.lua`<br>`ssd1306_test.lua` |
| `lua_driver_mcpwm` | `lua_driver_mcpwm.md` | `mcpwm_12ch.lua`<br>`mcpwm_api_coverage.lua`<br>`servo_sweep.lua` |
| `lua_driver_pcnt` | `lua_driver_pcnt.md` | `pcnt_count.lua`<br>`rotary_encoder.lua` |
| `lua_driver_rmt` | `lua_driver_rmt.md` | `ir_driver_learn_replay.lua`<br>`rmt_loopback.lua` |
| `lua_driver_touch` | `lua_driver_touch.md` | `touch_read.lua` |
| `lua_driver_uart` | `lua_driver_uart.md` | `uart_at.lua` |
| `lua_module_audio` | `lua_module_audio.md` | `audio_analyzer.lua`<br>`audio_device_tone.lua`<br>`audio_play_file.lua`<br>`audio_play_https.lua`<br>`audio_record_play_aac.lua` |
| `lua_module_board_manager` | `lua_module_board_manager.md` | - |
| `lua_module_button` | `lua_module_button.md` | `button_events.lua` |
| `lua_module_call_capability` | `lua_module_call_capability.md` | `call_im_send.lua`<br>`call_web_search.lua` |
| `lua_module_camera` | `lua_module_camera.md` | `camera_capabilities.lua`<br>`camera_capture.lua` |
| `lua_module_delay` | `lua_module_delay.md` | - |
| `lua_module_epaper` | `lua_module_epaper.md` | - |
| `lua_module_event_publisher` | `lua_module_event_publisher.md` | `llm_analyze_trigger.lua` |
| `lua_module_http_server` | `lua_module_http_server.md` | `http_server_panel.lua` |
| `lua_module_image` | `lua_module_image.md` | `image_convert_cache.lua`<br>`image_file_convert.lua`<br>`image_resize.lua` |
| `lua_module_json` | `lua_module_json.md` | `json_roundtrip.lua` |
| `lua_module_led_strip` | `lua_module_led_strip.md` | `led_strip_rainbow.lua` |
| `lua_module_ledc` | `lua_module_ledc.md` | - |
| `lua_module_storage` | `lua_module_storage.md` | - |
| `lua_module_system` | `lua_module_system.md` | `system_info.lua` |
| `lua_module_thread` | `lua_module_thread.md` | `thread_child_a.lua`<br>`thread_child_b.lua`<br>`thread_parent.lua` |
| `lua_module_vision` | `lua_module_vision.md` | `camera_display_color.lua`<br>`camera_display_motion.lua`<br>`espdet_camera.lua`<br>`espdet_image.lua`<br>`motion_detect.lua` |
