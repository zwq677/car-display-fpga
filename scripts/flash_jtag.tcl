# ============================================================
#  JTAG 下载到 SRAM —— 调试用，掉电即失效
# ------------------------------------------------------------
#  cd 到交接包根目录后运行：
#  "C:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/bin/td_commands_prompt.exe" "绝对路径/scripts/flash_jtag.tcl"
#
#  注意：这个必须用 td_commands_prompt.exe（TD 主程序）
#        固化 Flash 才用 bw_commands_prompt.exe（BitWriter），两者不可混用
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

puts "PROGRAMMING: $BIT"
download -bit $BIT -chip EG4S20BG256 -cable 0
puts "JTAG_DONE"
exit
