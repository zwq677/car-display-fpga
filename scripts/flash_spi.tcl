# ============================================================
#  固化到板载 QSPI Flash —— 掉电保存，通电即用（交付用）
# ------------------------------------------------------------
#  cd 到交接包根目录后运行（注意工具是 bw 不是 td！）：
#  "C:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/bin/bw_commands_prompt.exe" "绝对路径/scripts/flash_spi.tcl"
#
#  本板：HX4S20C，配置 Flash = 兆易创新 GD25Q128（16MB / 128Mbit）
#  实测整片擦除+写入约 57 秒，回读校验约 7 秒，总计约 67 秒。
#
#  固化完成后必须断电重上电才会从 Flash 启动。
#  -v 参数会自动追加 verify_spi 回读校验，建议保留。
# ============================================================

set D [pwd]
set BIT "$D/build/car_hdmi_Runs/phy_1/car_hdmi.bit"

# 编译过就用新产物；没编译过就用包里预置的已验证版本，保证一拿到就能烧
if {![file exists $BIT]} {
    set BIT "$D/bit/car_v22_sd_timing_fix.bit"
    puts "NOTE: 未找到编译产物，改用预置比特流"
}
if {![file exists $BIT]} {
    puts "ERROR: 找不到任何比特流，请先运行 scripts/build.tcl"
    exit
}

puts "PROGRAMMING SPI FLASH: $BIT"
download -mode program_spi -v -bit $BIT -chip EG4S20BG256 -cable 0
puts "SPI_FLASH_DONE"
exit
