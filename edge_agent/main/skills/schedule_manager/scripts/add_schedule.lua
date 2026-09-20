-- --------------------------------------------------------------
-- schedule_manager: add one or more schedules.
-- Stores schedules as JSON on the writable storage partition and creates
-- matching on-device scheduler entries (wake_agent mode) so the device
-- auto-triggers a time announcement at the scheduled moment.
-- --------------------------------------------------------------

local capability = require("capability")
local storage = require("storage")
local json = require("json")

local SCHEDULES_DIR = "schedules"
local SCHEDULES_FILE = "schedules.json"

local raw_args = type(args) == "table" and args or {}

local function raw_arg(name)
    if type(args) == "table" and args[name] ~= nil then
        return args[name]
    end
    return nil
end

local function require_string(name)
    local v = raw_arg(name)
    if type(v) ~= "string" or v == "" then
        error("args." .. name .. " is required")
    end
    return v
end

-- 从日程对象取字符串字段（带错误提示）
local function item_string(item, key, label)
    local v = item[key]
    if type(v) ~= "string" or v == "" then
        error(label .. " is required")
    end
    return v
end

-- 解析 YYYY-MM-DD
local function parse_date(s)
    local y, m, d = s:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
    if not y then
        error("invalid date: " .. tostring(s) .. " (expected YYYY-MM-DD)")
    end
    return tonumber(y), tonumber(m), tonumber(d)
end

-- 解析 HH:MM
local function parse_time(s)
    local h, m = s:match("^(%d?%d):(%d%d)$")
    if not h then
        error("invalid time: " .. tostring(s) .. " (expected HH:MM)")
    end
    h = tonumber(h)
    m = tonumber(m)
    if h < 0 or h > 23 or m < 0 or m > 59 then
        error("invalid time: " .. tostring(s) .. " (hour 0-23, minute 0-59)")
    end
    return h, m
end

-- 加载现有日程（不存在则返回空表）
local function load_schedules()
    local root = storage.get_root_dir()
    local dir = storage.join_path(root, SCHEDULES_DIR)
    local file = storage.join_path(dir, SCHEDULES_FILE)
    if not storage.exists(file) then
        return {}, dir, file
    end
    local ok, data = pcall(function() return json.decode(storage.read_file(file)) end)
    if not ok or type(data) ~= "table" or type(data.schedules) ~= "table" then
        return {}, dir, file
    end
    return data.schedules, dir, file
end

-- 保存日程文件
local function save_schedules(list, dir, file)
    if not storage.exists(dir) then
        storage.mkdir(dir)
    end
    storage.write_file(file, json.encode({ schedules = list }))
end

-- 生成唯一 id（同日期同时刻冲突时加 _2/_3 后缀）
local function gen_unique_id(list, y, m, d, h, min)
    local base = string.format("sched_%04d%02d%02d_%02d%02d", y, m, d, h, min)
    local id = base
    local suffix = 1
    local function exists(candidate)
        for _, s in ipairs(list) do
            if s.id == candidate then
                return true
            end
        end
        return false
    end
    while exists(id) do
        suffix = suffix + 1
        id = base .. "_" .. suffix
    end
    return id
end

-- 构建 wake_agent 调度器条目
local function build_scheduler_entry(id, kind, start_at_ms, cron_expr,
                                     chat_channel, chat_id, text, max_runs)
    return {
        id = id,
        enabled = true,
        kind = kind,
        start_at_ms = start_at_ms or 0,
        end_at_ms = 0,
        interval_ms = 0,
        cron_expr = cron_expr or "",
        event_type = "message",
        event_key = "text",
        source_channel = chat_channel,
        chat_id = chat_id,
        content_type = "text",
        session_policy = "chat",
        text = text,
        payload_json = "{}",
        max_runs = max_runs or 0,
    }
end

-- 调用 scheduler_add，失败抛错
local function scheduler_add(entry)
    local ok, out, err = capability.call("scheduler_add", {
        schedule_json = json.encode(entry),
    }, {
        source_cap = "schedule_manager",
        max_output_bytes = 8192,
    })
    if not ok then
        error("scheduler_add failed: err=" .. tostring(err) .. " out=" .. tostring(out))
    end
    return out
end

local function run()
    local raw_schedules = raw_arg("schedules")
    if type(raw_schedules) ~= "table" or #raw_schedules == 0 then
        error("args.schedules must be a non-empty array")
    end
    local chat_channel = require_string("chat_channel")
    local chat_id = require_string("chat_id")

    local list, dir, file = load_schedules()

    local added = 0
    for i, item in ipairs(raw_schedules) do
        if type(item) ~= "table" then
            error("schedules[" .. i .. "] must be an object")
        end

        local recurrence = item.recurrence or "once"
        local title = item_string(item, "title", "schedules[" .. i .. "].title")
        local title_ascii = item.title_ascii or title
        local description = item.description or ""

        -- 墨水屏标签最多显示 3 行 × 10 字符，超长标签会折行并截断加省略号。
        -- 这里只告警提示 LLM，不强制截断（保留完整内容，由显示层折行）。
        if #title_ascii > 30 then
            print("[schedule_manager] WARNING: title_ascii is " .. #title_ascii ..
                  " chars (>30); it will wrap to 3 lines and be truncated with '...' on e-paper")
        end

        local h, min = parse_time(item_string(item, "time", "schedules[" .. i .. "].time"))

        local y, m, d
        local kind
        local start_at_ms = 0
        local cron_expr = ""
        local max_runs
        local weekday = -1
        local date_str

        if recurrence == "once" then
            date_str = item_string(item, "date", "schedules[" .. i .. "].date")
            y, m, d = parse_date(date_str)
            kind = "once"
            -- 用 1000.0 强制浮点乘法：LUA_32BITS=1 下 os.time()*1000 会 32 位整数回绕成负数，
            -- 触发 scheduler_add 的 ESP_ERR_INVALID_ARG（start_at_ms<=0）。
            start_at_ms = os.time({ year = y, month = m, day = d, hour = h, min = min, sec = 0 }) * 1000.0
            if start_at_ms <= 0 then
                error("start_at_ms must be positive (got " .. tostring(start_at_ms) ..
                      "); os.time may be unset (NTP not synced?)")
            end
            max_runs = 1
        elseif recurrence == "daily" then
            -- 起始日期可选，缺省用今天
            date_str = item.date or os.date("%Y-%m-%d")
            y, m, d = parse_date(date_str)
            kind = "cron"
            cron_expr = string.format("%d %d * * *", min, h)
            max_runs = 0
        elseif recurrence == "weekly" then
            local wd = tonumber(item.weekday)
            if not wd or wd < 0 or wd > 6 then
                error("weekly schedule requires weekday 0-6 (0=Sunday)")
            end
            weekday = wd
            date_str = item.date or os.date("%Y-%m-%d")
            y, m, d = parse_date(date_str)
            kind = "cron"
            cron_expr = string.format("%d %d * * %d", min, h, wd)
            max_runs = 0
        else
            error("unsupported recurrence: " .. tostring(recurrence) .. " (once/daily/weekly)")
        end

        local id = gen_unique_id(list, y, m, d, h, min)
        local reminder_id = id .. "_remind"

        -- 提前 5 分钟的预警时间（借位处理跨小时/跨午夜）
        local reminder_kind
        local reminder_start_at_ms = 0
        local reminder_cron_expr = ""
        local skip_reminder = false

        if recurrence == "once" then
            reminder_kind = "once"
            reminder_start_at_ms = start_at_ms - 5 * 60 * 1000
            if reminder_start_at_ms <= os.time() * 1000.0 then
                skip_reminder = true
                print(string.format("[schedule_manager] reminder time already passed for id=%s, skipping reminder entry", id))
            end
        else
            reminder_kind = "cron"
            local rmin, rh
            if min >= 5 then
                rmin = min - 5
                rh = h
            else
                rmin = min + 55
                rh = (h - 1 + 24) % 24
            end
            if recurrence == "daily" then
                reminder_cron_expr = string.format("%d %d * * *", rmin, rh)
            else -- weekly
                local rwd = weekday
                if h == 0 and min < 5 then
                    rwd = (weekday - 1 + 7) % 7
                end
                reminder_cron_expr = string.format("%d %d * * %d", rmin, rh, rwd)
            end
        end

        local remind_text = string.format("日程提醒：%s。请播报当前时间，并回复日程详情。", title)
        local reminder_text = string.format("日程预警：%s 将在5分钟后开始。请播报当前时间，并简短回复提醒。", title)

        local entry = build_scheduler_entry(id, kind, start_at_ms, cron_expr,
                                            chat_channel, chat_id, remind_text, max_runs)
        scheduler_add(entry)

        if not skip_reminder then
            local reminder_entry = build_scheduler_entry(reminder_id, reminder_kind, reminder_start_at_ms,
                                                         reminder_cron_expr, chat_channel, chat_id, reminder_text, max_runs)
            scheduler_add(reminder_entry)
        end

        table.insert(list, {
            id = id,
            reminder_id = (not skip_reminder) and reminder_id or nil,
            date = date_str,
            time = string.format("%02d:%02d", h, min),
            hour = h,
            minute = min,
            title = title,
            title_ascii = title_ascii,
            description = description,
            recurrence = recurrence,
            weekday = weekday,
            enabled = true,
        })

        added = added + 1
        print(string.format("[schedule_manager] added id=%s %s %s recurrence=%s kind=%s",
                            id, date_str, string.format("%02d:%02d", h, min), recurrence, kind))
    end

    save_schedules(list, dir, file)
    print(string.format("[schedule_manager] saved %d schedule(s), total=%d", added, #list))

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
