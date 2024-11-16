#import "Compiler";
#run {
    defer set_build_options_dc(.{do_output=false});
    w := compiler_create_workspace();
    options := get_build_options(w);
    options.output_path = "build/";
    options.output_executable_name = "handmade";
    options.additional_linker_arguments = string.["/SUBSYSTEM:WINDOWS", "/ENTRY:main", "/IGNORE:4216"];
    set_build_options(options, w);

    // add all your files here.
    add_build_file("src/main.jai", w);
}
