#!/usr/bin/env python3
"""生成时间播报语音片段（WAV 版，esp-claw announce_time skill 用）

Windows 自带中文 TTS（System.Speech / Microsoft Huihui）合成 15 个片段，
静音裁剪 + 峰值归一化后输出 16kHz/16bit/单声道 WAV 到 skill 的 audio/ 目录。

用法:
    python application/edge_agent/tools/gen_time_clips_wav.py
"""
import base64
import os
import struct
import subprocess
import sys
import wave

HERE = os.path.dirname(os.path.abspath(__file__))
OUT_BASE_DIR = os.path.join(HERE, '..', 'main', 'skills')

TARGET_RATE = 16000
SILENCE_THRESH = 800     # 静音判定阈值
LEAD_PAD_MS = 60         # 裁剪后保留的前导静音
TAIL_PAD_MS = 120        # 裁剪后保留的尾部静音（拼接时自然停顿）
NORM_PEAK = 28000        # 归一化目标峰值（约 -1.4dBFS）
TTS_TMP_DIR = os.path.join(HERE, '_tts_tmp')

# (文件名, 朗读文本) —— 与 announce_time.lua 里的片段名一一对应，勿改
TIME_CLIPS = [
    ('prefix', '现在是北京时间'),
    ('digit0', '零'),
    ('digit1', '一'),
    ('digit2', '二'),
    ('digit3', '三'),
    ('digit4', '四'),
    ('digit5', '五'),
    ('digit6', '六'),
    ('digit7', '七'),
    ('digit8', '八'),
    ('digit9', '九'),
    ('ten', '十'),
    ('dian', '点'),
    ('fen', '分'),
    ('zheng', '整'),
]

# 晨间播报片段 —— 与 announce_morning.lua 里的片段名一一对应，勿改
MORNING_CLIPS = [
    ('morning', '早上好'),
    ('you_have', '您今天有'),
    ('count_word', '个代办'),
    ('sent_feishu', '已通过飞书发送给您'),
    ('open_feishu', '可以打开飞书进一步查看'),
]

# (skill 名, 片段组)
SKILL_GROUPS = [
    ('announce_time', TIME_CLIPS),
    ('announce_morning', MORNING_CLIPS),
]


def build_ps_command(voice, rate):
    """构建 PowerShell 合成脚本文本（内联执行，不落地 .ps1 文件）"""
    lines = [
        'Add-Type -AssemblyName System.Speech',
        '$s = New-Object System.Speech.Synthesis.SpeechSynthesizer',
        '$s.SelectVoice("%s")' % voice,
        '$s.Rate = %d' % rate,
    ]
    for _, clips in SKILL_GROUPS:
        for fname, text in clips:
            wav = os.path.abspath(os.path.join(TTS_TMP_DIR, fname + '.wav'))
            lines.append('$s.SetOutputToWaveFile("%s")' % wav)
            lines.append('$s.Speak("%s")' % text)
    lines.append('$s.Dispose()')
    return '\n'.join(lines)


def run_tts(ps_script):
    """-EncodedCommand：UTF-16LE base64，中文编码安全，且无需改执行策略"""
    encoded = base64.b64encode(ps_script.encode('utf-16-le')).decode()
    subprocess.check_call(['powershell', '-NoProfile', '-EncodedCommand', encoded])


def wav_to_pcm_samples(path):
    """wav → 16kHz/16bit 单声道采样列表
    含静音裁剪（Huihui 尾部有 ~0.8s 静音）+ 峰值归一化（单字合成音量偏低）"""
    w = wave.open(path, 'rb')
    nch, sw, rate, nframes = (w.getnchannels(), w.getsampwidth(),
                              w.getframerate(), w.getnframes())
    raw = w.readframes(nframes)
    w.close()

    if sw == 2:
        samples = list(struct.unpack('<%dh' % (len(raw) // 2), raw))
    elif sw == 1:  # 8bit unsigned
        samples = [(b - 128) * 256 for b in raw]
    elif sw == 4:  # 32bit int
        samples = [v >> 16 for v in struct.unpack('<%di' % (len(raw) // 4), raw)]
    else:
        sys.exit('不支持的采样宽度: %d 字节 (%s)' % (sw, path))

    if nch > 1:  # 多声道 → 取第 0 声道
        samples = samples[0::nch]

    # 静音裁剪
    first = next((i for i, s in enumerate(samples) if abs(s) > SILENCE_THRESH), 0)
    last = next((i for i, s in enumerate(reversed(samples))
                 if abs(s) > SILENCE_THRESH), 0)
    start = max(0, first - int(rate * LEAD_PAD_MS / 1000))
    end = min(len(samples), len(samples) - last + int(rate * TAIL_PAD_MS / 1000))
    samples = samples[start:end]

    if not samples:
        sys.exit('片段全静音: %s' % path)

    if rate != TARGET_RATE:  # 线性重采样
        n_out = int(len(samples) * TARGET_RATE / rate)
        res = []
        for i in range(n_out):
            pos = i * rate / TARGET_RATE
            i0 = int(pos)
            i1 = min(i0 + 1, len(samples) - 1)
            frac = pos - i0
            res.append(int(samples[i0] * (1 - frac) + samples[i1] * frac))
        samples = res

    # 峰值归一化：各片段响度一致
    peak = max(abs(s) for s in samples)
    if peak > 0:
        gain = min(NORM_PEAK / peak, 8.0)  # 上限 8 倍，避免放大纯噪声
        samples = [int(s * gain) for s in samples]

    return [max(-32768, min(32767, s)) for s in samples]


def main():
    voice = 'Microsoft Huihui Desktop'
    rate = 0
    if len(sys.argv) > 1:
        voice = sys.argv[1]
    if len(sys.argv) > 2:
        rate = int(sys.argv[2])

    os.makedirs(TTS_TMP_DIR, exist_ok=True)
    for skill_name, _ in SKILL_GROUPS:
        os.makedirs(os.path.join(OUT_BASE_DIR, skill_name, 'audio'), exist_ok=True)

    print('[1/3] TTS 合成 %d 个片段 (%s, rate=%d)...'
          % (sum(len(c) for _, c in SKILL_GROUPS), voice, rate))
    run_tts(build_ps_command(voice, rate))

    print('[2/3] 裁剪 + 归一化 + 转 16k/16bit/mono ...')
    for skill_name, clips in SKILL_GROUPS:
        out_dir = os.path.join(OUT_BASE_DIR, skill_name, 'audio')
        total = 0
        for fname, _ in clips:
            src = os.path.join(TTS_TMP_DIR, fname + '.wav')
            samples = wav_to_pcm_samples(src)
            dst = os.path.join(out_dir, fname + '.wav')
            with wave.open(dst, 'wb') as w:
                w.setnchannels(1)
                w.setsampwidth(2)
                w.setframerate(TARGET_RATE)
                w.writeframes(struct.pack('<%dh' % len(samples), *samples))
            total += len(samples)
            print('  [%s] %-12s %5.2f 秒' % (skill_name, fname, len(samples) / TARGET_RATE))
        print('  [%s] 共 %d 片段, %.1f 秒' % (skill_name, len(clips), total / TARGET_RATE))

    print('[3/3] 完成: %s' % os.path.relpath(OUT_BASE_DIR))


if __name__ == '__main__':
    main()
