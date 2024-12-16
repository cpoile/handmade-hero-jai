#import "Compiler";
#run {
    defer set_build_options_dc(.{do_output=false});
    w := compiler_create_workspace();
    options := get_build_options(w);
    options.output_path = "build/";
    options.output_executable_name = "handmade";
    //options.additional_linker_arguments = string.["/SUBSYSTEM:WINDOWS", "/ENTRY:main", "/IGNORE:4216"];
    set_optimization(*options, .DEBUG);
    set_build_options(options, w);

    // add all your files here.
    add_build_file("src/win32_handmade.jai", w);

    // HANDMADE_INTERNAL indicates when we're trying to do something that we'de only want to do internally
    //  (e.g., specify allocator pointer positions)

    build_constants := tprint(#string STRING
            HANDMADE_INTERNAL :: %;
            HANDMADE_DEBUG    :: %;
        STRING,
            true,
            true,
    );
    add_build_string(build_constants, w);
}

#import "Basic";
