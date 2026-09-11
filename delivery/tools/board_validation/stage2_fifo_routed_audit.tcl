# Audit the existing routed FIFO without changing constraints or waivers.
if {[llength $argv] != 2} { error "Expected routed checkpoint and new output directory" }
lassign $argv checkpoint output
if {[file exists $output]} { error "Refusing to overwrite audit evidence" }
file mkdir $output
set audit [open [file join $output fifo_paths.tsv] {WRONLY CREAT EXCL}]
puts $audit "crossing\tstartpoint\tendpoint\trequirement_ns\tslack_ns"
set base protection_system_i/protection_ip_axi_lite_0/inst/u_adc_sample_cdc_bridge
proc check_paths {label sources destinations count limit} {
    global audit output
    set paths [get_timing_paths -from $sources -to $destinations -delay_type max \
        -max_paths $count -nworst 1]
    if {[llength $paths] != $count} {
        error "$label: timing path count [llength $paths] != $count"
    }
    report_timing -from $sources -to $destinations -delay_type max \
        -max_paths $count -nworst 1 -file [file join $output ${label}.rpt]
    set endpoints {}
    foreach path $paths {
        set requirement [get_property REQUIREMENT $path]
        set slack [get_property SLACK $path]
        set endpoint [get_property ENDPOINT_PIN $path]
        if {abs($requirement - $limit) > 0.001 || $slack < 0.0} {
            error "$label: unexpected requirement/slack $requirement/$slack"
        }
        lappend endpoints $endpoint
        puts $audit "$label\t[get_property STARTPOINT_PIN $path]\t$endpoint\t$requirement\t$slack"
    }
    if {[llength [lsort -unique $endpoints]] != $count} {
        error "$label: endpoint coverage is incomplete"
    }
    flush $audit
}
set outcome [catch {
    open_checkpoint $checkpoint
    set dest [get_cells -quiet -hier -regexp \
        {(^|.*/)u_adc_sample_cdc_bridge/destination_data_reg\[[0-9]+\]$}]
    if {[llength $dest] != 57} { error "Expected 57 FIFO destination bits" }
    set source_period [get_property PERIOD [get_clocks clk_fpga_1]]
    set dest_period [get_property PERIOD [get_clocks clk_fpga_0]]
    if {$source_period != 8.0 || $dest_period != 10.0} { error "Clock contract differs" }
    for {set address 0} {$address < 8} {incr address} {
        set expression [format {(^|.*/)u_adc_sample_cdc_bridge/u_fifo/mem_reg\[%d\]\[[0-9]+\]$} $address]
        set sources [get_cells -quiet -hier -regexp $expression]
        if {[llength $sources] != 57} { error "Expected 57 bits in FIFO word $address" }
        check_paths payload_word_$address $sources $dest 57 8.0
    }
    foreach direction {wr rd} {
        set sources {}
        set first_stage {}
        for {set bit 0} {$bit < 4} {incr bit} {
            set previous [get_cells [format {%s/u_fifo/%s_gray_reg[%d]} $base $direction $bit]]
            lappend sources $previous
            foreach stage {1 2} {
                set cell [get_cells [format {%s/u_fifo/%s_gray_sync%d_reg[%d]} $base $direction $stage $bit]]
                if {[llength $cell] != 1 || [get_property ASYNC_REG $cell] ni {1 TRUE true}} {
                    error "Missing ASYNC_REG on $direction bit $bit stage $stage"
                }
                if {$stage == 1} { lappend first_stage $cell }
                set d [get_pins -of_objects $cell -filter {REF_PIN_NAME == D}]
                set roots [get_cells -of_objects [all_fanin -flat -startpoints_only -to $d]]
                set root_names [lsort -unique [get_property NAME $roots]]
                if {[llength $root_names] != 1 ||
                    [lindex $root_names 0] ne [get_property NAME $previous]} {
                    error "Unexpected synchronizer fanin: $cell <- $roots, expected $previous"
                }
                set previous $cell
            }
        }
        check_paths ${direction}_gray $sources $first_stage 4 8.0
    }
    report_cdc -details -file [file join $output cdc_unwaived.rpt]
    report_bus_skew -file [file join $output bus_skew.rpt]
    puts "FIFO_ROUTED_AUDIT=PASS"
    puts "PAYLOAD_PATHS_CHECKED=456"
    puts "GRAY_PATHS_CHECKED=8"
    puts "ASYNC_REG_STAGES_CHECKED=16"
    puts "CONSTRAINT_CHANGES=0"
    puts "WAIVERS_CREATED=0"
} message options]
close $audit
catch {close_design}
if {$outcome} {
    puts stderr "FIFO_ROUTED_AUDIT=FAIL: $message"
    puts stderr [dict get $options -errorinfo]
    exit 1
}
exit 0
