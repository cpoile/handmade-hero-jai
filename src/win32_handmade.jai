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


SAMPLE_RATE      : s32 : 48000;
BYTES_PER_SAMPLE :: size_of(s16) * 2;
BUFFER_SIZE      :: SAMPLE_RATE * BYTES_PER_SAMPLE;  // 1 second

global_running     := true;
global_back_buffer : Offscreen_Buffer;
dsound_lib         :: #system_library "dsound";
dsound             : *IDirectSound8;
sec_sound_buffer   : *IDirectSoundBuffer8;

Offscreen_Buffer :: struct {
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

win32_sound_output :: struct {
    running_sample_index  : s32 = 0;
    wave_period           : s32 = SAMPLE_RATE/261; // initial value
    latency_sample_count  :: SAMPLE_RATE/15;
}

// Services that the platform layer provides the game
//
#if HANDMADE_INTERNAL {

    // NOTE: These are not for anything in the shipping game.
    //  They are blocking and the write doesn't protect against lost data!

    DEBUG_platform_read_entire_file :: (filename: string) -> memory: []u8, ok: bool {
        fh := CreateFileW(U.utf8_to_wide_new(filename), GENERIC_READ, FILE_SHARE_READ, null, OPEN_EXISTING, 0, null);

        if !fh return .{}, false;

        size_large: LARGE_INTEGER;
        s_res := GetFileSizeEx(fh, *size_large);
        if !s_res {return .{}, false;}

        size := size_large.LowPart;
        assert(size <= U32_MAX);

        raw_mem := VirtualAlloc(null, size, MEM_RESERVE | MEM_COMMIT, PAGE_READWRITE);

        if raw_mem == null {return .{}, false;}

        memory : []u8 = .{size, raw_mem};

        bytes_read: DWORD;
        ok := ReadFile(fh, raw_mem, size, *bytes_read, null);

        if !ok || bytes_read != size {
            DEBUG_platform_free_file_memory(*memory);
            return .{}, false;
        }

        if CloseHandle(fh) == 0 {
            DEBUG_platform_free_file_memory(*memory);
            return .{}, false;
        }

        return memory, true;
    }

    DEBUG_platform_free_file_memory :: (memory: *[]u8) {
        VirtualFree(memory.data, 0, MEM_RELEASE);
        memory.count = 0;
    }
    DEBUG_platform_write_entire_file :: (filename: string, memory: []u8) -> bool {
        fh := CreateFileW(U.utf8_to_wide_new(filename), GENERIC_WRITE, FILE_SHARE_WRITE, null, CREATE_ALWAYS, 0, null);

        if !fh {return false;}

        bytes_written: DWORD;
        ok := WriteFile(fh, memory.data, cast(u32)memory.count, *bytes_written, null);
        if !ok {return false;}

        return bytes_written == memory.count;
    }
}


win32_fill_sound_buffer :: (
    sound_output: *win32_sound_output,
    source_buffer: *Game_Sound_Buffer,
    byte_to_lock: s32,
    bytes_to_write: s32
) {

    //  u16   u16     u16   u16    u16   u16
    // [left right] [left right] [left right]
    region1, region2: *void;
    size1, size2: s32;
    if SUCCEEDED(sec_sound_buffer.Lock(sec_sound_buffer, byte_to_lock, bytes_to_write, *region1, *size1, *region2, *size2, 0)) {
        region1_sample_count : s32 = size1/BYTES_PER_SAMPLE;
        dest_samples := cast(*s16) region1;
        src_samples := source_buffer.samples;
        for 0..region1_sample_count-1 {
            <<dest_samples = <<src_samples;
            dest_samples += 1;
            src_samples  += 1;
            <<dest_samples = <<src_samples;
            dest_samples += 1;
            src_samples  += 1;

            sound_output.running_sample_index += 1 ;
        }

        region2_sample_count : s32 = size2/BYTES_PER_SAMPLE;
        dest_samples = cast(*s16) region2;
        for 0..region2_sample_count-1 {
            <<dest_samples = <<src_samples;
            dest_samples += 1;
            src_samples  += 1;
            <<dest_samples = <<src_samples;
            dest_samples += 1;
            src_samples  += 1;

            sound_output.running_sample_index += 1 ;
        }

        _ = sec_sound_buffer.Unlock(sec_sound_buffer, region1, size1, region2, size2);
    }
}

win32_init_dsound :: (window: HWND) {
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

    KSDATAFORMAT_SUBTYPE_PCM: GUID;
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
    sec_desc.dwBufferBytes = xx BUFFER_SIZE;
    sec_desc.lpwfxFormat   = *wfx.Format;

    hr = dsound.vtable.CreateSoundBuffer(dsound, *sec_desc, *sec_sound_buffer, null);
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

win32_resize_DIB_section :: (back_buffer: *Offscreen_Buffer, width: s32, height: s32) {
    if back_buffer.memory  free(back_buffer.memory);
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

    bitmap_memory_size := ((back_buffer.width * back_buffer.height) * bytes_per_pixel);
    back_buffer.memory = alloc(bitmap_memory_size);
}

win32_display_buffer_in_window :: (back_buffer: *Offscreen_Buffer, deviceContext: HDC, destWidth: int, destHeight: int) {
    // TODO: aspect ratio correction
    StretchDIBits(deviceContext, 0, 0, destWidth, destHeight, 0, 0, back_buffer.width, back_buffer.height,
                  back_buffer.memory, *back_buffer.BitmapInfo, DIB_RGB_COLORS, ROP.SRCCOPY);
}

win32_process_xinput_digital_button :: (
    old_state: Game_Button_State,
    new_state: *Game_Button_State,
    button_bit: u16,
    button_state: u16
) {
    new_state.ended_down = button_state & button_bit != 0;
    new_state.half_transition_count += xx ifx old_state.ended_down != new_state.ended_down  1;
}

#add_context _windows_windowproc :: win32_main_window_callback;
#add_context _windows_windowproc_allocator: Allocator;

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
                assert(false, "Keyboard input came in through a non-dispatch message!");
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

                win32_display_buffer_in_window(*global_back_buffer, device_context, dims.width, dims.height);
                EndPaint(window, *paint);
            }

            case;
                //            OutputDebugStringA("default\n")
                result = DefWindowProcA(window, message, WParam, LParam);
        }

        return (result);
    }
};

win32_process_keyboard_message :: (new_state: *Game_Button_State, isDown: bool) {
    new_state.ended_down = isDown;
    new_state.half_transition_count += 1;
}

win32_process_messages :: (keyboard_controller: *Game_Controller_Input) {
    message: MSG;
    while PeekMessageA(*message, null, 0, 0, PM_REMOVE) {
        if message.message == {
        case WM_QUIT;        global_running = false;
        case WM_SYSKEYDOWN;  #through;
        case WM_SYSKEYUP;    #through;
        case WM_KEYDOWN;     #through;
        case WM_KEYUP;
            vk_code := cast(u32)message.wParam;
            altDown := (message.lParam & (1 << 29)) != 0;
            wasDown := (message.lParam & (1 << 30)) != 0;
            isDown  := (message.lParam & (1 << 31)) == 0;
            if (isDown != wasDown) {
                if vk_code == {
                case VK_F4;      if altDown  global_running = false;
                case #char "W";  win32_process_keyboard_message(*keyboard_controller.up, isDown);
                case #char "R";  win32_process_keyboard_message(*keyboard_controller.down, isDown);
                case #char "A";  win32_process_keyboard_message(*keyboard_controller.left, isDown);
                case #char "S";  win32_process_keyboard_message(*keyboard_controller.right, isDown);
                case #char "Q";  win32_process_keyboard_message(*keyboard_controller.left_shoulder, isDown);
                case #char "F";  win32_process_keyboard_message(*keyboard_controller.right_shoulder, isDown);
                case VK_UP;      win32_process_keyboard_message(*keyboard_controller.up, isDown);
                case VK_DOWN;    win32_process_keyboard_message(*keyboard_controller.down, isDown);
                case VK_LEFT;    win32_process_keyboard_message(*keyboard_controller.left, isDown);
                case VK_RIGHT;   win32_process_keyboard_message(*keyboard_controller.right, isDown);
                case VK_ESCAPE;  global_running = false;
                }
            }
        case;
            TranslateMessage(*message);
            DispatchMessageA(*message);
        }
    }
}

main :: () {
    perf_counter_frequency : s64;   // frequency is per second
    QueryPerformanceFrequency(*perf_counter_frequency);

    window := create_window(1280, 720, "Handmade Hero");

    win32_resize_DIB_section(*global_back_buffer, 1280, 720);
    defer free(global_back_buffer.memory);

    // NOTE: since we specified CS_OWNDC (in Window_Creation/windows.jai), we can just get one device context and use it
    // forever because we are not sharing it with anyone.
    deviceContext := GetDC(window);

    success := init_xinput();
    if !success {
        OutputDebugStringA("Error: Could not initialize xinput!");
        return;
    }

    sound_output : win32_sound_output = .{};
    win32_init_dsound(window);
    // no need to clear the secondary sound buffer in Jai, it's initialized to zero.
    hr := sec_sound_buffer.Play(sec_sound_buffer, 0, 0, DSBPLAY_LOOPING);
    if FAILED(hr) {
        log_error("Play failed!");
    }

    // TODO: pool with bitmap make
    samples := alloc(BUFFER_SIZE);
    defer free(samples);

    // NOTE: Casey uses VirtualAlloc, so I'm going to do the same (for now). We're simulating our own allocator, so why not go raw.

    #if HANDMADE_INTERNAL {
        // in windows 64-bit, first 8 terabytes are reserved for the application
        base_address := cast(*void)TERABYTES(2);
    } else {
        base_address : *void = null;
    }
    permanent_len := MEGABYTES(64);
    temporary_len := GIGABYTES(4);

    // TODO: Handle various memory footprints.
    total_size := permanent_len + temporary_len;
    permanent_mem := VirtualAlloc(base_address, xx total_size, MEM_RESERVE | MEM_COMMIT, PAGE_READWRITE);
    temporary_mem := permanent_mem + permanent_len;

    if (permanent_mem == null || temporary_mem == null) {
        log_error("Could not allocate memory for game, exiting!");
        return;
    }

    game_memory := Game_Memory.{
        permanent = .{permanent_len, permanent_mem},
        temporary = .{temporary_len, temporary_mem},
    };

#if false {
    last_counter: s64;
    last_cycle_count := rdtsc();
    QueryPerformanceCounter(*last_counter);
}

    message: MSG;
    new_input := Game_Input.{};
    old_input := Game_Input.{};

    while (global_running) {
        // zero the keyboard at the start of each frame
        // TODO: we can't zero everything because the up/down state will be wrong (we can't hold down the key)
        keyboard_controller := *new_input.controllers[0];
        <<keyboard_controller = .{};

        win32_process_messages(keyboard_controller);

        // TODO: Should we poll this more frequently?
        for controller_index: 1..XUSER_MAX_COUNT {
            old_controller := *old_input.controllers[controller_index];
            new_controller := *new_input.controllers[controller_index];

            controller_state: XINPUT_STATE;
            if XInputGetState(xx controller_index, *controller_state) == 0 /*ERROR_SUCCESS*/ {
                pad := *controller_state.Gamepad;
                // up := pad.wButtons & XINPUT_GAMEPAD_DPAD_UP;
                // down := pad.wButtons & XINPUT_GAMEPAD_DPAD_DOWN;
                // left := pad.wButtons & XINPUT_GAMEPAD_DPAD_LEFT;
                // right := pad.wButtons & XINPUT_GAMEPAD_DPAD_RIGHT;

                denom : float32 = xx ifx pad.sThumbLX < 0 then 32768 else 32767;
                x := cast(float32)pad.sThumbLX / denom;
                denom = xx ifx pad.sThumbLY < 0 then 32768 else 32767;
                y := cast(float32)pad.sThumbLY / denom;

                new_controller.analog = true;
                new_controller.start_x = old_controller.end_x;
                new_controller.start_y = old_controller.end_y;
                new_controller.min_x = x;
                new_controller.max_x = x;
                new_controller.end_x = x;
                new_controller.min_y = y;
                new_controller.max_y = y;
                new_controller.end_y = y;

                win32_process_xinput_digital_button(old_controller.a, *new_controller.a, pad.wButtons, XINPUT_GAMEPAD_A);
                win32_process_xinput_digital_button(old_controller.b, *new_controller.b, pad.wButtons, XINPUT_GAMEPAD_B);
                win32_process_xinput_digital_button(old_controller.x, *new_controller.x, pad.wButtons, XINPUT_GAMEPAD_X);
                win32_process_xinput_digital_button(old_controller.y, *new_controller.y, pad.wButtons, XINPUT_GAMEPAD_Y);
                win32_process_xinput_digital_button(
                    old_controller.left_shoulder,
                    *new_controller.left_shoulder,
                    pad.wButtons,
                    XINPUT_GAMEPAD_LEFT_SHOULDER,
                );
                win32_process_xinput_digital_button(
                    old_controller.right_shoulder,
                    *new_controller.right_shoulder,
                    pad.wButtons,
                    XINPUT_GAMEPAD_RIGHT_SHOULDER,
                );

                // start := pad.wButtons & XINPUT_GAMEPAD_START;
                // back := pad.wButtons & XINPUT_GAMEPAD_BACK;

                // sound_output.tone_hz = cast(s32)(512 + 256.0*(stick_y / 30000.0));
                // sound_output.wave_period = SAMPLE_RATE/sound_output.tone_hz;
            } else {
                // controller not available
            }
        }

        // DirectSound output test
        byte_to_lock, target_cursor, bytes_to_write, play_cursor, write_cursor: s32;

        // TODO: Tighten up sound logic so that we know where we should be
        // writing to and can anticipate the time spent in the game update.
        hr := sec_sound_buffer.GetCurrentPosition(sec_sound_buffer, *play_cursor, *write_cursor);
        if FAILED(hr) {
            log_error("GetCurrentPosition failed!");
        } else {
            byte_to_lock = (sound_output.running_sample_index * BYTES_PER_SAMPLE) % BUFFER_SIZE;
            target_cursor = (play_cursor + (sound_output.latency_sample_count * BYTES_PER_SAMPLE)) % BUFFER_SIZE;

            if byte_to_lock > target_cursor {
                bytes_to_write = BUFFER_SIZE - byte_to_lock;  // we have this much ahead of us in the buffer to write to
                bytes_to_write += target_cursor;                   // and add the first part of the buffer up to the play cursor
            } else {
                bytes_to_write = target_cursor - byte_to_lock;    // we only have to fill from byte_to_lock up to the play_cursor
            }
        }

        game_sound_buffer := Game_Sound_Buffer.{
            samples_per_second = SAMPLE_RATE,
            samples_count      = bytes_to_write / BYTES_PER_SAMPLE,
            samples            = samples,
        };
        buffer := Game_Offscreen_Buffer.{
            memory = global_back_buffer.memory,
            width  = global_back_buffer.width,
            height = global_back_buffer.height,
            pitch  = global_back_buffer.pitch,
        };
        game_update_and_render(*game_memory, *new_input, *buffer, *game_sound_buffer);
        win32_fill_sound_buffer(*sound_output, *game_sound_buffer, byte_to_lock, bytes_to_write);

        dims := get_window_dimensions(window);

        win32_display_buffer_in_window(*global_back_buffer, deviceContext, dims.width, dims.height);

        // Frame timings
        end_counter: s64;
        QueryPerformanceCounter(*end_counter);

#if false {
        counter_elapsed := end_counter - last_counter;
        ms_elapsed := (1000 * cast(float32) counter_elapsed) / perf_counter_frequency;
        fps := cast(float32)perf_counter_frequency / counter_elapsed;

        // Using rdtsc
        end_cycle_count := rdtsc();
        cycles_elapsed := end_cycle_count - last_cycle_count;
        mcpf := cycles_elapsed / (1000 * 1000);

 #if HANDMADE_INTERNAL {
            log_error("ms_elapsed: %, FPS: %, cycles: % mc\n", ms_elapsed, fps, mcpf);
 }

        last_counter = end_counter;
        last_cycle_count = end_cycle_count;
}
        new_input, old_input = old_input, new_input;
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
U :: #import "Windows_Utf8";
