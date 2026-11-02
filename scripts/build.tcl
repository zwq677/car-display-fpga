# ============================================================
#  车载辅助多媒体显示系统 —— 一键综合+布局布线
# ------------------------------------------------------------
#  运行方式（注意：绝对不要用 td.exe -tcl，必须这样传脚本路径）：
#
#      1) 在命令行里 cd 到交接包根目录（本文件上一级）
#      2) 运行：
#         "C:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/bin/td_commands_prompt.exe" "绝对路径/scripts/build.tcl"
#
#  脚本用 [pwd] 自动取当前目录，所以只要 cd 对了，放哪个盘都不用改路径。
#  但当前目录路径里**不要有中文和空格**，一律用英文路径。
#
#  产物：build/car_hdmi_Runs/phy_1/car_hdmi.bit
# ============================================================

set D [pwd]
puts "PROJDIR: $D"

# 每次全量重建，清掉旧工程。
# 这一步是必须的：create_project 在工程已存在时会报 PRJ-8646 ERROR，
# 然后工具会停在 "td >" 交互提示符上无限等待，看起来像卡死。
if {[file exists "$D/build"]} {
    file delete -force "$D/build"
    puts "CLEANED: old build dir removed"
}

create_project car_hdmi "$D/build" -family EG4 -device EG4S20BG256
open_project "$D/build/car_hdmi.al"

top_module top
add_dir -r "$D/rtl"
add_include_dir "$D/rtl"
add_files "$D/pin.adc"
add_files "$D/timing.sdc"

launch_runs {syn_1 phy_1}
wait_run phy_1

puts "BUILD_DONE"
puts "BITFILE: $D/build/car_hdmi_Runs/phy_1/car_hdmi.bit"
exit
