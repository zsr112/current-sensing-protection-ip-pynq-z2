set script_path [file normalize [info script]]
set repository_root [file normalize \
    [file join [file dirname $script_path] .. .. .. ..]]
set constraint_path [file join $repository_root fpga vivado constraints \
    stage2e_transaction_observability_cdc.xdc]

proc fail {message} {
    puts stderr "FAIL: $message"
    exit 1
}

proc assert_true {condition message} {
    if {![uplevel 1 [list expr $condition]]} { fail $message }
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
            set counter_pairs {
                source_accept_count_gray_reg
                source_accept_count_gray_sync1_reg
                backpressure_cycle_count_gray_reg
                backpressure_cycle_count_gray_sync1_reg
                source_protocol_violation_count_gray_reg
                source_protocol_violation_count_gray_sync1_reg
                source_drop_count_gray_reg
                source_drop_count_gray_sync1_reg
                fifo_overflow_attempt_count_gray_reg
                fifo_overflow_attempt_count_gray_sync1_reg
                counter_saturation_event_count_gray_reg
                counter_saturation_event_count_gray_sync1_reg
            }
            set cells {}
            foreach leaf $counter_pairs {
                set hierarchy {top/u_source_observability_cdc}
                if {[string first {_sync1_reg} $leaf] < 0} {
                    set hierarchy \
                        {top/u_adc_sample_cdc_bridge/u_source_observer}
                }
                set width 32
                if {$::mock_mode eq {too_few} &&
                    $leaf eq {source_accept_count_gray_reg}} {
                    set width 15
                }
                for {set index 0} {$index < $width} {incr index} {
                    if {$::mock_mode eq {missing_bit} &&
                        $leaf eq {source_drop_count_gray_sync1_reg} &&
                        $index == 7} { continue }
                    set name "${hierarchy}/${leaf}\[$index\]"
                    if {[regexp $pattern $name]} { lappend cells $name }
                }
            }
            foreach leaf {
                last_source_sequence_gray_reg
                last_source_sequence_gray_sync1_reg
            } {
                set hierarchy {top/u_source_observability_cdc}
                if {[string first {_sync1_reg} $leaf] < 0} {
                    set hierarchy \
                        {top/u_adc_sample_cdc_bridge/u_source_observer}
                }
                set width 32
                if {$::mock_mode eq {bus_width} &&
                    $leaf eq {last_source_sequence_gray_sync1_reg}} {
                    set width 31
                }
                for {set index 0} {$index < $width} {incr index} {
                    set name "${hierarchy}/${leaf}\[$index\]"
                    if {[regexp $pattern $name]} { lappend cells $name }
                }
            }
            if {$::mock_mode eq {duplicate} && [llength $cells] != 0 &&
                [string first {source_accept_count_gray_reg} $pattern] >= 0 &&
                [string first {_sync1_reg} $pattern] < 0} {
                lappend cells [lindex $cells 0]
            }
            return $cells
        }

        proc get_property {property object} {
            if {$property eq {NAME}} { return $object }
            if {$property eq {PERIOD}} {
                if {$::mock_mode eq {invalid_period} &&
                    [string first {source_accept_count_gray_reg[0]} \
                        $object] >= 0} { return zero }
                if {[string first {u_source_observer} $object] >= 0} {
                    return 6.000
                }
                return 10.000
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
                [string first {source_accept_count_gray_reg[0]/C} \
                    $pin] >= 0} { return {} }
            if {$::mock_mode eq {multiple_clocks} &&
                [string first {source_accept_count_gray_reg[0]/C} \
                    $pin] >= 0} {
                return [list ${pin}/clock0 ${pin}/clock1]
            }
            return [list ${pin}/clock]
        }

        proc set_max_delay {args} { lappend ::max_delay_calls $args }
        proc set_bus_skew {args} { lappend ::bus_skew_calls $args }
    }]
}

proc run_fixture {constraint_path mode} {
    set child [interp create]
    interp eval $child [mock_prelude $mode]
    set code [catch {interp eval $child [list source $constraint_path]} \
        message options]
    set result [dict create code $code message $message]
    if {!$code} {
        dict set result max_delay_calls \
            [interp eval $child {set ::max_delay_calls}]
        dict set result bus_skew_calls \
            [interp eval $child {set ::bus_skew_calls}]
        dict set result authority_result [interp eval $child \
            {set ::stage2e_transaction_observability_cdc_constraint_result}]
    } elseif {[dict exists $options -errorcode]} {
        dict set result errorcode [dict get $options -errorcode]
    }
    interp delete $child
    return $result
}

assert_true {[file isfile $constraint_path]} \
    "Stage 2E observability CDC authority is missing"
set source [read_text $constraint_path]
assert_true {![regexp {(?m)^[ \t]*(namespace|proc|foreach|if|lappend|error)([ \t]|$)} $source]} \
    {constraint authority is not restricted-XDC-compatible straight-line Tcl}
set observer_source [read_text [file join $repository_root rtl transaction_source_observer.v]]
foreach gray_register {
    source_accept_count_gray
    backpressure_cycle_count_gray
    source_protocol_violation_count_gray
    source_drop_count_gray
    fifo_overflow_attempt_count_gray
    counter_saturation_event_count_gray
    last_source_sequence_gray
} {
    assert_true {[regexp [format {KEEP = "TRUE" \*\)\s+output reg[^\n]*%s} $gray_register] $observer_source]} \
        "Source Gray register is not explicitly preserved: $gray_register"
}
foreach required {
    {u_adc_sample_cdc_bridge/u_source_observer}
    {u_source_observability_cdc}
    {source_accept_count_gray_reg}
    {source_accept_count_gray_sync1_reg}
    {counter_saturation_event_count_gray_reg}
    {last_source_sequence_gray_reg}
    {set_max_delay -datapath_only}
    {set_bus_skew}
    {report_cdc}
    {report_timing}
} {
    assert_true {[string first $required $source] >= 0} \
        "constraint lacks required token: $required"
}
foreach forbidden {
    {set_false_path}
    {set_clock_groups}
    {source_accept_count_reg[}
    {fifo_write_data}
    {fifo_read_data}
    {short_pulse}
} {
    assert_true {[string first $forbidden $source] < 0} \
        "constraint contains forbidden token: $forbidden"
}

set positive [run_fixture $constraint_path positive]
assert_true {[dict get $positive code] == 0} \
    "positive fixture failed: [dict get $positive message]"
assert_true {[llength [dict get $positive max_delay_calls]] == 7} \
    {positive fixture did not emit seven max-delay constraints}
assert_true {[llength [dict get $positive bus_skew_calls]] == 7} \
    {positive fixture did not emit seven bus-skew constraints}
assert_true {[llength [dict get $positive authority_result]] == 7} \
    {positive fixture did not publish seven crossing records}
foreach call [concat [dict get $positive max_delay_calls] \
    [dict get $positive bus_skew_calls]] {
    assert_true {[lsearch -exact $call 6.0] >= 0 ||
        [lsearch -exact $call 6.000] >= 0} \
        "crossing did not use conservative 6 ns bound: $call"
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
        assert_true {[regexp {_reg\[[0-9]+\]$} $endpoint]} \
            "crossing endpoint is not an exact register cell: $endpoint"
    }
}

foreach mode {
    too_few
    missing_bit
    duplicate
    bus_width
    missing_clock
    multiple_clocks
    invalid_period
} {
    set result [run_fixture $constraint_path $mode]
    assert_true {[dict get $result code] == 1} \
        "$mode negative fixture unexpectedly passed"
}

puts {STAGE2E_OBSERVABILITY_CDC_CONSTRAINT_AUTHORITY=PASS}
puts {REGISTERED_GRAY_SOURCE_TELEMETRY=PASS}
puts {BINARY_MULTI_BIT_SYNCHRONIZATION=FORBIDDEN}
puts {SHORT_SOURCE_PULSE_SYNCHRONIZATION=FORBIDDEN}
puts {STAGE2E_OBSERVABILITY_CDC_CONSTRAINT_TESTS=PASS}
