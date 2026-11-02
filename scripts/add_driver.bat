@echo off
cd /d D:\fpga_work\scripts
del drv_done.flag 2>nul
pnputil /add-driver "D:\TD\driver\al-link\win10\x64\anlocyusb.inf" /install > drv_add.log 2>&1
echo ADD_EXIT=%errorlevel% >> drv_done.flag
pnputil /enum-drivers > drv_list.log 2>&1
echo LIST_EXIT=%errorlevel% >> drv_done.flag
echo DONE >> drv_done.flag
