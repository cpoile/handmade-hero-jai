// Platform-independent game code

// Useful macros
KILOBYTES :: (v: $T) -> T #expand { return v * 1024; }
MEGABYTES :: (v: $T) -> T #expand { return KILOBYTES(v) * 1024; }
GIGABYTES :: (v: $T) -> T #expand { return MEGABYTES(v) * 1024; }
TERABYTES :: (v: $T) -> T #expand { return GIGABYTES(v) * 1024; }

Game_Memory :: struct {
    permanent : []u8;
    temporary : []u8;
}

Game_State :: struct {
    initialized  : bool;
    blue_offset  : s32;
    green_offset : s32;
    tone_hz      : s32;
}

// TODO: In the future, rendering _specifically_ will become a three-tiered abstraction!!
Game_Offscreen_Buffer :: struct {
    // NOTE: Pixels are always 32-bits wide, Memory Order BB GG RR XX
    memory     : *u8;
    width      : int;
    height     : int;
    pitch      : int;
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
    analog         : bool;
    start_x        : float32;
    start_y        : float32;
    min_x          : float32;
    min_y          : float32;
    max_x          : float32;
    max_y          : float32;
    end_x          : float32;
    end_y          : float32;
    a              : Game_Button_State;
    b              : Game_Button_State;
    x              : Game_Button_State;
    y              : Game_Button_State;
    left_shoulder  : Game_Button_State;
    right_shoulder : Game_Button_State;
}

Game_Input :: struct {
    controllers: [4]Game_Controller_Input;
}

game_sound_output :: (sound_buffer: *Game_Sound_Buffer, tone_hz: s32) {
    tone_volume := 3000;
    wave_period := sound_buffer.samples_per_second / tone_hz;

    sample_out := sound_buffer.samples;
    for i: 0 .. sound_buffer.samples_count-1 {
        sine_val := sin(t_sine);
        sample_value := cast(s16)(sine_val * cast(float32)tone_volume);
        <<sample_out = sample_value;
        sample_out += 1;
        <<sample_out = sample_value;
        sample_out += 1;

        t_sine += 2.0 * PI / cast(float32)wave_period;
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
            bb := cast,trunc(u8)(x + xOffset);
            gg := cast,trunc(u8)(y + yOffset);
            <<pixel = ((cast(u32) gg) << 8 | bb);
            pixel += 1;
        }

        row += back_buffer.pitch;
    }
}



// NOTE: may expand in the future
// need FOUR THINGS: timing, controller/keyboard input, bitmap buffer to use, sound buffer to use
game_update_and_render :: (
    game_memory  : *Game_Memory,
    input        : *Game_Input,
    back_buffer  : *Game_Offscreen_Buffer,
    sound_buffer : *Game_Sound_Buffer
) -> bool {
    #if HANDMADE_DEBUG {
        assert(size_of(Game_State) <= game_memory.permanent.count);
    }

    state := cast(*Game_State)game_memory.permanent.data;
    if !state.initialized {
        state.tone_hz = 256;
        state.initialized = true;

        bitmap_memory, success := DEBUG_platform_read_entire_file(#file);
        if !success return false;  // TODO: ofc we'll do some real error handling when needed.

        DEBUG_platform_write_entire_file("../data/test_file_output.txt", bitmap_memory);

        DEBUG_platform_free_file_memory(*bitmap_memory);
    }

    input_0 := input.controllers[0];

    if input_0.analog {
        // NOTE: Use analog movement tuning
        state.tone_hz = cast(s32)clamp(261 + 64 * input_0.end_y, 120, 1566);
        state.blue_offset += cast(s32)(input_0.end_x * 4);
        state.green_offset -= cast(s32)(input_0.end_y * 4);
    } else {
        // NOTE: Use digital movement tuning.
    }

    // TODO: Allow sample offsets here (eg, set sound further out in the future, or closer to immediately)
    game_sound_output(sound_buffer, state.tone_hz);

    render_weird_gradient(back_buffer, state.blue_offset, state.green_offset);

    return true;
}

#import "Basic";
#import "Math";

// statics:
#scope_file
t_sine       : float32;
blue_offset  : s32;
green_offset : s32;
tone_hz      : s32 = 256;
