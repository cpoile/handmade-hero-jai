BeginPaint :: (hwnd: HWND, lpPaint: LPPAINTSTRUCT) -> HDC #foreign user32;

EndPaint :: (hwnd: HWND, lpPaint: *PAINTSTRUCT) -> bool #foreign user32;

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
