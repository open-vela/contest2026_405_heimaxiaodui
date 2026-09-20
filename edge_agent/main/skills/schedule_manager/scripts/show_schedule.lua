-- --------------------------------------------------------------
-- schedule_manager: show TODAY + next 3 days' schedules on the 3.5" 4-color
-- e-paper. 184x384, ASCII only (no Chinese font). Draws time + ASCII/pinyin
-- label into the schedule cache (NO display); the BOOT-key switcher shows it on
-- the 待办 screen (index 2) when the user switches there.
-- Renders the current date's schedules plus any one-off (once) schedules falling
-- within the next 3 days, grouped by date.
--
-- Layout (black / white / yellow / red):
--   yellow top bar "TODAY" + short date; full date + weekday; full-width rule;
--   per-item color marker block; past items (time < now) drawn red, upcoming
--   items black; future dates grouped under a yellow band; Font8 footer with
--   today/upcoming counts.
-- --------------------------------------------------------------

local storage = require("storage")
local json = require("json")
local epaper = require("epaper")

local SCHEDULES_DIR = "schedules"
local SCHEDULES_FILE = "schedules.json"

-- 面板与字体常量
local COLOR_BLACK = 0
local COLOR_WHITE = 1
local COLOR_YELLOW = 2
local COLOR_RED = 3
local FONT_TITLE = 24   -- 17px/char
local FONT_BODY = 16    -- 11px/char
local FONT_SMALL = 8    -- 5px/char（页脚）
local LINE_GAP = 20
local LABEL_WIDTH_CHARS = 10   -- 标签可用宽度：整行 184/11≈16 字符，减 "HH:MM "(6) = 10
local MAX_LINES_PER_ITEM = 3   -- 单条日程最多 3 行，防超长标签挤掉其他条目
local CONTINUE_INDENT = "      "  -- 6 空格，续行对齐标签起始列（x=76px）

local W = 184                     -- 面板宽度
local ADVANCE = { [8] = 5, [16] = 11, [24] = 17 }  -- 等宽字体单字宽
local WEEKDAY3 = { "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" }

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

-- 判断某条日程是否在「今天 + 未来 3 天」窗口内显示
-- once: date 在 [今天, 今天+3天] 区间；daily: 总是显示；weekly: 今天星期 == weekday
local function is_visible(item, today_str, today_wday, max_date_str)
    if item.enabled == false then
        return false
    end
    local rec = item.recurrence or "once"
    if rec == "once" then
        local d = item.date or ""
        return d >= today_str and d <= max_date_str
    elseif rec == "daily" then
        return true
    elseif rec == "weekly" then
        return tonumber(item.weekday) == today_wday
    end
    return false
end

-- 每条日程归属的显示日期（用于分组与排序）：
-- once 用其自身 date，daily/weekly 归入「今天」组。
local function bucket_date(item, today_str)
    local rec = item.recurrence or "once"
    if rec == "once" then
        return item.date or today_str
    end
    return today_str
end

-- 把 YYYY-MM-DD 折成 ASCII 短日期（如 "Sep 18"），供未来日期分组小标题使用
local MONTH_NAMES = { "Jan", "Feb", "Mar", "Apr", "May", "Jun",
                      "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" }
local function short_date(date_str)
    local y, m, d = date_str:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
    if not y then
        return date_str
    end
    return (MONTH_NAMES[tonumber(m)] or m) .. " " .. tonumber(d)
end

-- 计算 date_str 之后 n 天的日期串（YYYY-MM-DD），用于确定未来窗口上界
local function days_later(date_str, n)
    local y, m, d = date_str:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
    if not y then
        return date_str
    end
    local base = os.time({ year = tonumber(y), month = tonumber(m), day = tonumber(d),
                            hour = 12, min = 0, sec = 0 })
    if not base then
        return date_str
    end
    return os.date("%Y-%m-%d", base + n * 86400.0)
end

-- ASCII 标签安全化：非 ASCII 字符（中文/多字节）替换为 '?'
-- 不再做长度截断 —— 多行折行由 wrap_text 负责，标签内容完整保留。
local function sanitize_ascii(s)
    s = s or ""
    s = s:gsub("[^%w%p%s]", "?")  -- 保留字母数字/标点/空白，其余替换为 ?
    return s
end

-- 把 text 按 max_chars 切成多行。贪心折行：尽量在空格处断词；
-- 单个单词超过 max_chars 时硬切（拼音无空格场景也能兜底不溢出）。
-- 返回字符串数组，每个元素长度 <= max_chars。
local function wrap_text(text, max_chars)
    text = text or ""
    if #text <= max_chars then
        return { text }
    end

    -- 按空白拆词（%S+ 匹配非空白序列，连续空格自动压缩）
    local words = {}
    for word in text:gmatch("%S+") do
        local rest = word                 -- 拷贝到独立局部，避免对循环变量赋值（luacheck W111）
        while #rest > max_chars do        -- 单词本身超长 → 硬切成 max_chars 段
            table.insert(words, rest:sub(1, max_chars))
            rest = rest:sub(max_chars + 1)
        end
        if #rest > 0 then
            table.insert(words, rest)
        end
    end
    if #words == 0 then                     -- 全空白兜底
        return { text:sub(1, max_chars) }
    end

    -- 贪心装箱
    local lines = {}
    local cur = words[1]
    for i = 2, #words do
        local w = words[i]
        if #cur + 1 + #w <= max_chars then  -- 加一个空格还能塞下
            cur = cur .. " " .. w
        else                                 -- 当前行满，换行
            table.insert(lines, cur)
            cur = w
        end
    end
    table.insert(lines, cur)
    return lines
end

-- 右对齐绘制（等宽字体，宽度 = 字符数 × 单字宽）
local function text_right(s, y, size, color)
    local adv = ADVANCE[size] or 11
    epaper.text(s, W - #s * adv - 4, y, size, color)
end

-- 居中绘制
local function text_center(s, y, size, color)
    local adv = ADVANCE[size] or 11
    epaper.text(s, math.floor((W - #s * adv) / 2), y, size, color)
end

local function run()
    -- 显示「今天 + 未来 3 天」：不读取外部 date，始终以系统当前日期为基准。
    local now_tbl = os.date("*t")
    local today_str = os.date("%Y-%m-%d")
    -- os.date wday: 1=Sunday .. 7=Saturday；weekly weekday 字段 0-6 (0=Sunday)
    local today_wday = (now_tbl and now_tbl.wday and now_tbl.wday - 1) or -1
    local now_hhmm = os.date("%H:%M")
    local max_date_str = days_later(today_str, 3)

    local list = load_schedules()

    -- 过滤窗口内可见日程
    local visible = {}
    for _, item in ipairs(list) do
        if is_visible(item, today_str, today_wday, max_date_str) then
            table.insert(visible, item)
        end
    end

    -- 按日期+时间排序：先按显示日期，再按 time
    table.sort(visible, function(a, b)
        local da = bucket_date(a, today_str)
        local db = bucket_date(b, today_str)
        if da ~= db then
            return da < db
        end
        return (a.time or "99:99") < (b.time or "99:99")
    end)

    -- 统计今日/未来条数（页脚用）
    local n_today, n_upcoming = 0, 0
    for _, item in ipairs(visible) do
        if bucket_date(item, today_str) == today_str then
            n_today = n_today + 1
        else
            n_upcoming = n_upcoming + 1
        end
    end

    -- 绘制
    epaper.init()
    epaper.clear(COLOR_WHITE)

    -- 顶部黄条：左 "TODAY"（Font24 黑字），右短日期（Font16 黑字）
    epaper.fill_rect(0, 0, W, 26, COLOR_YELLOW)
    epaper.text("TODAY", 2, 0, FONT_TITLE, COLOR_BLACK)
    text_right(short_date(today_str), 6, FONT_BODY, COLOR_BLACK)

    -- 完整日期 + 星期（3 字母）
    epaper.text(os.date("%Y-%m-%d") .. "  " .. WEEKDAY3[(today_wday >= 0 and today_wday + 1) or 1],
                0, 28, FONT_BODY, COLOR_BLACK)

    -- 全宽黑色实线分割（取代旧的虚线）
    epaper.fill_rect(0, 48, W, 2, COLOR_BLACK)

    local y = 56
    local bottom = epaper.height() - 16   -- 368：留 16px 给页脚

    if #visible == 0 then
        text_center("No schedules", 120, FONT_BODY, COLOR_BLACK)
    else
        local cur_date = nil
        for _, item in ipairs(visible) do
            if y >= bottom then
                break  -- 屏幕已满，剩余条目不画
            end

            local bdate = bucket_date(item, today_str)
            if bdate ~= cur_date then
                cur_date = bdate
                if bdate ~= today_str then
                    -- 未来日期分组：分割线 + 黄色窄条 + 居中日期
                    if y >= bottom then break end
                    epaper.fill_rect(0, y, W, 2, COLOR_BLACK)
                    y = y + 2
                    if y >= bottom then break end
                    epaper.fill_rect(0, y, W, 16, COLOR_YELLOW)
                    text_center(short_date(bdate), y, FONT_BODY, COLOR_BLACK)
                    y = y + 16
                end
            end

            local time_str = item.time or "??:??"
            -- 时间已过 = 今日 bucket 且 time < now（HH:MM 零填充，字典序 = 时间序）
            local is_past = (bdate == today_str) and ((item.time or "99:99") < now_hhmm)
            local item_color = is_past and COLOR_RED or COLOR_BLACK
            local label = sanitize_ascii(item.title_ascii)
            local segments = wrap_text(label, LABEL_WIDTH_CHARS)

            -- 单条日程行数上限：超限截到 MAX_LINES_PER_ITEM 行，末行加省略号
            if #segments > MAX_LINES_PER_ITEM then
                local last = segments[MAX_LINES_PER_ITEM]
                if #last > LABEL_WIDTH_CHARS - 3 then
                    last = last:sub(1, LABEL_WIDTH_CHARS - 3)
                end
                segments[MAX_LINES_PER_ITEM] = last .. "..."
                for j = #segments, MAX_LINES_PER_ITEM + 1, -1 do
                    segments[j] = nil
                end
            end

            -- marker 与整条文字同色：已过红，未开始黑
            for i, seg in ipairs(segments) do
                if y >= bottom then
                    break  -- 当前条剩余行画不下，跳出（已画的行保留）
                end
                if i == 1 then
                    epaper.fill_rect(0, y + 1, 4, 14, item_color)
                    epaper.text(time_str .. " " .. seg, 10, y, FONT_BODY, item_color)
                else
                    epaper.text(CONTINUE_INDENT .. seg, 10, y, FONT_BODY, item_color)
                end
                y = y + LINE_GAP
            end
        end
    end

    -- 页脚：今日/未来条数（Font8 小字，ASCII 分号）
    text_center(string.format("Today: %d  Upcoming: %d", n_today, n_upcoming),
                372, FONT_SMALL, COLOR_BLACK)

    -- 存缓存（不刷屏）：BOOT 切到待办屏时才 display
    epaper.save_schedule_cache()
    epaper.sleep()

    print(string.format("[schedule_manager] cached %d schedule(s) for %s .. %s for e-paper",
                        #visible, today_str, max_date_str))
end

local ok, err = xpcall(run, debug.traceback)
if not ok then
    print("[schedule_manager] ERROR: " .. tostring(err))
    error(err)
end
