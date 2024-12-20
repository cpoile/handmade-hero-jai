// Platform-independent game code

#import "Basic";
#import "Math";
#load "handmade_h.jai";

Game_State :: struct {
    initialized  : bool;
    blue_offset  : s32;
    green_offset : s32;
    tone_hz      : s32;
    t_sine       : float32;
}


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

// TODO: is there a way to export the type from here, into handmade_h, without repeating ourselves?
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
