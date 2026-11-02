# 车载辅助多媒体显示系统（Anlogic EG4S20 FPGA）

基于安路 EG4S20BG256 的车载多媒体显示与倒车辅助系统：从 SD 卡读取 BMP 图像，经 SDRAM 双缓冲送 HDMI 输出 640×480@60，并在倒车模式下叠加俯视车道、距离档位与分级告警，配套 OSD 字幕和 HDMI 内嵌音频提示音。

整个链路在一块 HX4S20C 开发板上跑通，可脱离电脑独立运行（开发板 + HDMI 显示器 + 移动电源）。

## 功能

- **图像轮播**：SD 卡（SPI 模式）按扇区扫描 BMP，24 bit 真彩，宽 16~1024（4 的倍数）、高 16~768，逐扇区匹配文件头，无需文件系统
- **双缓冲显示**：SDRAM 2 M×32 划分两块 1.2 MB 帧缓存（0x00000 / 0x4B000），写侧后台预读、读侧按场切换索引，切换时机在消隐区，无撕裂
- **跨时钟域**：写域与读域（25.175 MHz 像素时钟）各经异步 FIFO 接入 SDRAM 控制器，控制信号用 toggle + 两级同步传递
- **倒车辅助**：四档距离（200 / 120 / 60 / 20 cm）由按键切换，几何按距离反算——车道梯形随距离收窄，四组障碍物色块随距离下移，绿/黄/橙/红分级着色，告警节拍随距离缩短（半周期上限 2/2/5/9 tick）
- **OSD 叠加**：16×16 点阵字模字幕（40 字去重，6 bit 字符索引）+ 32 级音频电平柱条，两级流水完成判定与叠色
- **音频**：48 kHz 采样经 I2S 发送，HDMI 音频包内嵌输出；提示音由片上 ROM 语音数据经双缓冲异步 FIFO 分频播放（ACR 的 N=6144，CTS 计数窗口 48 行）

## 硬件与工具链

| 项目 | 说明 |
| --- | --- |
| 开发板 | 安路 EG4S20BG256（HX4S20C 板） |
| 工具链 | Anlogic TD 6.2.1（版本号 6.2.168.116） |
| 显示器 | 标准 HDMI 输入，640×480@60 |
| 外部存储 | microSD 卡（SPI 模式，4 张 BMP） |
| 时钟 | 板载 50 MHz 晶振 |

时钟分配：`clk` 50 MHz（逻辑）、`ext_mem_clk` 125 MHz（SDRAM）、`video_clk` 25.175 MHz（像素）、`hdmi_5x_clk` 125.875 MHz（TMDS 5 倍）、`aud_clk` 12.288 MHz（音频）、`sd_card_clk` 100 MHz（SD 控制器）。

## 目录结构

```
.
├── rtl/            自研 RTL（Verilog / VHDL）
│   ├── top.v                     顶层：视频链路 + 音频 + OSD 叠加
│   ├── sd_card_*.v               SD 卡 SPI 初始化与扇区读写
│   ├── bmp_read.v                BMP 头匹配与像素读取状态机
│   ├── scaler.v                  最近邻缩放（累加-比较实现）
│   ├── frame_fifo_read/write.v   帧缓存异步 FIFO
│   ├── osd_overlay.v / osd_font.v  字幕与电平柱条叠加、16×16 字模
│   ├── reverse_assist.v          倒车可视化（车道、障碍物、分级告警）
│   ├── audio_*.v / hdmi_audio_tone_i2s_64fs.v  I2S 音频与提示音
│   └── voice_rom.v / voice_rom.hex             片上语音数据
├── scripts/        构建、烧写与辅助脚本（TD tcl + Python）
├── docs/           技术文档（设计说明、时序分析与实测数据）
├── pin.adc         引脚约束（EG4S20BG256）
└── timing.sdc      时钟约束
```

## 编译说明

**本仓库只包含自研 RTL。** HDMI 发送核、SDRAM 控制器与 PLL 属于安路 TD 的加密 IP / 自动生成 IP，受厂商授权约束不能随仓库分发，需要在本地重新生成后才能综合：

1. 在 TD 中新建工程，器件选 `EG4S20BG256`
2. 用 IP Generator 生成以下单元，名称保持一致：
   - `sys_pll`、`video_pll`、`PLL_HDMI_AUDIO`（按上表时钟频率配置）
   - `afifo_16_32_256`、`afifo_32_16_256`（异步 FIFO，位宽 16/32、深度 256）
   - HDMI 1.4b Transmitter Core（含 `DVITransmitter`、`SerializerN_1_lvds`、`SerializerN_1_lvds_dat`、`TMDSEncoder`）
   - SDRAM Controller（2 M×32，含 `sdr_as_ram`、`sdr_init_ref`、`sdr_wrrd`）
3. 将 `rtl/`、`pin.adc`、`timing.sdc` 加入工程
4. 执行一键编译：

```bash
td_commands_prompt.exe "<工程路径>/scripts/build.tcl"
```

> TD 对路径敏感：**工程必须放在纯英文路径下**，中文路径或中文用户名会导致 `couldn't read file`。脚本路径要作为程序参数直接传入，且脚本末尾必须有 `exit`，否则会停在 `td >` 提示符空等。

## 资源与时序

在 EG4S20BG256 上的实现结果（TD 6.2.1，实测）：LUT 9514/19600（48.54%）、寄存器 4380（22.35%）、BRAM 61/64（95.31%）、DSP 2/29（6.90%）、PLL 3/4、全局时钟 3/16、IO 22/188（11.70%），平均扇出 2.95。

时序：`sd_card` 域 WNS +0.117 ns（Fmax 101.18 MHz）、`ext_mem` 域 +0.119 ns（126.89 MHz）、`video` 域 +21.915 ns（55.29 MHz）、`hdmi_5x` 域 +4.509 ns（286.45 MHz）、`clk` 域 +11.033 ns（111.52 MHz）。全局 WNS 为负值，来自跨时钟域路径未被误约束声明，属预期而非真实违例，详见技术文档第 3 章。

## 已知限制

- 距离输入为 2 bit 档位（按键循环切换），不是真实测距；接入传感器属改板范围（22 个可用 IO 已分配完毕）
- 板上无蜂鸣器，提示音走 HDMI 内嵌音频
- 单张 BMP 上限 1024×768，超出会拒绝加载并保持上一帧
- 工程未做 SD 卡热插拔检测，拔插后需复位

## 文档

`docs/车载辅助多媒体显示系统_技术文档.pdf`：设计说明、模块划分、时序分析与实测数据、问题与改进方向。

## 许可证

MIT，见 [LICENSE](LICENSE)。第三方 IP（安路 TD 生成的 PLL / FIFO / HDMI 核 / SDRAM 控制器）不在本许可证范围内，需遵守安路科技的相关授权条款。