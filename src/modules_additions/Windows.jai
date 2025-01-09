RGB :: (r: u8, g: u8, b: u8) -> u32 #expand {
    return cast(u32)r | (cast(u32)g << 8) | (cast(u32)b << 16);
}

COLORREF  :: DWORD;
LWA_ALPHA :: 0x00000002;

SetLayeredWindowAttributes :: (hwnd: HWND, crKey: COLORREF, bAlpha: u8, dwFlags: DWORD) -> bool #foreign user32;

GET_FILEEX_INFO_LEVELS :: u8;
GetFileExInfoStandard  :: 0x0;

WIN32_FILE_ATTRIBUTE_DATA :: struct {
  dwFileAttributes : DWORD;
  ftCreationTime   : FILETIME;
  ftLastAccessTime : FILETIME;
  ftLastWriteTime  : FILETIME;
  nFileSizeHigh    : DWORD;
  nFileSizeLow     : DWORD;
}
GetFileAttributesExW :: (lpFileName: *u16, fInfoLevelId: GET_FILEEX_INFO_LEVELS, lpFileInformation: *void) -> bool #foreign kernel32;

// from: https://github.com/luzexi/MinGW/blob/master/x86/include/winioctl.h
CTL_CODE :: (t: u32, f: u32, m: u32, a: u32) -> u32 {
    return (t << 16) | (a << 14) | (f << 2) | m;
}

FILE_DEVICE_FILE_SYSTEM :: 9;
METHOD_BUFFERED         :: 0;
FILE_ANY_ACCESS         :: 0x00000000;
FILE_SPECIAL_ACCESS     :: FILE_ANY_ACCESS;

FSCTL_SET_SPARSE : u32 : #run CTL_CODE(FILE_DEVICE_FILE_SYSTEM, 49, METHOD_BUFFERED, FILE_SPECIAL_ACCESS);


DeviceIoControl ::(hDevice: HANDLE, dwIoControlCode: DWORD, lpInBuffer: *void, nInBufferSize: DWORD,
    lpOutBuffer: *void, nOutBufferSize: DWORD, lpBytesReturned: *u32, lpOverlapped: *void) -> bool #foreign kernel32;

CompareFileTime :: (lpFileTime1: *FILETIME, lpFileTime2: *FILETIME) -> s32 #foreign kernel32;

BeginPaint :: (hwnd: HWND, lpPaint: LPPAINTSTRUCT) -> HDC #foreign user32;

EndPaint :: (hwnd: HWND, lpPaint: *PAINTSTRUCT) -> bool #foreign user32;

MAKEINTRESOURCEW :: (i: u32) -> *u16 { return cast(*u16)i; }

PAINTSTRUCT :: struct {
  hdc:  HDC;
  fErase: bool;
  rcPaint: RECT;
  fRestore: bool;
  fIncUpdate: bool;
  rgbReserved: [32]u8;
}
PPAINTSTRUCT :: PAINTSTRUCT;
NPPAINTSTRUCT :: *PAINTSTRUCT;
LPPAINTSTRUCT :: *PAINTSTRUCT;

StretchDIBits :: (hdc: HDC, xDest: int, yDest: int, DestWidth: int, DestHeight: int, xSrc: int, ySrc: int, SrcWidth: int, SrcHeight: int, lpBits: *void, lpbmi: *BITMAPINFO, iUsage: u32, rop: ROP) -> int #foreign gdi;

LockSetForegroundWindow :: (hwnd: HWND) -> bool #foreign user32;
SetForegroundWindow :: (hWnd: HWND) -> bool #foreign user32;
SetFocus :: (hWnd: HWND) -> HWND #foreign user32;
BringWindowToTop :: (hWnd: HWND) -> HWND #foreign user32;

#scope_file

user32   :: #system_library "user32";
gdi      :: #system_library "Gdi32";
kernel32 :: #system_library "kernel32";
