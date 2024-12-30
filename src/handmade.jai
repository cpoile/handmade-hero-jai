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

// NOTE: at the moment this has to be a very fast function, it cannot be more than a ms or so.
#program_export
game_get_sound_samples :: (game_memory: *Game_Memory, sound_buffer: *Game_Sound_Buffer) {
    // TODO: Allow sample offsets here (eg, set sound further out in the future, or closer to immediately)
    state := cast(*Game_State)game_memory.permanent.data;

    game_sound_output(sound_buffer);
}

get_tile_value_unchecked :: inline (world: *World, map: *Tile_Map, x: s32, y: s32) -> u32 {
    assert(map != null);
    assert(x >= 0 && x < world.tile_count_x && y >= 0 && y < world.tile_count_y);

    return map.tiles[y * world.tile_count_x + x];
}

get_tile_map :: inline (world: *World, tile_map_x: s32, tile_map_y: s32) -> *Tile_Map {
    if tile_map_x < world.world_count_x && tile_map_y < world.world_count_y {
        return *world.tile_maps[tile_map_y * world.world_count_x + tile_map_x];
    }
    return null;
}

is_tile_map_point_empty :: (world: *World, map: *Tile_Map, test_tile_x: s32, test_tile_y: s32) -> bool {
    if world == null || map == null  return false;

    empty := false;
    if test_tile_x >= 0 && test_tile_x < world.tile_count_x && test_tile_y >= 0 && test_tile_y < world.tile_count_y {
        empty = get_tile_value_unchecked(world, map, test_tile_x, test_tile_y) == 0;
    }
    return empty;
}

re_canonicalize_coord :: (world: *World, tile_count: s32, tile_map: *s32, tile: *s32, tile_rel: *float) {
    // TODO: this can end up rounding back to the tile you just came from.
    // TODO: add bounds checking to prevent wrapping
    offset := floor_float_to_s32(tile_rel.* / world.tile_side_in_meters);
    tile.* += offset;
    tile_rel.* -= offset * world.tile_side_in_meters;

    assert(tile_rel.* >= 0);
    // TODO: should be <
    assert(tile_rel.* <= cast(float)world.tile_side_in_meters);

    if tile.* < 0 {
        tile.* = tile_count + tile.*;
        tile_map.* -= 1;
    }
    if tile.* >= tile_count {
        tile.* = tile.* - tile_count;
        tile_map.* += 1;
    }
}


re_canonicalize_position :: (world: *World, pos: Canonical_Position) -> Canonical_Position {
    res := pos;

    re_canonicalize_coord(world, world.tile_count_x, *res.tile_map_x, *res.tile_x, *res.tile_rel_x);
    re_canonicalize_coord(world, world.tile_count_y, *res.tile_map_y, *res.tile_y, *res.tile_rel_y);

    return res;
}

is_world_point_empty :: (world: *World, pos: Canonical_Position) -> bool {
    tile_map := get_tile_map(world, pos.tile_map_x, pos.tile_map_y);
    empty := is_tile_map_point_empty(world, tile_map, pos.tile_x, pos.tile_y);

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
    empty := false;
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
        .[1, 1, 1, 1,  1, 1, 1, 1,  1, 1, 1, 1,  1, 1, 1, 1, 1],
        .[1, 1, 0, 0,  0, 0, 0, 0,  0, 0, 0, 0,  0, 1, 0, 0, 1],
        .[1, 1, 0, 0,  0, 0, 0, 0,  1, 0, 0, 0,  0, 0, 1, 0, 1],
        .[1, 0, 0, 0,  0, 0, 0, 0,  0, 0, 0, 0,  0, 0, 0, 0, 1],
        .[0, 0, 0, 0,  0, 0, 0, 0,  0, 0, 0, 0,  0, 0, 0, 0, 1],
        .[1, 1, 0, 0,  0, 0, 0, 0,  1, 0, 0, 0,  0, 1, 0, 0, 1],
        .[1, 0, 0, 0,  0, 0, 0, 0,  0, 0, 0, 0,  1, 0, 0, 0, 1],
        .[1, 1, 1, 1,  1, 0, 0, 0,  0, 0, 0, 0,  0, 1, 0, 0, 1],
        .[1, 1, 1, 1,  1, 1, 1, 1,  0, 1, 1, 1,  1, 1, 1, 1, 1],
    ];

    tile_map_10: [TILE_COUNT_Y][TILE_COUNT_X]u32 = .[
        .[1, 1, 1, 1,  1, 1, 1, 1,  0, 1, 1, 1,  1, 1, 1, 1, 1],
        .[1, 1, 0, 0,  0, 1, 0, 0,  0, 0, 0, 0,  0, 1, 0, 0, 1],
        .[1, 1, 0, 0,  0, 0, 0, 0,  1, 0, 0, 0,  0, 0, 1, 0, 1],
        .[1, 0, 0, 0,  0, 0, 0, 0,  1, 0, 0, 0,  0, 0, 0, 0, 1],
        .[1, 1, 0, 0,  0, 1, 0, 0,  1, 0, 0, 0,  0, 0, 0, 0, 0],
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
        .[0, 0, 0, 0,  0, 0, 0, 0,  1, 0, 0, 0,  0, 0, 0, 0, 1],
        .[1, 1, 0, 0,  0, 0, 0, 0,  1, 0, 0, 0,  0, 1, 0, 0, 1],
        .[1, 0, 0, 0,  0, 0, 0, 0,  1, 0, 0, 0,  1, 0, 0, 0, 1],
        .[1, 1, 1, 1,  1, 0, 0, 0,  0, 0, 0, 0,  0, 1, 0, 0, 1],
        .[1, 1, 1, 1,  1, 1, 1, 1,  1, 1, 1, 1,  1, 1, 1, 1, 1],
    ];

    tile_maps: [2][2]Tile_Map;

    tile_maps[0][0] = Tile_Map.{.{
            count    = TILE_COUNT_X * TILE_COUNT_Y,
            data     = cast(*u32)tile_map_00.data,
        },
    };
    tile_maps[0][1] = Tile_Map.{.{
            count    = TILE_COUNT_X * TILE_COUNT_Y,
            data     = cast(*u32)tile_map_01.data,
        },
    };
    tile_maps[1][0] = Tile_Map.{.{
            count    = TILE_COUNT_X * TILE_COUNT_Y,
            data     = cast(*u32)tile_map_10.data,
        },
    };
    tile_maps[1][1] = Tile_Map.{.{
            count    = TILE_COUNT_X * TILE_COUNT_Y,
            data     = cast(*u32)tile_map_11.data,
        },
    };

    world := World.{
        tile_side_in_meters = 1.4,
        tile_side_in_pixels = 60,
        world_count_x = 2,
        world_count_y = 2,
        tile_count_x  = TILE_COUNT_X,
        tile_count_y  = TILE_COUNT_Y,
        upper_left_y  = 0,
        tile_maps     = cast(*Tile_Map)tile_maps.data,
    };
    world.upper_left_x = cast(float)-world.tile_side_in_pixels/2;
    world.meters_to_pixels = cast(float)world.tile_side_in_pixels / cast(float)world.tile_side_in_meters;

    state := cast(*Game_State)game_memory.permanent.data;
    if !game_memory.initialized {
        game_memory.initialized = true;
        state.player_p.tile_map_x = 0;
        state.player_p.tile_map_y = 0;
        state.player_p.tile_x = 3;
        state.player_p.tile_y = 3;
        state.player_p.tile_rel_x = .5;
        state.player_p.tile_rel_y = .5;
    }

    map := get_tile_map(*world, state.player_p.tile_map_x, state.player_p.tile_map_y);
    assert(map != null);

    player_height := world.tile_side_in_meters;
    player_width := .75 * player_height;

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
            // SPEDE
            d_player_x *= 8;  // speed him up
            d_player_y *= 8;  // speed him up

            new_player_p := state.player_p;
             new_player_p.tile_rel_x += input.dt_for_frame * d_player_x;
            new_player_p.tile_rel_y += input.dt_for_frame * d_player_y;
            new_player_p = re_canonicalize_position(*world, new_player_p);

            player_left := new_player_p;
            player_left.tile_rel_x -= 0.5*player_width;
            player_left = re_canonicalize_position(*world, player_left);

            player_right := new_player_p;
            player_right.tile_rel_x += 0.5*player_width;
            player_right = re_canonicalize_position(*world, player_right);

            if is_world_point_empty(*world, player_left) && is_world_point_empty(*world, player_right) {
                state.player_p = new_player_p;
            }
        }
    }

    draw_rectangle(buffer, 0, 0, cast(float)buffer.width, cast(float)buffer.height, 1, 0, 1);

    // DRAW MAP
    for y: 0..world.tile_count_y-1 {
        for x: 0..world.tile_count_x-1 {
            tile := get_tile_value_unchecked(*world, map, x, y);
            gray := ifx tile == 1  1.0 else .5;
            gray  = ifx state.player_p.tile_x == x && state.player_p.tile_y == y  0 else gray;
            min_x := world.upper_left_x + x*world.tile_side_in_pixels;
            min_y := world.upper_left_y + y*world.tile_side_in_pixels;
            max_x := min_x + world.tile_side_in_pixels;
            max_y := min_y + world.tile_side_in_pixels;
            draw_rectangle(buffer, min_x, min_y, max_x, max_y, gray, gray, gray);
        }
    }

    // DRAW PLAYER
    player_r := 1.0;
    player_g := 1.0;
    player_b := 0.0;
    player_left := world.upper_left_x + world.tile_side_in_pixels * state.player_p.tile_x +
        world.meters_to_pixels * state.player_p.tile_rel_x - 0.5*world.meters_to_pixels*player_width;
    player_top := world.upper_left_y + world.tile_side_in_pixels * state.player_p.tile_y +
        world.meters_to_pixels * state.player_p.tile_rel_y - world.meters_to_pixels* player_height;
    draw_rectangle(buffer,
                   player_left, player_top,
                   player_left + world.meters_to_pixels * player_width,
                   player_top + world.meters_to_pixels * player_height,
                   player_r, player_g, player_b);

    return true;
}

#load "handmade_h.jai";
#load "handmade_intrinsics.jai";

#import "Basic";

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
