-- --------------------------------------------------------------
-- epaper_show_image: display a JPEG image on the 3.5" 4-color e-paper.
-- Pipeline: JPEG (load) -> resize 184x384 -> 4-color quantize (C, in
-- epaper.draw_image) -> full refresh. Optional Floyd-Steinberg dithering.
-- --------------------------------------------------------------

local image = require("image")
local epaper = require("epaper")

local EPAPER_WIDTH = 184
local EPAPER_HEIGHT = 384

local args_t = type(args) == "table" and args or {}

local function run()
    local path = args_t.path
    if type(path) ~= "string" or path == "" then
        error("args.path is required (JPEG file path)")
    end
    local dither = args_t.dither == true

    -- JPEG only: image.load_file rejects any other suffix.
    local frame = image.load_file(path)
    -- Resize to the panel; default output is RGB565 ("RGBP"), which is the
    -- format epaper.draw_image decodes internally.
    local fitted = image.resize(frame, { width = EPAPER_WIDTH, height = EPAPER_HEIGHT })

    epaper.init()
    epaper.draw_image(fitted, dither)  -- writes the 4-color frame buffer
    epaper.display()                   -- flush to panel (~seconds)
    epaper.sleep()

    fitted:release()
    frame:release()

    print(string.format("[epaper_show_image] shown %s (dither=%s)", path, tostring(dither)))
end

local ok, err = xpcall(run, debug.traceback)
if not ok then
    print("[epaper_show_image] ERROR: " .. tostring(err))
    error(err)
end
