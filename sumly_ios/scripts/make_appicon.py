#!/usr/bin/env python3
"""生成 neo-brutalism 风格的 AppIcon（1024x1024，单尺寸）。

优先用系统中文字体画「金」字符；字体加载失败时退化为金币+走势线图形。
依赖 Pillow（可选）：python3 -m pip install Pillow

用法：python3 scripts/make_appicon.py [输出路径]
"""

import sys

from PIL import Image, ImageDraw, ImageFont

W = 1024
PAPER = (250, 243, 232)
GOLD = (255, 220, 88)
INK = (17, 17, 17)

img = Image.new("RGB", (W, W), PAPER)
draw = ImageDraw.Draw(img)

# 外框：粗墨色描边
margin = 72
draw.rounded_rectangle(
    [margin, margin, W - margin, W - margin], radius=96, outline=INK, width=44
)

# 金币：硬阴影偏移 + 墨色描边
cx, cy, r = W // 2, W // 2, 296
draw.ellipse([cx - r + 44, cy - r + 44, cx + r + 44, cy + r + 44], fill=INK)
draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=GOLD, outline=INK, width=40)

font = None
for index in range(6):
    try:
        font = ImageFont.truetype("/System/Library/Fonts/PingFang.ttc", 310, index=index)
        break
    except Exception:
        continue

if font is not None:
    draw.text((cx, cy), "金", font=font, fill=INK, anchor="mm")
else:
    # 退化方案：币内走势线
    pts = [(cx - 170, cy + 110), (cx - 60, cy + 20), (cx + 30, cy + 80), (cx + 170, cy - 110)]
    draw.line(pts, fill=INK, width=34, joint="curve")

out = (
    sys.argv[1]
    if len(sys.argv) > 1
    else "Sumly/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon1024.png"
)
img.save(out, "PNG")
print("wrote", out)
