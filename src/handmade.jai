// Platform-independent game code

// TODO: In the future, rendering _specifically_ will become a three-tiered abstraction!!
game_offscreen_buffer :: struct {
    // NOTE: Pixels are always 32-bits wide, Memory Order BB GG RR XX
    memory     : *u8;
    width      : int;
    height     : int;
    pitch      : int;
}

render_weird_gradient :: (back_buffer: *offscreen_buffer,  xOffset: int, yOffset: int) {
    row : *u8 = back_buffer.memory;
    for y: 0..back_buffer.height-1 {
        pixel : *u32 = xx row;
        for x: 0..back_buffer.width-1 {
            //                   1  2  3  4
            // pixel in memory: BB GG RR xx  (bc MSFT wanted to see RGB in register (see register)
            //     in register: xx RR GG BB  (bc it's little endian)
            bb := cast (u8)max(((x + xOffset) % 255), 0);
            gg := cast (u8)max(((y + yOffset) % 255), 0);
            <<pixel = ((cast(u32) gg) << 8 | bb);
            pixel += 1;
        }

        row += back_buffer.pitch;
    }
}



// NOTE: may expand in the future
// need FOUR THINGS: timing, controller/keyboard input, bitmap buffer to use, sound buffer to use
game_update_and_render :: (back_buffer: *game_offscreen_buffer, xOffset: int, yOffset: int) {
    render_weird_gradient(*GlobalBackBuffer, xOffset, yOffset);
}
