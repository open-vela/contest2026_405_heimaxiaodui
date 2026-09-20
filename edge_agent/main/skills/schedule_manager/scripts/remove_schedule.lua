-- --------------------------------------------------------------
-- schedule_manager: remove a schedule by id.
-- Deletes the JSON entry and its matching on-device scheduler entry.
-- --------------------------------------------------------------

local capability = require("capability")
local storage = require("storage")
local json = require("json")

local SCHEDULES_DIR = "schedules"
local SCHEDULES_FILE = "schedules.json"

local raw_args = type(args) == "table" and args or {}

local function require_string(name)
    local v = raw_args[name]
    if type(v) ~= "string" or v == "" then
        error("args." .. name .. " is required")
    end
    return v
end

local function run()
    local schedule_id = require_string("schedule_id")

    local root = storage.get_root_dir()
    local dir = storage.join_path(root, SCHEDULES_DIR)
    local file = storage.join_path(dir, SCHEDULES_FILE)

    if not storage.exists(file) then
        error("no schedules file: " .. file)
    end

    local ok, data = pcall(function() return json.decode(storage.read_file(file)) end)
    if not ok or type(data) ~= "table" or type(data.schedules) ~= "table" then
        error("schedules file is corrupt")
    end

    local list = data.schedules
    local found = false
    local reminder_id = nil
    local new_list = {}
    for _, s in ipairs(list) do
        if s.id == schedule_id then
            found = true
            reminder_id = s.reminder_id
        else
            table.insert(new_list, s)
        end
    end

    if not found then
        error("schedule not found: " .. schedule_id)
    end

    -- 删除调度器条目（best-effort：once 条目触发后可能已被调度器消费，但 id 仍在）
    local rem_ok, rem_out, rem_err = capability.call("scheduler_remove", {
        id = schedule_id,
    }, {
        source_cap = "schedule_manager",
        max_output_bytes = 8192,
    })

    -- 删除提前5分钟预警条目（best-effort，不阻断正式删除流程）
    local rem2_ok = true
    local rem2_out = "no reminder entry"
    local rem2_err = ""
    if type(reminder_id) == "string" and reminder_id ~= "" then
        rem2_ok, rem2_out, rem2_err = capability.call("scheduler_remove", {
            id = reminder_id,
        }, {
            source_cap = "schedule_manager",
            max_output_bytes = 8192,
        })
    end

    -- 无论调度器删除成功与否，都从 JSON 中移除并写回
    storage.write_file(file, json.encode({ schedules = new_list }))

    if rem_ok then
        print(string.format("[schedule_manager] removed id=%s (scheduler + json), remaining=%d",
                            schedule_id, #new_list))
    else
        print(string.format("[schedule_manager] removed id=%s from json (remaining=%d); scheduler_remove failed: err=%s out=%s",
                            schedule_id, #new_list, tostring(rem_err), tostring(rem_out)))
    end

    if type(reminder_id) == "string" and reminder_id ~= "" then
        if rem2_ok then
            print(string.format("[schedule_manager] removed reminder id=%s", reminder_id))
        else
            print(string.format("[schedule_manager] reminder id=%s scheduler_remove failed: err=%s out=%s",
                                reminder_id, tostring(rem2_err), tostring(rem2_out)))
        end
    end

    -- 刷新墨水屏「待办」屏缓存：复用 show_schedule.lua 的绘制（pcall 兜底，失败不影响主流程）
    local refresh_ok, refresh_err = pcall(function() require("show_schedule") end)
    if not refresh_ok then
        print("[schedule_manager] WARNING: refresh e-paper cache failed: " .. tostring(refresh_err))
    end
end

local ok, err = xpcall(run, debug.traceback)
if not ok then
    print("[schedule_manager] ERROR: " .. tostring(err))
    error(err)
end
