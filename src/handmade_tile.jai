Tile_Map_Position :: struct {
    // NOTE: These are fixed point tile locations. The high 24 bits are the tile
    // chunk index, and the low 8 bits are the tile index in the chunk.
    abs_tile_x : u32;
    abs_tile_y : u32;
    abs_tile_z : u32;

    // NOTE: offsets from the center of the tile
    offset_x : float;
    offset_y : float;
}

Tile_Chunk_Position :: struct {
    tile_chunk_x : u32;
    tile_chunk_y : u32;
    tile_chunk_z : u32;
    rel_tile_x   : u32;
    rel_tile_y   : u32;
    rel_tile_z   : u32;
}

Tile_Chunk :: []u32;

Tile_Map :: struct {
    chunk_shift         : u32;
    chunk_mask          : u32;
    chunk_dim           : u32;

    tile_side_in_meters : float;

    tile_chunk_count_x  : u32;
    tile_chunk_count_y  : u32;
    tile_chunk_count_z  : u32;

    tile_chunks         : []Tile_Chunk;
}

get_tile_chunk :: (tile_map: *Tile_Map, tile_chunk_x: u32, tile_chunk_y: u32, tile_chunk_z: u32) -> *Tile_Chunk {
    if tile_chunk_x >= 0 && tile_chunk_x < tile_map.tile_chunk_count_x &&
        tile_chunk_y >= 0 && tile_chunk_y < tile_map.tile_chunk_count_y &&
        tile_chunk_z >= 0 && tile_chunk_z < tile_map.tile_chunk_count_z
    {
        return *tile_map.tile_chunks[tile_chunk_z * tile_map.tile_chunk_count_y * tile_map.tile_chunk_count_x +
                                     tile_chunk_y * tile_map.tile_chunk_count_x + tile_chunk_x];
    }
    return null;
}

get_tile_value_unchecked :: (tile_map: *Tile_Map, tile_chunk: Tile_Chunk, tile_x: u32, tile_y: u32) -> u32 {
    assert(tile_chunk.data != null);
    assert(tile_y < tile_map.chunk_dim);
    assert(tile_x < tile_map.chunk_dim);

    tile_chunk_value := tile_chunk[tile_y * tile_map.chunk_dim + tile_x];
    return tile_chunk_value;
}

set_tile_value_unchecked :: (tile_map: *Tile_Map, tile_chunk: Tile_Chunk, tile_x: u32, tile_y: u32, tile_value: u32) {
    assert(tile_chunk.data != null);
    assert(tile_y < tile_map.chunk_dim);
    assert(tile_x < tile_map.chunk_dim);

    tile_chunk[tile_y * tile_map.chunk_dim + tile_x] = tile_value;
}

get_tile_value :: (tile_map: *Tile_Map, tile_chunk: *Tile_Chunk, test_tile_x: u32, test_tile_y: u32) -> u32 {
    tile_chunk_value : u32 = 0;
    if tile_chunk != null && tile_chunk.data {
        tile_chunk_value = get_tile_value_unchecked(tile_map, tile_chunk.*, test_tile_x, test_tile_y);
    }
    return tile_chunk_value;
}

set_tile_value :: (tile_map: *Tile_Map, tile_chunk: Tile_Chunk, test_tile_x: u32, test_tile_y: u32, tile_value: u32) {
    if tile_chunk.data {
        set_tile_value_unchecked(tile_map, tile_chunk, test_tile_x, test_tile_y, tile_value);
    }
}

get_chunk_pos_for :: (tile_map: *Tile_Map, abs_tile_x: u32, abs_tile_y: u32, abs_tile_z: u32) -> Tile_Chunk_Position {
    res: Tile_Chunk_Position;
    res.tile_chunk_x = abs_tile_x >> tile_map.chunk_shift;
    res.tile_chunk_y = abs_tile_y >> tile_map.chunk_shift;
    res.tile_chunk_z = abs_tile_z;
    res.rel_tile_x = abs_tile_x & tile_map.chunk_mask;
    res.rel_tile_y = abs_tile_y & tile_map.chunk_mask;
    return res;
}

get_tile_value :: (tile_map: *Tile_Map, abs_tile_x: u32, abs_tile_y: u32, abs_tile_z: u32) -> u32 {
    chunk_pos := get_chunk_pos_for(tile_map, abs_tile_x, abs_tile_y, abs_tile_z);
    tile_chunk := get_tile_chunk(tile_map, chunk_pos.tile_chunk_x, chunk_pos.tile_chunk_y, chunk_pos.tile_chunk_z);
    tile := get_tile_value(tile_map, tile_chunk, chunk_pos.rel_tile_x, chunk_pos.rel_tile_y);

    return tile;
}

get_tile_value :: (tile_map: *Tile_Map, pos: Tile_Map_Position) -> u32 {
    tile_chunk_value := get_tile_value(tile_map, pos.abs_tile_x, pos.abs_tile_y, pos.abs_tile_z);
    return tile_chunk_value;
 }

is_tile_map_point_empty :: (tile_map: *Tile_Map, can_pos: Tile_Map_Position) -> bool {
    tile_chunk_value := get_tile_value(tile_map, can_pos.abs_tile_x, can_pos.abs_tile_y, can_pos.abs_tile_z);

    empty := tile_chunk_value == 1 || tile_chunk_value == 3 || tile_chunk_value == 4;

    return empty;
}

set_tile_value :: (arena: *Memory_Arena, tile_map: *Tile_Map, abs_tile_x: u32, abs_tile_y: u32, abs_tile_z: u32, tile_value: u32) {
    chunk_pos := get_chunk_pos_for(tile_map, abs_tile_x, abs_tile_y, abs_tile_z);
    tile_chunk := get_tile_chunk(tile_map, chunk_pos.tile_chunk_x, chunk_pos.tile_chunk_y, chunk_pos.tile_chunk_z);

    assert(tile_chunk != null);

    if !tile_chunk.data {
        tile_chunk.* = push_array(arena, u32, CHUNK_DIM * CHUNK_DIM);
        for * tile_chunk.*  it.* = 1;
    }

     set_tile_value(tile_map, tile_chunk.*, chunk_pos.rel_tile_x, chunk_pos.rel_tile_y, tile_value);
}

//
// Do these really belong in a more position/geometry type of file?
//
re_canonicalize_coord :: (tile_map: *Tile_Map, tile: *u32, tile_rel: *float) {
    // NOTE: world is toroidal
    offset := round_s32(tile_rel.* / tile_map.tile_side_in_meters);
    tile.* = cast,trunc(u32)(cast(s64)tile.* + offset);
    tile_rel.* -= offset * tile_map.tile_side_in_meters;

    assert(tile_rel.* >= -0.5*tile_map.tile_side_in_meters);
    assert(tile_rel.* <= 0.5*tile_map.tile_side_in_meters);
}

re_canonicalize_position :: (tile_map: *Tile_Map, pos: Tile_Map_Position) -> Tile_Map_Position {
    res := pos;

    re_canonicalize_coord(tile_map, *res.abs_tile_x, *res.offset_x);
    re_canonicalize_coord(tile_map, *res.abs_tile_y, *res.offset_y);

    return res;
}

are_on_same_tile :: (a: *Tile_Map_Position, b: *Tile_Map_Position) -> bool {
    res := a.abs_tile_x == b.abs_tile_x && a.abs_tile_y == b.abs_tile_y && a.abs_tile_z == b.abs_tile_z;
    return res;
}

Tile_Map_Difference :: struct {
    dx, dy, dz: float;
}

subtract :: (tile_map: *Tile_Map, a: *Tile_Map_Position, b: *Tile_Map_Position) -> Tile_Map_Difference {
    d_tile_x := cast(float)a.abs_tile_x - cast(float)b.abs_tile_x;
    d_tile_y := cast(float)a.abs_tile_y - cast(float)b.abs_tile_y;
    d_tile_z := cast(float)a.abs_tile_z - cast(float)b.abs_tile_z;

    ret := Tile_Map_Difference.{
        tile_map.tile_side_in_meters * d_tile_x + (a.offset_x - b.offset_x),
        tile_map.tile_side_in_meters *  d_tile_y + (a.offset_y - b.offset_y),
        // TODO: think about what to do about z
        tile_map.tile_side_in_meters * d_tile_z};

    return ret;
}
