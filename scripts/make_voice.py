# -*- coding: utf-8 -*-
"""
倒车语音播报 ROM 生成脚本（预警词版）
流程：edge-tts 合成 -> miniaudio 解码 -> 裁剪静音 -> 抗混叠低通重采样 -> 峰值归一化 -> 8bit hex

文案（预警词，距离越近越紧急）：
  200cm -> "安全"
  120cm -> "注意"
  60cm  -> "小心"
  20cm  -> "危险"
采样率 16kHz，音色 zh-CN-XiaoxiaoNeural（晓晓女声，甜美清晰柔和）
"""
import asyncio
import io
import os
import struct
import numpy as np
import miniaudio
import edge_tts

SRC_DIR = r"D:\fpga_work\voice"
OUT_HEX = r"D:\fpga_work\voice_rom.hex"
RTL_HEX = r"D:\fpga_work\rtl\voice_rom.hex"

VOICE = "zh-CN-XiaoxiaoNeural"
RATE = "-8%"           # 稍慢，字正腔圆
TARGET_RATE = 16000    # 16kHz（96kHz 帧率的整数分频 HOLD=6，频带 8kHz）
TEXTS = ["安全", "注意", "小心", "危险"]

# 静音裁剪阈值（绝对值，相对满幅 32767 的比例很小）
SIL_THR = 300
# 峰值归一化目标（8bit 有符号，留余量避免削顶）
PEAK = 100


async def synth(text: str, out_mp3: str):
    com = edge_tts.Communicate(text, VOICE, rate=RATE)
    await com.save(out_mp3)


def load_pcm(mp3_path):
    """用 miniaudio 解码 MP3 -> float32 numpy 数组（-1..1）"""
    raw = miniaudio.mp3_read_file_f32(mp3_path)
    # raw: (nchannels, nsamples) 或 (nsamples,) 的 float32
    arr = np.array(raw.samples, dtype=np.float32)
    if raw.nchannels == 2:
        arr = arr.reshape(-1, 2).mean(axis=1)  # 左右平均 -> 单声道
    else:
        arr = arr.reshape(-1)
    return arr, raw.sample_rate


def trim_silence(pcm: np.ndarray, thr=SIL_THR):
    """裁剪首尾静音，按绝对值阈值（float 幅度 -1..1，thr 对应 int16 满幅）"""
    a = np.abs(pcm)
    nz = np.where(a > thr / 32767.0)[0]
    if len(nz) == 0:
        return pcm
    return pcm[nz[0]:nz[-1] + 1]


def resample(pcm: np.ndarray, src_rate: int, dst_rate: int):
    """抗混叠重采样：先 FFT 低通到目标奈奎斯特，再线性插值降采样

    关键：直接从 24kHz 插值到 16kHz 会把 8~12kHz 的高频成分混叠回 4~8kHz，
    产生刺耳破音（"炸麦"）。必须先低通滤波再降采样。
    """
    if src_rate == dst_rate:
        return pcm

    # 1) 抗混叠低通：截止到 dst 奈奎斯特的 0.92 倍（留过渡带）
    cutoff = dst_rate / 2.0 * 0.92
    n = len(pcm)
    spec = np.fft.rfft(pcm)
    freqs = np.fft.rfftfreq(n, 1.0 / src_rate)
    spec[freqs > cutoff] = 0.0
    lowpassed = np.fft.irfft(spec, n).astype(np.float32)

    # 2) 线性插值降采样
    n_out = int(round(n * dst_rate / src_rate))
    x_old = np.linspace(0.0, n - 1, n)
    x_new = np.linspace(0.0, n - 1, n_out)
    return np.interp(x_new, x_old, lowpassed).astype(np.float32)


def normalize(pcm: np.ndarray, peak=PEAK):
    """峰值归一化到 ±peak"""
    m = np.max(np.abs(pcm))
    if m < 1e-6:
        return pcm
    return pcm * (peak / m)


def to_s8(pcm: np.ndarray):
    """float(-1..1) -> int8 有符号 (-128..127)，clamp 防溢出"""
    v = np.round(pcm).astype(np.int32)
    v = np.clip(v, -128, 127)
    return v.astype(np.int8)


def main():
    os.makedirs(SRC_DIR, exist_ok=True)

    # 1) 合成 MP3（v5 = 晓晓女声）
    mp3s = []
    for i, t in enumerate(TEXTS):
        mp3 = os.path.join(SRC_DIR, f"v5_{i}.mp3")
        if not os.path.exists(mp3):
            asyncio.run(synth(t, mp3))
        mp3s.append(mp3)
        print(f"[synth] seg{i} '{t}' -> {mp3}")

    # 2) 解码 + 裁剪 + 重采样 + 归一化
    segs = []
    for i, mp3 in enumerate(mp3s):
        pcm, sr = load_pcm(mp3)
        pcm = trim_silence(pcm)
        pcm = resample(pcm, sr, TARGET_RATE)
        pcm = normalize(pcm)
        s8 = to_s8(pcm)
        segs.append(s8)
        print(f"[seg{i}] '{TEXTS[i]}' src={sr}Hz -> {TARGET_RATE}Hz, "
              f"len={len(s8)} ({len(s8)/TARGET_RATE*1000:.0f}ms)")

    # 3) 紧凑布局（无对齐填充）+ 生成 hex
    ALIGN = 1
    base = [0, 0, 0, 0]
    cur = 0
    for i in range(4):
        base[i] = cur
        cur += len(segs[i])
    total = cur

    # 布局敏感性 padding：语音 ROM 的数据量会不可预测地影响整个芯片的布局，
    # 某些数据量（如 26.3KB）会把 SD 读图跨域路径推崩导致黑屏。
    # 已知"好布局"的数据量：云希版 32282（50 EMB）、女声版 35611（61 EMB）。
    # 故把总深度 padding 到 32282（与好布局的云希版一致），末尾补静音中点 0x80。
    PAD_TO = 32282
    if total < PAD_TO:
        pad_n = PAD_TO - total
        total = PAD_TO
        print(f"[layout] padding {pad_n} 静音样本 -> 总深度 {total}（对齐好布局的 EMB 占用）")

    addr_bits = max(15, int(np.ceil(np.log2(total + 1))))
    print(f"[layout] base={[hex(b) for b in base]}, total={total}, addr_bits={addr_bits}")

    # 写 hex（每行 8bit 十六进制），未覆盖区域为 0x80（静音中点）
    mem = np.full(total, 0x80, dtype=np.uint8)
    for i in range(4):
        s8 = segs[i]
        mem[base[i]:base[i] + len(s8)] = (s8.astype(np.uint8) & 0xFF)

    lines = []
    for v in mem:
        lines.append(f"{v:02X}")
    hexstr = "\n".join(lines) + "\n"

    for path in (OUT_HEX, RTL_HEX):
        with open(path, "w") as f:
            f.write(hexstr)
        print(f"[hex] {path} ({len(lines)} samples)")

    # 打印段参数（供 voice_player.v 使用）
    print("\n=== 段参数（填入 voice_player.v）===")
    for i in range(4):
        print(f"  seg{i}: base=0x{base[i]:05X}, len={len(segs[i])}")
    print(f"  总深度={total}, 地址位宽={addr_bits}bit, "
          f"数据量={total/1024:.1f}KB")


if __name__ == "__main__":
    main()
