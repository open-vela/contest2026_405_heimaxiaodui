-- --------------------------------------------------------------
-- 晨间播报：早上好，您今天有 X 个代办，已通过飞书发送给您，可以打开飞书进一步查看
-- 数字片段（digit0-9/ten）复用 announce_time skill 的音频目录。
-- --------------------------------------------------------------

local arg_schema = require("arg_schema")
local audio = require("audio")
local bm = require("board_manager")

local DEFAULT_BASE = "/system/skills"

local ARG_SCHEMA = {
    count = arg_schema.int({ default = -1, min = 0, max = 99 }),
}

local ctx = arg_schema.parse(type(args) == "table" and args or {}, ARG_SCHEMA)

local function raw_arg(name)
    if type(args) == "table" and type(args[name]) == "string" and args[name] ~= "" then
        return args[name]
    end
    return nil
end

-- 0-99 的数字拆成中文片段名序列（数字片段在 announce_time 的音频目录里）：
-- 3→digit3, 10→ten, 14→ten+digit4, 20→digit2+ten, 45→digit4+ten+digit5
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

local skill_dir = raw_arg("skill_dir") or (DEFAULT_BASE .. "/announce_morning")
local morning_audio = skill_dir .. "/audio"

-- 数字片段目录：从本 skill 目录推导同级 announce_time，推导失败用默认路径
local digits_base = string.gsub(skill_dir, "announce_morning$", "announce_time")
if digits_base == skill_dir then
    digits_base = DEFAULT_BASE .. "/announce_time"
end
local digits_audio = digits_base .. "/audio"

local function build_clips(count)
    local clips = {
        { morning_audio, "morning" },
        { morning_audio, "you_have" },
    }
    local nums = {}
    append_number_clips(count, nums)
    for _, name in ipairs(nums) do
        table.insert(clips, { digits_audio, name })
    end
    table.insert(clips, { morning_audio, "count_word" })
    table.insert(clips, { morning_audio, "sent_feishu" })
    table.insert(clips, { morning_audio, "open_feishu" })
    return clips
end

local codec, rate, channels, bits = bm.get_audio_codec_output_params("audio_dac")
if not codec then
    error("get_audio_codec_output_params(audio_dac) failed: " .. tostring(rate))
end

local output = assert(audio.new_output({ codec, rate, channels, bits, volume = 90 }))
local player = assert(audio.player({ output = output }))

local ok, err = xpcall(function()
    if ctx.count < 0 then
        error("args.count is required (0-99)")
    end

    local clips = build_clips(ctx.count)
    local info = output:info()
    print(string.format("[announce_morning] %d todos via %d clips, output=%dHz/%dch/%dbit",
                        ctx.count, #clips, info.sample_rate, info.channels, info.bits))

    for _, clip in ipairs(clips) do
        player:play(clip[1] .. "/" .. clip[2] .. ".wav", { wait = true })
    end

    print(string.format("[announce_morning] done: announced %d todos", ctx.count))
end, debug.traceback)

pcall(function() player:close() end)
pcall(function() output:close() end)
if not ok then
    print("[announce_morning] ERROR: " .. tostring(err))
    error(err)
end
