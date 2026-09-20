-- --------------------------------------------------------------
-- schedule_manager: show today's schedule on the 3.5" 4-color e-paper.
-- 184x384, ASCII only (no Chinese font). Draws time + ASCII/pinyin label.
-- --------------------------------------------------------------

local storage = require("storage")
local json = require("json")
local epaper = require("epaper")

local SCHEDULES_DIR = "schedules"
local SCHEDULES_FILE = "schedules.json"

local raw_args = type(args) == "table" and args or {}

-- 面板与字体常量
local COLOR_BLACK = 0
local COLOR_WHITE = 1
local FONT_TITLE = 24   -- 17px/char
local FONT_BODY = 16    -- 11px/char
local LINE_GAP = 20
local MAX_LABEL_CHARS = 10   -- "HH:MM " 占 6 字符，剩 10 字符给标签

local function raw_arg(name)
    if type(args) == "table" and args[name] ~= nil then
        return args[name]
    end
    return nil
end

-- 读取日程列表
local function load_schedules()
    local root = storage.get_root_dir()
    local file = storage.join_path(root, SCHEDULES_DIR, SCHEDULES_FILE)
    if not storage.exists(file) then
        return {}
    end
    local ok, data = pcall(function() return json.decode(storage.read_file(file)) end)
    if not ok or type(data) ~= "table" or type(data.schedules) ~= "table" then
        return {}
    end
    return data.schedules
end

-- 判断某条日程今天是否显示
-- once: date 匹配；daily: 总是显示；weekly: 今天星期 == weekday
local function is_today(item, date_str, today_wday)
    if item.enabled == false then
        return false
    end
    local rec = item.recurrence or "once"
    if rec == "once" then
        return item.date == date_str
    elseif rec == "daily" then
        return true
    elseif rec == "weekly" then
        return tonumber(item.weekday) == today_wday
    end
    return false
end

-- ASCII 标签安全化：非 ASCII 字符替换为 '?'，截断到 max 长度
local function sanitize_ascii(s, max)
    s = s or ""
    s = s:gsub("[^%w%p%s]", "?")  -- 保留字母数字/标点/空白，其余替换为 ?
    if #s > max then
        s = s:sub(1, max)
    end
    return s
end

local function run()
    local date_str = raw_arg("date")
    local now_tbl = os.date("*t")
    if type(date_str) ~= "string" or date_str == "" then
        date_str = os.date("%Y-%m-%d")
    end
    -- os.date wday: 1=Sunday .. 7=Saturday；weekly weekday 字段 0-6 (0=Sunday)
    local today_wday = (now_tbl and now_tbl.wday and now_tbl.wday - 1) or -1

    local list = load_schedules()

    -- 过滤今日日程
    local todays = {}
    for _, item in ipairs(list) do
        if is_today(item, date_str, today_wday) then
            table.insert(todays, item)
        end
    end

    -- 按 time 排序
    table.sort(todays, function(a, b)
        return (a.time or "99:99") < (b.time or "99:99")
    end)

    -- 绘制
    epaper.init()
    epaper.clear(COLOR_WHITE)

    epaper.text("TODAY", 0, 0, FONT_TITLE, COLOR_BLACK)
    epaper.text(date_str, 0, 30, FONT_BODY, COLOR_BLACK)
    epaper.text("----------------", 0, 52, FONT_BODY, COLOR_BLACK)

    local y = 72
    if #todays == 0 then
        epaper.text("No schedules", 0, y, FONT_BODY, COLOR_BLACK)
    else
        for _, item in ipairs(todays) do
            if y >= epaper.height() - FONT_BODY then
                break  -- 超出面板
            end
            local line = (item.time or "??:??") .. " " .. sanitize_ascii(item.title_ascii, MAX_LABEL_CHARS)
            epaper.text(line, 0, y, FONT_BODY, COLOR_BLACK)
            y = y + LINE_GAP
        end
    end

    epaper.display()
    epaper.sleep()

    print(string.format("[schedule_manager] shown %d schedule(s) for %s on e-paper", #todays, date_str))
end

local ok, err = xpcall(run, debug.traceback)
if not ok then
    print("[schedule_manager] ERROR: " .. tostring(err))
    error(err)
end
