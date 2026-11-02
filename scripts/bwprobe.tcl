set BIT D:/fpga_work/build/car_hdmi_Runs/phy_1/car_hdmi.bit
read_device_id
download -bit $BIT -chip EG4S20BG256
exit
