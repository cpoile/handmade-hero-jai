// Thanks to https://github.com/colinbellino/jai-code-hot-reloading-example
#import "Basic";
#import "File";
#import "File_Utilities"; // for visit_files
#import "Compiler";

OUTPUT_PATH           :: "build/";
OUPUT_EXECUTABLE_NAME :: "handmade";

#run {
    set_build_options_dc(.{ do_output = false });
    make_directory_if_it_does_not_exist(OUTPUT_PATH, recursive = true);

    // Since the build can generate a lot debug and temporary files if you use it a lot,
    // we do some clean up to not keep too much garbage.
    visit_files(OUTPUT_PATH, recursive = false, null, delete_app_files_visitor, visit_files = true, visit_directories = true);

    log("Compiling app. | OS: % | CPU: %", OS, CPU);
    w := compiler_create_workspace("Build handmade");

    options := get_build_options(w);
    copy_commonly_propagated_fields(get_build_options(), *options);
    options.output_path = OUTPUT_PATH;
    options.output_executable_name = OUPUT_EXECUTABLE_NAME;
    options.output_type = .DYNAMIC_LIBRARY; // Important!
    options.os_target   = OS;
    options.cpu_target  = CPU;
    //options.backend     = .X64;
    set_optimization(*options, .DEBUG);
    set_build_options(options, w);

    compiler_begin_intercept(w);

    // HANDMADE_INTERNAL indicates when we're trying to do something that we'de only want to do internally
    //  (e.g., specify allocator pointer positions)
    // HANDMADE_DEBUG indicates something we'd only want in debug builds (e.g., asserts) -- there might be a better way to do this,
    //  or I think assert already does an #if ASSERT

    build_constants := tprint(#string STRING
            HANDMADE_INTERNAL :: %;
            HANDMADE_DEBUG    :: %;
        STRING,
            true,
            true,
    );
    add_build_string(build_constants, w);

    add_build_file("src/handmade.jai", w);

    while true {
        message := compiler_wait_for_message();
        if message.kind == {
            case .COMPLETE; {
                message_complete := (cast(*Message_Complete) message);
                if message_complete.error_code != .NONE {
                    exit(1);
                }
                break;
            }
        }
    }
    compiler_end_intercept(w);
};

delete_app_files_visitor :: (info: *File_Visit_Info, user_data: *void) {
    #import "String";
    if starts_with(info.short_name, "handmade.") {
        if info.is_directory {
            delete_directory(info.full_name);
        } else {
            file_delete(info.full_name);
        }
    }
}
