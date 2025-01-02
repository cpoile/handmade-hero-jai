MAX_INPUTS :: 5;  // 4 controllers + keyboard

// Useful macros
KILOBYTES :: (v: $T) -> T #expand { return v * 1024; }
MEGABYTES :: (v: $T) -> T #expand { return KILOBYTES(v) * 1024; }
GIGABYTES :: (v: $T) -> T #expand { return MEGABYTES(v) * 1024; }
TERABYTES :: (v: $T) -> T #expand { return GIGABYTES(v) * 1024; }

Game_Memory :: struct {
    permanent         : []u8;
    temporary         : []u8;
    initialized       : bool;

    // Procs from the platform layer
    read_entire_file  : DEBUG_Platform_Read_Entire_File;
    free_file_memory  : DEBUG_Platform_Free_File_Memory;
    write_entire_file : DEBUG_Platform_Write_Entire_File;
}

// TODO: In the future, rendering _specifically_ will become a three-tiered abstraction!!
Game_Offscreen_Buffer :: struct {
    // NOTE         : Pixels are always 32-bits wide, Memory Order BB GG RR XX
    memory          : *u8;
    width           : s32;
    height          : s32;
    pitch           : s32;
    bytes_per_pixel : s32;
}

Game_Sound_Buffer :: struct {
    samples_per_second : s32;
    samples_count      : s32;
    samples            : *s16;
}

Game_Button_State :: struct {
    half_transition_count : u8;
    ended_down            : bool;
}

Game_Controller_Input :: struct {
    is_connected   : bool;
    analog         : bool;
    stick_avg_x    : float32;
    stick_avg_y    : float32;
    union {
        buttons: [12]Game_Button_State;
        struct {
            up             : Game_Button_State;
            down           : Game_Button_State;
            left           : Game_Button_State;
            right          : Game_Button_State;
            a              : Game_Button_State;
            b              : Game_Button_State;
            x              : Game_Button_State;
            y              : Game_Button_State;
            left_shoulder  : Game_Button_State;
            right_shoulder : Game_Button_State;
            back           : Game_Button_State;
            start          : Game_Button_State;
            // NOTE: always add new buttons above the terminator
            terminator     : Game_Button_State;
        }
    };
};

Game_Input :: struct {
    mouse_buttons : [5]Game_Button_State;
    mouse_x       : s32;
    mouse_y       : s32;
    dt_for_frame  : float32;
    controllers   : [MAX_INPUTS]Game_Controller_Input;
}

//
// Functions the dll provides
//
Game_Update_And_Render :: #type (*Game_Memory, *Game_Input, *Game_Offscreen_Buffer) -> bool;
Game_Get_Sound_Samples :: #type (*Game_Memory, *Game_Sound_Buffer);

//
// Functions the platform layer provides
//
DEBUG_Platform_Read_Entire_File  :: #type (filename: string) -> memory: []u8, ok: bool;
DEBUG_Platform_Free_File_Memory  :: #type (memory: *[]u8);
DEBUG_Platform_Write_Entire_File :: #type (filename: string, memory: []u8) -> bool;

