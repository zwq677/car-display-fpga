import ctypes, subprocess
from ctypes import wintypes

setupapi = ctypes.WinDLL('setupapi', use_last_error=True)

GUID = bytes([0xA5,0xDC,0xBF,0x9F,0xEE,0xEE,0x4A,0x6F,0x86,0x38,0x5E,0x36,0x6B,0x8E,0x1F,0x8F])
g = ctypes.create_string_buffer(GUID, 16)

setupapi.SetupDiGetClassDevsW.restype = wintypes.HANDLE
setupapi.SetupDiGetClassDevsW.argtypes = [ctypes.c_void_p, wintypes.LPCWSTR, wintypes.HWND, wintypes.DWORD]
h = setupapi.SetupDiGetClassDevsW(ctypes.byref(g), None, None, 0x12)

class DID(ctypes.Structure):
    _fields_ = [('cb', wintypes.DWORD), ('cls', ctypes.c_char*16), ('dev', wintypes.DWORD), ('res', wintypes.DWORD)]

setupapi.SetupDiEnumDeviceInfo.argtypes = [wintypes.HANDLE, wintypes.DWORD, ctypes.POINTER(DID)]
setupapi.SetupDiGetDeviceInstanceIdW.argtypes = [wintypes.HANDLE, ctypes.POINTER(DID), wintypes.LPWSTR, wintypes.DWORD, ctypes.POINTER(wintypes.DWORD)]
setupapi.SetupDiGetDeviceRegistryPropertyW.argtypes = [wintypes.HANDLE, ctypes.POINTER(DID), wintypes.DWORD, ctypes.POINTER(wintypes.DWORD), ctypes.c_void_p, wintypes.DWORD, ctypes.POINTER(wintypes.DWORD)]

d = DID()
d.cb = ctypes.sizeof(DID)
i = 0
while setupapi.SetupDiEnumDeviceInfo(h, i, ctypes.byref(d)):
    i += 1
    buf = ctypes.create_unicode_buffer(512)
    req = wintypes.DWORD()
    ok = setupapi.SetupDiGetDeviceInstanceIdW(h, ctypes.byref(d), buf, 512, ctypes.byref(req))
    inst = buf.value if ok else '?'
    ds = ctypes.create_unicode_buffer(512)
    setupapi.SetupDiGetDeviceRegistryPropertyW(h, ctypes.byref(d), 0x0C, None, ds, 1024, None)
    if '336C' in inst.upper() or 'JTAG' in ds.value.upper():
        print('INST:', inst)
        print('DESC:', ds.value)

print('--- powercfg/usb ---')
