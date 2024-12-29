// TODO: convert these to platform-efficient versions

round_s32 :: inline (x: float) -> s32 {
    return cast,trunc(s32)(x + 0.5);
}

round_u32 :: inline (x: float) -> u32 {
    return cast,trunc(u32)(x + 0.5);
}

floor_float_to_s32 :: (f: float) -> s32 {
    return cast(s32)floor(f);
}

// and sin, cos, atan2

#scope_file
#import "Math";
