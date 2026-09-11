# Fixed non-Vivado command facade for the PRT02-D Collector candidate.
# It creates only synthetic fixture evidence at caller-supplied external paths.

namespace eval ::stage1e::evidence_collector_command_model_v1 {
    variable interface_version stage1e-evidence-collector-command-model-v1
    variable event_root {}
    variable role_states {}
    variable role_text_maps {}
    variable invocation_log {}
}

proc ::stage1e::evidence_collector_command_model_v1::interface_version {} {
    variable interface_version
    return $interface_version
}

proc ::stage1e::evidence_collector_command_model_v1::roles {} {
    return {
        TIMING_SUMMARY TIMING_PATH_GROUPS CLOCK_INTERACTION
        CLOCKS_GENERATED_CLOCKS CONSTRAINT_COVERAGE CHECK_TIMING
        TIMING_EXCEPTION_SOURCE CONDITIONAL_BUS_SKEW UTILIZATION DRC
        METHODOLOGY CDC MESSAGE_SOURCE
    }
}

proc ::stage1e::evidence_collector_command_model_v1::reset {root} {
    variable event_root
    variable role_states
    variable invocation_log
    variable role_text_maps
    set event_root $root
    set role_states {}
    foreach role [roles] { dict set role_states $role SUCCESS }
    set role_text_maps {}
    set invocation_log {}
    return 1
}

proc ::stage1e::evidence_collector_command_model_v1::set_role_text_map {
    role old new
} {
    variable role_text_maps
    if {[lsearch -exact [roles] $role] < 0} {
        error "Unknown fixture report role '$role'."
    }
    if {$old eq {}} { error {Fixture mutation source cannot be empty.} }
    dict set role_text_maps $role [list $old $new]
}

proc ::stage1e::evidence_collector_command_model_v1::set_role_state {
    role state
} {
    variable role_states
    if {[lsearch -exact [roles] $role] < 0} {
        error "Unknown fixture report role '$role'."
    }
    if {[lsearch -exact {
            SUCCESS FAILURE MISSING ZERO BLOCKED INTEGRITY_LOSS
            PRODUCER_TERMINATED
        } $state] < 0} {
        error "Unknown fixture report state '$state'."
    }
    dict set role_states $role $state
}

proc ::stage1e::evidence_collector_command_model_v1::invocation_log {} {
    variable invocation_log
    return $invocation_log
}

proc ::stage1e::evidence_collector_command_model_v1::invocation_count {role} {
    variable invocation_log
    set count 0
    foreach entry $invocation_log {
        if {[dict get $entry role] eq $role} { incr count }
    }
    return $count
}

proc ::stage1e::evidence_collector_command_model_v1::_open_count {} {
    variable event_root
    variable invocation_log
    if {$event_root eq {} || ![file exists $event_root]} { return 0 }
    set command_ordinal [expr {[llength $invocation_log] + 1}]
    set event_ordinal [expr {($command_ordinal * 2) - 1}]
    set expected [file join $event_root \
        [format {event-%04d-open.json} $event_ordinal]]
    if {![file exists $expected] || ![file isfile $expected]} { return -1 }
    return $command_ordinal
}

proc ::stage1e::evidence_collector_command_model_v1::_write {path text} {
    set channel [open $path wb]
    fconfigure $channel -translation binary -encoding binary
    try {
        puts -nonewline $channel [encoding convertto utf-8 $text]
    } finally {
        close $channel
    }
}

proc ::stage1e::evidence_collector_command_model_v1::_profile {role} {
    set profiles [dict create \
        TIMING_SUMMARY stage1e-fixture-timing-summary-profile-v1 \
        TIMING_PATH_GROUPS stage1e-fixture-timing-path-groups-profile-v1 \
        CLOCK_INTERACTION stage1e-fixture-clock-interaction-profile-v1 \
        CLOCKS_GENERATED_CLOCKS stage1e-fixture-clocks-profile-v1 \
        CONSTRAINT_COVERAGE stage1e-fixture-constraint-coverage-profile-v1 \
        CHECK_TIMING stage1e-fixture-check-timing-profile-v1 \
        TIMING_EXCEPTION_SOURCE stage1e-fixture-timing-exception-profile-v1 \
        CONDITIONAL_BUS_SKEW stage1e-fixture-bus-skew-profile-v1 \
        UTILIZATION stage1e-fixture-utilization-profile-v1 \
        DRC stage1e-fixture-drc-profile-v1 \
        METHODOLOGY stage1e-fixture-methodology-profile-v1 \
        CDC stage1e-fixture-cdc-profile-v1 \
        MESSAGE_SOURCE stage1e-fixture-message-profile-v1]
    return [dict get $profiles $role]
}

proc ::stage1e::evidence_collector_command_model_v1::_records {role} {
    switch -- $role {
        TIMING_SUMMARY {
            return {
TIMING|SETUP|ALL|WNS_PS|1250|1250|PS|0|42|COMPLETE
TIMING|HOLD|ALL|WHS_PS|80|80|PS|0|42|COMPLETE
TIMING|PULSE_WIDTH|ALL|WPWS_PS|500|500|PS|0|8|COMPLETE}
        }
        TIMING_PATH_GROUPS {
            return {
TIMING|SETUP|CLOCK_A|WNS_PS|1250|1250|PS|0|20|COMPLETE
TIMING|HOLD|CLOCK_A|WHS_PS|80|80|PS|0|20|COMPLETE}
        }
        CLOCK_INTERACTION {
            return {CLOCK_CDC|INTERACTION|PAIR-1|SYNCHRONOUS|INFO|clk_a|clk_b|src_pin|dst_pin|RELATED|-1|NONE|clk_a|1|NOT_REPORTED|COMPLETE}
        }
        CLOCKS_GENERATED_CLOCKS {
            return {
CLOCK_CDC|PRIMARY|CLK-A|PRIMARY|INFO|clk_a|NONE|port_a|NONE|PRIMARY|10000|0,5000|NONE|1|NOT_REPORTED|COMPLETE
CLOCK_CDC|GENERATED|CLK-B|GENERATED|INFO|clk_b|NONE|pin_b|NONE|DIVIDE_BY_2|20000|0,10000|clk_a|1|NOT_REPORTED|COMPLETE}
        }
        CONSTRAINT_COVERAGE {
            return {
TIMING|COVERAGE|ALL|COVERED_ENDPOINTS|128|128|COUNT|0|128|COMPLETE
EXCEPTION|EXC-COVERAGE|set_false_path|FALSE_PATH|constraints.xdc:10|src_a|dst_b|NONE|src_a,dst_b|clk_a->clk_b|COVERED|ACTIVE|COMPLETE}
        }
        CHECK_TIMING {
            return {
TIMING|CHECK_TIMING|ALL|UNCONSTRAINED_PATHS|0|0|COUNT|0|42|COMPLETE
MESSAGE|CHECK-1|INFO|REPORT_COLLECTION|1|Synthetic_check_timing_complete|CHECK_TIMING|timing_context|section:check|COMPLETE}
        }
        TIMING_EXCEPTION_SOURCE {
            return {EXCEPTION|EXC-1|set_false_path|FALSE_PATH|constraints.xdc:20|src_sync|dst_sync|NONE|src_sync,dst_sync|clk_a->clk_b|COVERED|ACTIVE|COMPLETE}
        }
        CONDITIONAL_BUS_SKEW {
            return {TIMING|BUS_SKEW|BUS_A|WORST_SKEW_PS|75|75|PS|0|4|COMPLETE}
        }
        UTILIZATION {
            return {
UTILIZATION|LUT|Slice_LUTs|3000|53200|56391|COUNT|DEVICE|COMPLETE
UTILIZATION|FF|Slice_Registers|4500|106400|42293|COUNT|DEVICE|COMPLETE
UTILIZATION|BRAM|Block_RAM_Tile_MILLI|18000|140000|128571|MILLI_COUNT|DEVICE|COMPLETE
UTILIZATION|DSP|DSPs|2|220|909|COUNT|DEVICE|COMPLETE
UTILIZATION|IO|Bonded_IOB|12|125|96000|COUNT|DEVICE|COMPLETE
UTILIZATION|BUFG|BUFGCTRL|3|32|93750|COUNT|DEVICE|COMPLETE}
        }
        DRC {
            return {
DRC|DRC-1|WARNING|2|cell_a,cell_b|COMPLETE
DRC|DRC-2|INFO|1|net_a|COMPLETE}
        }
        METHODOLOGY {
            return {
METHODOLOGY|METH-1|WARNING|1|cell_sync|CDC|generated_ip|COMPLETE
METHODOLOGY|METH-2|INFO|1|clock_a|CLOCKING|user_constraints|COMPLETE}
        }
        CDC {
            return {
CLOCK_CDC|CDC|CDC-1|SYNCHRONIZER|INFO|clk_a|clk_b|src_reg|dst_reg|ASYNC|10000|NONE|NONE|2|NOT_REPORTED|COMPLETE
CLOCK_CDC|CDC|CDC-2|RESET|INFO|clk_a|clk_b|reset_src|reset_dst|ASYNC_RESET|10000|NONE|NONE|1|PRESENT|COMPLETE}
        }
        MESSAGE_SOURCE {
            return {
MESSAGE|MSG-100|WARNING|ROUTE_DESIGN|2|Synthetic_route_warning|REPORT|route_context|section:messages|COMPLETE
MESSAGE|MSG-200|INFO|REPORT_COLLECTION|1|Synthetic_report_information|REPORT|report_context|section:messages|COMPLETE}
        }
        default { error "No fixture records for role '$role'." }
    }
}

proc ::stage1e::evidence_collector_command_model_v1::_content {role} {
    variable role_text_maps
    set records [string trim [_records $role] "\n"]
    set content "STAGE1E_EVIDENCE_FIXTURE_V1\nPROFILE|[_profile $role]\nROLE|$role\nSCOPE|CURRENT_SYNTHETIC\n$records\nEND_STAGE1E_EVIDENCE_FIXTURE_V1\n"
    if {[dict exists $role_text_maps $role]} {
        lassign [dict get $role_text_maps $role] old new
        if {[string first $old $content] < 0} {
            error "Fixture mutation source token is absent for $role."
        }
        set content [string map [list $old $new] $content]
    }
    return $content
}

proc ::stage1e::evidence_collector_command_model_v1::_run {role path} {
    variable role_states
    variable invocation_log
    if {![dict exists $role_states $role]} {
        error {Fixture command model was not reset before use.}
    }
    set state [dict get $role_states $role]
    lappend invocation_log [dict create role $role path $path state $state \
        open_event_count_before_command [_open_count]]
    switch -- $state {
        SUCCESS {
            _write $path [_content $role]
            return SUCCESS
        }
        MISSING { return SUCCESS_WITHOUT_FILE }
        ZERO {
            _write $path {}
            return SUCCESS_ZERO_BYTE
        }
        FAILURE {
            return -code error \
                -errorcode {STAGE1E FIXTURE REPORT FAILURE} \
                "Synthetic report failure for $role."
        }
        BLOCKED {
            return -code error \
                -errorcode {STAGE1E FIXTURE REPORT BLOCKED} \
                "Synthetic report block for $role."
        }
        INTEGRITY_LOSS {
            return -code error \
                -errorcode {STAGE1E FIXTURE REPORT INTEGRITY_LOSS} \
                "Synthetic session-integrity loss for $role."
        }
        PRODUCER_TERMINATED {
            return -code error \
                -errorcode {STAGE1E FIXTURE REPORT PRODUCER_TERMINATED} \
                "Synthetic producer termination for $role."
        }
    }
}

proc ::stage1e::evidence_collector_command_model_v1::timing_summary {path} {
    return [_run TIMING_SUMMARY $path]
}
proc ::stage1e::evidence_collector_command_model_v1::timing_path_groups {path} {
    return [_run TIMING_PATH_GROUPS $path]
}
proc ::stage1e::evidence_collector_command_model_v1::clock_interaction {path} {
    return [_run CLOCK_INTERACTION $path]
}
proc ::stage1e::evidence_collector_command_model_v1::clocks {path} {
    return [_run CLOCKS_GENERATED_CLOCKS $path]
}
proc ::stage1e::evidence_collector_command_model_v1::constraint_coverage {path} {
    return [_run CONSTRAINT_COVERAGE $path]
}
proc ::stage1e::evidence_collector_command_model_v1::check_timing {path} {
    return [_run CHECK_TIMING $path]
}
proc ::stage1e::evidence_collector_command_model_v1::timing_exceptions {path} {
    return [_run TIMING_EXCEPTION_SOURCE $path]
}
proc ::stage1e::evidence_collector_command_model_v1::bus_skew {path} {
    return [_run CONDITIONAL_BUS_SKEW $path]
}
proc ::stage1e::evidence_collector_command_model_v1::utilization {path} {
    return [_run UTILIZATION $path]
}
proc ::stage1e::evidence_collector_command_model_v1::drc {path} {
    return [_run DRC $path]
}
proc ::stage1e::evidence_collector_command_model_v1::methodology {path} {
    return [_run METHODOLOGY $path]
}
proc ::stage1e::evidence_collector_command_model_v1::cdc {path} {
    return [_run CDC $path]
}
proc ::stage1e::evidence_collector_command_model_v1::messages {path} {
    return [_run MESSAGE_SOURCE $path]
}
