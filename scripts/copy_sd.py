import shutil, os

src = r"D:\fpga_work\test_bmp"
dst = "E:\\"

files = ["test_800x600.bmp", "test_320x240.bmp", "test_1024x768.bmp"]
for f in files:
    sp = os.path.join(src, f)
    dp = os.path.join(dst, f)
    shutil.copy2(sp, dp)
    print(f"Copied: {f} ({os.path.getsize(dp)//1024}KB)")

print()
print("SD card contents:")
for f in sorted(os.listdir(dst)):
    if f.endswith(".bmp"):
        sz = os.path.getsize(os.path.join(dst, f))
        print(f"  {f} ({sz//1024}KB)")