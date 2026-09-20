-- --------------------------------------------------------------
-- Record WAV audio from the microphone and save it to SD card storage.
-- Path: <root>/rec/R_<timestamp>.wav  (or R<NNNNN>.wav when clock not synced)
-- --------------------------------------------------------------

local arg_schema    = require("arg_schema")
local audio         = require("audio")
local board_manager = require("board_manager")
local storage       = require("storage")

local DEFAULT_DURATION_MS = 3000
local DEFAULT_VOLUME = 70
local DEFAULT_DIR = "rec"
local DEFAULT_PREFIX = "R"

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
    duration_ms = arg_schema.int({ default = DEFAULT_DURATION_MS, min = 1000, max = 60000 }),
    volume      = arg_schema.int({ default = DEFAULT_VOLUME, min = 0, max = 100 }),
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

local input = nil
local recorder = nil

local function cleanup()
    if recorder then
        pcall(function() recorder:close() end)
        recorder = nil
    end
    if input then
        pcall(function() input:close() end)
        input = nil
    end
end

local function run()
    if storage.get_root_dir() == FLASH_STORAGE_PATH then
        error("no SD card mounted (storage root is flash fallback); insert a FAT32 SD card")
    end

    local codec, rate, channels, bits = board_manager.get_audio_codec_input_params("audio_adc")
    if not codec then
        error("get_audio_codec_input_params(audio_adc) failed: " .. tostring(rate))
    end

    local path = gen_storage_path(ctx.dir, ctx.prefix, "wav")

    input = assert(audio.new_input({ codec, rate, channels, bits, volume = ctx.volume }))
    recorder = assert(audio.recorder({ input = input }))

    local info = input:info()
    print(string.format(
        "[record_audio] input=%dHz/%dch/%dbit -> %s (%d ms)",
        info.sample_rate, info.channels, info.bits, path, ctx.duration_ms
    ))

    -- .wav suffix makes record() write PCM with a WAV header.
    local rec_info = recorder:record(path, { duration_ms = ctx.duration_ms })

    print(string.format(
        "[record_audio] saved: path=%s bytes=%d duration=%d ms format=%s",
        rec_info.path, rec_info.bytes, rec_info.duration_ms, tostring(rec_info.format)
    ))
end

local ok, err = xpcall(run, debug.traceback)
cleanup()
if not ok then
    print("[record_audio] ERROR: " .. tostring(err))
    error(err)
end
