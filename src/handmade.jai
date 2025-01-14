// Platform-independent game code

CHUNK_SHIFT        :: 4;
CHUNK_DIM          :: 1 << 4;

//
//  Game state
//

Memory_Arena :: struct {
    memory : []u8;
    free   : []u8;
}

World :: struct {
     tile_map : *Tile_Map;
}

Hero_Bitmap :: struct {
    align_x : s32;
    align_y : s32;
    head    : Bitmap;
    cape    : Bitmap;
    torso   : Bitmap;
}

DIRECTION :: enum s8 {
    UP    :: 1;
    DOWN  :: 3;
    LEFT  :: 2;
    RIGHT :: 0;
}

Entity :: struct {
    exists           : bool;
    p                : Tile_Map_Position;
    d_p              : Vector2;
    facing_direction : DIRECTION;
    height, width    : float;
}

Game_State :: struct {
    world_arena : Memory_Arena;
    world       : *World;

    // TODO: should we allow split-screen?
    camera_following_entity_index : u32;
    camera_p                      : Tile_Map_Position;
    entity_count                  : u32;
    entities                      : [256]Entity;  // we should be using a dynamic array with our perm storage.

    player_index_for_controller     : [MAX_INPUTS]u32;

    super_speed      : bool;
    background       : Bitmap;
    hero_bitmaps     : [4]Hero_Bitmap;
}

Raw_Position :: struct {
    tile_map_x : s32;
    tile_map_y : s32;

    // NOTE: this is tile-map relative x and y.
    x          : float;
    y          : float;
}

Bitmap_Header :: struct {
    file_type        : u16 #align 1;
    file_size        : u32 #align 1;
    reserved_1       : u16 #align 1;
    reserved_2       : u16 #align 1;
    bitmap_offset    : u32 #align 1;
    size             : u32 #align 1;
    width            : s32 #align 1;
    height           : s32 #align 1;
    planes           : u16 #align 1;
    bits_per_pixel   : u16 #align 1;
    compression      : u32 #align 1;
    size_of_bitmap   : u32 #align 1;
    horz_resolution  : s32 #align 1;
    vert_resolution  : s32 #align 1;
    colors_used      : u32 #align 1;
    colors_important : u32 #align 1;
    red_mask         : u32 #align 1;
    green_mask       : u32 #align 1;
    blue_mask        : u32 #align 1;
} #no_padding;

Bitmap :: struct {
    pixels        : []u32;
    width, height : s32;
    pitch         : u32;
}

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
    real_min: Vector2, real_max: Vector2,
    r: float, g: float, b: float)
{
    min_x, min_y := round_s32(real_min);
    max_x, max_y := round_s32(real_max);

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

    for min_y..max_y-1 {
        pixel := cast(*u32)row;
        for min_x..max_x-1 {
            <<pixel = color;
            pixel += 1;
        }

        row += buffer.pitch;
    }
}

draw_bitmap :: (buffer: *Game_Offscreen_Buffer, bitmap: Bitmap,
                x: float, y: float, align_x: s32 = 0, align_y: s32 = 0)
{
    x -= align_x;
    y -= align_y;

    min_x := round_s32(x);
    min_y := round_s32(y);
    max_x := round_s32(x + cast(float)bitmap.width);
    max_y := round_s32(y + cast(float)bitmap.height);

    src_offset_x := 0;
    if min_x < 0 {
        src_offset_x = -min_x;
        min_x = 0;
    }
    src_offset_y := 0;
    if min_y < 0 {
        src_offset_y = -min_y;
        min_y = 0;
    }
    if max_x > buffer.width   max_x = buffer.width;
    if max_y > buffer.height  max_y = buffer.height;

    // don't try to draw if we have zero width or zero height
    if min_x == max_x  return;
    if min_y == max_y  return;

    // TODO: src_row needs to be changed based on clipping
    src_row := bitmap.pixels.data + (bitmap.height - 1) * xx bitmap.pitch;
    src_row += -src_offset_y * bitmap.pitch + src_offset_x;
    dest_row := buffer.memory + min_y * buffer.pitch + min_x * buffer.bytes_per_pixel;
    for min_y..max_y-1 {
        dest_pixel := cast(*u32) dest_row;
        src_pixel := src_row;
        for min_x..max_x-1 {
            a := cast(float)((src_pixel.* >> 24) & 0xFF)/255.0;

            sr := cast(float)((src_pixel.* >> 16) & 0xFF);
            sg := cast(float)((src_pixel.* >> 8) & 0xFF);
            sb := cast(float)(src_pixel.* & 0xFF);

            dr := cast(float)((dest_pixel.* >> 16) & 0xFF);
            dg := cast(float)((dest_pixel.* >> 8) & 0xFF);
            db := cast(float)(dest_pixel.* & 0xFF);

            // NOTE: someday we'll talk about pre-multiplied alpha, this isn't
            r := (1-a)*dr + a*sr;
            g := (1-a)*dg + a*sg;
            b := (1-a)*db + a*sb;

            dest_pixel.* = ((cast,trunc(u32)(r + 0.5)) << 16) |
                           ((cast,trunc(u32)(g + 0.5)) << 8) |
                            cast,trunc(u32)(b + 0.5);

            dest_pixel += 1;
            src_pixel += 1;
        }
        dest_row += buffer.pitch;
        src_row -= bitmap.pitch;
    }
}

load_bmp :: (read_entire_file: DEBUG_Platform_Read_Entire_File, filename: string) -> Bitmap {
    // NOTE: gimp stored byte order: BB GG RR AA, from bottom row up
    // NOTE:       in little endian: AA RR GG BB

    // NOTE: don't use this generically, Bitmap can go in either direction!!
    //
    // The background asset in test are not like my tests in GIMP, they are:
    // NOTE: stored byte order: AA BB GG RR, from bottom row up
    // NOTE:  in little endian: 0xRRGGBBAA

    // NOTE: the byte order is determined by the Header, so we have to read out
    // the amsks and convert the pixels ourselves.


    contents, ok := read_entire_file(filename);
    if !ok {
        return .{};
    }
    header := cast(*Bitmap_Header)contents.data;

    assert(header.compression == 3);

    // not sure what to do with planes, so let's assert if we ever get any:
    assert(header.planes == 1);

    pixels := []u32.{
        count = header.width * header.height * header.planes,
        data = cast(*u32)(contents.data + header.bitmap_offset),
    };

    alpha_mask := ~(header.red_mask | header.green_mask | header.blue_mask);
    alpha_scan, red_scan, green_scan, blue_scan : s32;
    success: bool;
    alpha_scan, success = bit_scan_forward(alpha_mask);
    assert(success);
    red_scan, success = bit_scan_forward(header.red_mask);
    assert(success);
    green_scan, success = bit_scan_forward(header.green_mask);
    assert(success);
    blue_scan, success = bit_scan_forward(header.blue_mask);
    assert(success);

    alpha_shift := 24 - alpha_scan;
    red_shift   := 16 - red_scan;
    green_shift := 8 - green_scan;
    blue_shift  := 0 - blue_scan;

    // have to put the AA channel up front:
    for * pixels {
        it.* = ((it.* & alpha_mask)        <<< alpha_shift) |
               ((it.* & header.red_mask)   <<< red_shift)   |
               ((it.* & header.green_mask) <<< green_shift) |
               ((it.* & header.blue_mask)  <<< blue_shift);
    }

    ret := Bitmap.{
        pixels = pixels,
        width  = header.width,
        height = header.height,
        pitch  = xx header.width,
    };
    return ret;
}

// NOTE: at the moment this has to be a very fast function, it cannot be more than a ms or so.
#program_export
game_get_sound_samples :: (game_memory: *Game_Memory, sound_buffer: *Game_Sound_Buffer) {
    // TODO: Allow sample offsets here (eg, set sound further out in the future, or closer to immediately)
    state := cast(*Game_State)game_memory.permanent.data;

    game_sound_output(sound_buffer);
}

initialize_arena :: (arena: *Memory_Arena, memory: []u8) {
    arena.memory = memory;
    arena.free   = memory;
};

push_size :: (arena: *Memory_Arena, $T: Type) -> *T {
    assert(arena.free.count >= size_of(T));
    result := arena.free.data;
    arena.free = array_view(arena.free, size_of(T));
    return cast(*T)result;
}

push_array :: (arena: *Memory_Arena, $T: Type, $N: s64) -> []T {
    assert(arena.free.count >= size_of(T)*N);
    result := arena.free.data;
    arena.free = array_view(arena.free, size_of(T)*N);
    return cast([N]T)result;
}

get_entity :: (state: *Game_State, index: u32) -> *Entity {
    entity: *Entity;

    if index > 0 && index < state.entities.count {
        entity = *state.entities[index];
    }
    return entity;
}

initialize_player :: (state: *Game_State, entity_index: u32) {
    entity := get_entity(state, entity_index);

    entity.* = .{exists = true};

    entity.p.abs_tile_x = 2;
    entity.p.abs_tile_y = 3;
    entity.p.offset     = .{5, 5};
    entity.height       = 1.4;
    entity.width        = 0.75 * entity.height;

    if !get_entity(state, state.camera_following_entity_index) {
        state.camera_following_entity_index = entity_index;
    }
}

add_entity :: (state: *Game_State) -> u32 {
    assert(state.entity_count < state.entities.count);
    index := state.entity_count;
    state.entity_count += 1;
    // entity is already there, and auto initialized to 0
    return index;
}

move_player :: (state: *Game_State, entity: *Entity, dt: float, init_dd_p: Vector2) {
    dd_p := init_dd_p;
    tile_map  := state.world.tile_map;

    if dd_p.x != 0 && dd_p.y != 0 {
        dd_p *= 0.7071;  // 1/sqrt(2)
    }

    player_speed :=  ifx state.super_speed  200.0 else 100.0;  // m/s^2
    dd_p *= player_speed;

    // TODO: ODE here!
    dd_p += -10.0 * entity.d_p;

    old_player_p := entity.p;
    new_player_p := old_player_p;
    player_delta := 0.5*dd_p * square(dt) +
                            entity.d_p * dt;
    new_player_p.offset += player_delta;
    entity.d_p = dd_p * dt + entity.d_p;

    new_player_p = re_canonicalize_position(tile_map, new_player_p);
    // TODO: Delta function that auto-recanonicalizes

#if true {
    player_left := new_player_p;
    player_left.offset.x -= 0.5*entity.width;
    player_left = re_canonicalize_position(tile_map, player_left);

    player_right := new_player_p;
    player_right.offset.x += 0.5*entity.width;
    player_right = re_canonicalize_position(tile_map, player_right);

    collided := false;
    col_p: Tile_Map_Position;
    if !is_tile_map_point_empty(tile_map, new_player_p) {
        col_p = new_player_p;
        collided = true;
    } else if !is_tile_map_point_empty(tile_map, player_left) {
        col_p = player_left;
        collided = true;
    } else if !is_tile_map_point_empty(tile_map, player_right) {
        col_p = player_right;
        collided = true;
    }

    if collided {
        r: Vector2;
        if col_p.abs_tile_x < entity.p.abs_tile_x {
            // hit right wall, so wall's normal is pointing left
            r = .{-1, 0};
        }
        if col_p.abs_tile_x > entity.p.abs_tile_x {
            // hit left wall, so wall's normal is pointing right
            r = .{1, 0};
        }
        if col_p.abs_tile_y < entity.p.abs_tile_y {
            // hit top wall, so wall's normal is pointing down
            r = .{0, -1};
        }
        if col_p.abs_tile_y > entity.p.abs_tile_y {
            // hit bottom wall, so wall's normal is pointing up
            r = .{0, 1};
        }

        // 2*dot_product*r to bounce, dot*r to slide (vector only gets reflected to follow wall, not to reflect away from wall)
        entity.d_p = entity.d_p - dot_product(entity.d_p, r)*r;
    } else {
        entity.p = new_player_p;
    }
} else {
    min_tile_x : u32 = 0;
    min_tile_y : u32 = 0;
    max_tile_x : u32 = 0;
    max_tile_y : u32 = 0;
    abs_tile_z : u32 = entity.p.abs_tile_z;
    best_player_p := entity.p;
    // we don't care about the actual distance, just the best distance, so no need to take the square:
    best_distance_sq := length_squared(player_delta);
    for abs_tile_y: min_tile_y..max_tile_y {
        for abs_tile_x: min_tile_x..max_tile_x {
            test_tile_p := centered_tile_point(abs_tile_x, abs_tile_y, abs_tile_z);
            tile_value := get_tile_value(tile_map, abs_tile_x, abs_tile_y, abs_tile_z);
            if is_tile_value_empty(tile_value) {
                min_corner := -0.5 * xy(TILE_SIDE_IN_METERS, TILE_SIDE_IN_METERS);
                max_corner :=  0.5 * xy(TILE_SIDE_IN_METERS, TILE_SIDE_IN_METERS);

                rel_new_player_p := subtract(tile_map, *test_tile_p, *new_player_p);
                test_p := closest_point_in_rectangle(min_corner, max_corner, rel_new_player_p);
                //test_distance_sq := ;
                //if best_distance_sq > test_distance_sq {
                //    best_player_p = ;
                //    best_distance_sq = ;
                //}
            }
        }
    }
}

    //
    // NOTE: Updtate camera/player Z based on last movement.
    //
    if !are_on_same_tile(*old_player_p, *entity.p) {
        new_tile_value := get_tile_value(tile_map, entity.p);
        if new_tile_value == 3 {
            entity.p.abs_tile_z += 1;
        } else if new_tile_value == 4 {
            entity.p.abs_tile_z -= 1;
        }
    }

    using DIRECTION;

    if entity.d_p.x == 0 && entity.d_p.y == 0 {
        // NOTE: Leave facing_direction whatever it was
    } else if abs(entity.d_p.x) > abs(entity.d_p.y) {
        entity.facing_direction = ifx entity.d_p.x > 0 then .RIGHT else .LEFT;
    } else if abs(entity.d_p.x) < abs(entity.d_p.y) {
        entity.facing_direction = ifx entity.d_p.y > 0 then .UP else .DOWN;
    }
}

// NOTE: may expand in the future
// need FOUR THINGS: timing, controller/keyboard input, bitmap buffer to use, sound buffer to use

#program_export
game_update_and_render :: (
    game_memory: *Game_Memory,
    input: *Game_Input,
    buffer: *Game_Offscreen_Buffer
) -> bool {
    #if HANDMADE_DEBUG {
        assert(game_memory != null);
        assert(size_of(Game_State) <= game_memory.permanent.count);
        assert((*input.controllers[0].terminator - *input.controllers[0].up) == input.controllers[0].buttons.count);
    }

    TILE_CHUNK_COUNT_X  :: 128;
    TILE_CHUNK_COUNT_Y  :: 128;
    TILE_CHUNK_COUNT_Z   :: 128;

    TILE_SIDE_IN_METERS :: 1.4;
    TILE_SIDE_IN_PIXELS :: 60.0;
    METERS_TO_PIXELS    :: TILE_SIDE_IN_PIXELS / TILE_SIDE_IN_METERS;


    state := cast(*Game_State)game_memory.permanent.data;
    if !game_memory.initialized {
        // for dev, be deterministic
        // millis := to_milliseconds(current_time_consensus());
        //random_seed(cast(u64)millis);
        random_seed(1233445);

        // NOTE: reserve entity slot 0 for the null entity
        add_entity(state);

        //state.bmp = load_bmp(game_memory.read_entire_file, "structured_art.bmp");
        state.background = load_bmp(game_memory.read_entire_file, "test/test_background.bmp");

        bitmap := *state.hero_bitmaps[0];
        bitmap.head  = load_bmp(game_memory.read_entire_file, "test/test_hero_right_head.bmp");
        bitmap.cape  = load_bmp(game_memory.read_entire_file, "test/test_hero_right_cape.bmp");
        bitmap.torso = load_bmp(game_memory.read_entire_file, "test/test_hero_right_torso.bmp");
        bitmap.align_x = 72;
        bitmap.align_y = 182;
        bitmap += 1;

        bitmap.head  = load_bmp(game_memory.read_entire_file, "test/test_hero_back_head.bmp");
        bitmap.cape  = load_bmp(game_memory.read_entire_file, "test/test_hero_back_cape.bmp");
        bitmap.torso = load_bmp(game_memory.read_entire_file, "test/test_hero_back_torso.bmp");
        bitmap.align_x = 72;
        bitmap.align_y = 182;
        bitmap += 1;

        bitmap.head  = load_bmp(game_memory.read_entire_file, "test/test_hero_left_head.bmp");
        bitmap.cape  = load_bmp(game_memory.read_entire_file, "test/test_hero_left_cape.bmp");
        bitmap.torso = load_bmp(game_memory.read_entire_file, "test/test_hero_left_torso.bmp");
        bitmap.align_x = 72;
        bitmap.align_y = 182;
        bitmap += 1;

        bitmap.head  = load_bmp(game_memory.read_entire_file, "test/test_hero_front_head.bmp");
        bitmap.cape  = load_bmp(game_memory.read_entire_file, "test/test_hero_front_cape.bmp");
        bitmap.torso = load_bmp(game_memory.read_entire_file, "test/test_hero_front_torso.bmp");
        bitmap.align_x = 72;
        bitmap.align_y = 182;

        state.camera_p.abs_tile_x = 17/2;
        state.camera_p.abs_tile_y = 9/2;

        initialize_arena(*state.world_arena, array_view(game_memory.permanent, size_of(Game_State)));

        //state.world := World.{*tile_map};
        state.world = push_size(*state.world_arena, World);
        world := state.world;
        world.tile_map = push_size(*state.world_arena, Tile_Map);
        tile_map := world.tile_map;
        tile_map.chunk_shift = CHUNK_SHIFT;
        tile_map.chunk_mask = cast,trunc(u32)((1 << tile_map.chunk_shift) - 1);
        tile_map.chunk_dim = cast,trunc(u32)(1 << tile_map.chunk_shift);
        tile_map.tile_chunk_count_x  = TILE_CHUNK_COUNT_X;
        tile_map.tile_chunk_count_y  = TILE_CHUNK_COUNT_Y;
        tile_map.tile_chunk_count_z  = TILE_CHUNK_COUNT_Z;
        tile_map.tile_side_in_meters = TILE_SIDE_IN_METERS;

        tile_map.tile_chunks = push_array(*state.world_arena, Tile_Chunk,
                                          TILE_CHUNK_COUNT_X * TILE_CHUNK_COUNT_Y * TILE_CHUNK_COUNT_Z);

        lower_left_x := -TILE_SIDE_IN_PIXELS/2;
        lower_left_y := cast(float)buffer.height;

        tiles_per_width : u32 = 17;
        tiles_per_height : u32 = 9;
        screen_x, screen_y : u32 = 0, 0;
        // TODO: temp
        abs_tile_z : u32 = 0;

        //
        // CREATE MAP
        //
        door_left      := false;
        door_right     := false;
        door_top       := false;
        door_bottom    := false;
        door_up        := false;
        door_down      := false;
        random_choice  : u64 = 0;

        for 0..99 {
            if door_up || door_down {
                // previously we had gone up or down, next move has to be lateral
                random_choice = random_get() % 2;
            } else {
                random_choice = random_get() % 3;
            }

            created_z_door := false;
            if random_choice == 2 {
                if abs_tile_z == 0 then door_up = true; else door_down = true;
                created_z_door = true;
            } else if random_choice == 1 {
                door_right = true;
            } else {
                door_top = true;
            }

            for tile_y: 0..tiles_per_height-1 {
                for tile_x: 0..tiles_per_width-1 {
                    abs_tile_x := screen_x * tiles_per_width + tile_x;
                    abs_tile_y := screen_y * tiles_per_height + tile_y;
                    tile_value : u32 = 1;

                    if tile_x == 0  { // left edge
                        tile_value = xx ifx tile_y == tiles_per_height/2 && door_left  1 else 2;
                    }
                    if tile_x == (tiles_per_width - 1) { // right edge
                        tile_value = xx ifx tile_y == tiles_per_height/2 && door_right  1 else 2;
                    }
                    if tile_y == 0  { // bottom edge
                        tile_value = xx ifx tile_x == tiles_per_width/2 && door_bottom  1 else 2;
                    }
                    if tile_y == (tiles_per_height - 1) { // top edge
                        tile_value = xx ifx tile_x == tiles_per_width/2 && door_top  1 else 2;
                    }
                    if tile_x == 10 && tile_y == 5 {
                        if door_up {
                            tile_value = 3;
                        } else if door_down {
                            tile_value = 4;
                        }
                    }
                    set_tile_value(*state.world_arena, world.tile_map, abs_tile_x, abs_tile_y, abs_tile_z, tile_value);
                }
            }

            door_left   = door_right;
            door_bottom = door_top;
            door_right  = false;
            door_top    = false;

            if created_z_door {
                door_down = !door_down;
                door_up   = !door_up;
            } else {
                door_down = false;
                door_up   = false;
            }

            if random_choice == 2 {
                abs_tile_z = xx ifx abs_tile_z == 0  1 else 0;
            } else if random_choice == 1 {
                screen_x += 1;
            } else  {
                screen_y += 1;
            }
        }

        game_memory.initialized = true;
    }

    world := state.world;
    tile_map := world.tile_map;

    for controller: input.controllers {
        controlling_entity := get_entity(state, state.player_index_for_controller[it_index]);
        if controlling_entity {
            dd_player: Vector2;

            if controller.analog {
                // NOTE: Use analog movement tuning
                dd_player = .{controller.stick_avg_x, controller.stick_avg_y};
            } else {
                // NOTE: Use digital movement tuning

                if controller.up.ended_down {
                    dd_player.y = 1;
                }
                if controller.down.ended_down {
                    dd_player.y = -1;
                }
                if controller.left.ended_down {
                    dd_player.x = -1;
                }
                if controller.right.ended_down {
                    dd_player.x = 1;
                }
            }

            if controller.a.ended_down {
                state.super_speed = !state.super_speed;
            }

            move_player(state, controlling_entity, input.dt_for_frame, dd_player);
        } else {
            if controller.start.ended_down {
                entity_index := add_entity(state);
                initialize_player(state, entity_index);
                state.player_index_for_controller[it_index] = entity_index;
            }
        }
    }

    camera_following_entity := get_entity(state, state.camera_following_entity_index);
    if camera_following_entity {
        state.camera_p.abs_tile_z = camera_following_entity.p.abs_tile_z;

        diff := subtract(tile_map, *camera_following_entity.p, *state.camera_p);
        if diff.dxy.x > 9 * TILE_SIDE_IN_METERS  state.camera_p.abs_tile_x += 17;
        if diff.dxy.x < -9 * TILE_SIDE_IN_METERS  state.camera_p.abs_tile_x -= 17;
        if diff.dxy.y > 5 * TILE_SIDE_IN_METERS  state.camera_p.abs_tile_y += 9;
        if diff.dxy.y < -5 * TILE_SIDE_IN_METERS  state.camera_p.abs_tile_y -= 9;
    }

    // NOTE: RENDER
    draw_bitmap(buffer, state.background, 0, 0);

    //draw_rectangle(buffer, 0, 0, cast(float)buffer.width, cast(float)buffer.height, 1, 0, 1);

    screen_center_x := 0.5 * cast(float)buffer.width;
    screen_center_y := 0.5 * cast(float)buffer.height;

    // DRAW MAP
    for rel_row: -20..19 {
        for rel_col: -20..19 {
            col : u32 = cast,trunc(u32)(cast(s64)state.camera_p.abs_tile_x + rel_col);
            row : u32 = cast,trunc(u32)(cast(s64)state.camera_p.abs_tile_y + rel_row);
            tile_id := get_tile_value(tile_map, col, row, state.camera_p.abs_tile_z);
            if tile_id < 2 continue;

            gray := ifx tile_id == 2  1.0 else .5;
            gray  = ifx state.camera_p.abs_tile_x == col && state.camera_p.abs_tile_y == row  0 else gray;
            gray  = ifx tile_id > 2  0.25 else gray;

            cen: Vector2 = .{screen_center_x - METERS_TO_PIXELS * state.camera_p.offset.x +
                rel_col * TILE_SIDE_IN_PIXELS,
                screen_center_y + METERS_TO_PIXELS * state.camera_p.offset.y -
                rel_row * TILE_SIDE_IN_PIXELS};
            min := cen - 0.5 * TILE_SIDE_IN_PIXELS;
            max := cen + 0.5 * TILE_SIDE_IN_PIXELS;
            draw_rectangle(buffer, min, max, gray, gray, gray);
        }
    }

    // DRAW PLAYER
    for state.entities {
        // TODO: culling of entities based on Z / camera view
        if !it.exists  continue;

        diff := subtract(tile_map, *it.p , *state.camera_p);

        player_r, player_g, player_b := 1.0, 1.0, 0.0;

        player_ground_pt_x := screen_center_x + METERS_TO_PIXELS*diff.dxy.x;
        player_ground_pt_y := screen_center_y - METERS_TO_PIXELS*diff.dxy.y;
        player_left_top := xy(player_ground_pt_x - .5 * METERS_TO_PIXELS * it.width,
                              player_ground_pt_y - METERS_TO_PIXELS * it.height);
        player_width_height := xy(it.width, it.height);

        draw_rectangle(buffer,
                       player_left_top,
                       player_left_top + METERS_TO_PIXELS * player_width_height,
                       player_r, player_g, player_b);

        bitmaps := state.hero_bitmaps[it.facing_direction];
        draw_bitmap(buffer, bitmaps.torso, player_ground_pt_x, player_ground_pt_y, bitmaps.align_x, bitmaps.align_y);
        draw_bitmap(buffer, bitmaps.cape, player_ground_pt_x, player_ground_pt_y, bitmaps.align_x, bitmaps.align_y);
        draw_bitmap(buffer, bitmaps.head, player_ground_pt_x, player_ground_pt_y, bitmaps.align_x, bitmaps.align_y);
    }

    return true;
}

#load "handmade_h.jai";
#load "handmade_tile.jai";
#load "handmade_intrinsics.jai";
#load "handmade_math.jai";

#import "Basic";
#import "Random";

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
