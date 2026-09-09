set script_path [file normalize [info script]]
set repository_root [file normalize [file join [file dirname $script_path] .. .. .. ..]]
set constraint_path [file join $repository_root fpga vivado constraints stage2d_async_adc_atomic_cdc.xdc]

proc fail {message} {
    puts stderr "FAIL: $message"
    exit 1
}

proc assert_true {condition message} {
    if {![uplevel 1 [list expr $condition]]} {
        fail $message
    }
}

proc read_text {path} {
    set channel [open $path r]
    fconfigure $channel -encoding utf-8 -translation auto
    set value [read $channel]
    close $channel
    return $value
}

proc mock_prelude {mode} {
    return [string map [list @MODE@ [list $mode]] {
        set ::mock_mode @MODE@
        set ::max_delay_calls {}
        set ::bus_skew_calls {}

        proc get_cells {args} {
            set pattern [lindex $args end]
            set cells {}
            foreach leaf {wr_gray_reg wr_gray_sync1_reg rd_gray_reg rd_gray_sync1_reg} {
                set width 4
                if {$::mock_mode eq {too_few} && $leaf eq {wr_gray_reg}} {
                    set width 2
                }
                for {set index 0} {$index < $width} {incr index} {
                    if {$::mock_mode eq {missing_bit} &&
                        $leaf eq {wr_gray_sync1_reg} && $index == 2} {
                        continue
                    }
                    set name "top/u_adc_sample_cdc_bridge/u_fifo/${leaf}\[$index\]"
                    if {[regexp $pattern $name]} {
                        lappend cells $name
                    }
                }
            }
            for {set address 0} {$address < 8} {incr address} {
                for {set bit 0} {$bit < 57} {incr bit} {
                    if {$::mock_mode eq {payload_missing} &&
                        $address == 0 && $bit == 0} {
                        continue
                    }
                    set name "top/u_adc_sample_cdc_bridge/u_fifo/mem_reg\[$address\]\[$bit\]"
                    if {[regexp $pattern $name]} { lappend cells $name }
                }
            }
            for {set bit 0} {$bit < 57} {incr bit} {
                set name "top/u_adc_sample_cdc_bridge/destination_data_reg\[$bit\]"
                if {[regexp $pattern $name]} { lappend cells $name }
            }
            if {$::mock_mode eq {duplicate} &&
                [string first {wr_gray_reg} $pattern] >= 0 &&
                [string first {sync1} $pattern] < 0 && [llength $cells] != 0} {
                lappend cells [lindex $cells 0]
            }
            return $cells
        }

        proc get_property {property object} {
            if {$property eq {NAME}} {
                return $object
            }
            if {$property eq {PERIOD}} {
                if {$::mock_mode eq {invalid_period} &&
                    [string first {wr_gray_reg[0]} $object] >= 0} {
                    return zero
                }
                if {[string first {wr_gray_reg} $object] >= 0 ||
                    [string first {mem_reg} $object] >= 0 ||
                    [string first {rd_gray_sync1_reg} $object] >= 0} {
                    return 8.000
                }
                return 11.000
            }
            error "unexpected get_property: $property $object"
        }

        proc get_pins {args} {
            set position [lsearch -exact $args -of_objects]
            set cells [lindex $args [expr {$position + 1}]]
            set filter_position [lsearch -exact $args -filter]
            set filter [lindex $args [expr {$filter_position + 1}]]
            if {![regexp {REF_PIN_NAME == ([A-Z]+)} $filter _ pin]} {
                error "unexpected pin filter: $filter"
            }
            set pins {}
            foreach cell $cells { lappend pins ${cell}/${pin} }
            return $pins
        }

        proc get_clocks {args} {
            set position [lsearch -exact $args -of_objects]
            set pins [lindex $args [expr {$position + 1}]]
            set pin [lindex $pins 0]
            if {$::mock_mode eq {missing_clock} &&
                [string first {wr_gray_reg[0]/C} $pin] >= 0} {
                return {}
            }
            if {$::mock_mode eq {multiple_clocks} &&
                [string first {wr_gray_reg[0]/C} $pin] >= 0} {
                return [list ${pin}/clock0 ${pin}/clock1]
            }
            return [list ${pin}/clock]
        }

        proc set_max_delay {args} {
            lappend ::max_delay_calls $args
        }

        proc set_bus_skew {args} {
            lappend ::bus_skew_calls $args
        }
    }]
}

proc run_fixture {constraint_path mode} {
    set child [interp create]
    interp eval $child [mock_prelude $mode]
    set code [catch {interp eval $child [list source $constraint_path]} message options]
    set result [dict create code $code message $message]
    if {!$code} {
        dict set result max_delay_calls [interp eval $child {set ::max_delay_calls}]
        dict set result bus_skew_calls [interp eval $child {set ::bus_skew_calls}]
        dict set result authority_result \
            [interp eval $child {set ::stage2d_async_adc_atomic_cdc_constraint_result}]
    } elseif {[dict exists $options -errorcode]} {
        dict set result errorcode [dict get $options -errorcode]
    }
    interp delete $child
    return $result
}

if {![file isfile $constraint_path]} {
    fail "CDC constraint authority is missing: $constraint_path"
}

set source [read_text $constraint_path]
assert_true {![regexp {(?m)^[ \t]*(namespace|proc|foreach|if|lappend|error)([ \t]|$)} $source]} \
    {constraint authority is not restricted-XDC-compatible straight-line Tcl}
set fifo_source [read_text [file join $repository_root rtl async_fifo_gray.v]]
foreach gray_register {wr_gray rd_gray} {
    assert_true {[regexp [format {\(\* KEEP = "TRUE" \*\) reg \[PTR_WIDTH-1:0\] %s} $gray_register] $fifo_source]} \
        "FIFO Gray source register is not explicitly preserved: $gray_register"
}
foreach required {
    {u_adc_sample_cdc_bridge/u_fifo/}
    {wr_gray_reg}
    {wr_gray_sync1_reg}
    {WRITE_POINTER_TO_READ_DOMAIN}
    {rd_gray_reg}
    {rd_gray_sync1_reg}
    {READ_POINTER_TO_WRITE_DOMAIN}
    {mem_reg}
    {destination_data_reg}
    {FIFO_PAYLOAD_TO_DESTINATION_REGISTER}
    {set_max_delay -datapath_only}
    {set_bus_skew}
    {report_cdc}
    {report_timing}
} {
    assert_true {[string first $required $source] >= 0} \
        "constraint authority lacks required token: $required"
}
foreach forbidden {
    {set_false_path}
    {set_clock_groups}
    {fifo_write_data}
    {fifo_read_data}
    {mem[*]}
} {
    assert_true {[string first $forbidden $source] < 0} \
        "constraint authority contains forbidden broad token: $forbidden"
}

set positive [run_fixture $constraint_path positive]
assert_true {[dict get $positive code] == 0} \
    "distinct-clock positive fixture failed: [dict get $positive message]"
assert_true {[llength [dict get $positive max_delay_calls]] == 3} \
    {positive fixture did not emit exactly three max-delay constraints}
assert_true {[llength [dict get $positive bus_skew_calls]] == 2} \
    {positive fixture did not emit exactly two bus-skew constraints}
foreach call [concat \
    [dict get $positive max_delay_calls] \
    [dict get $positive bus_skew_calls]] {
    assert_true {[lsearch -exact $call 8.0] >= 0 ||
        [lsearch -exact $call 8.000] >= 0} \
        "crossing did not use the conservative 8 ns bound: $call"
    set from_position [lsearch -exact $call -from]
    set to_position [lsearch -exact $call -to]
    assert_true {$from_position >= 0 && $to_position >= 0} \
        "crossing lacks explicit endpoints: $call"
    set endpoint_cells [concat \
        [lindex $call [expr {$from_position + 1}]] \
        [lindex $call [expr {$to_position + 1}]]]
    foreach endpoint $endpoint_cells {
        assert_true {![regexp {/[QD]$} $endpoint]} \
            "crossing uses a segmented data-pin endpoint: $endpoint"
        assert_true {[regexp {_reg\[[0-9]+\]$} $endpoint] ||
            [regexp {mem_reg\[[0-9]+\]\[[0-9]+\]$} $endpoint]} \
            "crossing endpoint is not an exact register cell: $endpoint"
    }
}
assert_true {[llength [dict get $positive authority_result]] == 3} \
    {positive fixture did not publish all crossing records}

foreach mode {
    too_few
    missing_bit
    duplicate
    missing_clock
    multiple_clocks
    invalid_period
    payload_missing
} {
    set result [run_fixture $constraint_path $mode]
    assert_true {[dict get $result code] == 1} \
        "$mode negative fixture unexpectedly passed"
}

puts {STAGE2D_CDC_CONSTRAINT_AUTHORITY=PASS}
puts {GRAY_POINTER_BUS_SKEW_OR_MAX_DELAY_CONTRACT=PASS}
puts {STAGE2D_CDC_CONSTRAINT_TESTS=PASS}
