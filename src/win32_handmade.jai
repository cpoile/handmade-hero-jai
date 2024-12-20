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


SAMPLE_RATE               : s32 : 48000;
BYTES_PER_SAMPLE          :: size_of(s16) * 2;
SOUND_BUFFER_SIZE         :: SAMPLE_RATE * BYTES_PER_SAMPLE;  // 1 second
FRAMES_OF_AUDIO_LATENCY   :: 3;
// TODO: how do we reliably query this on Windows?
MONITOR_REFRESH_HZ        :: 60;
GAME_UPDATE_HZ            :: 30;
TARGET_MS_PER_GAME_UPDATE :: 1000 / cast(float32)GAME_UPDATE_HZ;
TARGET_SECONDS_PER_FRAME  :: 1 / cast(float32)GAME_UPDATE_HZ;
LATENCY_SAMPLE_COUNT      :: FRAMES_OF_AUDIO_LATENCY * (SAMPLE_RATE / GAME_UPDATE_HZ);
// TODO: compute to see how low we can go
SAFETY_BYTES              :: ((SAMPLE_RATE * BYTES_PER_SAMPLE) / GAME_UPDATE_HZ) / 3;

global_running           := true;
global_pause             := false;
global_back_buffer       : Offscreen_Buffer;
dsound_lib               :: #system_library "dsound";
dsound                   : *IDirectSound8;
global_sound_buffer      : *IDirectSoundBuffer8;
global_perf_counter_freq : s64;

Offscreen_Buffer :: struct {
    BitmapInfo      : BITMAPINFO;
    memory          : *u8;
    bytes_per_pixel :: 4;
    width           : s32;  // this is what RECT is in
    height          : s32;
    pitch           : s32;
}

Win32_Window_Dimensions :: struct {
    width  : s32;  // this is what RECT is in
    height : s32;
}

Win32_Sound_Output :: struct {
    running_sample_index  : s32 = 0;
    wave_period           : s32 = SAMPLE_RATE/261;
}

Win32_Game_Code :: struct {
    game_code_dll     : HMODULE;
    update_and_render : Game_Update_And_Render;
    get_sound_samples : Game_Get_Sound_Samples;
    is_valid          : bool;
}


// Load the platform-independent game code
win32_load_game_code :: () -> Win32_Game_Code {
    success := CopyFileW(U.utf8_to_wide_new("handmade.dll"), U.utf8_to_wide_new("handmade_copy.dll"), 0);
    if !success {
        log_error("could not copy handmade.dll");
        return .{};
    }
    game_code_dll := LoadLibraryW(U.utf8_to_wide_new("handmade_copy.dll",, temp));
    if game_code_dll == null  return .{};

    ret := Win32_Game_Code.{
        game_code_dll = game_code_dll,
        update_and_render = GetProcAddress(game_code_dll, to_c_string("game_update_and_render",, temp)),
        get_sound_samples = GetProcAddress(game_code_dll, to_c_string("game_get_sound_samples",, temp)),
    };
    ret.is_valid = ret.update_and_render != null && ret.get_sound_samples != null;

    if ret.is_valid {
        log_error("successfully loaded game!");
    } else {
        log_error("failed to load game. :(");
    }

    return ret;
}

win32_unload_game_code :: (game_code: *Win32_Game_Code) -> bool {
    success := FreeLibrary(game_code.game_code_dll);
    if !success  {
        log_error("failed to unload game code");
        return false;
    }

    game_code.game_code_dll = null;
    game_code.update_and_render = null;
    game_code.get_sound_samples = null;
    return true;
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
    sound_output: *Win32_Sound_Output,
    source_buffer: *Game_Sound_Buffer,
    byte_to_lock: s32,
    bytes_to_write: s32
) {

    //  u16   u16     u16   u16    u16   u16
    // [left right] [left right] [left right]
    region1, region2: *void;
    size1, size2: s32;
    if SUCCEEDED(global_sound_buffer.Lock(global_sound_buffer, byte_to_lock, bytes_to_write, *region1, *size1, *region2, *size2, 0)) {
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

        _ = global_sound_buffer.Unlock(global_sound_buffer, region1, size1, region2, size2);
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
    sec_desc.dwBufferBytes = xx SOUND_BUFFER_SIZE;
    sec_desc.lpwfxFormat   = *wfx.Format;

    hr = dsound.vtable.CreateSoundBuffer(dsound, *sec_desc, *global_sound_buffer, null);
    if FAILED(hr) {
        log_error("CreateSoundBuffer failed!\n");
        return;
    }

    log("Secondary buffer succeeded!\n");
}

get_window_dimensions :: (window: HWND) -> Win32_Window_Dimensions {
    client_rect: RECT;
    GetClientRect(window, *client_rect);
    return .{
        client_rect.right - client_rect.left,
        client_rect.bottom - client_rect.top
    };
}

win32_resize_DIB_section :: (buffer: *Offscreen_Buffer, width: s32, height: s32) {
    if buffer.memory  free(buffer.memory);
    buffer.width = width;
    buffer.height = height;
    buffer.pitch = width * buffer.bytes_per_pixel;

    // NOTE: When the biHeight field is negative, this is the clue to Windows to treat this bitmap as top down, not
    // bottom up, meaning that the first 3 bytes of the image are the color for the top left pixel in the bitmap,
    // not the bottom left
    buffer.BitmapInfo.bmiHeader.biSize        = size_of(type_of(buffer.BitmapInfo.bmiHeader));
    buffer.BitmapInfo.bmiHeader.biWidth       = width;
    buffer.BitmapInfo.bmiHeader.biHeight      = -height;
    buffer.BitmapInfo.bmiHeader.biPlanes      = 1;
    buffer.BitmapInfo.bmiHeader.biBitCount    = 32;
    buffer.BitmapInfo.bmiHeader.biCompression = BI_RGB;

    bitmap_memory_size := ((buffer.width * buffer.height) * buffer.bytes_per_pixel);
    buffer.memory = alloc(bitmap_memory_size);
}

win32_display_buffer_in_window :: (buffer: *Offscreen_Buffer, deviceContext: HDC, destWidth: int, destHeight: int) {
    // TODO: aspect ratio correction
    StretchDIBits(deviceContext, 0, 0, destWidth, destHeight, 0, 0, buffer.width, buffer.height,
                  buffer.memory, *buffer.BitmapInfo, DIB_RGB_COLORS, ROP.SRCCOPY);
}

win32_debug_draw_vertical :: (back_buffer: *Offscreen_Buffer, x: s32, top: s32, bottom: s32, color: u32) {
    pixel := back_buffer.memory + (x * back_buffer.bytes_per_pixel + top * back_buffer.pitch);
    for y: top .. bottom-1 {
        <<cast(*u32)pixel = color;
        pixel += back_buffer.pitch;
    }
}

win32_debug_sync_display :: (back_buffer: *Offscreen_Buffer, last_play_cursor_count: u16, last_play_cursors: []s32,
    sound_output: *Win32_Sound_Output) {
    // TODO: draw where we're writing out sound  --  doesn't match Casey's code in this proc

    pad_x  : s32 = 16;
    pad_y  : s32 = 16;
    top    : s32 = pad_y;
    bottom : s32 = back_buffer.height - 16;

    // remember Casey's talk on dimentional analysis: to change something mapped in sound buffer size into back_buffer size,
    // mult by coefficient C. The sound buffer sized thing cancels out with the denominator, leaving back_buffer units.
    C := cast(float32)(back_buffer.width - 2 * pad_x) / cast(float32)SOUND_BUFFER_SIZE;
    for i: 0..last_play_cursors.count-1 {
        last_play_cursor := last_play_cursors[i];
        x := pad_x + cast(s32)(C * cast(float32)last_play_cursor);
        win32_debug_draw_vertical(back_buffer, x, top, bottom, 0xFFFFFFFF);
    }
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
                win32_debug("WM_CREATE\n");

            case WM_SIZE;
                win32_debug("WM_SIZE\n");

            case WM_DESTROY;
                global_running = false;
                win32_debug("WM_DESTROY\n");

            case WM_SYSKEYDOWN;  #through;
            case WM_SYSKEYUP;    #through;
            case WM_KEYDOWN;     #through;
            case WM_KEYUP; {
                assert(false, "Keyboard input came in through a non-dispatch message!");
            }

            case WM_CLOSE; {
                global_running = false;
                win32_debug("WM_CLOSE\n");
            }

            case WM_ACTIVATEAPP;
                win32_debug("WM_ACTIVATEAPP\n");

            case WM_PAINT; {
                paint: PAINTSTRUCT;
                device_context: HDC           = BeginPaint(window, *paint);
                dims: Win32_Window_Dimensions = get_window_dimensions(window);

                win32_display_buffer_in_window(*global_back_buffer, device_context, dims.width, dims.height);
                EndPaint(window, *paint);
            }

            case;
                //            win32_debug("default\n")
                result = DefWindowProcA(window, message, WParam, LParam);
        }

        return (result);
    }
};

win32_process_keyboard_message :: (new_state: *Game_Button_State, isDown: bool) {
    assert(new_state.ended_down != isDown);  // should only enter when isDown changes
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
                case #char "P";  if isDown  global_pause = !global_pause;
                }
            }
        case;
            TranslateMessage(*message);
            DispatchMessageA(*message);
        }
    }
}

win32_get_wall_clock :: inline () -> s64 {
    res: s64;
    QueryPerformanceCounter(*res);
    return res;
}

win32_get_seconds_elapsed :: inline (start: s64, end: s64) -> float32 {
    return cast(float32)(end - start) / cast(float32)global_perf_counter_freq;
}

main :: () {
    QueryPerformanceFrequency(*global_perf_counter_freq);

    // NOTE: Set the windows scheduler granularity, so our sleep can be better
    desired_scheduler_ms :: 1;
    sleep_is_granular := timeBeginPeriod(desired_scheduler_ms) == TIMERR_NOERROR;
    defer timeEndPeriod(desired_scheduler_ms);

    window := create_window(1280, 720, "Handmade Hero");

    win32_resize_DIB_section(*global_back_buffer, 1280, 720);
    defer free(global_back_buffer.memory);

    // NOTE: since we specified CS_OWNDC (in Window_Creation/windows.jai), we can just get one device context and use it
    // forever because we are not sharing it with anyone.
    deviceContext := GetDC(window);

    success := init_xinput();
    if !success {
        win32_debug("Error: Could not initialize xinput!");
        return;
    }

    sound_output : Win32_Sound_Output = .{};
    win32_init_dsound(window);
    // no need to clear the secondary sound buffer in Jai, it's initialized to zero.
    hr := global_sound_buffer.Play(global_sound_buffer, 0, 0, DSBPLAY_LOOPING);
    if FAILED(hr) {
        log_error("Play failed!");
    }

    // TODO: pool with bitmap make
    samples := alloc(SOUND_BUFFER_SIZE);
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
        read_entire_file  = DEBUG_platform_read_entire_file,
        free_file_memory  = DEBUG_platform_free_file_memory,
        write_entire_file = DEBUG_platform_write_entire_file,
    };


    // Frame timings
    last_counter     := win32_get_wall_clock();
    last_cycle_count := rdtsc();
    flip_wall_clock  := win32_get_wall_clock();

    debug_last_play_cursor_index : u16 = 0;
    debug_last_play_cursor: [GAME_UPDATE_HZ / 2]s32;

    audio_latency_bytes : s32;
    audio_latency_sec   : float32;
    sound_is_valid      := false;

    message: MSG;
    new_input := Game_Input.{};
    old_input := Game_Input.{};

    // Load the game:
    game := win32_load_game_code();
    if !game.is_valid {
        log_error("could not load game code");
        return;
    }
    load_counter := 0;

    while (global_running) {
        load_counter += 1;
        if load_counter > 120 {
            success := win32_unload_game_code(*game);
            if !success {
                log_error("could not unload game code");
                return;
            }
            game = win32_load_game_code();
            load_counter = 0;
        }

        // zero the keyboard at the start of each frame
        old_keyboard_controller := *old_input.controllers[0];
        new_keyboard_controller := *new_input.controllers[0];
        <<new_keyboard_controller = .{is_connected = true};
        for i: 0..9 {  // 10 buttons
            new_keyboard_controller.buttons[i].ended_down = old_keyboard_controller.buttons[i].ended_down;
        }

        win32_process_messages(new_keyboard_controller);

        // TODO: Need to not poll disconnected controllers to avoid xinput frame rate hit on older libraries
        // TODO: Should we poll this more frequently?
        for controller_index: 0..XUSER_MAX_COUNT-1 {
            old_controller := *old_input.controllers[controller_index+1];  // +1 bc keyboard is 0
            new_controller := *new_input.controllers[controller_index+1];

            controller_state: XINPUT_STATE;
            if XInputGetState(xx controller_index, *controller_state) == 0 /*ERROR_SUCCESS*/ {
                pad := *controller_state.Gamepad;
                // up := pad.wButtons & XINPUT_GAMEPAD_DPAD_UP;
                // down := pad.wButtons & XINPUT_GAMEPAD_DPAD_DOWN;
                // left := pad.wButtons & XINPUT_GAMEPAD_DPAD_LEFT;
                // right := pad.wButtons & XINPUT_GAMEPAD_DPAD_RIGHT;

                // TODO: this is a square deadzone, check XINPUT to verify if the deadzone is round
                dzone := XINPUT_GAMEPAD_LEFT_THUMB_DEADZONE;
                denom : float32 = xx ifx pad.sThumbLX < dzone then 32768 else 32767;
                x := cast(float32)pad.sThumbLX / denom;
                denom = xx ifx pad.sThumbLY < -dzone then 32768 else 32767;
                y := cast(float32)pad.sThumbLY / denom;

                new_controller.analog = true;
                new_controller.stick_avg_x = x;
                new_controller.stick_avg_y = y;

                if pad.wButtons & XINPUT_GAMEPAD_DPAD_UP     new_controller.stick_avg_y = 1;
                if pad.wButtons & XINPUT_GAMEPAD_DPAD_DOWN   new_controller.stick_avg_y = -1;
                if pad.wButtons & XINPUT_GAMEPAD_DPAD_LEFT   new_controller.stick_avg_x = -1;
                if pad.wButtons & XINPUT_GAMEPAD_DPAD_RIGHT  new_controller.stick_avg_x = 1;

                // NOTE: not doing the stick->move_up/down/etc mapping that Casey did. Maybe I'll do it if we need it later.

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

                win32_process_xinput_digital_button(old_controller.back, *new_controller.back, pad.wButtons, XINPUT_GAMEPAD_BACK);
                win32_process_xinput_digital_button(old_controller.start, *new_controller.start, pad.wButtons, XINPUT_GAMEPAD_START);
            } else {
                // controller not available
            }
        }

        buffer := Game_Offscreen_Buffer.{
            memory = global_back_buffer.memory,
            width  = global_back_buffer.width,
            height = global_back_buffer.height,
            pitch  = global_back_buffer.pitch,
        };
        game.update_and_render(*game_memory, *new_input, *buffer);


        // DirectSound output test
        /* NOTE: How sound output computation works
            We define a safety value that is the number of samples we think our game update loop may vary by (let's say up to 2ms).
            When we wake up to write audio, we will look atnd see what the play cursor position is and we will forecast
            ahead where we think the play cursor will be on the next frame boundary.

            We will then look to see if the write cursor is before that. If it is, the target fill position is that frame
            boundary plus one frame. we will write up to the next frame boundary from the write cursor, and then one frame.
            This gives us perfect audio sync in the case of a card that has low enough latency.

            If the write cursor is _after_ that safety margin, then we assume we can never sync the audio perfectly,
            so we will write one frame's worth of audio plus plus the safety margin's worth of guard samples.
        */

        audio_wall_clock := win32_get_wall_clock();
        from_begin_to_audio_seconds := win32_get_seconds_elapsed(flip_wall_clock, audio_wall_clock);
        play_cursor, write_cursor: s32;
        // write cursor is where it's safe to write, play_cursor is where we are right now,
        // so write_cursor - play_cursor (+ wraparound) is our minimum latency
        if FAILED(global_sound_buffer.GetCurrentPosition(global_sound_buffer, *play_cursor, *write_cursor)) {
            win32_debug("Error in GetCurrentPosition");
            sound_is_valid = false;
        } else {
            byte_to_lock, target_cursor, bytes_to_write: s32;

            if !sound_is_valid {
                // we must be starting, or we failed getting position sometime earlier
                sound_output.running_sample_index = write_cursor / BYTES_PER_SAMPLE;
                sound_is_valid = true;
            }

            expected_sound_bytes_per_frame := (SAMPLE_RATE * BYTES_PER_SAMPLE) / GAME_UPDATE_HZ;
            expected_frame_boundary_byte := play_cursor + expected_sound_bytes_per_frame;

            // used for Casey's debugging lines (which we aren't drawing):
            seconds_left_until_flip := TARGET_SECONDS_PER_FRAME - from_begin_to_audio_seconds;
            expected_bytes_until_flip := (seconds_left_until_flip / TARGET_SECONDS_PER_FRAME) * cast(float32) expected_sound_bytes_per_frame;

            safe_write_cursor := write_cursor;
            if safe_write_cursor < play_cursor {
                safe_write_cursor += SOUND_BUFFER_SIZE;
            }
            assert(safe_write_cursor >= play_cursor);

            safe_write_cursor += SAFETY_BYTES;
            audio_card_is_low_latency := safe_write_cursor < expected_frame_boundary_byte;

            byte_to_lock = (sound_output.running_sample_index * BYTES_PER_SAMPLE) % SOUND_BUFFER_SIZE;
            if audio_card_is_low_latency {
                target_cursor = expected_frame_boundary_byte + expected_sound_bytes_per_frame;
            } else {
                target_cursor = write_cursor + expected_sound_bytes_per_frame + SAFETY_BYTES;
            }
            target_cursor %= SOUND_BUFFER_SIZE;

            if byte_to_lock > target_cursor {
                bytes_to_write = SOUND_BUFFER_SIZE - byte_to_lock; // we have this much ahead of us in the buffer to write to
                bytes_to_write += target_cursor; // and add the first part of the buffer up to the play cursor
            } else {
                bytes_to_write = target_cursor - byte_to_lock; // we only have to fill from bytes_to_lock up to the play_cursor
            }

            game_sound_buffer := Game_Sound_Buffer.{
                samples_per_second = SAMPLE_RATE,
                samples_count      = bytes_to_write / BYTES_PER_SAMPLE,
                samples            = samples,
            };
            game.get_sound_samples(*game_memory, *game_sound_buffer);
            win32_fill_sound_buffer(*sound_output, *game_sound_buffer, byte_to_lock, bytes_to_write);

            wrapped_around := play_cursor > write_cursor;
            audio_latency_bytes = ifx wrapped_around then write_cursor + SOUND_BUFFER_SIZE - play_cursor else write_cursor - play_cursor;
            audio_latency_sec = (cast(float32)audio_latency_bytes / cast(float32)BYTES_PER_SAMPLE / cast(float32)SAMPLE_RATE);

            win32_debug(
                    "BTL:  % -  PC: %  WC: %  TC: %  DELTA: %  LATENCY_SEC: %  Low Latency? %\n",
                    byte_to_lock,
                    play_cursor,
                    write_cursor,
                    target_cursor,
                    audio_latency_bytes,
                    audio_latency_sec,
                    audio_card_is_low_latency
            );
        }

        // Frame timings
        work_counter := win32_get_wall_clock();
        work_sec_elapsed := win32_get_seconds_elapsed(last_counter, work_counter);

        sec_elapsed_for_frame := work_sec_elapsed;
        if sec_elapsed_for_frame < TARGET_SECONDS_PER_FRAME {
            if sleep_is_granular {
                sleep_ms := cast(s32)(1000 * (TARGET_SECONDS_PER_FRAME - sec_elapsed_for_frame)) - 1;  // -1 makes it work...
                if sleep_ms > 0  Sleep(sleep_ms);
            }

            sec_elapsed_for_frame = win32_get_seconds_elapsed(last_counter, win32_get_wall_clock());
            //assert(sec_elapsed_for_frame < TARGET_SECONDS_PER_FRAME);
            while sec_elapsed_for_frame < TARGET_SECONDS_PER_FRAME {
                sec_elapsed_for_frame = win32_get_seconds_elapsed(last_counter, win32_get_wall_clock());
            }
        } else {
            log_error("missed a frame! sec_elapsed_for_frame > TARGET_SECONDS_PER_FRAME");
        }

        end_counter := win32_get_wall_clock();
        ms_per_frame := 1000 * win32_get_seconds_elapsed(last_counter, end_counter);
        last_counter = end_counter;

        // FLIP THE FRAME:
        dims := get_window_dimensions(window);

#if HANDMADE_INTERNAL {
        win32_debug_sync_display(*global_back_buffer, debug_last_play_cursor_index, debug_last_play_cursor, *sound_output);
}

        if !global_pause {
            win32_display_buffer_in_window(*global_back_buffer, deviceContext, dims.width, dims.height);
        }
        flip_wall_clock = win32_get_wall_clock();

#if HANDMADE_INTERNAL {
        // NOTE: this is debug code
        // We want the play cursor that we sampled back when we flipped the previous frame, and we want to add our frame latency into that.
        // play_cursor: s32;
        // write_cursor: s32;
        // if SUCCEEDED(global_sound_buffer.GetCurrentPosition(global_sound_buffer, *play_cursor, *write_cursor)) {
        //     last_play_cursor = play_cursor;
        //     sound_is_valid = true;
        // } else {
        //     sound_is_valid = false;
        // }

        debug_last_play_cursor[debug_last_play_cursor_index] = play_cursor;
        debug_last_play_cursor_index += 1;
        debug_last_play_cursor_index %= debug_last_play_cursor.count;
}

        // Using rdtsc
        end_cycle_count := rdtsc();
        cycles_elapsed := end_cycle_count - last_cycle_count;
        mcpf := cycles_elapsed / (1000 * 1000);
        fps := 0.0;

 #if HANDMADE_INTERNAL {
        win32_debug("ms_per_frame: %, FPS: %, cycles: % mc\n", ms_per_frame, fps, mcpf);
 }

        last_cycle_count = end_cycle_count;

        new_input, old_input = old_input, new_input;
    }
}

win32_debug :: (msg: string, args: ..Any) {
    OutputDebugStringA(to_c_string(tprint(msg, ..args),, temp));
}

#load "handmade_h.jai";

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
