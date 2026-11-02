# NOTICE

本仓库代码以 MIT 许可证发布（见 LICENSE）。

以下组件不随本仓库分发，也不在 MIT 许可证范围内：

- 安路科技（Anlogic）TD 工具生成的加密 IP 与自动生成 IP：HDMI 1.4b 发送核
  （DVITransmitter、SerializerN_1_lvds、SerializerN_1_lvds_dat、TMDSEncoder）、
  SDRAM 控制器（sdr_as_ram、sdr_init_ref、sdr_wrrd）、异步 FIFO
  （afifo_16_32_256、afifo_32_16_256）、PLL（sys_pll、video_pll、PLL_HDMI_AUDIO）。
  这些文件由 TD 生成，版权归安路科技，使用需遵守其授权条款。
- TD 授权文件（*.lic）不属于本仓库内容。

使用者需自行从 TD 生成上述组件后方可综合本工程，具体清单见 README.md 的“编译说明”。
