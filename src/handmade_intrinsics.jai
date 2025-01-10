// TODO: convert these to platform-efficient versions

round_s32 :: inline (x: float) -> s32 {
    return cast,trunc(s32)(x + ifx x > 0  0.5 else -0.5);
}

round_s32 :: inline (v: Vector2) -> s32, s32 {
    x := cast,trunc(s32)(v.x + ifx v.x > 0  0.5 else -0.5);
    y := cast,trunc(s32)(v.y + ifx v.y > 0  0.5 else -0.5);
    return x, y;
}

round_u32 :: inline (x: float) -> u32 {
    return cast,trunc(u32)(x + ifx x > 0  0.5 else -0.5);
}

round_u32 :: inline (v: Vector2) -> u32, u32 {
    x := cast,trunc(u32)(v.x + ifx v.x > 0  0.5 else -0.5);
    y := cast,trunc(u32)(v.y + ifx v.y > 0  0.5 else -0.5);
    return x, y;
}

floor_float_to_s32 :: (f: float) -> s32 {
    return cast(s32)floor(f);
}

// and sin, cos, atan2

// "reference"
bitscan :: (mask: $T) -> index: s32, success: bool {
    for i: 0..cast(u32)31 {
        if mask & (1 << i) {
            return cast,trunc(s32)i, true;
        }
    }
    return 0, false;
}

// copied and simplified from Bit_Operations, will only work on x64 and not 8 bits:
bit_scan_forward :: (input: $T) -> index: s32, success: bool #expand {
    BITS :: size_of(T)*8;

    #if CPU == .X64 && BITS > 8 {
        result: T = xx,no_check -1;
        #asm {
            bsf?T     result, input;
        }

        return cast,trunc(s32)(result), result != -1;
    } else {
        bitscan(input);
    }
}

#scope_file
#import "Math";
