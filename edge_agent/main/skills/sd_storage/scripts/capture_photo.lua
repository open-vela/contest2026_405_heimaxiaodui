-- --------------------------------------------------------------
-- Capture one JPEG still and save it to SD card storage.
-- Path: <root>/photo/P_<timestamp>.jpg  (or P<NNNNN>.jpg when clock not synced)
-- --------------------------------------------------------------

local arg_schema    = require("arg_schema")
local board_manager = require("board_manager")
local camera        = require("camera")
local image         = require("image")
local storage       = require("storage")

local DEFAULT_TIMEOUT_MS = 3000
local DEFAULT_SKIP_FRAMES = 3
local DEFAULT_DIR = "photo"
local DEFAULT_PREFIX = "P"

-- 2025-01-01 00:00:00 UTC; earlier timestamps mean the clock is not synced.
local MIN_VALID_EPOCH = 1735689600

-- app_fs.c falls back to this fixed path when no SD card is mounted.
local FLASH_STORAGE_PATH = "/fatfs"

-- arg_schema has no string type; take string args manually.
local function raw_arg(name, default)
    if type(args) == "table" and type(args[name]) == "string" and args[name] ~= "" then
        return args[name]
    end
    return default
end

local ARG_SCHEMA = {
    timeout_ms  = arg_schema.int({ default = DEFAULT_TIMEOUT_MS, min = 0 }),
    skip_frames = arg_schema.int({ default = DEFAULT_SKIP_FRAMES, min = 0 }),
}

local ctx = arg_schema.parse(args, ARG_SCHEMA)
ctx.dir = raw_arg("dir", DEFAULT_DIR)
ctx.prefix = raw_arg("prefix", DEFAULT_PREFIX)

-- Generate a non-colliding path under <root>/<dir>.
-- Clock synced  -> <prefix>_<YYYYmmdd_HHMMSS>.<ext>
-- Clock not set -> <prefix><NNNNN>.<ext> (max index in dir + 1)
local function gen_storage_path(dir, prefix, ext)
    local root = storage.get_root_dir()
    local dir_path = storage.join_path(root, dir)
    if not storage.exists(dir_path) then
        storage.mkdir(dir_path)
    end

    local function scan_max_index()
        local max = 0
        local ok, entries = pcall(storage.listdir, dir_path)
        if not ok then
            return max
        end
        for _, e in ipairs(entries or {}) do
            local n = string.match(e.name or "", "^" .. prefix .. "(%d+)%." .. ext .. "$")
            if n then
                local v = tonumber(n)
                if v and v > max then
                    max = v
                end
            end
        end
        return max
    end

    if os.time() >= MIN_VALID_EPOCH then
        local name = prefix .. "_" .. os.date("%Y%m%d_%H%M%S") .. "." .. ext
        local path = storage.join_path(dir_path, name)
        if not storage.exists(path) then
            return path
        end
        -- Same-second collision: fall through to indexed name.
    end

    local name = prefix .. string.format("%05d", scan_max_index() + 1) .. "." .. ext
    return storage.join_path(dir_path, name)
end

local camera_opened = false

local function cleanup()
    if camera_opened then
        local ok, err = pcall(camera.close)
        if not ok then
            print("[capture_photo] WARN: camera.close failed: " .. tostring(err))
        end
        camera_opened = false
    end
end

local function run()
    if storage.get_root_dir() == FLASH_STORAGE_PATH then
        error("no SD card mounted (storage root is flash fallback); insert a FAT32 SD card")
    end

    local camera_paths, path_err = board_manager.get_camera_paths()
    if not camera_paths then
        error("get_camera_paths failed: " .. tostring(path_err))
    end

    local save_path = gen_storage_path(ctx.dir, ctx.prefix, "jpg")

    local opened, open_err = pcall(camera.open, camera_paths.dev_path)
    if not opened then
        error(tostring(open_err))
    end
    camera_opened = true

    local info_ok, info_or_err = pcall(camera.info)
    if not info_ok then
        error(tostring(info_or_err))
    end

    print(string.format(
        "[capture_photo] camera stream: %dx%d format=%s",
        info_or_err.width, info_or_err.height, tostring(info_or_err.pixel_format)
    ))

    camera.flush()

    -- Skip the first few frames after opening/flushing because some sensors
    -- produce overexposed warm-up frames.
    for i = 1, ctx.skip_frames do
        local warmup_frame <close> = camera.get_frame(ctx.timeout_ms)
        local warmup_info = warmup_frame:info()
        print(string.format(
            "[capture_photo] skipped warm-up frame %d/%d: %dx%d format=%s",
            i, ctx.skip_frames, warmup_info.width, warmup_info.height,
            tostring(warmup_info.pixel_format)
        ))
    end

    local frame <close> = camera.get_frame(ctx.timeout_ms)
    local frame_info = frame:info()
    -- .jpg suffix makes save_file auto-encode to JPEG.
    image.save_file(save_path, frame)

    local saved_info, stat_err = storage.stat(save_path)
    if not saved_info then
        error("storage.stat failed after save: " .. tostring(stat_err))
    end

    print(string.format(
        "[capture_photo] saved: path=%s bytes=%d frame=%dx%d format=%s",
        save_path, saved_info.size, frame_info.width, frame_info.height,
        tostring(frame_info.pixel_format)
    ))
end

local ok, err = xpcall(run, debug.traceback)
cleanup()
if not ok then
    print("[capture_photo] ERROR: " .. tostring(err))
    error(err)
end
