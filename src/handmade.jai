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

get_tile_value_unchecked :: inline (map: *Tile_Map, x: u32, y: u32) -> u32 {
    return map.tiles[y * map.count_x + x];
}

get_tile_map :: inline (world: *World, tile_map_x: u32, tile_map_y: u32) -> *Tile_Map {
    if tile_map_x < world.count_x && tile_map_y < world.count_y {
        return *world.tile_maps[tile_map_y * world.count_x + tile_map_x];
    }
    return null;
}

is_tile_map_point_empty :: (map: *Tile_Map, x: float, y: float) -> bool {
    player_tile_x := cast,trunc(u32)((x - map.upper_left_x)/map.tile_width);
    player_tile_y := cast,trunc(u32)((y - map.upper_left_y)/map.tile_height);

    is_valid := false;
    if player_tile_x >= 0 && player_tile_x < map.count_x && player_tile_y >= 0 && player_tile_y < map.count_y {
        is_valid = get_tile_value_unchecked(map, player_tile_x, player_tile_y) == 0;
    }
    return is_valid;
}

is_world_map_point_empty :: (world: *World, tile_map_x: u32, tile_map_y: u32, test_x: float, test_y: float) -> bool {
    empty := false;

    map := get_tile_map(world, tile_map_x, tile_map_y);
    if map {
        player_tile_x := cast,trunc(u32)((test_x - map.upper_left_x)/map.tile_width);
        player_tile_y := cast,trunc(u32)((test_y - map.upper_left_y)/map.tile_height);

        if player_tile_x >= 0 && player_tile_x < map.count_x && player_tile_y >= 0 && player_tile_y < map.count_y {
            empty = get_tile_value_unchecked(map, player_tile_x, player_tile_x) == 0;
        }
    }

    return empty;
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

    TILE_COUNT_X :: 17;
    TILE_COUNT_Y :: 9;

    tile_map_00: [TILE_COUNT_Y][TILE_COUNT_X]u32 = .[
        .[1, 1, 1, 1,  1, 1, 1, 1,  1, 1, 1, 1,  1, 1, 1, 1, 1],
        .[1, 1, 0, 0,  0, 1, 0, 0,  0, 0, 0, 0,  0, 1, 0, 0, 1],
        .[1, 1, 0, 0,  0, 0, 0, 0,  1, 0, 0, 0,  0, 0, 1, 0, 1],
        .[1, 0, 0, 0,  0, 0, 0, 0,  1, 0, 0, 0,  0, 0, 0, 0, 1],
        .[1, 1, 0, 0,  0, 1, 0, 0,  1, 0, 0, 0,  0, 0, 1, 0, 0],
        .[1, 1, 0, 0,  0, 1, 0, 0,  1, 0, 0, 0,  0, 1, 0, 0, 1],
        .[1, 0, 0, 0,  0, 1, 0, 0,  1, 0, 0, 0,  1, 0, 0, 0, 1],
        .[1, 1, 1, 1,  1, 0, 0, 0,  0, 0, 0, 0,  0, 1, 0, 0, 1],
        .[1, 1, 1, 1,  1, 1, 1, 1,  0, 1, 1, 1,  1, 1, 1, 1, 1],
    ];
    tile_map_01: [TILE_COUNT_Y][TILE_COUNT_X]u32 = .[
        .[1, 1, 1, 1,  1, 1, 1, 1,  0, 1, 1, 1,  1, 1, 1, 1, 1],
        .[1, 1, 0, 0,  0, 0, 0, 0,  0, 0, 0, 0,  0, 1, 0, 0, 1],
        .[1, 1, 0, 0,  0, 0, 0, 0,  1, 0, 0, 0,  0, 0, 1, 0, 1],
        .[1, 0, 0, 0,  0, 0, 0, 0,  1, 0, 0, 0,  0, 0, 0, 0, 1],
        .[0, 1, 0, 0,  0, 0, 0, 0,  1, 0, 0, 0,  0, 0, 0, 0, 1],
        .[1, 1, 0, 0,  0, 0, 0, 0,  1, 0, 0, 0,  0, 1, 0, 0, 1],
        .[1, 0, 0, 0,  0, 0, 0, 0,  1, 0, 0, 0,  1, 0, 0, 0, 1],
        .[1, 1, 1, 1,  1, 0, 0, 0,  0, 0, 0, 0,  0, 1, 0, 0, 1],
        .[1, 1, 1, 1,  1, 1, 1, 1,  0, 1, 1, 1,  1, 1, 1, 1, 1],
    ];

    tile_map_10: [TILE_COUNT_Y][TILE_COUNT_X]u32 = .[
        .[1, 1, 1, 1,  1, 1, 1, 1,  0, 1, 1, 1,  1, 1, 1, 1, 1],
        .[1, 1, 0, 0,  0, 1, 0, 0,  0, 0, 0, 0,  0, 1, 0, 0, 1],
        .[1, 1, 0, 0,  0, 0, 0, 0,  1, 0, 0, 0,  0, 0, 1, 0, 1],
        .[1, 0, 0, 0,  0, 0, 0, 0,  1, 0, 0, 0,  0, 0, 0, 0, 1],
        .[1, 1, 0, 0,  0, 1, 0, 0,  1, 0, 0, 0,  0, 0, 1, 0, 0],
        .[1, 1, 0, 0,  0, 1, 0, 0,  1, 0, 0, 0,  0, 1, 0, 0, 1],
        .[1, 0, 0, 0,  0, 1, 0, 0,  1, 0, 0, 0,  1, 0, 0, 0, 1],
        .[1, 1, 1, 1,  1, 0, 0, 0,  0, 0, 0, 0,  0, 1, 0, 0, 1],
        .[1, 1, 1, 1,  1, 1, 1, 1,  1, 1, 1, 1,  1, 1, 1, 1, 1],
    ];
    tile_map_11: [TILE_COUNT_Y][TILE_COUNT_X]u32 = .[
        .[1, 1, 1, 1,  1, 1, 1, 1,  0, 1, 1, 1,  1, 1, 1, 1, 1],
        .[1, 1, 0, 0,  0, 0, 0, 0,  0, 0, 0, 0,  0, 1, 0, 0, 1],
        .[1, 1, 0, 0,  0, 0, 0, 0,  1, 0, 0, 0,  0, 0, 1, 0, 1],
        .[1, 0, 0, 0,  0, 0, 0, 0,  1, 0, 0, 0,  0, 0, 0, 0, 1],
        .[0, 1, 0, 0,  0, 0, 0, 0,  1, 0, 0, 0,  0, 0, 0, 0, 1],
        .[1, 1, 0, 0,  0, 0, 0, 0,  1, 0, 0, 0,  0, 1, 0, 0, 1],
        .[1, 0, 0, 0,  0, 0, 0, 0,  1, 0, 0, 0,  1, 0, 0, 0, 1],
        .[1, 1, 1, 1,  1, 0, 0, 0,  0, 0, 0, 0,  0, 1, 0, 0, 1],
        .[1, 1, 1, 1,  1, 1, 1, 1,  1, 1, 1, 1,  1, 1, 1, 1, 1],
    ];

    tile_maps: [2][2]Tile_Map;

    tile_maps[0][0] = Tile_Map.{
        count_x      = TILE_COUNT_X,
        count_y      = TILE_COUNT_Y,
        upper_left_x = -30,
        upper_left_y = 0,
        tile_height  = 60,
        tile_width   = 60,
        tiles        = .{
            count    = TILE_COUNT_X * TILE_COUNT_Y,
            data     = cast(*u32)tile_map_00.data,
        },
    };

    tile_maps[0][1] = tile_maps[0][0];
    tile_maps[0][1].tiles.data = cast(*u32)tile_map_01.data;

    tile_maps[1][0] = tile_maps[0][0];
    tile_maps[1][0].tiles.data = cast(*u32)tile_map_10.data;

    tile_maps[1][1] = tile_maps[0][0];
    tile_maps[1][1].tiles.data = cast(*u32)tile_map_11.data;

    map := *tile_maps[0][0];

    world := World.{
        count_x = 2,
        count_y = 2,
        tile_maps = cast(*Tile_Map)tile_maps.data,
    };

    state := cast(*Game_State)game_memory.permanent.data;
    if !game_memory.initialized {
        game_memory.initialized = true;
        state.player_x = 150;
        state.player_y = 150;
    }

    player_width := .6 * map.tile_width;
    player_height := .75 * map.tile_height;

    for controller: input.controllers {
        if controller.analog {
             // NOTE: Use analog movement tuning
        } else {
            // NOTE: Use digital movement tuning
            d_player_x := 0.0;  // pixels/second
            d_player_y := 0.0;  // pixels/second

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
            d_player_x *= 64;  // speed him up
            d_player_y *= 64;  // speed him up
            new_player_x := state.player_x + input.dt_for_frame * d_player_x;
            new_player_y := state.player_y + input.dt_for_frame * d_player_y;
            new_player_left := new_player_x - 0.5*player_width;

            if is_tile_map_point_empty(map, new_player_left, new_player_y) &&
                is_tile_map_point_empty(map, new_player_left + player_width, new_player_y) {
                state.player_x = new_player_x;
                state.player_y = new_player_y;
            }
        }
    }

    draw_rectangle(buffer, 0, 0, cast(float)buffer.width, cast(float)buffer.height, 1, 0, 1);

    for y: 0..map.count_y-1 {
        for x: 0..map.count_x-1 {
            tile := get_tile_value_unchecked(map, x, y);
            gray := ifx tile == 1  1.0 else .5;
            min_x := map.upper_left_x + x*map.tile_width;
            min_y := map.upper_left_y + y*map.tile_height;
            max_x := min_x + map.tile_width;
            max_y := min_y + map.tile_height;
            draw_rectangle(buffer, min_x, min_y, max_x, max_y, gray, gray, gray);
        }
    }

    player_r := 1.0;
    player_g := 1.0;
    player_b := 0.0;
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
