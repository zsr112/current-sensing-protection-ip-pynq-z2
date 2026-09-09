# Host-only Stage2I BIT/LTX and System ILA binding preflight.
#
# The caller must provide an already running Hardware Server. This script does
# not launch one, program the FPGA, reset the device, or arm a capture.

set script_directory [file dirname [file normalize [info script]]]
source [file join $script_directory stage1_board_ila_common.tcl]

proc execute_binding_preflight {} {
    global options bit_path ltx_path
    set preflight_status [catch {
        ::stage1::open_bound_hardware \
            $bit_path $ltx_path $options(-profile) \
            $options(-hw_server_url)
        puts "STAGE2I_ILA_BINDING_PREFLIGHT_PASS"
    } preflight_error preflight_options]

    ::stage1::close_bound_hardware
    if {$preflight_status != 0} {
        puts stderr \
            "STAGE2I_ILA_BINDING_PREFLIGHT_FAILED: $preflight_error"
        return -options $preflight_options $preflight_error
    }
}

if {[info exists ::stage1_preflight_library_only] &&
    $::stage1_preflight_library_only} {
    return
}

array set options {
    -bit {}
    -ltx {}
    -profile {}
    -hw_server_url {localhost:3121}
    -static_check {0}
}

if {[expr {[llength $argv] % 2}] != 0} {
    error "Arguments must be key/value pairs: $argv"
}
foreach {name value} $argv {
    if {![info exists options($name)]} {
        error "Unknown argument: $name"
    }
    set options($name) $value
}
foreach required {-bit -ltx -profile} {
    if {$options($required) eq {}} {
        error "Missing required argument: $required"
    }
}
if {$options(-static_check) ni {0 1}} {
    error "-static_check must be 0 or 1"
}
::stage1::profile_core_roles $options(-profile)

set bit_path [file normalize $options(-bit)]
set ltx_path [file normalize $options(-ltx)]
foreach {label path} [list BIT $bit_path LTX $ltx_path] {
    if {![file isfile $path]} {
        error "Accepted $label is missing: $path"
    }
}

if {$options(-static_check)} {
    ::stage1::static_compile {execute_binding_preflight}
    puts "STAGE2I_ILA_BINDING_PREFLIGHT_STATIC_CHECK_PASS"
    puts "PROFILE=$options(-profile)"
    puts "BIT=$bit_path"
    puts "LTX=$ltx_path"
    return
}

execute_binding_preflight
