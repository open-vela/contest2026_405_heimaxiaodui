-- --------------------------------------------------------------
-- Show text (or a solid color) on the 3.5" 4-color e-paper panel.
-- --------------------------------------------------------------

local arg_schema = require("arg_schema")
local epaper = require("epaper")

local DEFAULT_TEXT = ""
local DEFAULT_SIZE = 24
local DEFAULT_COLOR = 0   -- black
local DEFAULT_BG = 1      -- white
local DEFAULT_X = 0
local DEFAULT_Y = 0

local function raw_arg(name, default)
  if type(args) == "table" and args[name] ~= nil then
    return args[name]
  end
  return default
end

local ARG_SCHEMA = {
  size = arg_schema.int({ default = DEFAULT_SIZE }),
  color = arg_schema.int({ default = DEFAULT_COLOR }),
  x = arg_schema.int({ default = DEFAULT_X }),
  y = arg_schema.int({ default = DEFAULT_Y }),
  background = arg_schema.int({ default = DEFAULT_BG }),
}

local ctx = arg_schema.parse(args, ARG_SCHEMA)
ctx.text = raw_arg("text", DEFAULT_TEXT)

local function check_range(name, value, lo, hi)
  if value < lo or value > hi then
    error(string.format("%s must be in [%d, %d], got %d", name, lo, hi, value))
  end
end

local function run()
  if type(ctx.text) ~= "string" then
    error("text must be a string")
  end
  check_range("size", ctx.size, 8, 24)
  check_range("color", ctx.color, 0, 3)
  check_range("background", ctx.background, 0, 3)
  check_range("x", ctx.x, 0, epaper.width() - 1)
  check_range("y", ctx.y, 0, epaper.height() - 1)

  epaper.init()
  epaper.clear(ctx.background)
  if ctx.text ~= "" then
    epaper.text(ctx.text, ctx.x, ctx.y, ctx.size, ctx.color)
  end
  epaper.display()
  epaper.sleep()

  print(string.format(
    "[epaper_show_text] shown: text=%q size=%d color=%d x=%d y=%d background=%d (184x384)",
    ctx.text, ctx.size, ctx.color, ctx.x, ctx.y, ctx.background
  ))
end

local ok, err = xpcall(run, debug.traceback)
if not ok then
  print("[epaper_show_text] ERROR: " .. tostring(err))
  error(err)
end
