#import "Basic";
#import "File";
#import "Compiler";

OUTPUT_PATH     :: "build/";
OUTPUT_EXE_NAME :: "win32_handmade";

#run {
    defer set_build_options_dc(.{do_output=false});
    make_directory_if_it_does_not_exist(OUTPUT_PATH, recursive = true);

    log("Compiling main. | OS: % | CPU: %", OS, CPU);
    w := compiler_create_workspace("build win32_handmade");

    options := get_build_options(w);
    copy_commonly_propagated_fields(get_build_options(), *options);
    options.output_path = OUTPUT_PATH;
    options.output_executable_name = OUTPUT_EXE_NAME;
    options.output_type = .EXECUTABLE;
    options.os_target   = OS;
    options.cpu_target  = CPU;
    //options.backend     = .X64;
    //options.additional_linker_arguments = string.["/SUBSYSTEM:WINDOWS", "/ENTRY:main", "/IGNORE:4216"];
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

    // add all your files here.
    add_build_file("src/win32_handmade.jai", w);

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
}
