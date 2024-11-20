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

global_running := true;
GlobalBackBuffer : offscreen_buffer;
dsound_lib :: #system_library "dsound";
dsound: *IDirectSound8;
sec_buffer: *IDirectSoundBuffer8;

win32_init_dsound :: (window: HWND, samples_per_second: u32, buffer_size: s32) {
    primary_buffer: *IDirectSoundBuffer8;

    // load the library
    DirectSoundCreate8 :: (device: *void, ppds8: **IDirectSound8, outer: *void) -> s32 #foreign dsound_lib;
    hr := DirectSoundCreate8(null, *dsound, null);
    if !SUCCEEDED(hr) {
        log_error("DirectSoundCreate8 failed!\n");
        return;
    } else {
        log("DirectSoundCreate8 Worked!\n");
    }

    DSSCL_PRIORITY :: 0x2;
    hr = dsound.SetCooperativeLevel(dsound, window, DSSCL_PRIORITY);
    if !SUCCEEDED(hr) {
        log_error("SetCooperativeLevel failed!\n");
        return;
    }

    dsbd: DSBUFFERDESC;
    dsbd.dwSize        = size_of(DSBUFFERDESC);
    dsbd.dwFlags       = DSBCAPS_PRIMARYBUFFER;
    dsbd.dwBufferBytes = PRIMARY_BUFFER_SIZE_IN_BYTES;

    hr = dsound.CreateSoundBuffer(dsound, *dsbd, *primary_buffer, null);
    if !SUCCEEDED(hr) {
        log_error("CreateSoundBuffer failed!\n");
        return;
    }

    KSDATAFORMAT_SUBTYPE_PCM : GUID;
    init_KSDATAFORMAT_SUBTYPE_PCM(*KSDATAFORMAT_SUBTYPE_PCM);
    WAVE_FORMAT_PCM :: 0x0001;

    wfx: WAVEFORMATEXTENSIBLE;
    wfx.Format.wFormatTag      = WAVE_FORMAT_PCM;
    wfx.Format.nChannels       = 2;
    wfx.Format.wBitsPerSample  = 16;
    wfx.Format.nSamplesPerSec  = OUTPUT_SAMPLING_RATE;
    wfx.Format.nBlockAlign     = (wfx.Format.wBitsPerSample / 8) * wfx.Format.nChannels;
    wfx.Format.nAvgBytesPerSec = wfx.Format.nSamplesPerSec * wfx.Format.nBlockAlign;

    hr = primary_buffer.SetFormat(primary_buffer, *wfx.Format);
    if !SUCCEEDED(hr) {
        log_error("SetFormat failed!\n");
        return;
    }

    // secondary buffer
    sec_desc: DSBUFFERDESC;
    sec_desc.dwSize        = size_of(DSBUFFERDESC);
    sec_desc.dwFlags       = DSBCAPS_CTRLVOLUME | DSBCAPS_GETCURRENTPOSITION2;
    sec_desc.dwBufferBytes = buffer_size;
    sec_desc.lpwfxFormat   = *wfx.Format;

    hr = dsound.vtable.CreateSoundBuffer(dsound, *sec_desc, *sec_buffer, null);
    if !SUCCEEDED(hr) {
        log_error("CreateSoundBuffer failed!\n");
        return;
    }

    log("Secondary buffer succeeded!\n");
}

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
            bb := cast (u8)max(((x + xOffset) % 255), 0);
            gg := cast (u8)max(((y + yOffset) % 255), 0);
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
    GlobalBackBuffer.memory  = VirtualAlloc(null, bitmap_memory_size, MEM_RESERVE|MEM_COMMIT, PAGE_READWRITE);
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

        alt_is_down := false;

        if message == {
            case WM_CREATE;
                OutputDebugStringA("WM_CREATE\n");

            case WM_SIZE;
                OutputDebugStringA("WM_SIZE\n");

            case WM_DESTROY;
                global_running = false;
                OutputDebugStringA("WM_DESTROY\n");

            case WM_SYSKEYDOWN;  #through;
            case WM_SYSKEYUP;    #through;
            case WM_KEYDOWN;     #through;
            case WM_KEYUP; {
                vk_code: u32 = xx WParam;
                altDown := (LParam & (1 << 29)) != 0;
                wasDown := (LParam & (1 << 30)) != 0;
                isDown := (LParam & (1 << 31)) == 0;
                if (isDown != wasDown) {
                    // NOTE: not real code, just a placeholder, later we'll use a switch or something.
                    if vk_code == VK_F4 && altDown  global_running = false;
                    else if vk_code == #char "W"    OutputDebugStringA("W\n");
                    else if vk_code == #char "A"    OutputDebugStringA("A\n");
                    else if vk_code == #char "R"    OutputDebugStringA("R\n");
                    else if vk_code == #char "S"    OutputDebugStringA("S\n");
                    else if vk_code == #char "Q"    OutputDebugStringA("Q\n");
                    else if vk_code == #char "F"    OutputDebugStringA("F\n");
                    else if vk_code == VK_UP        OutputDebugStringA("up\n");
                    else if vk_code == VK_DOWN      OutputDebugStringA("down\n");
                    else if vk_code == VK_LEFT      OutputDebugStringA("left\n");
                    else if vk_code == VK_RIGHT     OutputDebugStringA("Right\n");
                    else if vk_code == VK_ESCAPE    OutputDebugStringA(to_c_string(tprint("Escape is down? % was down? %\n", isDown, wasDown),, temp));
                    else if vk_code == VK_SPACE     OutputDebugStringA("Space\n");
                }
            }

            case WM_CLOSE; {
                global_running = false;
                OutputDebugStringA("WM_CLOSE\n");
            }

            case WM_ACTIVATEAPP;
                OutputDebugStringA("WM_ACTIVATEAPP\n");

            case WM_PAINT; {
                paint: PAINTSTRUCT;
                device_context: HDC            = BeginPaint(window, *paint);
                dims: win32_window_dimensions = get_window_dimensions(window);

                win32_display_buffer_in_window(device_context, dims.width, dims.height);
                EndPaint(window, *paint);
            }

            case;
                //            OutputDebugStringA("default\n")
                result = DefWindowProcA(window, message, WParam, LParam);
        }

        return (result);
    }
};

#add_context _windows_windowproc :: win32_main_window_callback;
#add_context _windows_windowproc_allocator: Allocator;

//WinMain :: (Instance: HINSTANCE, PrevInstance: HINSTANCE, CommandLine: *u8, ShowCode: int) -> {
main :: () {
    window := create_window(1280, 720, "Handmade Hero");

    win32_resize_DIB_section(1280, 720);

    // NOTE: since we specified CS_OWNDC (in Window_Creation/windows.jai), we can just get one device context and use it
    // forever because we are not sharing it with anyone.
    deviceContext := GetDC(window);

    // NOTE: graphics test
    xOffset := 0;
    yOffset := 0;

    // NOTE: sound test
    samples_per_second :: 48000;
    tone_hz := 261;
    volume : s16 = 3000;
    running_sample_index : u32 = 0;
    square_wave_period := samples_per_second/tone_hz;
    half_square_wave_period := square_wave_period/2;
    bytes_per_sample :: size_of(u16)*2;
    sec_buffer_size : u32 = samples_per_second*bytes_per_sample;

    success := init_xinput();
    if !success {
        OutputDebugStringA("Error: Could not initialize xinput!");
        return;
    }

    win32_init_dsound(window, samples_per_second, xx sec_buffer_size);
    hr := sec_buffer.Play(sec_buffer, 0, 0, DSBPLAY_LOOPING);
    if FAILED(hr) {
        log_error("Play failed!");
    }

    message: MSG;
    while (global_running)
    {
        if PeekMessageA(*message, null, 0, 0, PM_REMOVE) {
            if message.message == WM_QUIT  global_running = false;

            TranslateMessage(*message);
            DispatchMessageA(*message);
        }

        // TODO: Should we poll this more frequently?
        for controller_index: 0..XUSER_MAX_COUNT-1 {
            controller_state: XINPUT_STATE;
            if XInputGetState(xx controller_index, *controller_state) == 0 /*ERROR_SUCCESS*/ {
                pad := *controller_state.Gamepad;
                up := pad.wButtons & XINPUT_GAMEPAD_DPAD_UP;
                down := pad.wButtons & XINPUT_GAMEPAD_DPAD_DOWN;
                left := pad.wButtons & XINPUT_GAMEPAD_DPAD_LEFT;
                right := pad.wButtons & XINPUT_GAMEPAD_DPAD_RIGHT;
                start := pad.wButtons & XINPUT_GAMEPAD_START;
                back := pad.wButtons & XINPUT_GAMEPAD_BACK;
                left_shoulder := pad.wButtons & XINPUT_GAMEPAD_LEFT_SHOULDER;
                right_shoulder := pad.wButtons & XINPUT_GAMEPAD_RIGHT_SHOULDER;
                a_button := pad.wButtons & XINPUT_GAMEPAD_A;
                b_button := pad.wButtons & XINPUT_GAMEPAD_B;
                x_button := pad.wButtons & XINPUT_GAMEPAD_X;
                y_button := pad.wButtons & XINPUT_GAMEPAD_Y;

                stick_x := pad.sThumbLX;
                stick_y := pad.sThumbLY;

                xOffset += stick_x >> 12;
                yOffset -= stick_y >> 12;
            } else {
                // controller not available
            }
        }

        // vibration: XINPUT_VIBRATION = .{60000, 60000};
        // XInputSetState(0, *vibration);

        render_weird_gradient(xOffset, yOffset);

        // DirectSound output test
        play_cursor, write_cursor : s32;
        hr := sec_buffer.GetCurrentPosition(sec_buffer, *play_cursor, *write_cursor);
        if FAILED(hr) {
            log_error("GetCurrentPosition failed!");
        } else {
            log_error("running_sample_index: %", running_sample_index);
            bytes_to_lock : u32 = (running_sample_index * bytes_per_sample) % sec_buffer_size;
            bytes_to_write: u32;

             if bytes_to_lock > xx play_cursor {
                bytes_to_write = sec_buffer_size - bytes_to_lock;  // we have this much ahead of us in the buffer to write to
                bytes_to_write += xx play_cursor;                   // and add the first part of the buffer up to the play cursor
            } else {
                bytes_to_write = xx play_cursor - bytes_to_lock;    // we only have to fill from bytes_to_lock up to the play_cursor
            }

            //  u16   u16     u16   u16    u16   u16
            // [left right] [left right] [left right]
            region1, region2: *void;
            size1, size2: s32;
            hr = sec_buffer.Lock(sec_buffer, cast(s32) write_cursor, cast(s32) bytes_to_write,
                                 *region1, *size1, *region2, *size2, 0);

            if FAILED(hr) {
                log_error("Lock failed!");
            } else {
                log_error("GOT LOCK!");
                sample_out := cast(*s16) region1;
                region1_sample_count : s32 = size1/bytes_per_sample;
                for 0..region1_sample_count-1 {
                    sample_value := cast(s16) ifx ((running_sample_index / half_square_wave_period) % 2) volume else -volume;
                    sample_out.* = sample_value;
                    sample_out += 1;
                    sample_out.* = sample_value;
                    sample_out += 1;
                    running_sample_index += 1 ;
                }

                sample_out = xx region2;
                region2_sample_count : s32 = size2/bytes_per_sample;
                for 0..region2_sample_count-1 {
                    sample_value := cast(s16) ifx ((square_wave_period / half_square_wave_period) % 2) volume else -volume;
                    sample_out.* = sample_value;
                    sample_out += 1;
                    sample_out.* = sample_value;
                    sample_out += 1;
                    running_sample_index += 1;
                }

                hr = sec_buffer.Unlock(sec_buffer, region1, size1, region2, size2);
            }
        }


        dims := get_window_dimensions(window);

        win32_display_buffer_in_window(deviceContext, dims.width, dims.height);
    }
}


#import "Window_Creation";
#import "Random";
#import,file "/jai/modules/Gamepad/Xinput.jai";
#import "Sound_Player";
#import "Math";
