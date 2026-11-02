@echo off
REM Anlogic AL-Link USB driver migrate: WINUSB -> ANLOCYUSB
cd /d D:\fpga_work\scripts
pnputil /add-driver "D:\TD\driver\al-link\win10\x64\anlocyusb.inf" /install > drv_add.log 2>&1
pnputil /remove-device "USB\VID_336C&PID_1002\8&42F5850&0&2" > drv_rm.log 2>&1
pnputil /scan-devices > drv_scan.log 2>&1
timeout /t 6 /nobreak > nul
pnputil /enum-devices /instanceid "USB\VID_336C&PID_1002\8&42F5850&0&2" > drv_after.log 2>&1
echo DONE > drv_done.flag
