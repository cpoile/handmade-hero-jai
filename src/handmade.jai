// Platform-independent game code


game_sound_output :: (sound_buffer: *Game_Sound_Buffer) {
    //tone_volume := 3000;
    tone_volume := 0;
    //wave_period := sound_buffer.samples_per_second / tone_hz;

    sample_out := sound_buffer.samples;
    for i: 0 .. sound_buffer.samples_count-1 {
#if false {
        sine_val := sin(<<t_sine);
        sample_value := cast(s16)(sine_val * cast(float)tone_volume);
} else {
        sample_value : s16 = 0;
}
        sample_out.* = sample_value;
        sample_out += 1;
        <<sample_out = sample_value;
        sample_out += 1;

#if false {
        << t_sine += 2.0 * PI / cast(float)wave_period;
        if <<t_sine > 2.0 * PI {
            <<t_sine -= 2.0 * PI;
        }
}
    }
}

// rectangle will fill up to but not including final row/col
draw_rectangle :: (buffer: *Game_Offscreen_Buffer,
    real_min_x: float, real_min_y: float, real_max_x: float, real_max_y: float,
    r: float, g: float, b: float)
{
    min_x := round_s32(real_min_x);
    min_y := round_s32(real_min_y);
    max_x := round_s32(real_max_x);
    max_y := round_s32(real_max_y);

    if min_x < 0  min_x = 0;
    if min_y < 0  min_y = 0;
    if max_x > buffer.width  max_x = buffer.width;
    if max_y > buffer.height  max_y = buffer.height;

    // don't try to draw if we have zero width or zero height
    if min_x == max_x  return;
    if min_y == max_y  return;

    // bit pattern: 0x AA RR GG BB
    //        bits:     8  8  8  8
    color : u32 = (round_u32(r * 255.0) << 16) | (round_u32(g * 255.0) << 8) | (round_u32(b * 255.0));

    row := buffer.memory + (min_y * buffer.pitch + min_x * buffer.bytes_per_pixel);

    for y: min_y..max_y-1 {
        pixel := cast(*u32)row;
        for x: min_x..max_x-1 {
            <<pixel = color;
            pixel += 1;
        }

        row += buffer.pitch;
    }
}

round_s32 :: inline (x: float) -> s32 {
    return cast,trunc(s32)(x + 0.5);
}
round_u32 :: inline (x: float) -> u32 {
    return cast,trunc(u32)(x + 0.5);
}

// NOTE: at the moment this has to be a very fast function, it cannot be more than a ms or so.
#program_export
game_get_sound_samples :: (game_memory: *Game_Memory, sound_buffer: *Game_Sound_Buffer) {
    // TODO: Allow sample offsets here (eg, set sound further out in the future, or closer to immediately)
    state := cast(*Game_State)game_memory.permanent.data;

    game_sound_output(sound_buffer);
}


// NOTE: may expand in the future
// need FOUR THINGS: timing, controller/keyboard input, bitmap buffer to use, sound buffer to use

#program_export
game_update_and_render :: (
    game_memory: *Game_Memory,
    input: *Game_Input,
    buffer: *Game_Offscreen_Buffer
) -> bool {
    assert(game_memory != null);
    #if HANDMADE_DEBUG {
        assert(size_of(Game_State) <= game_memory.permanent.count);
        assert((*input.controllers[0].terminator - *input.controllers[0].up) == input.controllers[0].buttons.count);
    }

    state := cast(*Game_State)game_memory.permanent.data;
    if !game_memory.initialized {
        game_memory.initialized = true;
    }

    for controller: input.controllers {
        if controller.analog {
             // NOTE: Use analog movement tuning
        } else {
            // NOTE: Use digital movement tuning
            d_player_x := 0.0;  // pixels/second
            d_player_y := 0.0;  // pixels/second

            // TODO: take a close look at timing, because it appears things are
            // moving 1/2 as fast as expected
            if controller.up.ended_down {
                d_player_y = -1;
            }
            if controller.down.ended_down {
                d_player_y = 1;
            }
            if controller.left.ended_down {
                d_player_x = -1;
            }
            if controller.right.ended_down {
                d_player_x = 1;
            }

            // TODO: diagonal will be faster, fix once we have vectors!
            d_player_x *= 128;  // speed him up
            d_player_y *= 128;  // speed him up
            state.player_x += input.dt_for_frame * d_player_x;
            state.player_y += input.dt_for_frame * d_player_y;
        }
    }



    HEIGHT :: 9;
    WIDTH  :: 17;
    TILE_HEIGHT : float : 60;
    TILE_WIDTH : float : 60;
    upper_left_x := -30;
    upper_left_y := 0 ;


    tile_map: [HEIGHT][WIDTH]u32 = .[
        .[1, 1, 1, 1,  1, 1, 1, 1,  0, 1, 1, 1,  1, 1, 1, 1, 1],
        .[1, 1, 0, 0,  0, 1, 0, 0,  0, 0, 0, 0,  0, 1, 0, 0, 1],
        .[1, 1, 0, 0,  0, 0, 0, 0,  1, 0, 0, 0,  0, 0, 1, 0, 1],
        .[1, 0, 0, 0,  0, 0, 0, 0,  1, 0, 0, 0,  0, 0, 0, 0, 1],
        .[1, 1, 0, 0,  0, 1, 0, 0,  1, 0, 0, 0,  0, 0, 1, 0, 0],
        .[1, 1, 0, 0,  0, 1, 0, 0,  1, 0, 0, 0,  0, 1, 0, 0, 1],
        .[1, 0, 0, 0,  0, 1, 0, 0,  1, 0, 0, 0,  1, 0, 0, 0, 1],
        .[1, 1, 1, 1,  1, 0, 0, 0,  0, 0, 0, 0,  0, 1, 0, 0, 1],
        .[1, 1, 1, 1,  1, 1, 1, 1,  0, 1, 1, 1,  1, 1, 1, 1, 1],
    ];

    draw_rectangle(buffer, 0, 0, cast(float)buffer.width, cast(float)buffer.height, 1, 0, 1);

    for row: tile_map {
        y := it_index;
        for tile: row {
            x := it_index;
            gray := ifx tile == 1  1.0 else .5;
            min_x := upper_left_x + x*TILE_WIDTH;
            min_y := upper_left_y + y*TILE_HEIGHT;
            max_x := min_x + TILE_WIDTH;
            max_y := min_y + TILE_HEIGHT;
            draw_rectangle(buffer, min_x, min_y, max_x, max_y, gray, gray, gray);
        }
    }

    player_r := 1.0;
    player_g := 1.0;
    player_b := 0.0;
    player_width := .75 * TILE_WIDTH;
    player_height := .75 * TILE_HEIGHT;
    player_left := state.player_x - 0.5*player_width;
    player_top := state.player_y - player_height;
    draw_rectangle(buffer, player_left, player_top, player_left + player_width, player_top + player_height,
                   player_r, player_g, player_b);

    return true;
}

#load "handmade_h.jai";

#import "Basic";
#import "Math";

/*
render_weird_gradient :: (back_buffer: *Game_Offscreen_Buffer, xOffset: int, yOffset: int) {
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
*/
