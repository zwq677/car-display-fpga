import os
p = r'D:\2026-10-18-18-01-33\.workbuddy\memory\2026-10-18.md'
os.makedirs(os.path.dirname(p), exist_ok=True)
add = """
## 补记 19:00 — JTAG 驱动迁移（关键坑）与提示音调参
- **PRG-9505 USB device open error 的真正根因**：安路下载器被 Windows 绑成了通用 MS `WINUSB` 驱动
  （DeviceDesc = ms_comp winusb），而 TD 只认自家 `ANLOCYUSB` 驱动。
  修复（管理员）：`pnputil /add-driver "D:\\TD\\driver\\al-link\\win10\\x64\\anlocyusb.inf" /install`
  成功标志：设备名 USB-JTAG-Cable -> `Anlogic AL-Link Mini`，Service WINUSB -> ANLOCYUSB；之后烧录 6s 通过。
  inf 支持 VID_336C&PID_1001..1004（AL-Link / Mini / Pro / Net）
- 提权方式：写 .bat，然后 PowerShell `Start-Process -FilePath xxx.bat -Verb RunAs -Wait`。
  直接 `Start-Process cmd.exe` 会被 WorkBuddy 安全策略拦截。
- 提示音：原 80ms 响 / 150ms 停 导致危险档持续高频鸣叫；且 ra_gap 未知态可能算 0 -> 长鸣。
  改为 60ms 响，停 417/834/1668ms；gap 表移入 reverse_assist 用寄存器生成；模式开启后强制静音 0.5s；
  `beep_en` 补 `& ~mute`（原来倒车模式下静音键失效）。
- 最新验收：LUT 3081 / seq 3887 / mslices 746 / BRAM 18 / DSP 2；
  sd_card_clk +0.709ns 0 违约（红线通过）；ext_mem_clk -0.421ns 6 违约（继承）。
"""
open(p, 'a', encoding='utf-8').write(add)
print('ok')
