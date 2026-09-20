-- --------------------------------------------------------------
-- Announce the given time through the speaker (voice clips).
-- 输入 hour/minute（24 小时制），拼接 15 个预录语音片段播放：
--   14:30 → 现在是北京时间 十四点三十分
--   14:05 → 现在是北京时间 十四点零五分
--   14:00 → 现在是北京时间 十四点整
-- --------------------------------------------------------------

local arg_schema = require("arg_schema")
local audio = require("audio")
local bm = require("board_manager")

local DEFAULT_SKILL_DIR = "/system/skills/announce_time"

local ARG_SCHEMA = {
    hour = arg_schema.int({ default = -1, min = 0, max = 23 }),
    minute = arg_schema.int({ default = -1, min = 0, max = 59 }),
}

local ctx = arg_schema.parse(type(args) == "table" and args or {}, ARG_SCHEMA)

local function raw_arg(name)
    if type(args) == "table" and type(args[name]) == "string" and args[name] ~= "" then
        return args[name]
    end
    return nil
end

-- 0-59 的数字拆成中文片段名序列：
-- 1→digit1, 10→ten, 14→ten+digit4, 20→digit2+ten, 45→digit4+ten+digit5
local function append_number_clips(n, out)
    if n == 0 then
        table.insert(out, "digit0")
    elseif n < 10 then
        table.insert(out, "digit" .. n)
    elseif n == 10 then
        table.insert(out, "ten")
    elseif n < 20 then
        table.insert(out, "ten")
        table.insert(out, "digit" .. (n - 10))
    else
        table.insert(out, "digit" .. math.floor(n / 10))
        table.insert(out, "ten")
        if n % 10 ~= 0 then
            table.insert(out, "digit" .. (n % 10))
        end
    end
end

local function build_clip_names(hour, minute)
    local clips = { "prefix" }
    append_number_clips(hour, clips)
    table.insert(clips, "dian")
    if minute == 0 then
        table.insert(clips, "zheng")
    else
        if minute < 10 then
            table.insert(clips, "digit0")  -- 零五分
        end
        append_number_clips(minute, clips)
        table.insert(clips, "fen")
    end
    return clips
end

local skill_dir = raw_arg("skill_dir") or DEFAULT_SKILL_DIR
local audio_dir = skill_dir .. "/audio"

local codec, rate, channels, bits = bm.get_audio_codec_output_params("audio_dac")
if not codec then
    error("get_audio_codec_output_params(audio_dac) failed: " .. tostring(rate))
end

local output = assert(audio.new_output({ codec, rate, channels, bits, volume = 90 }))
local player = assert(audio.player({ output = output }))

local ok, err = xpcall(function()
    if ctx.hour < 0 or ctx.minute < 0 then
        error("args.hour and args.minute are required (0-23 / 0-59)")
    end

    local clips = build_clip_names(ctx.hour, ctx.minute)
    local info = output:info()
    print(string.format("[announce_time] %02d:%02d via %d clips, output=%dHz/%dch/%dbit",
                        ctx.hour, ctx.minute, #clips, info.sample_rate, info.channels, info.bits))

    for _, name in ipairs(clips) do
        player:play(audio_dir .. "/" .. name .. ".wav", { wait = true })
    end

    print(string.format("[announce_time] done: announced %02d:%02d", ctx.hour, ctx.minute))
end, debug.traceback)

pcall(function() player:close() end)
pcall(function() output:close() end)
if not ok then
    print("[announce_time] ERROR: " .. tostring(err))
    error(err)
end
