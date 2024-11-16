#import "Basic";
#import "Windows";
#load "modules_additions/Windows.jai";

offscreen_buffer :: struct {
    BitmapInfo : BITMAPINFO;
    memory     : *u8;
    width      : int;
    height     : int;
    pitch      : int;
}

win32_window_dimensions :: struct {
    width  : int;
    height : int;
}

GlobalRunning := true;
GlobalBackBuffer : offscreen_buffer;

get_window_dimensions :: (window: HWND) -> win32_window_dimensions {
    client_rect: RECT;
    GetClientRect(window, *client_rect);
    return .{
        client_rect.right - client_rect.left,
        client_rect.bottom - client_rect.top
    };
}

render_weird_gradient :: (xOffset: int, yOffset: int) {
    row : *u8 = GlobalBackBuffer.memory;
    for y: 0..GlobalBackBuffer.height-1 {
        pixel : *u32 = xx row;
        for x: 0..GlobalBackBuffer.width-1 {
            //                   1  2  3  4
            // pixel in memory: BB GG RR xx  (bc MSFT wanted to see RGB in register (see register)
            //     in register: xx RR GG BB  (bc it's little endian)
            bb := cast (u8)((x + xOffset) % 255);
            gg := cast (u8)((y + yOffset) % 255);
            <<pixel = ((cast(u32) gg) << 8 | bb);
            pixel += 1;
        }

        row += GlobalBackBuffer.pitch;
    }
}

win32_resize_DIB_section :: (width: s32, height: s32) {
    if GlobalBackBuffer.memory  VirtualFree(GlobalBackBuffer.memory, 0, MEM_RELEASE);
    GlobalBackBuffer.width = width;
    GlobalBackBuffer.height = height;
    bytes_per_pixel := 4;
    GlobalBackBuffer.pitch = width * bytes_per_pixel;

    // NOTE: When the biHeight field is negative, this is the clue to Windows to treat this bitmap as top down, not
    // bottom up, meaning that the first 3 bytes of the image are the color for the top left pixel in the bitmap,
    // not the bottom left
    GlobalBackBuffer.BitmapInfo.bmiHeader.biSize        = size_of(type_of(GlobalBackBuffer.BitmapInfo.bmiHeader));
    GlobalBackBuffer.BitmapInfo.bmiHeader.biWidth       = width;
    GlobalBackBuffer.BitmapInfo.bmiHeader.biHeight      = -height;
    GlobalBackBuffer.BitmapInfo.bmiHeader.biPlanes      = 1;
    GlobalBackBuffer.BitmapInfo.bmiHeader.biBitCount    = 32;
    GlobalBackBuffer.BitmapInfo.bmiHeader.biCompression = BI_RGB;

    bitmap_memory_size      := cast(u64) ((GlobalBackBuffer.width * GlobalBackBuffer.height) * bytes_per_pixel);
    GlobalBackBuffer.memory  = VirtualAlloc(null, bitmap_memory_size, MEM_COMMIT, PAGE_READWRITE);
}

win32_display_buffer_in_window :: (deviceContext: HDC, destWidth: int, destHeight: int) {
    // TODO: aspect ratio correction
    StretchDIBits(deviceContext, 0, 0, destWidth, destHeight, 0, 0, GlobalBackBuffer.width, GlobalBackBuffer.height,
                  GlobalBackBuffer.memory, *GlobalBackBuffer.BitmapInfo, DIB_RGB_COLORS, ROP.SRCCOPY);
}

win32_main_window_callback :: (window: HWND, message: u32, WParam: WPARAM, LParam: LPARAM) -> LRESULT #c_call {
    new_context: Context;

    push_context new_context {
        result : LRESULT = 0;

        if message == {
            case WM_CREATE;
            OutputDebugStringA("WM_CREATE\n");

            case WM_SIZE;
            OutputDebugStringA("WM_SIZE\n");

            case WM_DESTROY;
            GlobalRunning = false;
            OutputDebugStringA("WM_DESTROY\n");

            case WM_CLOSE;
            GlobalRunning = false;
            OutputDebugStringA("WM_CLOSE\n");

            case WM_ACTIVATEAPP;
            OutputDebugStringA("WM_ACTIVATEAPP\n");

            case WM_PAINT;
            paint: PAINTSTRUCT;
            deviceContext: HDC            = BeginPaint(window, *paint);
            dims: win32_window_dimensions = get_window_dimensions(window);

            win32_display_buffer_in_window(deviceContext, dims.width, dims.height);
            EndPaint(window, *paint);

            case;
            //            OutputDebugStringA("default\n")
            result = DefWindowProcA(window, message, WParam, LParam);
        }

        return (result);
    }
};

#import "Window_Creation";

#add_context _windows_windowproc :: win32_main_window_callback;
#add_context _windows_windowproc_allocator: Allocator;

//WinMain :: (Instance: HINSTANCE, PrevInstance: HINSTANCE, CommandLine: *u8, ShowCode: int) -> {
main :: () {
    windowHandle := create_window(1280, 720, "Handmade Hero");

    win32_resize_DIB_section(1280, 720);

    // NOTE: since we specified CS_OWNDC (in Window_Creation/windows.jai), we can just get one device context and use it
    // forever because we are not sharing it with anyone.
    deviceContext := GetDC(windowHandle);

    xOffset := 0;
    yOffset := 0;

    message: MSG;
    while (GlobalRunning)
    {
        if PeekMessageA(*message, null, 0, 0, PM_REMOVE) {
            if message.message == WM_QUIT  GlobalRunning = false;

            TranslateMessage(*message);
            DispatchMessageA(*message);
        }

        render_weird_gradient(xOffset, yOffset);

        dims := get_window_dimensions(windowHandle);

        win32_display_buffer_in_window(deviceContext, dims.width, dims.height);

        xOffset += 1;
        yOffset += 2;
    }
}
