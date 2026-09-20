-- --------------------------------------------------------------
-- weather: draw today's weather + this week's calendar on the 3.5" 4-color
-- e-paper and store it into the epaper weather cache (NO display). The BOOT-key
-- switcher shows this cached frame when the user switches to the weather screen.
-- 184x384, ASCII only (no Chinese font) — city/condition must be English/pinyin.
-- --------------------------------------------------------------

local epaper = require("epaper")

-- 面板与字体常量
local COLOR_BLACK = 0
local COLOR_WHITE = 1
local COLOR_YELLOW = 2
local COLOR_RED = 3
local FONT_BIG = 24     -- 17px/char
local FONT_SMALL = 16   -- 11px/char
local WEEKDAY_NAMES = { "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun" }

-- 读取 args（cap_lua 注入的全局 table），缺失时给默认值
local function raw_arg(name)
    if type(args) == "table" and type(args[name]) == "string" and args[name] ~= "" then
        return args[name]
    end
    return nil
end

-- ASCII 安全化：非 ASCII 字符（中文/多字节）替换为 '?'，并截断到 max 长度
local function sanitize_ascii(s, max)
    s = s or ""
    s = s:gsub("[^%w%p%s]", "?")
    if max and #s > max then
        s = s:sub(1, max)
    end
    return s
end

local function run()
    -- 天气信息（LLM 通过 web_search 拿到后传入，已 ASCII 化兜底）
    local city = sanitize_ascii(raw_arg("city"), 14) or "Beijing"
    local cond = sanitize_ascii(raw_arg("cond"), 12)
    local temp = sanitize_ascii(raw_arg("temp"), 8)
    local range = sanitize_ascii(raw_arg("range"), 12)
    local wind = sanitize_ascii(raw_arg("wind"), 12)

    if not cond or cond == "" then
        cond = "--"
    end
    if not temp or temp == "" then
        temp = "--"
    end

    -- 日期与星期：NTP 未同步时 os.date("*t") 返回 1970/无效时间，画进缓存会
    -- 显示错误日期。这里直接跳过（不画、不存缓存），等下一次每小时刷新兜底。
    if os.time() < 1704067200 then
        print("[weather] WARNING: time not synced, skip render")
        return
    end

    local now = os.date("*t")
    local date_str = os.date("%Y-%m-%d")
    local today_wday = now.wday            -- 1=Sunday .. 7=Saturday
    local today_name = WEEKDAY_NAMES[((today_wday - 2) % 7) + 1]  -- 0=Mon 映射
    -- 本周一（0 点）与「今天距周一的天数」（0=周一）
    local today_midnight = os.time({ year = now.year, month = now.month, day = now.day, hour = 0, min = 0, sec = 0 })
    local days_since_monday = (today_wday + 5) % 7
    local monday_midnight = today_midnight - days_since_monday * 86400

    -- 绘制
    epaper.init()
    epaper.clear(COLOR_WHITE)

    -- 顶部：日期 + 城市
    epaper.text("WEATHER", 0, 0, FONT_SMALL, COLOR_YELLOW)
    epaper.text(date_str .. " " .. today_name, 0, 18, FONT_SMALL, COLOR_BLACK)
    epaper.text(city, 0, 38, FONT_BIG, COLOR_BLACK)
    epaper.text("----------------", 0, 66, FONT_SMALL, COLOR_BLACK)

    -- 中部：大号温度 + 天气状况
    epaper.text(temp, 0, 84, FONT_BIG, COLOR_RED)
    epaper.text(cond, 0, 112, FONT_BIG, COLOR_BLACK)
    if range and range ~= "" then
        epaper.text("Range " .. range, 0, 142, FONT_SMALL, COLOR_BLACK)
    end
    if wind and wind ~= "" then
        epaper.text("Wind  " .. wind, 0, 162, FONT_SMALL, COLOR_BLACK)
    end

    -- 底部：本周 7 天日历
    epaper.text("----------------", 0, 186, FONT_SMALL, COLOR_BLACK)
    local y = 204
    for i = 0, 6 do
        local d = os.date("*t", monday_midnight + i * 86400)
        local name = WEEKDAY_NAMES[i + 1]
        local is_today = (i == days_since_monday)
        local marker = is_today and ">" or " "
        local color = is_today and COLOR_RED or COLOR_BLACK
        epaper.text(string.format("%s %s %02d", marker, name, d.day), 0, y, FONT_SMALL, color)
        y = y + 22
    end

    -- 存缓存（不刷屏）：BOOT 切到天气屏时才 display
    epaper.save_weather_cache()
    epaper.sleep()

    print(string.format("[weather] cached %s %s %s (%s) for %s",
        city, cond, temp, range or "--", date_str))
end

local ok, err = xpcall(run, debug.traceback)
if not ok then
    print("[weather] ERROR: " .. tostring(err))
    error(err)
end
