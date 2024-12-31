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

get_tile_chunk :: (world: *World, tile_chunk_x: u32, tile_chunk_y: u32) -> Tile_Chunk {
    if tile_chunk_x >= 0 && tile_chunk_x < world.tile_chunk_count_x &&
        tile_chunk_y >= 0 && tile_chunk_y < world.tile_chunk_count_y
    {
        return Tile_Chunk.{.{
            count = world.chunk_dim * world.chunk_dim,
            data = *world.tile_chunks.tiles[tile_chunk_y * world.tile_chunk_count_x + tile_chunk_x],
        }};
    }
    return .{};
}

get_tile_value_unchecked :: (world: *World, tile_chunk: *Tile_Chunk, tile_x: u32, tile_y: u32) -> u32 {
    assert(tile_chunk != null);
    assert(tile_y < world.chunk_dim);
    assert(tile_x < world.chunk_dim);

    tile_chunk_value := tile_chunk.tiles[tile_y * world.chunk_dim + tile_x];
    return tile_chunk_value;
}

get_tile_value :: (world: *World, tile_chunk: *Tile_Chunk, test_tile_x: u32, test_tile_y: u32) -> u32 {
    tile_chunk_value : u32 = 0;
    if tile_chunk.tiles {
        tile_chunk_value = get_tile_value_unchecked(world, tile_chunk, test_tile_x, test_tile_y);
    }
    return tile_chunk_value;
}

re_canonicalize_coord :: (world: *World, tile: *u32, tile_rel: *float) {
    // NOTE: world is toroidal
    offset := floor_float_to_s32(tile_rel.* / world.tile_side_in_meters);
    new_tile := cast(s32)tile.*;  // because we can't add/subtract s32 from u32
    new_tile += offset;
    tile.* = cast(u32)new_tile;
    tile_rel.* -= offset * world.tile_side_in_meters;

    assert(tile_rel.* >= 0);
    assert(tile_rel.* <= world.tile_side_in_meters);
}


re_canonicalize_position :: (world: *World, pos: World_Position) -> World_Position {
    res := pos;

    re_canonicalize_coord(world, *res.abs_tile_x, *res.tile_rel_x);
    re_canonicalize_coord(world, *res.abs_tile_y, *res.tile_rel_y);

    return res;
}

get_chunk_pos_for :: (world: *World, abs_tile_x: u32, abs_tile_y: u32) -> Tile_Chunk_Position {
    res: Tile_Chunk_Position;
    res.tile_chunk_x = abs_tile_x >> world.chunk_shift;
    res.tile_chunk_y = abs_tile_y >> world.chunk_shift;
    res.rel_tile_x = abs_tile_x & world.chunk_mask;
    res.rel_tile_y = abs_tile_y & world.chunk_mask;
    return res;
}

get_tile_value :: (world: *World, abs_tile_x: u32, abs_tile_y: u32) -> u32 {
    chunk_pos := get_chunk_pos_for(world, abs_tile_x, abs_tile_y);
    tile_map := get_tile_chunk(world, chunk_pos.tile_chunk_x, chunk_pos.tile_chunk_y);
    tile := get_tile_value(world, *tile_map, chunk_pos.rel_tile_x, chunk_pos.rel_tile_y);

    return tile;
}

is_world_point_empty :: (world: *World, can_pos: World_Position) -> bool {
    tile_chunk_value := get_tile_value(world, can_pos.abs_tile_x, can_pos.abs_tile_y);

    return tile_chunk_value == 0;
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

    TILE_COUNT_X :: 256;
    TILE_COUNT_Y :: 256;

    //#load "tile_map.jai";
    //tiles := get_tile_map();

    filled_in_tile_map : [][]u32 = .[
        .[1, 1, 1, 1,  1, 1, 1, 1,  1, 1, 1, 1,  1, 1, 1, 1, 1,  1, 1, 1, 1,  1, 1, 1, 1,  1, 1, 1, 1,  1, 1, 1, 1, 1],
        .[1, 1, 0, 0,  0, 1, 0, 0,  0, 0, 0, 0,  0, 1, 0, 0, 1,  1, 0, 0, 0,  0, 0, 0, 0,  0, 0, 0, 0,  0, 0, 0, 0, 1],
        .[1, 1, 0, 0,  0, 0, 0, 0,  1, 0, 0, 0,  0, 0, 1, 0, 1,  1, 0, 0, 0,  0, 0, 0, 0,  0, 0, 0, 0,  0, 0, 0, 0, 1],
        .[1, 0, 0, 0,  0, 0, 0, 0,  1, 0, 0, 0,  0, 0, 0, 0, 1,  1, 0, 0, 0,  0, 0, 0, 0,  0, 0, 0, 0,  0, 0, 0, 0, 1],
        .[1, 0, 0, 0,  0, 1, 0, 0,  1, 0, 0, 0,  0, 0, 0, 0, 0,  0, 0, 0, 0,  0, 0, 0, 0,  0, 0, 0, 0,  0, 0, 0, 0, 1],
        .[1, 1, 0, 0,  0, 1, 0, 0,  1, 0, 0, 0,  0, 1, 0, 0, 1,  1, 0, 0, 0,  0, 0, 0, 0,  0, 0, 0, 0,  0, 0, 0, 0, 1],
        .[1, 0, 0, 0,  0, 1, 0, 0,  1, 0, 0, 0,  1, 0, 0, 0, 1,  1, 0, 0, 0,  0, 0, 0, 0,  0, 0, 0, 0,  0, 0, 0, 0, 1],
        .[1, 1, 1, 1,  1, 0, 0, 0,  0, 0, 0, 0,  0, 1, 0, 0, 1,  1, 0, 0, 0,  0, 0, 0, 0,  0, 0, 0, 0,  0, 0, 0, 0, 1],
        .[1, 1, 1, 1,  1, 1, 1, 1,  0, 1, 1, 1,  1, 1, 1, 1, 1,  1, 1, 1, 1,  1, 1, 1, 1,  0, 1, 1, 1,  1, 1, 1, 1, 1],
        .[1, 1, 1, 1,  1, 1, 1, 1,  0, 1, 1, 1,  1, 1, 1, 1, 1,  1, 1, 1, 1,  1, 1, 1, 1,  0, 1, 1, 1,  1, 1, 1, 1, 1],
        .[1, 0, 0, 0,  0, 0, 0, 0,  0, 0, 0, 0,  0, 0, 0, 0, 1,  1, 0, 0, 0,  0, 0, 0, 0,  0, 0, 0, 0,  0, 0, 0, 0, 1],
        .[1, 0, 0, 0,  0, 0, 0, 0,  0, 0, 0, 0,  0, 0, 0, 0, 1,  1, 0, 0, 0,  0, 0, 0, 0,  0, 0, 0, 0,  0, 0, 0, 0, 1],
        .[1, 0, 0, 0,  0, 0, 0, 0,  0, 0, 0, 0,  0, 0, 0, 0, 1,  1, 0, 0, 0,  0, 0, 0, 0,  0, 0, 0, 0,  0, 0, 0, 0, 1],
        .[1, 0, 0, 0,  0, 0, 0, 0,  0, 0, 0, 0,  0, 0, 0, 0, 0,  0, 0, 0, 0,  0, 0, 0, 0,  0, 0, 0, 0,  0, 0, 0, 0, 1],
        .[1, 0, 0, 0,  0, 0, 0, 0,  0, 0, 0, 0,  0, 0, 0, 0, 1,  1, 0, 0, 0,  0, 0, 0, 0,  0, 0, 0, 0,  0, 0, 0, 0, 1],
        .[1, 0, 0, 0,  0, 0, 0, 0,  0, 0, 0, 0,  0, 0, 0, 0, 1,  1, 0, 0, 0,  0, 0, 0, 0,  0, 0, 0, 0,  0, 0, 0, 0, 1],
        .[1, 0, 0, 0,  0, 0, 0, 0,  0, 0, 0, 0,  0, 0, 0, 0, 1,  1, 0, 0, 0,  0, 0, 0, 0,  0, 0, 0, 0,  0, 0, 0, 0, 1],
        .[1, 1, 1, 1,  1, 1, 1, 1,  1, 1, 1, 1,  1, 1, 1, 1, 1,  1, 1, 1, 1,  1, 1, 1, 1,  1, 1, 1, 1,  1, 1, 1, 1, 1],
    ];

    // we want the non filled-in-tiles to be zero
    tiles : [TILE_COUNT_Y][TILE_COUNT_X]u32;

    // now fill in what we have  (could do a memcpy, but this is probably almost as fast)
    for row: filled_in_tile_map {
        row_index := it_index;
        for row {
            tiles[row_index][it_index] = it;
        }
    }

    tile_chunk := Tile_Chunk.{.{
        count    = TILE_COUNT_X * TILE_COUNT_Y,
        data     = cast(*u32)tiles.data,
    }};

    world := World.{
        tile_side_in_meters = 1.4,
        tile_side_in_pixels = 60,
        tile_chunk_count_x  = 1,
        tile_chunk_count_y  = 1,
        tile_chunks         = *tile_chunk,
    };
    world.meters_to_pixels = cast(float)world.tile_side_in_pixels / cast(float)world.tile_side_in_meters;
    world.chunk_shift = 8;
    world.chunk_mask = cast(u32)((1 << world.chunk_shift) - 1);
    world.chunk_dim = 256;

    player_height := world.tile_side_in_meters;
    player_width := .75 * player_height;

    lower_left_x := -cast(float)world.tile_side_in_pixels/2;
    lower_left_y := cast(float)buffer.height;

    state := cast(*Game_State)game_memory.permanent.data;
    if !game_memory.initialized {
        state.player_p.abs_tile_x = 3;
        state.player_p.abs_tile_y = 3;
        state.player_p.tile_rel_x = 5;
        state.player_p.tile_rel_y = 5;

        game_memory.initialized = true;
    }

    for controller: input.controllers {
        if controller.analog {
             // NOTE: Use analog movement tuning
        } else {
            // NOTE: Use digital movement tuning
            d_player_x := 0.0;  // pixels/second
            d_player_y := 0.0;  // pixels/second

            if controller.up.ended_down {
                d_player_y = 1;
            }
            if controller.down.ended_down {
                d_player_y = -1;
            }
            if controller.left.ended_down {
                d_player_x = -1;
            }
            if controller.right.ended_down {
                d_player_x = 1;
            }

            // TODO: diagonal will be faster, fix once we have vectors!
            // MOVEMENT
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

    center_x := 0.5 * cast(float)buffer.width;
    center_y := 0.5 * cast(float)buffer.height;

    // DRAW MAP
    for rel_row: -10..9 {
        for rel_col: -20..19 {
            col : u32 = cast,trunc(u32)(cast(s32)state.player_p.abs_tile_x + rel_col);
            row : u32 = cast,trunc(u32)(cast(s32)state.player_p.abs_tile_y + rel_row);
            tile_id := get_tile_value(*world, col, row);

            gray := ifx tile_id == 1  1.0 else .5;
            gray  = ifx state.player_p.abs_tile_x == col && state.player_p.abs_tile_y == row  0 else gray;

            min_x := center_x + rel_col * cast(float)world.tile_side_in_pixels;
            min_y := center_y - rel_row * cast(float)world.tile_side_in_pixels;
            max_x := min_x + world.tile_side_in_pixels;
            max_y := min_y - world.tile_side_in_pixels;
            draw_rectangle(buffer, min_x, max_y, max_x, min_y, gray, gray, gray);
        }
    }

    // DRAW PLAYER
    player_r, player_g, player_b := 1.0, 1.0, 0.0;

    player_left := center_x + world.meters_to_pixels * state.player_p.tile_rel_x - .5 * world.meters_to_pixels * player_width;
    player_top  := center_y - world.meters_to_pixels * state.player_p.tile_rel_y - world.meters_to_pixels * player_height;
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
