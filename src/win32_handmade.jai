/* TODO: This is not the final platform layer!

  - Saved game locations
  - Getting a handle to our own executable file
  - Asset loading path
  - Threading (launch a thread)
  - Raw input (support for multiple keyboards)
  - Sleep/timeBeginPeriod
  - ClipCursor() (for muliple monitor supprot)
  - Fullscreen support
  - WM_SETCURSOR (control cursor visibility)
  - QueryCancelAutoplay
  - WM_ACTIVATEAPP (for when we are not the active application)
  - Blit speed improvements (BitBlt)
  - Hardware acceleration (OpenGL or Direct3D or BOTH??)
  - GetKeyboardLayout (for French keyboards, international WASD support)

  Just a partial list of stuff!
*/


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
GlobalBackBuffer :offscreen_buffer;
dsound_lib :: #system_library "dsound";
dsound: *IDirectSound8;
sec_buffer: *IDirectSoundBuffer8;

win32_init_dsound :: (window: HWND, samples_per_second: u32, buffer_size: s32) {
    primary_buffer: *IDirectSoundBuffer8;

    // load the library
    DirectSoundCreate8 :: (device: *void, ppds8: **IDirectSound8, outer: *void) -> s32 #foreign dsound_lib;
    hr := DirectSoundCreate8(null, *dsound, null);
    if FAILED(hr) {
        log_error("DirectSoundCreate8 failed!\n");
        return;
    } else {
        log("DirectSoundCreate8 Worked!\n");
    }

    DSSCL_PRIORITY :: 0x2;
    hr = dsound.SetCooperativeLevel(dsound, window, DSSCL_PRIORITY);
    if FAILED(hr) {
        log_error("SetCooperativeLevel failed!\n");
        return;
    }

    dsbd: DSBUFFERDESC;
    dsbd.dwSize        = size_of(DSBUFFERDESC);
    dsbd.dwFlags       = DSBCAPS_PRIMARYBUFFER;
    dsbd.dwBufferBytes = PRIMARY_BUFFER_SIZE_IN_BYTES;

    hr = dsound.CreateSoundBuffer(dsound, *dsbd, *primary_buffer, null);
    if FAILED(hr) {
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
    if FAILED(hr) {
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
    if FAILED(hr) {
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

win32_resize_DIB_section :: (back_buffer: *offscreen_buffer, width: s32, height: s32) {
    if back_buffer.memory  VirtualFree(back_buffer.memory, 0, MEM_RELEASE);
    back_buffer.width = width;
    back_buffer.height = height;
    bytes_per_pixel := 4;
    back_buffer.pitch = width * bytes_per_pixel;

    // NOTE: When the biHeight field is negative, this is the clue to Windows to treat this bitmap as top down, not
    // bottom up, meaning that the first 3 bytes of the image are the color for the top left pixel in the bitmap,
    // not the bottom left
    back_buffer.BitmapInfo.bmiHeader.biSize        = size_of(type_of(back_buffer.BitmapInfo.bmiHeader));
    back_buffer.BitmapInfo.bmiHeader.biWidth       = width;
    back_buffer.BitmapInfo.bmiHeader.biHeight      = -height;
    back_buffer.BitmapInfo.bmiHeader.biPlanes      = 1;
    back_buffer.BitmapInfo.bmiHeader.biBitCount    = 32;
    back_buffer.BitmapInfo.bmiHeader.biCompression = BI_RGB;

    bitmap_memory_size      := cast(u64) ((back_buffer.width * back_buffer.height) * bytes_per_pixel);
    back_buffer.memory  = VirtualAlloc(null, bitmap_memory_size, MEM_RESERVE|MEM_COMMIT, PAGE_READWRITE);
}

win32_display_buffer_in_window :: (back_buffer: *offscreen_buffer, deviceContext: HDC, destWidth: int, destHeight: int) {
    // TODO: aspect ratio correction
    StretchDIBits(deviceContext, 0, 0, destWidth, destHeight, 0, 0, back_buffer.width, back_buffer.height,
                  back_buffer.memory, *back_buffer.BitmapInfo, DIB_RGB_COLORS, ROP.SRCCOPY);
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

                win32_display_buffer_in_window(*GlobalBackBuffer, device_context, dims.width, dims.height);
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

win32_sound_output :: struct {
    samples_per_second :: 48000;
    tone_hz : float32 = 261;  // middle C
    volume : s16 = 10000;
    running_sample_index : u32 = 0;
    wave_period : float32 = samples_per_second/261; // initial value
    bytes_per_sample :: size_of(u16)*2;
    sec_buffer_size : u32 = samples_per_second*bytes_per_sample;
    tSine : float32;
    latency_sample_count :: samples_per_second/20;
}

win32_fill_sound_buffer :: (sound_output: *win32_sound_output, byte_to_lock: u32, bytes_to_write: u32) {
    //  u16   u16     u16   u16    u16   u16
    // [left right] [left right] [left right]
    region1, region2: *void;
    size1, size2: s32;
    hr := sec_buffer.Lock(sec_buffer, cast(s32) byte_to_lock, cast(s32) bytes_to_write,
                         *region1, *size1, *region2, *size2, 0);

    if SUCCEEDED(hr) {
        region1_sample_count : s32 = size1/sound_output.bytes_per_sample;
        sample_out := cast(*s16) region1;
        for 0..region1_sample_count-1 {
            sine_val := sin(sound_output.tSine);
            sample_value : s16 = xx (sine_val * sound_output.volume);
            sample_out.* = sample_value;
            sample_out += 1;
            sample_out.* = sample_value;
            sample_out += 1;

            sound_output.tSine += 2.0 * PI / sound_output.wave_period;
            sound_output.running_sample_index += 1 ;
        }

        region2_sample_count : s32 = size2/sound_output.bytes_per_sample;
        sample_out = cast(*s16) region2;
        for 0..region2_sample_count-1 {
            sine_val := sin(sound_output.tSine);
            sample_value : s16 = xx (sine_val * sound_output.volume);
            sample_out.* = sample_value;
            sample_out += 1;
            sample_out.* = sample_value;
            sample_out += 1;

            sound_output.tSine += 2.0 * PI / sound_output.wave_period;
            sound_output.running_sample_index += 1;
        }

        hr = sec_buffer.Unlock(sec_buffer, region1, size1, region2, size2);
    }
}

main :: () {
    perf_counter_frequency : s64;   // frequency is per second
    QueryPerformanceFrequency(*perf_counter_frequency);

    window := create_window(1280, 720, "Handmade Hero");

    win32_resize_DIB_section(*GlobalBackBuffer, 1280, 720);

    // NOTE: since we specified CS_OWNDC (in Window_Creation/windows.jai), we can just get one device context and use it
    // forever because we are not sharing it with anyone.
    deviceContext := GetDC(window);

    // NOTE: graphics test
    xOffset := 0;
    yOffset := 0;

    success := init_xinput();
    if !success {
        OutputDebugStringA("Error: Could not initialize xinput!");
        return;
    }

    sound_output : win32_sound_output = .{};
    win32_init_dsound(window, sound_output.samples_per_second, xx sound_output.sec_buffer_size);
    win32_fill_sound_buffer(*sound_output, 0, sound_output.latency_sample_count * sound_output.bytes_per_sample);

    hr := sec_buffer.Play(sec_buffer, 0, 0, DSBPLAY_LOOPING);
    if FAILED(hr) {
        log_error("Play failed!");
    }

    last_counter: s64;
    last_cycle_count := rdtsc();
    QueryPerformanceCounter(*last_counter);

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

                // NOTE: we will do deadzone handling later:
                // XINPUT_GAMEPAD_RIGHT_THUMB_DEADZONE
                // XINPUT_GAMEPAD_LEFT_THUMB_DEADZONE
                xOffset += stick_x / 4096;
                yOffset -= stick_y / 4096;

                sound_output.tone_hz = 512 + 256.0*(stick_y / 30000.0);
                sound_output.wave_period = sound_output.samples_per_second/sound_output.tone_hz;
            } else {
                // controller not available
            }
        }

        // vibration: XINPUT_VIBRATION = .{60000, 60000};
        // XInputSetState(0, *vibration);

        buffer := game_offscreen_buffer.{
            memory = GlobalBackBuffer.memory,
            width = GlobalBackBuffer.width,
            height = GlobalBackBuffer.height,
            pitch = GlobalBackBuffer.pitch,
        };
        game_update_and_render(*buffer, xOffset, yOffset);

        // DirectSound output test
        play_cursor, write_cursor : s32;
        hr := sec_buffer.GetCurrentPosition(sec_buffer, *play_cursor, *write_cursor);
        if FAILED(hr) {
            log_error("GetCurrentPosition failed!");
        } else {
            byte_to_lock : u32 = (sound_output.running_sample_index * sound_output.bytes_per_sample) % sound_output.sec_buffer_size;
            target_cursor := xx (play_cursor + (sound_output.latency_sample_count * sound_output.bytes_per_sample)) % sound_output.sec_buffer_size;
            bytes_to_write: u32;

            if byte_to_lock > xx target_cursor {
                bytes_to_write = sound_output.sec_buffer_size - byte_to_lock;  // we have this much ahead of us in the buffer to write to
                bytes_to_write += xx target_cursor;                   // and add the first part of the buffer up to the play cursor
            } else {
                bytes_to_write = xx target_cursor - byte_to_lock;    // we only have to fill from byte_to_lock up to the play_cursor
            }

            win32_fill_sound_buffer(*sound_output, byte_to_lock, bytes_to_write);
        }

        dims := get_window_dimensions(window);

        win32_display_buffer_in_window(*GlobalBackBuffer, deviceContext, dims.width, dims.height);

        // Frame timings
        end_counter: s64;
        QueryPerformanceCounter(*end_counter);

        counter_elapsed := end_counter - last_counter;
        ms_elapsed := (1000 * cast(float32) counter_elapsed) / perf_counter_frequency;
        fps := cast(float32)perf_counter_frequency / counter_elapsed;

        // Using rdtsc
        end_cycle_count := rdtsc();
        cycles_elapsed := end_cycle_count - last_cycle_count;
        mcpf := cycles_elapsed / (1000 * 1000);

        log_error("ms_elapsed: %, FPS: %, cycles: % mc\n", ms_elapsed, fps, mcpf);

        last_counter = end_counter;
        last_cycle_count = end_cycle_count;
    }
}

#load "handmade.jai";
#import "Basic";
#import "Windows";
#load "modules_additions/Windows.jai";
#import "Window_Creation";
#import "Random";
#import,file "/jai/modules/Gamepad/Xinput.jai";
#import "Sound_Player";
#import "Math";
#import "Machine_X64";
