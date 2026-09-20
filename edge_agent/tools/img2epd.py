#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
img2epd.py - 图片转 4 色 2bit 数据并通过串口发送给 ESP32-P4 墨水屏
临时验证工具：验证 P4 固件的接收+显示链路，不进最终 Android App。

复用 Waveshare converterTo4color.cpp 的 4 色调色板和 2bit 打包逻辑，
加 Floyd-Steinberg 抖动开关（照片类内容打开，文字图标类关闭）。

用法:
  python img2epd.py <图片> --port COM21            # 发图到屏幕
  python img2epd.py <图片> --out image.c           # 输出 C 数组
  python img2epd.py <图片> --port COM21 --dither   # 开抖动
"""
import sys
import struct
import argparse
from pathlib import Path

from PIL import Image

# 串口可选（输出 C 数组时不强制）
try:
    import serial
except ImportError:
    serial = None

# ── 屏幕/调色板参数（对齐 P4 端 EPD_3in5g_V2.h）──────────────────────
WIDTH = 184
HEIGHT = 384

# 4 色调色板 [R, G, B]，索引即 2bit 编码：
#   0=黑 1=白 2=黄 3=红  （与 EPD_3in5g_V2.h 的宏一致）
PALETTE = [
    (0,   0,   0),
    (255, 255, 255),
    (255, 255, 0),
    (255, 0,   0),
]

# ── 协议（对齐 P4 端 epd_protocol.h）─────────────────────────────────
FRAME_HEAD = b"\xA5\x5A"
CMD_IMAGE = 0x01


def nearest_color(r, g, b):
    """最近色量化（欧氏距离），对应 C++ depalette()。返回调色板索引 0~3。"""
    best, best_diff = 0, 1 << 30
    for i, (pr, pg, pb) in enumerate(PALETTE):
        diff = (r - pr) ** 2 + (g - pg) ** 2 + (b - pb) ** 2
        if diff < best_diff:
            best_diff, best = diff, i
    return best


def convert_image(img: Image.Image, dither: bool) -> bytes:
    """
    转换为 17664 字节 4 色 2bit 数据。
    打包顺序与 converterTo4color.cpp 一致：
        byte = c3 | (c2<<2) | (c1<<4) | (c0<<6)   (c0 最左像素)
    """
    img = img.convert("RGB").resize((WIDTH, HEIGHT))
    px = img.load()

    # 工作缓冲：每个像素的 RGB（抖动时会被误差修改）
    buf = [[[0, 0, 0] for _ in range(WIDTH)] for _ in range(HEIGHT)]
    for y in range(HEIGHT):
        for x in range(WIDTH):
            r, g, b = px[x, y]
            buf[y][x][0] = r
            buf[y][x][1] = g
            buf[y][x][2] = b

    out = bytearray()
    for y in range(HEIGHT):
        row_bytes = WIDTH // 4  # 184 % 4 == 0
        for i in range(row_bytes):
            c = [0, 0, 0, 0]
            for k in range(4):
                x = i * 4 + k
                r, g, b = buf[y][x]
                idx = nearest_color(r, g, b)
                c[k] = idx

                if dither:
                    # Floyd-Steinberg 误差扩散
                    pr, pg, pb = PALETTE[idx]
                    er, eg, eb = r - pr, g - pg, b - pb
                    # 7/16 右
                    if x + 1 < WIDTH:
                        buf[y][x + 1][0] += er * 7 // 16
                        buf[y][x + 1][1] += eg * 7 // 16
                        buf[y][x + 1][2] += eb * 7 // 16
                    # 3/16 左下
                    if y + 1 < HEIGHT and x - 1 >= 0:
                        buf[y + 1][x - 1][0] += er * 3 // 16
                        buf[y + 1][x - 1][1] += eg * 3 // 16
                        buf[y + 1][x - 1][2] += eb * 3 // 16
                    # 5/16 下
                    if y + 1 < HEIGHT:
                        buf[y + 1][x][0] += er * 5 // 16
                        buf[y + 1][x][1] += eg * 5 // 16
                        buf[y + 1][x][2] += eb * 5 // 16
                    # 1/16 右下
                    if y + 1 < HEIGHT and x + 1 < WIDTH:
                        buf[y + 1][x + 1][0] += er * 1 // 16
                        buf[y + 1][x + 1][1] += eg * 1 // 16
                        buf[y + 1][x + 1][2] += eb * 1 // 16

            # 打包 4 像素到 1 字节（c0 在高位，与 C++ 源码一致）
            byte = c[3] | (c[2] << 2) | (c[1] << 4) | (c[0] << 6)
            out.append(byte)

    assert len(out) == WIDTH // 4 * HEIGHT, f"长度错误: {len(out)} != {WIDTH//4*HEIGHT}"
    return bytes(out)


def crc16(data: bytes) -> int:
    """CRC-16/MODBUS，P4 端用同一算法校验。"""
    crc = 0xFFFF
    for b in data:
        crc ^= b
        for _ in range(8):
            if crc & 0x0001:
                crc = (crc >> 1) ^ 0xA001
            else:
                crc >>= 1
    return crc & 0xFFFF


def build_frame(payload: bytes, cmd: int = CMD_IMAGE) -> bytes:
    """
    协议帧: 帧头(2) | CMD(1) | LEN(4, 小端) | PAYLOAD(N) | CRC16(2)
    LEN 只含 PAYLOAD 长度。CRC16 校验 PAYLOAD。
    """
    n = len(payload)
    crc = crc16(payload)
    head = FRAME_HEAD + struct.pack("<BI", cmd, n)
    return head + payload + struct.pack("<H", crc)


def send_serial(port: str, payload: bytes, baud: int = 115200, chunk: int = 512):
    """分块发送，给 P4 端接收留时间。"""
    if serial is None:
        print("错误: 未安装 pyserial，请 pip install pyserial")
        sys.exit(1)
    frame = build_frame(payload)
    print(f"帧总长 {len(frame)}B，开串口 {port}@{baud}...")
    with serial.Serial(port, baud, timeout=2) as s:
        # 先发个唤醒/握手（可选，P4 端按需处理）
        offset = 0
        total = len(frame)
        while offset < total:
            n = min(chunk, total - offset)
            s.write(frame[offset:offset + n])
            offset += n
            pct = offset * 100 // total
            print(f"\r发送 {offset}/{total}B ({pct}%)", end="", flush=True)
        print("\n发送完成，等待屏幕刷新（约 12 秒）...")


def output_c_array(payload: bytes, path: str, width: int = WIDTH, height: int = HEIGHT):
    """输出 C 数组，格式对齐 Waveshare ImageData.cpp。"""
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(f"// 4 Color Image Data {width}*{height}\n")
        f.write('#include "ImageData.h"\n')
        f.write(f"const unsigned char Image4color[{len(payload)}] = {{\n")
        for i in range(0, len(payload), 16):
            line = ",".join(f"0x{b:02X}" for b in payload[i:i + 16])
            f.write(f"    {line},\n")
        f.write("};\n")
    print(f"已输出 C 数组到 {path}（{len(payload)}B）")


def main():
    ap = argparse.ArgumentParser(description="图片转 4 色 2bit 并串口发送给 P4 墨水屏")
    ap.add_argument("image", help="输入图片路径 (JPG/PNG/BMP)")
    ap.add_argument("--port", help="串口号，如 COM21（不填则不发）")
    ap.add_argument("--baud", type=int, default=115200, help="波特率")
    ap.add_argument("--dither", action="store_true", help="启用 Floyd-Steinberg 抖动（照片推荐）")
    ap.add_argument("--out", help="输出 C 数组到文件（不发串口）")
    args = ap.parse_args()

    img = Image.open(args.image)
    print(f"输入 {args.image}  size={img.size}  抖动={'开' if args.dither else '关'}")
    payload = convert_image(img, dither=args.dither)
    print(f"转换完成: {len(payload)}B（应为 {WIDTH//4*HEIGHT}B）")

    if args.out:
        output_c_array(payload, args.out)
    if args.port:
        send_serial(args.port, payload, args.baud)


if __name__ == "__main__":
    main()
