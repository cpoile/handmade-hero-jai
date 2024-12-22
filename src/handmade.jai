// Platform-independent game code

MAX_INPUTS :: 5;  // 4 controllers + keyboard

// Useful macros
KILOBYTES :: (v: $T) -> T #expand { return v * 1024; }
MEGABYTES :: (v: $T) -> T #expand { return KILOBYTES(v) * 1024; }
GIGABYTES :: (v: $T) -> T #expand { return MEGABYTES(v) * 1024; }
TERABYTES :: (v: $T) -> T #expand { return GIGABYTES(v) * 1024; }

Game_State :: struct {
    initialized  : bool;
    blue_offset  : s32;
    green_offset : s32;
    tone_hz      : s32;
    t_sine       : float32;
}

Game_Memory :: struct {
    permanent : []u8;
    temporary : []u8;

    // Procs from the platform layer
    read_entire_file  : DEBUG_Platform_Read_Entire_File;
    free_file_memory  : DEBUG_Platform_Free_File_Memory;
    write_entire_file : DEBUG_Platform_Write_Entire_File;
}

// TODO: In the future, rendering _specifically_ will become a three-tiered abstraction!!
Game_Offscreen_Buffer :: struct {
    // NOTE: Pixels are always 32-bits wide, Memory Order BB GG RR XX
    memory     : *u8;
    width      : s32;
    height     : s32;
    pitch      : s32;
}

Game_Sound_Buffer :: struct {
    samples_per_second : s32;
    samples_count      : s32;
    samples            : *s16;
}

Game_Button_State :: struct {
    half_transition_count : u8;
    ended_down            : bool;
}

Game_Controller_Input :: struct {
    is_connected   : bool;
    analog         : bool;
    stick_avg_x    : float32;
    stick_avg_y    : float32;
    union {
        buttons: [12]Game_Button_State;
        struct {
            up             : Game_Button_State;
            down           : Game_Button_State;
            left           : Game_Button_State;
            right          : Game_Button_State;
            a              : Game_Button_State;
            b              : Game_Button_State;
            x              : Game_Button_State;
            y              : Game_Button_State;
            left_shoulder  : Game_Button_State;
            right_shoulder : Game_Button_State;
            back           : Game_Button_State;
            start          : Game_Button_State;
            // NOTE: always add new buttons above the terminator
            terminator     : Game_Button_State;
        }
    }
}

Game_Input :: struct {
    controllers: [MAX_INPUTS]Game_Controller_Input;
}

Game_Update_And_Render :: #type (
    game_memory          : *Game_Memory,
    input                : *Game_Input,
    back_buffer          : *Game_Offscreen_Buffer
) -> bool;
Game_Get_Sound_Samples :: #type (game_memory: *Game_Memory, sound_buffer: *Game_Sound_Buffer);


// Below is implementation, the platform only needed the above (kind of like a header file).
#scope_file

// Functions the platform layer provides
//
DEBUG_Platform_Read_Entire_File  :: #type (filename: string) -> memory: []u8, ok: bool;
DEBUG_Platform_Free_File_Memory  :: #type (memory: *[]u8);
DEBUG_Platform_Write_Entire_File :: #type (filename: string, memory: []u8) -> bool;


game_sound_output :: (sound_buffer: *Game_Sound_Buffer, tone_hz: s32, t_sine: *float32) {
    tone_volume := 3000;
    wave_period := sound_buffer.samples_per_second / tone_hz;

    sample_out := sound_buffer.samples;
    for i: 0 .. sound_buffer.samples_count-1 {
        sine_val := sin(<<t_sine);
        sample_value := cast(s16)(sine_val * cast(float32)tone_volume);
        <<sample_out = sample_value;
        sample_out += 1;
        <<sample_out = sample_value;
        sample_out += 1;

        <<t_sine += 2.0 * PI / cast(float32)wave_period;
        if <<t_sine > 2.0 * PI {
            <<t_sine -= 2.0 * PI;
        }
    }
}

render_weird_gradient :: (back_buffer: *Game_Offscreen_Buffer,  xOffset: int, yOffset: int) {
    row := back_buffer.memory;
    for y: 0..back_buffer.height-1 {
        pixel := cast(*u32) row;
        for x: 0..back_buffer.width-1 {
            //                   1  2  3  4
            // pixel in memory: BB GG RR xx  (bc MSFT wanted to see RGB in register (see register)
            //     in register: xx RR GG BB  (bc it's little endian)
            bb := cast,trunc(u8)(x + xOffset+100);
            gg := cast,trunc(u8)(y + yOffset);
            <<pixel = ((cast(u32) gg) << 8 | bb);
            pixel += 1;
        }

        row += back_buffer.pitch;
    }
}


// NOTE: at the moment this has to be a very fast function, it cannot be more than a ms or so.
#program_export
game_get_sound_samples :: (game_memory: *Game_Memory, sound_buffer: *Game_Sound_Buffer) {
    // TODO: Allow sample offsets here (eg, set sound further out in the future, or closer to immediately)
    state := cast(*Game_State)game_memory.permanent.data;

    game_sound_output(sound_buffer, state.tone_hz, *state.t_sine);
}


// NOTE: may expand in the future
// need FOUR THINGS: timing, controller/keyboard input, bitmap buffer to use, sound buffer to use

#program_export
game_update_and_render :: (
    game_memory: *Game_Memory,
    input: *Game_Input,
    back_buffer: *Game_Offscreen_Buffer
) -> bool {
    assert(game_memory != null);
    #if HANDMADE_DEBUG {
        assert(size_of(Game_State) <= game_memory.permanent.count);
        assert((*input.controllers[0].terminator - *input.controllers[0].up) == input.controllers[0].buttons.count);
    }

    state := cast(*Game_State)game_memory.permanent.data;
    if !state.initialized {
        state.tone_hz = 256;
        state.initialized = true;

        bitmap_memory, success := game_memory.read_entire_file(#file);
        if !success  log_error("failed to read file");

        success = game_memory.write_entire_file("../data/test_file_output.txt", bitmap_memory);
        if !success  log_error("failed to write file");

        game_memory.free_file_memory(*bitmap_memory);
    }

    for i: 0..MAX_INPUTS-1 {
        cur_input := input.controllers[i];

        if cur_input.analog {
            // NOTE: Use analog movement tuning
            state.tone_hz       = cast(s32)clamp(261 + 64 * cur_input.stick_avg_y, 120, 1566);
            state.blue_offset  += cast(s32)(cur_input.stick_avg_x * 15);
            state.green_offset -= cast(s32)(cur_input.stick_avg_y * 15);
        } else {
            state.blue_offset  += cast(s32)((ifx cur_input.right.ended_down 1 else 0) * 15);
            state.blue_offset  -= cast(s32)((ifx cur_input.left.ended_down 1 else 0) * 15);
            state.green_offset -= cast(s32)((ifx cur_input.up.ended_down 1 else 0) * 15);
            state.green_offset += cast(s32)((ifx cur_input.down.ended_down 1 else 0) * 15);
        }
    }

    render_weird_gradient(back_buffer, state.blue_offset, state.green_offset);

    return true;
}

#import "Basic";
#import "Math";
