-- --------------------------------------------------------------
-- schedule_manager: list all stored schedules to stdout.
-- LLM reads the script output and summarizes it for the user.
-- --------------------------------------------------------------

local storage = require("storage")
local json = require("json")

local SCHEDULES_DIR = "schedules"
local SCHEDULES_FILE = "schedules.json"

local function run()
    local root = storage.get_root_dir()
    local file = storage.join_path(root, SCHEDULES_DIR, SCHEDULES_FILE)
    if not storage.exists(file) then
        print("[schedule_manager] no schedules yet (file not found: " .. file .. ")")
        return
    end

    local ok, data = pcall(function() return json.decode(storage.read_file(file)) end)
    if not ok or type(data) ~= "table" or type(data.schedules) ~= "table" then
        print("[schedule_manager] no valid schedules (empty or corrupt)")
        return
    end

    local list = data.schedules
    if #list == 0 then
        print("[schedule_manager] no schedules")
        return
    end

    print(string.format("[schedule_manager] %d schedule(s):", #list))
    for i, s in ipairs(list) do
        local wd = ""
        if s.recurrence == "weekly" then
            wd = " weekday=" .. tostring(s.weekday)
        end
        print(string.format(
            "[%d] %s %s %s (ascii=%s) recurrence=%s%s enabled=%s id=%s",
            i,
            s.date or "?",
            s.time or "??:??",
            s.title or "",
            s.title_ascii or "",
            s.recurrence or "once",
            wd,
            tostring(s.enabled ~= false),
            s.id or ""
        ))
    end
end

local ok, err = xpcall(run, debug.traceback)
if not ok then
    print("[schedule_manager] ERROR: " .. tostring(err))
    error(err)
end
