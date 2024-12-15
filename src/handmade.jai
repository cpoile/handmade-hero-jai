// Platform-independent game code

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


render_weird_gradient :: (back_buffer: *Game_Offscreen_Buffer,  xOffset: int, yOffset: int) #no_abc {
    row : *u8 = back_buffer.memory;
    for y: 0..back_buffer.height-1 {
        pixel : *u32 = xx row;
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
    back_buffer: *Game_Offscreen_Buffer,
    sound_buffer: *Game_Sound_Buffer,
    blue_offset: int,
    green_offset: int,
    tone_hz: s32
) {
    // TODO: Allow sample offsets here (eg, set sound further out in the future, or closer to immediately)
    game_sound_output(sound_buffer, tone_hz);

    render_weird_gradient(back_buffer, blue_offset, green_offset);
}

#import "Math";

#scope_file
t_sine: float32;
