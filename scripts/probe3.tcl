puts "P1"
set rc [catch {read_device_id} res]
puts "RC=$rc RES=$res"
puts "P2"
set rc2 [catch {download -bit {D:/fpga_work/build/car_hdmi_Runs/phy_1/car_hdmi.bit} -chip EG4S20BG256} res2]
puts "DL_RC=$rc2 RES=$res2"
puts "P3"
exit
