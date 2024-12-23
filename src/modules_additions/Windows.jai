RGB :: (r: u8, g: u8, b: u8) -> u32 #expand {
    return cast(u32)r | (cast(u32)g << 8) | (cast(u32)b << 16);
}

COLORREF :: DWORD;
LWA_ALPHA :: 0x00000002;

SetLayeredWindowAttributes :: (hwnd: HWND, crKey: COLORREF, bAlpha: u8, dwFlags: DWORD) -> bool #foreign user32;

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


#scope_file

user32   :: #system_library "user32";
gdi      :: #system_library "Gdi32";
kernel32 :: #system_library "kernel32";
