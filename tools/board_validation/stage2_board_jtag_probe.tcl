# Read-only JTAG discovery. Programming, reset, and ILA capture are not performed.
set script_directory [file dirname [file normalize [info script]]]
source [file join $script_directory stage1_board_ila_common.tcl]
set server_url localhost:3121
if {[llength $argv] == 1} { set server_url [lindex $argv 0] }
set outcome [catch {
    puts "VIVADO_VERSION=[version -short]"
    open_hw_manager
    connect_hw_server -url $server_url
    set targets [get_hw_targets]
    puts "JTAG_TARGETS=$targets"
    if {[llength $targets] != 1} { error "Expected one project JTAG target" }
    current_hw_target [lindex $targets 0]
    set_property PARAM.FREQUENCY 1000000 [current_hw_target]
    open_hw_target
    set records [::stage1::runtime_device_records]
    puts "JTAG_DEVICE_RECORDS=$records"
    puts [help wait_on_hw_ila]
    set device [::stage1::select_fpga_device_record $records]
    puts "JTAG_DEVICE=$device"
    puts "JTAG_DISCOVERY=PASS"
} message options]
catch {close_hw_target}
catch {close_hw_manager}
if {$outcome} {
    puts stderr "JTAG_DISCOVERY=BLOCKED: $message"
    exit 1
}
exit 0
