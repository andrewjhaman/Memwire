
#import "Basic";
#import "System";
#import "Math";

#import "Window_Creation";

#import "GetRect_LeftHanded";
Simp :: #import "Simp";
Input :: #import "Input";

#import "Windows";
#import "Windows_Utf8";

#import "String";

#load "psapi.jai";


my_window : Window_Type;

window_width  : s32 = 1920;
window_height : s32 = 1080;

current_time: float64;
last\  _time: float64;

active_process_index : s32;

// Data values that we manipulate with the widgets:
scroll_value: float;
scroll_value_dragdrop_region: float;
horizontal_scroll_value: float;
vertical_scroll_value: float;

dropped_files: [..] string;

// For windows that move around autonomously:
subwindow_info_text:   Subwindow_Info;
subwindow_info_circle: Subwindow_Info;
subwindow_info_color_animation_editor: Subwindow_Info;
subwindows_initted := false;

my_theme: Overall_Theme;  // This gets filled out by calling the Theme_Proc for current_theme.
current_theme := Default_Themes.Grayscale;

main :: () {
    refresh_processes();

    {
        SetProcessDPIAware();
        timeBeginPeriod(1);
    }

    {
        WANTED_MSAA :: 8;
        // On Linux, we need to pass the MSAA value to create_window
        my_window = create_window(window_width, window_height, "Memwire", wanted_msaa = WANTED_MSAA);
        // On other operating systems, the MSAA value needs to be passed to *_create_context, so we
        // need to have an extra step here if you want MSAA.
        msaa := Simp.prepare_window(my_window, wanted_msaa = WANTED_MSAA);
        log("Wanted MSAA: %\nChosen MSAA: %", WANTED_MSAA, msaa);
        // Actual render size in pixels can be different from the window dimensions we specified above (for example on high-resolution displays on macOS/iOS).
        window_width, window_height = Simp.get_render_dimensions(my_window);
        Simp.set_render_target(my_window, .LEFT_HANDED);


        DragAcceptFiles(my_window, cast(Windows.BOOL) true);

        my_init_fonts();
        ui_init();
    }

    quit := false;
    while !quit {
        current_time = seconds_since_init();
        dt := cast(float)(current_time - last_time);
        Clamp(*dt, 0, 0.1);
        last_time = current_time;

        Input.update_window_events();

        for Input.get_window_resizes() {
            Simp.update_window(it.window);  // Simp will do nothing if it doesn't care about this window.

            if it.window == my_window {
                should_reinit := (it.width != window_width) || (it.height != window_height);

                window_width  = it.width;
                window_height = it.height;

                if should_reinit my_init_fonts();  // Resize the font for the new window size.
            }
        }

        for event : Input.events_this_frame {
            if event.type == .QUIT then quit = true;

            getrect_handle_event(event);

            if event.type == {
              case .KEYBOARD;
                if event.key_pressed && event.key_code == .ESCAPE {
                    active_widget_deactivate_all();
                }

              case .DRAG_AND_DROP_FILES;
                for dropped_files free(it);
                array_reset(*dropped_files);
                for event.files array_add(*dropped_files, copy_string(it));
            }
        }

        draw_one_frame(dt);

        reset_temporary_storage();
        sleep_milliseconds(10);
    }
}


draw_one_frame :: (dt: float) {
    proc := default_theme_procs[current_theme];
    my_theme = proc();
    set_default_theme(my_theme);  // Just in case we don't explicitly pass themes sometimes...!

    bg_col := my_theme.background_color;
    Simp.clear_render_target(bg_col.x, bg_col.y, bg_col.z, 1);
    Simp.set_shader_for_color();

    x, y, width, height := get_dimensions(my_window, true);
    ui_per_frame_update(my_window, width, height, current_time);

    k := window_height * .1;
    r := get_rect(k*.5, 2.1*k, 3*k, k);

    #if 0{
        if active_process_name print("Found process %. (PID %)\n", active_process_name, active_pid);
        else print("main.exe is not found.\n");

        dump_memory(active_pid);
    }

    {
        refresh_processes();

        button_height := window_height * .03;
        r = get_rect(0, 0, 2.2*k, button_height);
        
        text_theme := my_theme.text_input_theme;
        text_theme.font = my_font;
        text_action, new_filter, state := text_input(r, name_filter_string, *text_theme);
        if text_action modify_string(*name_filter_string, new_filter);

        dropdown_theme := *my_theme.dropdown_theme;
        r.x += r.w;

        // The 'dropdown' function causes a popup to be created, which
        // gets rendered at the end of the frame when we call draw_popups().
        // The theme and choices array must remain valid until after that time!
        // The 'current_theme' pointer also needs to remain pointing at valid memory
        // until after that time, as that is when it will be changed.

        dropdown(r, selectable_process_names, *active_process_index, dropdown_theme);
        if last_active_process_index != active_process_index {
            print("HERE!\n");
            process := selectable_processes[active_process_index];
            dump_memory(process.pid);
        }
        last_active_process_index = active_process_index;
    }

    draw_popups();  // This draws Subwindows as well.

    Simp.swap_buffers(my_window);
}

refresh_processes :: () {
    bytes_out : DWORD;
    if !EnumProcesses(processes_memory.data, size_of(DWORD) * processes_memory.count, *bytes_out) {
        code, description := get_error_value_and_string();
        log_error("ERROR in refresh_processes: % (%)\n", description, code);
        processes.count = 0;
    }
    processes.data = processes_memory.data;
    processes.count = bytes_out / size_of(DWORD);

    array_reset_keeping_memory(*selectable_processes);

    for selectable_process_names {
        free(it);
    }
    array_reset_keeping_memory(*selectable_process_names);

    for pid : processes {
        name, success := get_process_name(pid);
        if success && name.count && (name_filter_string.count == 0 || contains(name, name_filter_string)) {
            process : Process; 
            process.pid = pid;
            process.name = name;
            array_add(*selectable_processes, process);
            array_add(*selectable_process_names, name);
        }
    }
}

dump_memory :: (process_id : DWORD) {
    process := OpenProcess(PROCESS_QUERY_INFORMATION | PROCESS_VM_READ, .FALSE, process_id);
    defer CloseHandle(process);
    print("Begin search.\n");


    mbi : MEMORY_BASIC_INFORMATION;
    address : *void;

    while VirtualQueryEx(process, address, *mbi, size_of(MEMORY_BASIC_INFORMATION)) {
        //print("Region at %, of size 0x% with protection %\n", mbi.BaseAddress, mbi.RegionSize, cast(Memory_Protection_Constant)mbi.Protect);
        if mbi.State == MEM_COMMIT && (mbi.Protect & (PAGE_READONLY | PAGE_READWRITE | PAGE_WRITECOPY | PAGE_EXECUTE_READ | PAGE_EXECUTE_READWRITE | PAGE_EXECUTE_WRITECOPY)) {
            bytes_read : u64;
            region_base_address := mbi.BaseAddress;
            region_size := mbi.RegionSize;

            offset : u64 = 0;
            buffer : [4096]u8;
            while offset < region_size {
                bytes_to_read := cast(u64)buffer.count;
                if offset + xx bytes_to_read > region_size bytes_to_read = region_size - offset;

                read_address := region_base_address + offset;

                ReadProcessMemory(process, read_address, buffer.data, bytes_to_read, *bytes_read);

                as_string : string = xx buffer;
                if contains(as_string, "Reticle") {
                    print("Found the string at read_address %\n", read_address);
                }
                if contains(as_string, "RETICLE") {
                    print("Found the string at read_address %\n", read_address);
                }

                offset += buffer.count;
            }
        }

        address = mbi.BaseAddress + mbi.RegionSize;
    }
}



get_process_name :: (process_id : DWORD) -> string, success : bool {
    process := OpenProcess(PROCESS_QUERY_INFORMATION | PROCESS_VM_READ, .FALSE, process_id);
    defer CloseHandle(process);

    name : string = copy_string("UNKNOWN PROCESS NAME");

    if !process {
        //code, description := get_error_value_and_string();
        //log_error("ERROR in get_process_name for %: % (%)\n", process_id, description, code);
        return name, false;
    }

    module_handle : HMODULE;
    cb_needed : DWORD;

    success := false;
    if EnumProcessModules(process, *module_handle, size_of(HMODULE), *cb_needed) {
        process_name : [1024]u16;
        GetModuleBaseNameW(process, module_handle, xx process_name.data, process_name.count);

        p_name: , success = wide_to_utf8_new(process_name.data);
        if success name = p_name;
    } 

    return name, success;
}


my_init_fonts :: () {
    // So that we can load our font, set to path of running executable.
    // @Incomplete: Pack a default font into Simp.

    if !working_directory_set {
        path := path_strip_filename(get_path_of_running_executable());
        set_working_directory(path);
        working_directory_set = true;
    }

    pixel_height := window_height / 24;

    // @Cleanup: Don't have path + name be separate.
    my_font = Simp.get_font_at_size(".", "OpenSans-BoldItalic.ttf", pixel_height);
    assert(my_font != null);
}



working_directory_set := false;
my_font: *Simp.Dynamic_Font;

last_active_process_index := -1;

MAX_PROCESS_COUNT :: 1024;
processes_memory : [MAX_PROCESS_COUNT] DWORD;
processes : [] DWORD;

selectable_processes : [..]Process;
selectable_process_names : [..]string;

name_filter_string : string;

Process :: struct {
    pid : DWORD;
    name : string;
}


modify_string :: (ps: *string, new_value: string) {
    free(ps.*);
    ps.* = copy_string(new_value);
}



Memory_Protection_Constant :: enum_flags u32 {
    PAGE_NOACCESS ::                0x01;
    PAGE_READONLY ::                0x02;
    PAGE_READWRITE ::               0x04;
    PAGE_WRITECOPY ::               0x08;
    PAGE_EXECUTE ::                 0x10;
    PAGE_EXECUTE_READ ::            0x20;
    PAGE_EXECUTE_READWRITE ::       0x40;
    PAGE_EXECUTE_WRITECOPY ::       0x80;
    PAGE_GUARD ::                   0x100;
    PAGE_NOCACHE ::                 0x200;
    PAGE_WRITECOMBINE ::            0x400;
    PAGE_REVERT_TO_FILE_MAP ::      0x80000000;
    PAGE_ENCLAVE_THREAD_CONTROL ::  0x80000000;
    PAGE_TARGETS_NO_UPDATE ::       0x40000000;
    PAGE_TARGETS_INVALID ::         0x40000000;
    PAGE_ENCLAVE_UNVALIDATED ::     0x20000000;
}


kernel32 :: #system_library "kernel32";
VirtualQueryEx :: (hProcess : HANDLE, lpAddress : *void, lpBUFFER : *MEMORY_BASIC_INFORMATION, dwLength : u64) -> SIZE_T #foreign kernel32;

OpenProcess :: (dwDesiredAccess : DWORD, bInheritHandle : BOOL, dwProcessId : DWORD) -> HANDLE #foreign kernel32;

ReadProcessMemory :: (hProcess : HANDLE, lpBaseAddress : *void, lpBuffer : *void, nSize : u64, lpNumberOfBytesRead : *u64) -> BOOL #foreign kernel32;

