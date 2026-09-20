#!/usr/bin/env python3
"""生成墨水屏三个界面（工卡 / 天气日历 / 待办）→ main/ui_screens.c/.h

PC 端 PIL + 微软雅黑渲染，复用 img2epd.py 的 4 色 2bit 转换（文字不开抖动，
此前已验证抖动会糊化文字边缘）。内容为演示占位，动态数据后续走 BLE 推图，
显示通路不变。

用法:
    python tools/gen_ui_screens.py

改内容（姓名/待办/天气）直接编辑下方 CONFIG，重新运行即可。
"""
import sys
from pathlib import Path

HERE = Path(__file__).parent
sys.path.insert(0, str(HERE))

from img2epd import WIDTH, HEIGHT, convert_image  # noqa: E402
from PIL import Image, ImageDraw, ImageFont  # noqa: E402

OUT_C = HERE.parent / "main" / "ui_screens.c"
OUT_H = HERE.parent / "main" / "ui_screens.h"
SCREEN_BYTES = WIDTH // 4 * HEIGHT  # 17664

# ---------------- 演示内容（占位，后续动态化） ----------------
CONFIG = {
    "todos": [
        ("评审 P4 原理图", True),
        ("回复供应商邮件", False),
        ("跟进相机驱动 bug", False),
        ("整理墨水屏文档", False),
        ("准备周会材料", False),
    ],
}

BLACK = (0, 0, 0)
WHITE = (255, 255, 255)
RED = (255, 0, 0)
YELLOW = (255, 255, 0)

# 工卡照片源图（用户放置，整屏满铺进工卡屏）
PHOTO_PATH = HERE.parent / "test.png"  # application/edge_agent/test.png


def font(size, bold=False):
    path = "C:/Windows/Fonts/msyhbd.ttc" if bold else "C:/Windows/Fonts/msyh.ttc"
    try:
        return ImageFont.truetype(path, size)
    except OSError:
        return ImageFont.truetype("C:/Windows/Fonts/msyh.ttc", size)


def text_centered(d, cx, y, s, f, fill):
    """以 cx 为水平中心画文本"""
    bb = d.textbbox((0, 0), s, font=f)
    d.text((cx - (bb[2] - bb[0]) // 2, y), s, font=f, fill=fill)


def text_width(d, s, f):
    return d.textbbox((0, 0), s, font=f)[2]


def draw_footer(d, idx, label):
    """黄色底栏：页码 + 界面名（所有屏统一，切到哪一屏一目了然）"""
    d.rectangle([0, HEIGHT - 22, WIDTH - 1, HEIGHT - 1], fill=YELLOW)
    text_centered(d, WIDTH // 2, HEIGHT - 19, "%d/3 · %s" % (idx + 1, label),
                  font(12), BLACK)


def new_screen():
    img = Image.new("RGB", (WIDTH, HEIGHT), WHITE)
    return img, ImageDraw.Draw(img)


# ---------------- 界面 1：工卡（开机首屏） ----------------
def draw_badge():
    img, _ = new_screen()  # 白底 184×384
    # 整屏满铺 test.png：aspect-crop 到 184×384 后贴满，无文字无页脚
    try:
        photo = Image.open(PHOTO_PATH).convert("RGB")
        w, h = photo.size
        if w * HEIGHT > h * WIDTH:          # 太宽，居中裁两侧
            nw = int(h * WIDTH / HEIGHT)
            photo = photo.crop(((w - nw) // 2, 0, (w - nw) // 2 + nw, h))
        else:                               # 太高，居中裁上下
            nh = int(w * HEIGHT / WIDTH)
            photo = photo.crop((0, (h - nh) // 2, w, (h - nh) // 2 + nh))
        photo = photo.resize((WIDTH, HEIGHT))
        img.paste(photo, (0, 0))
    except OSError as e:
        print("[badge] test.png 加载失败，整屏留白: %s" % e, file=sys.stderr)
    return img


# ---------------- 界面 2：天气日历 ----------------
def draw_weather():
    img, d = new_screen()
    d.rectangle([0, 0, WIDTH - 1, 32], fill=RED)
    text_centered(d, WIDTH // 2, 8, "WEATHER", font(14), WHITE)

    # 占位帧（缓存无效时的回退）。不渲染「今天」的日期/星期/日历高亮——那会是
    # 编译时刻的过期日期，固件放一天就显示昨天。改为中性提示，等首次天气刷新
    # （LLM → show_weather.lua → save_weather_cache）填真实帧。
    text_centered(d, WIDTH // 2, 44, "--", font(56, bold=True), BLACK)
    text_centered(d, WIDTH // 2, 126, "加载中...", font(18), BLACK)

    # 天气未配置占位：web_search 需 Brave/Tavily 密钥，未配前不编造天气数据
    text_centered(d, WIDTH // 2, 166, "Set API Key", font(22, bold=True), BLACK)
    text_centered(d, WIDTH // 2, 202, "天气待配置", font(16), BLACK)

    d.line([16, 236, WIDTH - 16, 236], fill=BLACK)

    # 底部提示：如何配置天气密钥
    text_centered(d, WIDTH // 2, 250, "Configure Brave/Tavily key", font(12), BLACK)
    text_centered(d, WIDTH // 2, 268, "in Web UI", font(12), BLACK)

    draw_footer(d, 1, "天气日历")
    return img


# ---------------- 界面 3：待办 ----------------
def draw_todo():
    img, d = new_screen()
    d.rectangle([0, 0, WIDTH - 1, 32], fill=RED)
    d.text((12, 7), "今日待办", font=font(16), fill=WHITE)

    y, row_h = 52, 42
    for text, done in CONFIG["todos"]:
        if done:  # 红色实心块 = 已完成
            d.rectangle([12, y + 2, 24, y + 14], fill=RED)
        else:
            d.rectangle([12, y + 2, 24, y + 14], outline=BLACK, width=1)
        d.text((34, y), text, font=font(15), fill=BLACK)
        if done:  # 删除线
            tw = text_width(d, text, font(15))
            d.line([34, y + 10, 34 + tw, y + 10], fill=BLACK, width=1)
        y += row_h

    done_n = sum(1 for _, done in CONFIG["todos"] if done)
    d.line([16, y + 6, WIDTH - 16, y + 6], fill=BLACK)
    text_centered(d, WIDTH // 2, y + 18, "共 %d 项 · 已完成 %d 项"
                  % (len(CONFIG["todos"]), done_n), font(13), BLACK)

    draw_footer(d, 2, "待办")
    return img


def emit_c(payloads):
    lines = [
        "/* 自动生成：tools/gen_ui_screens.py，勿手改 */",
        "#include \"ui_screens.h\"",
        "",
    ]
    for name, data in payloads:
        lines.append("const unsigned char %s[%d] = {" % (name, len(data)))
        for i in range(0, len(data), 16):
            lines.append("    " + ",".join("0x%02X" % b for b in data[i:i + 16]) + ",")
        lines.append("};")
        lines.append("")
    lines += [
        "/* 按键循环顺序：0=工卡 1=天气日历 2=待办 */",
        "const unsigned char *const ui_screens[UI_SCREEN_COUNT] = {",
        "    ui_screen_badge, ui_screen_weather, ui_screen_todo,",
        "};",
        "",
        "const char *const ui_screen_names[UI_SCREEN_COUNT] = {",
        '    "工卡", "天气日历", "待办",',
        "};",
        "",
    ]
    return "\n".join(lines)


def main():
    screens = [
        ("ui_screen_badge", draw_badge()),
        ("ui_screen_weather", draw_weather()),
        ("ui_screen_todo", draw_todo()),
    ]
    payloads = [(name, convert_image(img, dither=False)) for name, img in screens]
    for name, img in screens:  # PNG 预览，PC 上直接看效果
        img.save(HERE / ("_preview_%s.png" % name.replace("ui_screen_", "")))
    for (name, _), (_, data) in zip(screens, payloads):
        assert len(data) == SCREEN_BYTES, "%s size %d != %d" % (name, len(data), SCREEN_BYTES)

    OUT_H.write_text(
        "/* 自动生成：tools/gen_ui_screens.py，勿手改 */\n"
        "#ifndef _UI_SCREENS_H_\n"
        "#define _UI_SCREENS_H_\n\n"
        "#ifdef __cplusplus\n"
        'extern "C" {\n'
        "#endif\n\n"
        "#define UI_SCREEN_COUNT 3\n"
        "#define UI_SCREEN_BYTES %d\n\n" % SCREEN_BYTES +
        "extern const unsigned char ui_screen_badge[UI_SCREEN_BYTES];\n"
        "extern const unsigned char ui_screen_weather[UI_SCREEN_BYTES];\n"
        "extern const unsigned char ui_screen_todo[UI_SCREEN_BYTES];\n\n"
        "/* 按键循环顺序：0=工卡 1=天气日历 2=待办 */\n"
        "extern const unsigned char *const ui_screens[UI_SCREEN_COUNT];\n"
        "extern const char *const ui_screen_names[UI_SCREEN_COUNT];\n\n"
        "#ifdef __cplusplus\n"
        "}\n"
        "#endif\n\n"
        "#endif\n",
        encoding="utf-8",
    )
    OUT_C.write_text(emit_c(payloads), encoding="utf-8")
    print("wrote %s (%d screens x %d bytes)" % (OUT_C, len(payloads), SCREEN_BYTES))
    print("wrote %s" % OUT_H)


if __name__ == "__main__":
    main()
