# -*- coding: utf-8 -*-
"""
编译结果自动验收。只依赖标准库。

用法（在交接包根目录下）:
    python scripts/verify_build.py

它会去 build/ 里找最新的 final_timing.rpt 和编译日志，输出:
  - 资源占用 (LUT / mslices)
  - 每个时钟域的 SWNS
  - 重点判定 sd_card_clk 域是否满足红线

为什么要专门判定 sd_card_clk 域：
本工程 SD 卡读图的扇区地址计算路径曾经在一个 10ns 周期里串了两个 26bit 加法
加一个 32bit 比较，裕量只有 0.1~0.3ns。这个域一旦裕量转负，现象不是报错，
而是「切图偶发卡住、屏幕整片变黑」，极难从现象反推原因。
所以把 sd_card_clk 域 SWNS >= +0.4ns 且 0 违约作为硬性验收红线。
"""
import os
import re
import sys
import glob


def newest(pattern):
    files = glob.glob(pattern, recursive=True)
    if not files:
        return None
    return max(files, key=os.path.getmtime)


def parse_resources(root):
    """从编译日志里抓 PHY-1001 / RUN-0007 的资源行"""
    log = newest(os.path.join(root, "**", "*.log"))
    if not log:
        return None
    out = None
    with open(log, "r", encoding="utf-8", errors="ignore") as f:
        for line in f:
            if "luts," in line and "mslices" in line:
                out = line.strip()
    return out


def parse_timing(rpt):
    """解析 final_timing.rpt，返回 (全局SWNS, {域: (swNS, 违约端点)})"""
    with open(rpt, "r", encoding="utf-8", errors="ignore") as f:
        txt = f.read()

    g = re.search(r"SWNS:\s*(-?[\d.]+)ns", txt)
    global_wns = float(g.group(1)) if g else None

    domains = {}
    # 每个 Path Group 段里的 "Max : SWNS x.xxxns, STNS ..., N Viol Endpoints"
    for m in re.finditer(
        r"Path Group\s+:\s+(\S+)\s*->\s*(\S+).*?"
        r"Max\s+:\s+SWNS\s+(-?[\d.]+)ns.*?(\d+)\s+Viol Endpoints",
        txt, re.S,
    ):
        src, dst = m.group(1), m.group(2)
        if src != dst:
            continue          # 只看域内路径，跨域多为 CDC 伪路径
        domains[src] = (float(m.group(3)), int(m.group(4)))
    return global_wns, domains


def main():
    root = os.getcwd()
    build = os.path.join(root, "build")
    if not os.path.isdir(build):
        print("[错误] 找不到 build/ 目录。请先在交接包根目录下完成一次编译。")
        return 1

    print("=" * 62)
    res = parse_resources(build)
    print("资源占用:")
    print("  " + (res if res else "(未在日志中找到资源行，可能编译没跑完)"))
    lut = ms = None
    if res:
        m = re.search(r"(\d+)\s+luts", res)
        n = re.search(r"(\d+)\s+mslices", res)
        lut = int(m.group(1)) if m else None
        ms = int(n.group(1)) if n else None

    rpt = newest(os.path.join(build, "**", "final_timing.rpt"))
    if not rpt:
        print("\n[错误] 找不到 final_timing.rpt，编译可能没走到布局布线。")
        return 1

    global_wns, domains = parse_timing(rpt)
    print("\n各时钟域域内时序裕量 (SWNS / 违约端点):")
    order = ["clk", "video_clk", "sd_card_clk", "ext_mem_clk", "hdmi_5x_clk"]
    for name in order:
        if name in domains:
            w, v = domains[name]
            flag = "OK" if v == 0 else "违约!"
            print("  %-14s %+8.3f ns   %3d 端点  %s" % (name, w, v, flag))
    for name, (w, v) in domains.items():
        if name not in order:
            print("  %-14s %+8.3f ns   %3d 端点" % (name, w, v))

    if global_wns is not None:
        print("\n全局 SWNS: %+.3f ns  (历史基线约 -6.7ns，属于继承问题，不影响出图)" % global_wns)

    # ---- 红线判定 ----
    print("\n" + "=" * 62)
    ok = True
    if "sd_card_clk" in domains:
        w, v = domains["sd_card_clk"]
        if v != 0:
            print("[不通过] sd_card_clk 域有 %d 个违约端点 -> 切图会偶发失败/黑屏" % v)
            ok = False
        elif w < 0.4:
            print("[不通过] sd_card_clk 域裕量 %+.3fns < +0.4ns，太薄，换个版本就可能翻负"
                  % w)
            ok = False
        else:
            print("[通过] sd_card_clk 域裕量 %+.3fns，0 违约" % w)
    else:
        print("[不通过] 报告里找不到 sd_card_clk 域")
        ok = False

    if lut is not None and lut > 3200:
        print("[警告] LUT %d 偏高（当前基线 2845），检查是否误加了逻辑" % lut)
    if ms is not None and ms > 480:
        print("[警告] mslices %d 偏高（当前基线 470），布局会变紧" % ms)

    if ok:
        print("\n结论: 编译结果合格，可以烧板验证。")
        return 0
    print("\n结论: 不合格。不要直接拿去烧板，先查上面的问题。")
    return 2


if __name__ == "__main__":
    sys.exit(main())
