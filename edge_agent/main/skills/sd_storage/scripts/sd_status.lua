-- --------------------------------------------------------------
-- Report SD card status: storage root, capacity, and saved file counts.
-- --------------------------------------------------------------

local storage = require("storage")

-- app_fs.c falls back to this fixed path when no SD card is mounted.
local FLASH_STORAGE_PATH = "/fatfs"

local function fmt_mb(bytes)
    return string.format("%.0f", bytes / (1024 * 1024))
end

-- photo/ and rec/ are dedicated dirs written only by this skill, so a plain
-- entry count is a faithful file count (no subdirectories).
local function count_entries(dir)
    local ok, entries = pcall(storage.listdir, dir)
    if not ok then
        return 0
    end
    return #(entries or {})
end

local root = storage.get_root_dir()
local is_sd = (root ~= FLASH_STORAGE_PATH)

local total_mb, used_mb, free_mb = "?", "?", "?"
local space_ok, space = pcall(storage.get_free_space)
if space_ok and space then
    local total = space.total or 0
    local free = space.free or 0
    total_mb = fmt_mb(total)
    free_mb = fmt_mb(free)
    used_mb = fmt_mb(total - free)
end

local photos = count_entries(storage.join_path(root, "photo"))
local recs = count_entries(storage.join_path(root, "rec"))

print(string.format(
    "[sd_status] root=%s is_sd=%s total=%sMB used=%sMB free=%sMB photos=%d recs=%d",
    root, tostring(is_sd), total_mb, used_mb, free_mb, photos, recs
))
