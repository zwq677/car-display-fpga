# -*- coding: utf-8 -*-
"""
生成 640x480 24 位非压缩 BMP 测试图，用于 SD 卡轮播验证。

只依赖 Python 标准库，不装任何第三方包也能跑。

用法:
    python make_test_bmp.py            # 默认输出到 ./sd_images
    python make_test_bmp.py D:\\imgs    # 指定输出目录

注意（这是本工程的硬性要求，不符合会读不出来）:
  - 分辨率必须是 640x480，BMP 头里的 width/height 要和实际一致
  - 必须是 24 位、不压缩（compression = 0）
  - 俯视/仰视都可以，本程序按标准 BMP 的 bottom-up 写
  - 文件名随意，但放 SD 卡根目录即可（程序是按物理扇区扫描，不解析 FAT32）
"""
import os
import struct
import sys

W, H = 640, 480

# 5x7 点阵数字，用于画大号序号，方便肉眼确认切图顺序
FONT = {
    0: ["01110", "10001", "10011", "10101", "11001", "10001", "01110"],
    1: ["00100", "01100", "00100", "00100", "00100", "00100", "01110"],
    2: ["01110", "10001", "00001", "00010", "00100", "01000", "11111"],
    3: ["11111", "00010", "00100", "00010", "00001", "10001", "01110"],
    4: ["00010", "00110", "01010", "10010", "11111", "00010", "00010"],
    5: ["11111", "10000", "11110", "00001", "00001", "10001", "01110"],
    6: ["00110", "01000", "10000", "11110", "10001", "10001", "01110"],
    7: ["11111", "00001", "00010", "00100", "01000", "01000", "01000"],
    8: ["01110", "10001", "10001", "01110", "10001", "10001", "01110"],
    9: ["01110", "10001", "10001", "01111", "00001", "00010", "01100"],
}

# 每张图的主色调（R, G, B），四张差异要大，方便一眼区分
THEMES = [
    ((20, 40, 120), (90, 160, 255)),
    ((10, 90, 40), (120, 230, 150)),
    ((110, 20, 20), (255, 140, 90)),
    ((70, 20, 100), (220, 150, 255)),
]


def draw_number(px, x0, y0, num, scale, color):
    """把数字 num 画到 px 上，左上角 (x0,y0)，每个点放大 scale 倍"""
    s = str(num)
    for i, ch in enumerate(s):
        glyph = FONT[int(ch)]
        ox = x0 + i * (5 * scale + 2 * scale)
        for ry, row in enumerate(glyph):
            for rx, bit in enumerate(row):
                if bit != "1":
                    continue
                for dy in range(scale):
                    yy = y0 + ry * scale + dy
                    if not (0 <= yy < H):
                        continue
                    base = yy * W * 3
                    for dx in range(scale):
                        xx = ox + rx * scale + dx
                        if 0 <= xx < W:
                            px[base + xx * 3 + 0] = color[2]  # B
                            px[base + xx * 3 + 1] = color[1]  # G
                            px[base + xx * 3 + 2] = color[0]  # R


def make_one(idx, total, path):
    bg, fg = THEMES[idx % len(THEMES)]
    px = bytearray(W * H * 3)

    for y in range(H):
        # 竖直渐变 + 每 32 行一条暗纹，用来检查是否有行错位/撕裂
        t = y / float(H - 1)
        r = int(bg[0] + (fg[0] - bg[0]) * t * 0.55)
        g = int(bg[1] + (fg[1] - bg[1]) * t * 0.55)
        b = int(bg[2] + (fg[2] - bg[2]) * t * 0.55)
        if (y // 32) % 2 == 0:
            r, g, b = int(r * 0.85), int(g * 0.85), int(b * 0.85)
        base = y * W * 3
        for x in range(W):
            # 左右边缘加刻度柱，检查水平方向是否完整
            if x < 24 or x >= W - 24:
                rr, gg, bb = (255, 255, 255) if (y // 16) % 2 == 0 else (0, 0, 0)
            else:
                rr, gg, bb = r, g, b
            px[base + x * 3 + 0] = bb
            px[base + x * 3 + 1] = gg
            px[base + x * 3 + 2] = rr

    # 中间画大号序号
    scale = 22
    txt = str(idx + 1)
    tw = len(txt) * (5 * scale + 2 * scale) - 2 * scale
    draw_number(px, (W - tw) // 2, (H - 7 * scale) // 2, idx + 1, scale, (255, 255, 255))

    # 四角画白色方块，用于确认图像方向没颠倒
    for (cx, cy) in ((40, 40), (W - 40 - 30, 40), (40, H - 40 - 30), (W - 40 - 30, H - 40 - 30)):
        for yy in range(cy, cy + 30):
            base = yy * W * 3
            for xx in range(cx, cx + 30):
                px[base + xx * 3 + 0] = 255
                px[base + xx * 3 + 1] = 255
                px[base + xx * 3 + 2] = 255

    row_bytes = W * 3                      # 640*3 = 1920，正好是 4 的倍数，无需补位
    img_size = row_bytes * H
    hdr = b"BM" + struct.pack("<IHHI", 54 + img_size, 0, 0, 54)
    info = struct.pack("<IiiHHIIiiII", 40, W, H, 1, 24, 0, img_size, 2835, 2835, 0, 0)

    with open(path, "wb") as f:
        f.write(hdr)
        f.write(info)
        # BMP 是 bottom-up：先写最后一行
        for y in range(H - 1, -1, -1):
            base = y * W * 3
            f.write(bytes(px[base:base + row_bytes]))
    return 54 + img_size


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "sd_images"
    os.makedirs(out, exist_ok=True)
    n = 4
    for i in range(n):
        p = os.path.join(out, "IMG%d.BMP" % (i + 1))
        size = make_one(i, n, p)
        print("生成 %s  (%d 字节, %dx%d 24bit)" % (p, size, W, H))
    print("\n完成。把这些 BMP 拷到 SD 卡根目录即可。")
    print("一张 640x480x3 的图约 900KB，4 张 3.6MB，SD 卡容量无压力。")


if __name__ == "__main__":
    main()
