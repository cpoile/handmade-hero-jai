/* TODO: This is not the final platform layer!

  - Fullscreen support
  - WM_SETCURSOR (control cursor visibility)


  - Saved game locations
  - Getting a handle to our own executable file
  - Asset loading path
  - Threading (launch a thread)
  - Raw input (support for multiple keyboards)
  - ClipCursor() (for muliple monitor supprot)
  - QueryCancelAutoplay
  - WM_ACTIVATEAPP (for when we are not the active application)
  - Blit speed improvements (BitBlt)
  - Hardware acceleration (OpenGL or Direct3D or BOTH??)
  - GetKeyboardLayout (for French keyboards, international WASD support)

  Just a partial list of stuff!
*/

// Set true when we want to do the stay on-top and transparent window thing:
LAYERED_WINDOW :: true;

SAMPLE_RATE            : s32 : 48000;
BYTES_PER_SAMPLE       :: size_of(s16) * 2;
SOUND_BUFFER_SIZE      :: SAMPLE_RATE * BYTES_PER_SAMPLE;  // 1 second
GAME_LOAD_FAILURES_MAX :: 30;  // avoid an infinite loop if we can't load the game dll

global_show_cursor       := false;
global_base_path         : string;
global_running           := true;
global_pause             := false;
global_back_buffer       : Offscreen_Buffer;
dsound_lib               :: #system_library "dsound";
dsound                   : *IDirectSound8;
global_sound_buffer      : *IDirectSoundBuffer8;
global_perf_counter_freq : s64;
global_saved_window_info : Saved_Window_Info;
global_is_fullscreen     := false;

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
    last_write_time   : FILETIME;

    // IMPORTANT      : either of these can be null, so check before using.
    update_and_render : Game_Update_And_Render;
    get_sound_samples : Game_Get_Sound_Samples;
    is_valid          : bool;
}

Win32_Replay_Buffer :: struct {
    filename     : *u16;
    file_handle  : HANDLE;
    memory_map   : HANDLE;
    memory_block : []u8;
}

Win32_State :: struct {
    game_memory_block     : []u8;

    // NOTE: can change this when we need more buffers.
    replay_buffers        : [2]Win32_Replay_Buffer;
    recording_handle      : HANDLE;
    input_recording_index : int;
    playback_handle       : HANDLE;
    input_playing_index   : int;
}

win32_get_last_write_time :: (filename: string) -> FILETIME {
    ret := FILETIME.{};
    find_data: WIN32_FIND_DATAW;
    full_filename := join(global_base_path, filename,, temp);
    full_wide_name := U.utf8_to_wide(full_filename,, temp);

    find_handle := FindFirstFileW(full_wide_name, *find_data);
    if find_handle != INVALID_HANDLE_VALUE {
        FindClose(find_handle);
        ret = find_data.ftLastWriteTime;
    }
    return ret;
}

// Load the platform-independent game code
win32_load_game_code :: (filename: string) -> Win32_Game_Code {
    filename_no_ext := path_strip_extension(filename);

    dll_filename := join(global_base_path, filename,, temp);
    temp_dll_filename := join(global_base_path, "handmade_copy.dll",, temp);
    ret := Win32_Game_Code.{};
    ret.last_write_time = win32_get_last_write_time(filename);

    source_dll_wide_name := U.utf8_to_wide(dll_filename,, temp);
    tmp_dll_wide_name := U.utf8_to_wide(temp_dll_filename,, temp);

    success := CopyFileW(source_dll_wide_name, tmp_dll_wide_name, 0);
    if !success {
        win32_debug("could not copy handmade.dll, last error: %\n", GetLastError());
        return .{};
    }

    game_code_dll := LoadLibraryW(tmp_dll_wide_name);
    if game_code_dll == null  return .{};

    ret.game_code_dll = game_code_dll;
    ret.update_and_render = GetProcAddress(game_code_dll, to_c_string("game_update_and_render",, temp));
    ret.get_sound_samples = GetProcAddress(game_code_dll, to_c_string("game_get_sound_samples",, temp));
    ret.is_valid = ret.update_and_render != null && ret.get_sound_samples != null;

    return ret;
}

win32_unload_game_code :: (game_code: *Win32_Game_Code) -> bool {
    if game_code.game_code_dll == null  return true;

    success := FreeLibrary(game_code.game_code_dll);
    if !success  {
        win32_debug("failed to unload game code, last error: %\n", GetLastError());
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
        fh := CreateFileW(U.utf8_to_wide(filename,, temp), GENERIC_READ, FILE_SHARE_READ, null, OPEN_EXISTING, 0, null);

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
        fh := CreateFileW(U.utf8_to_wide(filename,, temp), GENERIC_WRITE, FILE_SHARE_WRITE, null, CREATE_ALWAYS, 0, null);

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
    // NOTE: during prototyping, we're going to always blit 1-to-1 pixels to remove stretching artifacts
    // while we're learning to code the renderer.

    // TODO: centering?
    if destWidth >= buffer.width*2 && destHeight >= buffer.height*2 {
        StretchDIBits(deviceContext,
                      0, 0, buffer.width*2, buffer.height*2,
                      0, 0, buffer.width, buffer.height,
                      buffer.memory, *buffer.BitmapInfo, DIB_RGB_COLORS, ROP.SRCCOPY);
    } else {
        x_offset := 10;
        y_offset := 10;
        StretchDIBits(deviceContext,
                      x_offset, y_offset, buffer.width, buffer.height,
                      0, 0, buffer.width, buffer.height,
                      buffer.memory, *buffer.BitmapInfo, DIB_RGB_COLORS, ROP.SRCCOPY);
    }
}

win32_debug_draw_vertical :: (back_buffer: *Offscreen_Buffer, x: s32, top: s32, bottom: s32, color: u32) {
    pixel := back_buffer.memory + (x * back_buffer.bytes_per_pixel + top * back_buffer.pitch);
    for y: top .. bottom-1 {
        <<cast(*u32)pixel = color;
        pixel += back_buffer.pitch;
    }
}

#if false {
win32_debug_sync_display :: (back_buffer: *Offscreen_Buffer, last_play_cursor_count: u16, last_play_cursors: []s32,
    sound_output: *Win32_Sound_Output) {

    pad_x  : s32 = 16;
    pad_y  : s32 = 16;
    top    : s32 = pad_y;
    bottom : s32 = back_buffer.height - 16;

    // remember Casey's talk on dimentional analysis: to change something mapped in sound buffer size into back_buffer size,
    // mult by coefficient C. The sound buffer sized thing cancels out with the denominator, leaving back_buffer units.
    C := cast(float)(back_buffer.width - 2 * pad_x) / cast(float)SOUND_BUFFER_SIZE;
    for i: 0..last_play_cursors.count-1 {
        last_play_cursor := last_play_cursors[i];
        x := pad_x + cast(s32)(C * cast(float)last_play_cursor);
        win32_debug_draw_vertical(back_buffer, x, top, bottom, 0xFFFFFFFF);
    }
}
}

win32_process_xinput_stick_value :: (value: s16, dzone: s16) -> float {
    result := 0.0;

    if value < -dzone  result = cast(float)((value + dzone) / (32768.0 - dzone));
    if value >  dzone  result = cast(float)((value - dzone) / (32767.0 - dzone));

    return result;
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

// #add_context _windows_windowproc :: win32_main_window_callback;
// #add_context _windows_windowproc_allocator: Allocator;

win32_main_window_callback :: (window: HWND, message: u32, WParam: WPARAM, LParam: LPARAM) -> LRESULT #c_call {
    new_context: #Context;

    push_context new_context {
        result : LRESULT = 0;

        alt_is_down := false;

        if message == {
        case WM_ACTIVATEAPP;
#if LAYERED_WINDOW {
            if WParam {
                win32_debug("foreground");
                SetLayeredWindowAttributes(window, RGB(0, 0, 0), 255, LWA_ALPHA);
            } else {
                win32_debug("background");
                SetLayeredWindowAttributes(window, RGB(0, 0, 0), 64, LWA_ALPHA);
            }
}
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

        case WM_PAINT; {
            paint: PAINTSTRUCT;
            device_context: HDC           = BeginPaint(window, *paint);
            dims: Win32_Window_Dimensions = get_window_dimensions(window);

            win32_display_buffer_in_window(*global_back_buffer, device_context, dims.width, dims.height);
            EndPaint(window, *paint);
        }

        case;
            result = DefWindowProcW(window, message, WParam, LParam);
        }

        return (result);
    }
};

win32_process_keyboard_message :: (new_state: *Game_Button_State, isDown: bool) {
    if new_state.ended_down != isDown {
        new_state.ended_down = isDown;
        new_state.half_transition_count += 1;
    }
}

win32_process_pending_messages :: (state: *Win32_State, keyboard_controller: *Game_Controller_Input) {
    message: MSG;
    while PeekMessageW(*message, null, 0, 0, PM_REMOVE) {
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
                case #char "T";  win32_process_keyboard_message(*keyboard_controller.a, isDown);  // "turbo"
                case VK_UP;      win32_process_keyboard_message(*keyboard_controller.up, isDown);
                case VK_DOWN;    win32_process_keyboard_message(*keyboard_controller.down, isDown);
                case VK_LEFT;    win32_process_keyboard_message(*keyboard_controller.left, isDown);
                case VK_RIGHT;   win32_process_keyboard_message(*keyboard_controller.right, isDown);
                case VK_SPACE;   win32_process_keyboard_message(*keyboard_controller.start, isDown);
                case VK_ESCAPE;  global_running = false;  // TODO: will be back button, but keeping it hear b/c easier to develop
                case #char "P";  if isDown  global_pause = !global_pause;
                case #char "L";  if isDown {
                    // TODO: this doesn't seem to work if we change to -1 being the "no playing" state...
                    if state.input_playing_index == 0 {
                        if state.input_recording_index == 0 {
                            win32_begin_recording_input(state, 1);
                        } else {
                            win32_end_recording_input(state);
                            win32_begin_input_playback(state, 1);
                        }
                    } else {
                        win32_end_input_playback(state);
                    }
                }
                case VK_RETURN;
                    if isDown && altDown {
                        global_is_fullscreen = !global_is_fullscreen;
                        toggle_fullscreen(message.hwnd, global_is_fullscreen, *global_saved_window_info);
                    }
                }
            }
        case;
            TranslateMessage(*message);
            DispatchMessageW(*message);
        }
    }
}

win32_get_wall_clock :: inline () -> s64 {
    res: s64;
    QueryPerformanceCounter(*res);
    return res;
}

win32_get_seconds_elapsed :: inline (start: s64, end: s64) -> float {
    return cast(float)(end - start) / cast(float)global_perf_counter_freq;
}

win32_build_input_file_name :: (input_stream: bool, slot_index: int) -> *u16 {
    filename := sprint("input_recording_%_%.hmi", slot_index, ifx input_stream "input" else "state",, temp);
    return U.utf8_to_wide(join(global_base_path, filename,, temp),, temp);
}

win32_get_replay_buffer :: (state: *Win32_State, input_recording_index: int) -> Win32_Replay_Buffer {
    assert(input_recording_index >= 0);
    assert(input_recording_index < state.replay_buffers.count);
    return state.replay_buffers[input_recording_index];
}

win32_begin_recording_input :: (state: *Win32_State, input_recording_index: int) {
    replay_buffer := win32_get_replay_buffer(state, input_recording_index);
    if replay_buffer.memory_block.data {
        state.input_recording_index = input_recording_index;
        filename := win32_build_input_file_name(true, input_recording_index);
        state.recording_handle = CreateFileW(filename, GENERIC_WRITE, 0, null, CREATE_ALWAYS, 0, null);
        memcpy(replay_buffer.memory_block.data,
               state.game_memory_block.data,
               state.game_memory_block.count);
    }
}

win32_end_recording_input :: (state: *Win32_State) {
    CloseHandle(state.recording_handle);
    state.input_recording_index = 0;
}

win32_begin_input_playback :: (state: *Win32_State, input_playing_index: int) {
    replay_buffer := win32_get_replay_buffer(state, input_playing_index);
    if replay_buffer.memory_block.data {
        state.input_playing_index = input_playing_index;

        filename := win32_build_input_file_name(true, input_playing_index);
        state.playback_handle = CreateFileW(filename, GENERIC_READ, 0, null, OPEN_EXISTING, 0, null);

        memcpy(state.game_memory_block.data, replay_buffer.memory_block.data, state.game_memory_block.count);
    }
}

win32_end_input_playback :: (state: *Win32_State) {
    CloseHandle(state.playback_handle);
    state.input_playing_index = 0;
}

win32_record_input :: (state: Win32_State, new_input: Game_Input) {
    bytes_written : DWORD;
    WriteFile(state.recording_handle, *new_input, size_of(Game_Input), *bytes_written, null);
}

win32_playback_input :: (state: *Win32_State, new_input: *Game_Input) {
    bytes_read : DWORD;
    if !ReadFile(state.playback_handle, new_input, size_of(Game_Input), *bytes_read, null) {
        return;
    }
    if bytes_read == 0 {
        // finished reading file
        playing_index := state.input_playing_index;
        win32_end_input_playback(state);
        win32_begin_input_playback(state, playing_index);
        // Now read the next input (probably not necessary, I don't notice the missed input)>
        ReadFile(state.playback_handle, new_input, size_of(Game_Input), *bytes_read, null);
    }
}

create_window :: (width: int, height: int, name: string) -> HWND {
    window_x : int = 1100;
    window_y : int = 100;

    hInstance := GetModuleHandleW(null);

    // Load the first icon resource (RESOURCE_ID_FIRST_ICON).
    icon := LoadIconW(hInstance, MAKEINTRESOURCEW(2));
    err := GetLastError();

    // If the icon is null, then use the first one found in the exe.
    if icon == null {
        exe_path : [MAX_PATH]u16;
        GetModuleFileNameW(null, exe_path.data, MAX_PATH);

        icon = ExtractIconW(hInstance, exe_path.data, 0); // 0 means first icon.
    }

    window_class: WNDCLASSEXW  = .{};
    window_class.cbSize        = size_of(WNDCLASSEXW);
    window_class.style         = CS_HREDRAW | CS_VREDRAW | CS_OWNDC;
    window_class.lpfnWndProc   = xx win32_main_window_callback;
    window_class.cbClsExtra    = 0;
    window_class.cbWndExtra    = 0;
    window_class.hInstance     = hInstance;
    window_class.hIcon         = icon;
    window_class.hCursor       = LoadCursorW(null, IDC_ARROW);
    window_class.hbrBackground = cast(HBRUSH) GetStockObject(BLACK_BRUSH);
    window_class.lpszMenuName  = null;
    window_class.lpszClassName = U.utf8_to_wide("HandmadeHeroClass",, temp);

    if RegisterClassExW(*window_class) == 0 {
        win32_error("RegisterClassExW returned 0.\n");
        return null;
    }

#if false {
    // not sure how/why to use this... keeping it here in case Casey comes back to it.
    global_show_cursor = true;
}

    rect : RECT;
    rect.right  = xx width;
    rect.bottom = xx height;
    style : u32 = WS_OVERLAPPEDWINDOW | WS_VISIBLE;

    AdjustWindowRect(*rect, style, .FALSE); // @Robustness: Could this reasonably fail these days?

    client_width  := rect.right-rect.left;
    client_height := rect.bottom-rect.top;

    // NOTE: not sure why the title is not displaying correctly. Even tried creating the wide string manually:
    //buff : [100]u16;
    //MultiByteToWideChar(CP_ACP, 0, "My, Handmade Hero", -1, cast(*u16) *buff, 200);

    #if LAYERED_WINDOW {
        FLAGS : s32 = WS_EX_TOPMOST | WS_EX_LAYERED;
    } else {
        FLAGS : s32 = 0;
    }
    hwnd := CreateWindowExW(FLAGS,
                           window_class.lpszClassName,
                           U.utf8_to_wide("Handmade Hero",, temp),
                           style,
                           xx window_x, xx window_y,
                           xx client_width, xx client_height,
                           null,
                           null,
                           cast (HINSTANCE) 0,
                           null);

    UpdateWindow(hwnd);
    ShowWindow(hwnd, SW_SHOW);
    SetForegroundWindow(hwnd);

    res := SetWindowTextW(hwnd, U.utf8_to_wide("Handmade Hero",, temp));

    return hwnd;
}

main :: () {
    global_base_path = path_strip_filename(get_path_of_running_executable());

    QueryPerformanceFrequency(*global_perf_counter_freq);

    // NOTE: Set the windows scheduler granularity, so our sleep can be better
    desired_scheduler_ms :: 1;
    sleep_is_granular := timeBeginPeriod(desired_scheduler_ms) == TIMERR_NOERROR;
    defer timeEndPeriod(desired_scheduler_ms);

    width, height : s32 = 960, 540;
    win32_resize_DIB_section(*global_back_buffer, width, height);
    defer free(global_back_buffer.memory);

    // +20 to get a black border
    window := create_window(width + 20, height + 20, "Handmade Hero");
    if !window {
        return;
    }

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
    temporary_len := GIGABYTES(1);

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

    // Store the entire memory block (for when we want to save and replay):
    game_state := Win32_State.{
        game_memory_block = .{total_size, permanent_mem},
    };

    // TODO: Recording ystem still seems to take too long on record start --
    // find out what Windows is doing and if we can speed up / defer some of
    // that processing.
    for * buf: game_state.replay_buffers {
        filename := win32_build_input_file_name(false, it_index);
        buf.file_handle = CreateFileW(filename, GENERIC_READ|GENERIC_WRITE, FILE_SHARE_WRITE, null, CREATE_ALWAYS, 0, null);

        max_high := cast(u32)(total_size >> 32);
        max_low  := cast(u32)(total_size & 0xFFFFFFFF);
        buf.memory_map = CreateFileMappingW(buf.file_handle, null,
                                            PAGE_READWRITE,
                                            max_high,
                                            max_low,
                                            null);
        err := GetLastError();
        buf.memory_block = .{total_size, MapViewOfFile(buf.memory_map, FILE_MAP_ALL_ACCESS, 0, 0, xx total_size)};
    }

    // Refresh rates
    monitor_refresh_rate : s32 = 60;  // default
    refresh_dc := GetDC(window);
    win32_refresh_rate := GetDeviceCaps(refresh_dc, VREFRESH);
    ReleaseDC(window, refresh_dc);
    if win32_refresh_rate > 1 {
        monitor_refresh_rate = win32_refresh_rate;
    }

    game_update_hz            := monitor_refresh_rate / 1.0;
    target_seconds_per_frame  := 1 / game_update_hz;
    safety_bytes              := cast(s32)(((SAMPLE_RATE * BYTES_PER_SAMPLE) / game_update_hz) / 3);

    // Frame timings
    last_counter     := win32_get_wall_clock();
    last_cycle_count := rdtsc();
    flip_wall_clock  := win32_get_wall_clock();

    debug_last_play_cursor_index : u16 = 0;
    debug_last_play_cursor: [30]s32;

    audio_latency_bytes : s32;
    audio_latency_sec   : float;
    sound_is_valid      := false;

    message: MSG;
    new_input := Game_Input.{};
    old_input := Game_Input.{};

    // Load the game:
    game_load_failures := 0;
    game := win32_load_game_code("handmade.dll");
    if !game.is_valid {
        log_error("could not load game code");
        return;
    }

    // Main game Loop
    while (global_running) {
        new_input.dt_for_frame = target_seconds_per_frame;

        // Reload the game dll if it has changed
        new_dll_write_time := win32_get_last_write_time("handmade.dll");
        if CompareFileTime(*new_dll_write_time, *game.last_write_time) == 1 {
            success := win32_unload_game_code(*game);
            if !success {
                log_error("could not unload game code\n");
                win32_debug("could not unload game code\n");
            }
            game = win32_load_game_code("handmade.dll");
            if !game.is_valid {
                log_error("could not load game code\n");
                win32_debug("could not load game code\n");
                if game_load_failures > GAME_LOAD_FAILURES_MAX  {
                    return;
                }
                game_load_failures += 1;
                Sleep(1);
                continue;
            }
            game_load_failures = 0;
        }

        // zero the keyboard at the start of each frame
        old_keyboard_controller := *old_input.controllers[0];
        new_keyboard_controller := *new_input.controllers[0];
        <<new_keyboard_controller = .{is_connected = true};
        for i: 0..9 {  // 10 buttons
            new_keyboard_controller.buttons[i].ended_down = old_keyboard_controller.buttons[i].ended_down;
        }

        win32_process_pending_messages(*game_state, new_keyboard_controller);

        old_input.mouse_buttons = new_input.mouse_buttons;
        point: POINT;
        GetCursorPos(*point);
        ScreenToClient(window, *point);
        new_input.mouse_x          = point.x;
        new_input.mouse_y          = point.y;

        win32_process_keyboard_message(*new_input.mouse_buttons[0], GetKeyState(VK_LBUTTON) & (1 << 15) != 0);
        win32_process_keyboard_message(*new_input.mouse_buttons[1], GetKeyState(VK_MBUTTON) & (1 << 15) != 0);
        win32_process_keyboard_message(*new_input.mouse_buttons[2], GetKeyState(VK_RBUTTON) & (1 << 15) != 0);
        win32_process_keyboard_message(*new_input.mouse_buttons[3], GetKeyState(VK_XBUTTON1) & (1 << 15) != 0);
        win32_process_keyboard_message(*new_input.mouse_buttons[4], GetKeyState(VK_XBUTTON2) & (1 << 15) != 0);

        // TODO: Need to not poll disconnected controllers to avoid xinput frame rate hit on older libraries
        // TODO: Should we poll this more frequently?
        for controller_index: 0..XUSER_MAX_COUNT-1 {
            old_controller := *old_input.controllers[controller_index+1];  // +1 bc keyboard is 0
            new_controller := *new_input.controllers[controller_index+1];

            controller_state: XINPUT_STATE;
            if XInputGetState(xx controller_index, *controller_state) == 0 /*ERROR_SUCCESS*/ {
                pad := *controller_state.Gamepad;
                new_controller.analog = old_controller.analog;

                // up := pad.wButtons & XINPUT_GAMEPAD_DPAD_UP;
                // down := pad.wButtons & XINPUT_GAMEPAD_DPAD_DOWN;
                // left := pad.wButtons & XINPUT_GAMEPAD_DPAD_LEFT;
                // right := pad.wButtons & XINPUT_GAMEPAD_DPAD_RIGHT;

                // TODO: this is a square deadzone, check XINPUT to verify if the deadzone is round
                x := win32_process_xinput_stick_value(pad.sThumbLX, XINPUT_GAMEPAD_LEFT_THUMB_DEADZONE);
                y := win32_process_xinput_stick_value(pad.sThumbLY, XINPUT_GAMEPAD_LEFT_THUMB_DEADZONE);

                if x != 0 || y != 0  new_controller.analog = true;

                new_controller.stick_avg_x = x;
                new_controller.stick_avg_y = y;

                if pad.wButtons & XINPUT_GAMEPAD_DPAD_UP     {
                    new_controller.stick_avg_y = 1;
                    //new_controller.analog = false;
                }
                if pad.wButtons & XINPUT_GAMEPAD_DPAD_DOWN {
                    new_controller.stick_avg_y = -1;
                    //new_controller.analog = false;
                }
                if pad.wButtons & XINPUT_GAMEPAD_DPAD_LEFT {
                    new_controller.stick_avg_x = -1;
                    //new_controller.analog = false;
                }
                if pad.wButtons & XINPUT_GAMEPAD_DPAD_RIGHT {
                    new_controller.stick_avg_x = 1;
                    //new_controller.analog = false;
                }
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
            memory          = global_back_buffer.memory,
            width           = global_back_buffer.width,
            height          = global_back_buffer.height,
            pitch           = global_back_buffer.pitch,
            bytes_per_pixel = 4,
        };

        if game_state.input_recording_index  win32_record_input(*game_state, *new_input);
        if game_state.input_playing_index    win32_playback_input(*game_state, *new_input);

        if game.update_and_render  game.update_and_render(*game_memory, *new_input, *buffer);


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

            expected_sound_bytes_per_frame := cast(s32)((SAMPLE_RATE * BYTES_PER_SAMPLE) / game_update_hz);

            // used for Casey's debugging lines (which we aren't drawing):
            seconds_left_until_flip := target_seconds_per_frame - from_begin_to_audio_seconds;
            expected_bytes_until_flip := cast(s32)((seconds_left_until_flip / target_seconds_per_frame) * cast(float) expected_sound_bytes_per_frame);

            expected_frame_boundary_byte := play_cursor + expected_bytes_until_flip;

            safe_write_cursor := write_cursor;
            if safe_write_cursor < play_cursor {
                safe_write_cursor += SOUND_BUFFER_SIZE;
            }
            assert(safe_write_cursor >= play_cursor);

            safe_write_cursor += safety_bytes;
            audio_card_is_low_latency := safe_write_cursor < expected_frame_boundary_byte;

            byte_to_lock = (sound_output.running_sample_index * BYTES_PER_SAMPLE) % SOUND_BUFFER_SIZE;
            if audio_card_is_low_latency {
                target_cursor = expected_frame_boundary_byte + expected_sound_bytes_per_frame;
            } else {
                target_cursor = write_cursor + expected_sound_bytes_per_frame + safety_bytes;
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
            if game.get_sound_samples  game.get_sound_samples(*game_memory, *game_sound_buffer);
            win32_fill_sound_buffer(*sound_output, *game_sound_buffer, byte_to_lock, bytes_to_write);

            wrapped_around := play_cursor > write_cursor;
            audio_latency_bytes = ifx wrapped_around then write_cursor + SOUND_BUFFER_SIZE - play_cursor else write_cursor - play_cursor;
            audio_latency_sec = (cast(float)audio_latency_bytes / cast(float)BYTES_PER_SAMPLE / cast(float)SAMPLE_RATE);

#if false {
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
        }

        // Frame timings
        work_counter := win32_get_wall_clock();
        work_sec_elapsed := win32_get_seconds_elapsed(last_counter, work_counter);

        sec_elapsed_for_frame := work_sec_elapsed;
        if sec_elapsed_for_frame < target_seconds_per_frame {
            if sleep_is_granular {
                sleep_ms := cast(s32)(1000 * (target_seconds_per_frame - sec_elapsed_for_frame)) - 1;  // -1 makes it work...
                if sleep_ms > 0  Sleep(sleep_ms);
            }

            sec_elapsed_for_frame = win32_get_seconds_elapsed(last_counter, win32_get_wall_clock());
            //assert(sec_elapsed_for_frame < target_seconds_per_frame);
            while sec_elapsed_for_frame < target_seconds_per_frame {
                sec_elapsed_for_frame = win32_get_seconds_elapsed(last_counter, win32_get_wall_clock());
            }
        } else {
            log_error("missed a frame! sec_elapsed_for_frame > target_seconds_per_frame");
        }

        end_counter := win32_get_wall_clock();
        ms_per_frame := 1000 * win32_get_seconds_elapsed(last_counter, end_counter);
        last_counter = end_counter;

        // FLIP THE FRAME:
        dims := get_window_dimensions(window);

#if false {
        win32_debug_sync_display(*global_back_buffer, debug_last_play_cursor_index, debug_last_play_cursor, *sound_output);
}

        // TODO: need to make this a real pause, ofc.
        if !global_pause {
            device_context := GetDC(window);
            win32_display_buffer_in_window(*global_back_buffer, device_context, dims.width, dims.height);
            ReleaseDC(window, device_context);
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

#if false {
        // Using rdtsc
        end_cycle_count := rdtsc();
        cycles_elapsed := end_cycle_count - last_cycle_count;
        mcpf := cycles_elapsed / (1000 * 1000);
        fps := 0.0;

 #if HANDMADE_INTERNAL {
        win32_debug("ms_per_frame: %, FPS: %, cycles: % mc\n", ms_per_frame, fps, mcpf);
 }

        last_cycle_count = end_cycle_count;
}
        new_input, old_input = old_input, new_input;
    }

    ExitProcess(0);
}

win32_debug :: (msg: string, args: ..Any) {
    OutputDebugStringW(U.utf8_to_wide(tprint(msg, ..args),, temp));
}

win32_error :: (msg: string, args: ..Any) {
    OutputDebugStringW(U.utf8_to_wide(tprint(msg, ..args),, temp));
    log_error(msg, args);
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
#import "String";
#import "System";
U :: #import "Windows_Utf8";

#run {
    WR :: #import "Windows_Resources";
    WR.disable_runtime_console();
}
