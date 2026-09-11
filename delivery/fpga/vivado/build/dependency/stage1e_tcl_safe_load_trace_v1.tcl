# Stage 1E PRT02-E standalone-Tcl disconnected safe-load trace v1.

namespace eval ::stage1e::safe_load_trace_v1 {
    variable interface_version stage1e-tcl-safe-load-trace-interface-v1
    variable repository_root {}
    variable output_path {}
    variable scenario {}
    variable domain {}
    variable records {}
    variable rehearsal_records {}
    variable ordinal 0
    variable load_ordinal 0
    variable attempt_ordinal 0
    variable current_requester TRACE_ASSEMBLY
    variable current_predicate CONTROLLED_INTERNAL_HARNESS
    variable initial_cwd {}
    variable initial_auto_path {}
    variable initial_environment {}
    variable initial_files {}
    variable initial_commands {}
    variable initial_cwd {}
    variable provider_owners {}
    variable provider_fingerprints {}
    variable interface_commands {
        ::stage1e::production_vivado_runner_v1::interface_version
        ::stage1e::production_vivado_collector_v1::interface_version
        ::stage1e::production_evidence_parser_v1::interface_version
        ::stage1e::production_evidence_serializer_v1::interface_version
        ::stage1e::production_vivado_observer_v1::interface_version
        ::stage1e::canonical_json_v1::interface_version
        ::stage1e::canonical_json_v1::hash_provider_interface_version
        ::stage1e::atomic_publication_v1::interface_version
        ::stage1e::envelope_contract_v1::interface_version
        ::stage1e::vivado_runtime_contract_v1::interface_version
        ::stage1e::evidence_pipeline_contract_v1::interface_version
        ::stage1e::production_vivado_controller_v1::interface_version
        ::stage1e::production_vivado_adapter_v1::interface_version
        ::stage1e::production_evidence_controller_v1::interface_version
        ::stage1e::production_evidence_adapter_v1::interface_version
        ::stage1e::production_vivado_session_v1::interface_version
    }
}

proc ::stage1e::safe_load_trace_v1::interface_version {} {
    variable interface_version
    return $interface_version
}

proc ::stage1e::safe_load_trace_v1::_record {
    kind state source_path reason {provider NONE} {interface_version NONE}
    {declared_edge NONE} {target NONE} {edge_type NONE} {attempt_id NONE}
    {load_ordinal 0} {predicate NONE} {evidence_class OBSERVED_SAFE_LOAD_TRACE}
    {record_requester {}} {interface_command NONE}
} {
    variable records
    variable rehearsal_records
    variable ordinal
    variable rehearsal_ordinal
    variable scenario
    variable domain
    variable current_requester
    if {$record_requester eq {}} { set record_requester $current_requester }
    if {$evidence_class eq {DECLARED_ASSEMBLY_REHEARSAL}} {
        if {![info exists rehearsal_ordinal]} { set rehearsal_ordinal 0 }
        incr rehearsal_ordinal
        set event_ordinal $rehearsal_ordinal
    } else {
        incr ordinal
        set event_ordinal $ordinal
    }
    set record [dict create kind $kind ordinal $event_ordinal \
        scenario $scenario domain $domain requester $record_requester \
        target $target edge_type $edge_type attempt_id $attempt_id \
        load_ordinal $load_ordinal predicate $predicate \
        evidence_class $evidence_class \
        source_path [string map {\\ /} $source_path] provider $provider \
        interface_version $interface_version interface_command $interface_command \
        attempt_state $state \
        declared_edge $declared_edge reason $reason]
    if {$evidence_class eq {DECLARED_ASSEMBLY_REHEARSAL}} {
        lappend rehearsal_records $record
    } else {
        lappend records $record
    }
}

proc ::stage1e::safe_load_trace_v1::_node_for_path {path} {
    set relative [string map {\\ /} $path]
    set map [dict create \
        fpga/vivado/build/runtime/runner/stage1e_production_vivado_session_v1.tcl VIVADO_SESSION_ASSEMBLY \
        fpga/vivado/build/runtime/runner/stage1e_production_vivado_runner_v1.tcl RUNNER \
        fpga/vivado/build/runtime/collector/stage1e_production_vivado_collector_v1.tcl COLLECTOR \
        fpga/vivado/build/runtime/parser/stage1e_production_evidence_parser_v1.tcl PARSER \
        fpga/vivado/build/runtime/identity/stage1e_production_evidence_serializer_v1.tcl IDENTITY_SERIALIZER \
        fpga/vivado/build/runtime/observer/vivado/stage1e_production_vivado_observer_v1.tcl VIVADO_CAPABILITY_OBSERVER \
        fpga/vivado/build/controller/stage1e_production_vivado_controller_v1.tcl VIVADO_CONTROLLER \
        fpga/vivado/build/adapters/stage1e_production_vivado_adapter_v1.tcl VIVADO_ADAPTER \
        fpga/vivado/build/controller/stage1e_production_evidence_controller_v1.tcl EVIDENCE_CONTROLLER \
        fpga/vivado/build/adapters/stage1e_production_evidence_adapter_v1.tcl EVIDENCE_ADAPTER \
        fpga/vivado/build/lib/stage1e_vivado_runtime_contract_v1.tcl VIVADO_RUNTIME_CONTRACT \
        fpga/vivado/build/lib/stage1e_evidence_pipeline_contract_v1.tcl EVIDENCE_PIPELINE_CONTRACT \
        fpga/vivado/build/lib/stage1e_runtime_canonical_json_v1.tcl TCL_CANONICAL_JSON \
        fpga/vivado/build/lib/stage1e_runtime_envelope_contract_v1.tcl TCL_ENVELOPE_CONTRACT \
        fpga/vivado/build/lib/stage1e_runtime_atomic_publication_v1.tcl TCL_ATOMIC_PUBLICATION \
        fpga/vivado/build/config/stage1e_vivado_runtime_record_contract_v1.dict VIVADO_RECORD_CONTRACT \
        fpga/vivado/build/config/stage1e_vivado_runtime_command_contract_v1.dict VIVADO_COMMAND_CONTRACT \
        fpga/vivado/build/config/stage1e_vivado_runtime_property_map_v1.dict VIVADO_PROPERTY_MAP \
        fpga/vivado/build/config/stage1e_report_contract_v1.dict REPORT_CONTRACT \
        fpga/vivado/build/config/stage1e_message_contract_v1.dict MESSAGE_CONTRACT \
        fpga/vivado/build/config/stage1e_parser_format_profiles_v1.dict PARSER_PROFILE_CONTRACT \
        fpga/vivado/build/config/stage1e_evidence_record_contract_v1.dict EVIDENCE_RECORD_CONTRACT \
        fpga/vivado/build/lib/stage1e_runtime_vivado_authorization_consumption_receipt_v1.schema.json VIVADO_RECEIPT_SCHEMA]
    if {[dict exists $map $relative]} { return [dict get $map $relative] }
    return REVIEW_TCL_SAFE_LOAD_HARNESS
}

proc ::stage1e::safe_load_trace_v1::_requester_from_stack {fallback} {
    foreach frame [info frame] {
        if {![dict exists $frame file]} { continue }
        set candidate [dict get $frame file]
        if {$candidate eq {}} { continue }
        if {[catch {
            set relative [_relative $candidate]
            set node [_node_for_path $relative]
        }]} { continue }
        if {$node ne {REVIEW_TCL_SAFE_LOAD_HARNESS}} { return $node }
    }
    return $fallback
}

proc ::stage1e::safe_load_trace_v1::_begin {
    kind source_path requester target edge_type declared_edge
    {provider NONE} {interface_version NONE}
    {predicate CONTROLLED_INTERNAL_HARNESS} {evidence_class OBSERVED_SAFE_LOAD_TRACE}
    {reason CONTROLLED_TRACE_EVENT} {interface_command NONE}
} {
    variable attempt_ordinal
    variable load_ordinal
    incr attempt_ordinal
    incr load_ordinal
    set attempt_id [format {TCL-%04d} $attempt_ordinal]
    ::stage1e::safe_load_trace_v1::_record $kind ATTEMPTED $source_path "${reason}_ATTEMPT" $provider \
        $interface_version $declared_edge $target $edge_type $attempt_id \
        $load_ordinal $predicate $evidence_class $requester $interface_command
    return [dict create kind $kind source_path $source_path requester $requester \
        target $target edge_type $edge_type declared_edge $declared_edge \
        provider $provider interface_version $interface_version \
        interface_command $interface_command predicate $predicate \
        evidence_class $evidence_class reason $reason attempt_id $attempt_id \
        load_ordinal $load_ordinal]
}

proc ::stage1e::safe_load_trace_v1::_complete {context terminal_state} {
    if {$terminal_state ni {LOADED FAILED OPTIONAL_NOT_LOADED BLOCKED}} {
        error "Invalid trace terminal state: $terminal_state"
    }
    ::stage1e::safe_load_trace_v1::_record \
        [dict get $context kind] $terminal_state \
        [dict get $context source_path] "[dict get $context reason]_TERMINAL" \
        [dict get $context provider] [dict get $context interface_version] \
        [dict get $context declared_edge] [dict get $context target] \
        [dict get $context edge_type] [dict get $context attempt_id] \
        [dict get $context load_ordinal] [dict get $context predicate] \
        [dict get $context evidence_class] [dict get $context requester] \
        [dict get $context interface_command]
}

proc ::stage1e::safe_load_trace_v1::_attempt {
    kind source_path requester target edge_type declared_edge
    {provider NONE} {interface_version NONE} {terminal_state LOADED}
    {predicate CONTROLLED_INTERNAL_HARNESS} {evidence_class OBSERVED_SAFE_LOAD_TRACE}
    {reason CONTROLLED_TRACE_EVENT} {interface_command NONE}
} {
    set context [_begin $kind $source_path $requester $target $edge_type \
        $declared_edge $provider $interface_version $predicate $evidence_class \
        $reason $interface_command]
    _complete $context $terminal_state
}

proc ::stage1e::safe_load_trace_v1::_relative {path} {
    variable repository_root
    set root [string trimright [string map {\\ /} \
        [file normalize $repository_root]] /]
    set normalized [string map {\\ /} [file normalize $path]]
    if {[string first "${root}/" "${normalized}/"] != 0} {
        _record MUTATION BLOCKED $normalized SOURCE_PATH_ESCAPE
        error "Safe-load source escapes the repository: $normalized"
    }
    return [string range $normalized [expr {[string length $root] + 1}] end]
}

proc ::stage1e::safe_load_trace_v1::_snapshot_dir {directory prefix result_var} {
    upvar 1 $result_var result
    foreach path [lsort [glob -nocomplain -directory $directory *]] {
        set normalized [file normalize $path]
        if {[file type $normalized] eq {link}} {
            error "Reparse/link path encountered during safe-load snapshot: $normalized"
        }
        set relative [string map {\\ /} [string range $normalized \
            [expr {[string length $prefix] + 1}] end]]
        if {[file isdirectory $normalized]} {
            _snapshot_dir $normalized $prefix result
            continue
        }
        set channel [::stage1e::safe_load_trace_v1::open_original $normalized rb]
        fconfigure $channel -translation binary -encoding binary
        set bytes [read $channel]
        close $channel
        file stat $normalized stat
        dict set result $relative [list $stat(size) $stat(mtime) \
            [binary encode hex $bytes]]
    }
}

proc ::stage1e::safe_load_trace_v1::_snapshot_tree {root} {
    set result {}
    _snapshot_dir [file normalize $root] [file normalize $root] result
    return $result
}

proc ::stage1e::safe_load_trace_v1::_assert_snapshot_equal {
    before after excluded
} {
    set keys [lsort -unique [concat [dict keys $before] [dict keys $after]]]
    foreach key $keys {
        if {$key in $excluded} { continue }
        if {![dict exists $before $key] || ![dict exists $after $key] ||
            [dict get $before $key] ne [dict get $after $key]} {
            error "Controlled filesystem state changed: $key"
        }
    }
    return 1
}

proc ::stage1e::safe_load_trace_v1::_variable_mutation_trace {
    name1 name2 operation
} {
    set label [expr {$name2 eq {} ? $name1 : "${name1}($name2)"}]
    ::stage1e::safe_load_trace_v1::_record MUTATION BLOCKED NONE \
        "SOURCE_TIME_VARIABLE_MUTATION_PROHIBITED:$label" NONE NONE \
        VARIABLE_MUTATION NONE MUTATION NONE 0 SOURCE_TIME_MUTATION
    error "Source-time environment/auto_path mutation is prohibited: $label"
}

proc ::stage1e::safe_load_trace_v1::_install_process_state_traces {} {
    foreach specification {{::env {write unset}} {::auto_path {write unset}}} {
        lassign $specification variable operations
        if {[catch {trace add variable $variable $operations \
                ::stage1e::safe_load_trace_v1::_variable_mutation_trace}]} {
            # An absent variable is created only for the duration of the
            # disconnected harness; failure to install the guard is itself a
            # conservative blocker.
            _record MUTATION BLOCKED NONE \
                "PROCESS_STATE_TRACE_INSTALL_FAILED:$variable" NONE NONE \
                VARIABLE_MUTATION NONE MUTATION NONE 0 SOURCE_TIME_MUTATION
            error "Unable to install process-state mutation guard: $variable"
        }
    }
}

proc ::stage1e::safe_load_trace_v1::_remove_process_state_traces {} {
    foreach specification {{::env {write unset}} {::auto_path {write unset}}} {
        lassign $specification variable operations
        catch {trace remove variable $variable $operations \
            ::stage1e::safe_load_trace_v1::_variable_mutation_trace}
    }
}

proc ::stage1e::safe_load_trace_v1::_interface_fingerprint {command} {
    if {![llength [info procs $command]]} { return NONE }
    return [list [info args $command] [info body $command]]
}

proc ::stage1e::safe_load_trace_v1::_interface_snapshot {} {
    variable interface_commands
    set snapshot {}
    foreach command $interface_commands {
        dict set snapshot $command [_interface_fingerprint $command]
    }
    return $snapshot
}

proc ::stage1e::safe_load_trace_v1::_register_source_interfaces {
    relative before
} {
    variable interface_commands
    variable provider_owners
    variable provider_fingerprints
    foreach command $interface_commands {
        set prior [dict get $before $command]
        set after [_interface_fingerprint $command]
        if {$after eq {NONE}} { continue }
        if {[dict exists $provider_owners $command]} {
            set owner [dict get $provider_owners $command]
            if {$owner ne $relative &&
                $after ne [dict get $provider_fingerprints $command]} {
                error "Provider interface was overwritten by another source: $command"
            }
            continue
        }
        if {$prior ne {NONE}} {
            error "Provider interface existed without a controlled source owner: $command"
        }
        dict set provider_owners $command $relative
        dict set provider_fingerprints $command $after
    }
}

rename ::source ::stage1e::safe_load_trace_v1::source_original
rename ::open ::stage1e::safe_load_trace_v1::open_original
rename ::exec ::stage1e::safe_load_trace_v1::exec_original
rename ::load ::stage1e::safe_load_trace_v1::load_original
rename ::socket ::stage1e::safe_load_trace_v1::socket_original
rename ::cd ::stage1e::safe_load_trace_v1::cd_original
rename ::file ::stage1e::safe_load_trace_v1::file_original
rename ::chan ::stage1e::safe_load_trace_v1::chan_original
rename ::exit ::stage1e::safe_load_trace_v1::exit_original
rename ::rename ::stage1e::safe_load_trace_v1::rename_original

proc ::source {path args} {
    set relative [::stage1e::safe_load_trace_v1::_relative $path]
    set requester REVIEW_TCL_SAFE_LOAD_HARNESS
    if {[info script] ne {}} {
        if {![catch {
            set requester [::stage1e::safe_load_trace_v1::_node_for_path \
                [::stage1e::safe_load_trace_v1::_relative [info script]]]
        }]} { }
    }
    set target [::stage1e::safe_load_trace_v1::_node_for_path $relative]
    set prior $::stage1e::safe_load_trace_v1::current_requester
    set ::stage1e::safe_load_trace_v1::current_requester $requester
    set interface_before [::stage1e::safe_load_trace_v1::_interface_snapshot]
    set attempt [::stage1e::safe_load_trace_v1::_begin TCL_SOURCE $relative \
        $requester $target TCL_SOURCE TCL_SOURCE NONE NONE CONTROLLED_SOURCE \
        OBSERVED_SAFE_LOAD_TRACE CONTROLLED_SOURCE]
    set status [catch {
        uplevel 1 [list ::stage1e::safe_load_trace_v1::source_original $path \
            {*}$args]
        ::stage1e::safe_load_trace_v1::_register_source_interfaces \
            $relative $interface_before
    } result options]
    if {$status} {
        ::stage1e::safe_load_trace_v1::_complete $attempt FAILED
        set ::stage1e::safe_load_trace_v1::current_requester $prior
        return -options $options $result
    }
    ::stage1e::safe_load_trace_v1::_complete $attempt LOADED
    set ::stage1e::safe_load_trace_v1::current_requester $prior
    return $result
}

proc ::open {path args} {
    set mode [expr {[llength $args] ? [lindex $args 0] : {r}}]
    set relative [::stage1e::safe_load_trace_v1::_relative $path]
    set mode_words [concat $mode]
    set write_mode 0
    foreach token $mode_words {
        if {[string toupper $token] in {W W+ A A+ WRONLY RDWR CREAT TRUNC APPEND}} {
            set write_mode 1
        }
    }
    if {$write_mode} {
        ::stage1e::safe_load_trace_v1::_record MUTATION BLOCKED $relative \
            SOURCE_TIME_FILE_WRITE_PROHIBITED NONE NONE OPEN_MUTATION \
            NONE MUTATION NONE 0 SOURCE_TIME_MUTATION
        error "Safe-load blocked a source-time file mutation: $relative"
    }
    set requester [::stage1e::safe_load_trace_v1::_requester_from_stack \
        REVIEW_TCL_SAFE_LOAD_HARNESS]
    set target [::stage1e::safe_load_trace_v1::_node_for_path $relative]
    set read_edge [expr {[string match {*.dict} $relative] ? {CONFIG_READ} : {SCHEMA_PROVIDER}}]
    set attempt [::stage1e::safe_load_trace_v1::_begin FILE_READ $relative \
        $requester $target $read_edge $read_edge NONE NONE FILE_READ \
        OBSERVED_SAFE_LOAD_TRACE CONTROLLED_FILE_READ]
    set status [catch {
        uplevel 1 [list ::stage1e::safe_load_trace_v1::open_original $path \
            {*}$args]
    } channel options]
    if {$status} {
        ::stage1e::safe_load_trace_v1::_complete $attempt FAILED
        return -options $options $channel
    }
    ::stage1e::safe_load_trace_v1::_complete $attempt LOADED
    return $channel
}

proc ::exec {args} {
    ::stage1e::safe_load_trace_v1::_record MUTATION BLOCKED NONE \
        SOURCE_TIME_EXEC_PROHIBITED
    error {exec is prohibited during disconnected safe-load tracing.}
}
proc ::load {args} {
    ::stage1e::safe_load_trace_v1::_record MUTATION BLOCKED NONE \
        SOURCE_TIME_NATIVE_LOAD_PROHIBITED
    error {native load is prohibited during disconnected safe-load tracing.}
}
proc ::socket {args} {
    ::stage1e::safe_load_trace_v1::_record MUTATION BLOCKED NONE \
        SOURCE_TIME_SOCKET_PROHIBITED
    error {socket is prohibited during disconnected safe-load tracing.}
}
proc ::cd {args} {
    ::stage1e::safe_load_trace_v1::_record MUTATION BLOCKED NONE \
        SOURCE_TIME_CWD_MUTATION_PROHIBITED
    error {cwd mutation is prohibited during disconnected safe-load tracing.}
}

proc ::file {subcommand args} {
    set mutating [expr {$subcommand in {delete rename copy mkdir}}]
    if {$subcommand eq {attributes}} {
        foreach option $args {
            if {$option in {-permissions -owner -group -readonly -archive -hidden -system}} {
                set mutating 1
            }
        }
    }
    if {$mutating} {
        ::stage1e::safe_load_trace_v1::_record MUTATION BLOCKED NONE \
            "SOURCE_TIME_FILE_${subcommand}_PROHIBITED" NONE NONE \
            FILE_MUTATION NONE MUTATION NONE 0 SOURCE_TIME_MUTATION
        error "file $subcommand is prohibited during disconnected safe-load tracing."
    }
    tailcall ::stage1e::safe_load_trace_v1::file_original $subcommand {*}$args
}

proc ::chan {subcommand args} {
    if {$subcommand eq {configure}} {
        ::stage1e::safe_load_trace_v1::_record MUTATION BLOCKED NONE \
            SOURCE_TIME_CHAN_CONFIGURE_PROHIBITED NONE NONE \
            CHAN_CONFIGURE NONE MUTATION NONE 0 SOURCE_TIME_MUTATION
        error {chan configure is prohibited during disconnected safe-load tracing.}
    }
    tailcall ::stage1e::safe_load_trace_v1::chan_original $subcommand {*}$args
}

proc ::rename {args} {
    ::stage1e::safe_load_trace_v1::_record MUTATION BLOCKED NONE \
        SOURCE_TIME_PROVIDER_REDEFINITION_PROHIBITED NONE NONE \
        PROVIDER_REDEFINITION NONE MUTATION NONE 0 SOURCE_TIME_MUTATION
    error {rename is prohibited during disconnected safe-load tracing.}
}

proc ::exit {args} {
    ::stage1e::safe_load_trace_v1::_record MUTATION BLOCKED NONE \
        SOURCE_TIME_EXIT_PROHIBITED NONE NONE PROCESS_TERMINATION NONE MUTATION \
        NONE 0 SOURCE_TIME_TERMINATION
    error {exit is prohibited during disconnected safe-load tracing.}
}

proc ::stage1e::safe_load_trace_v1::_blocked_vivado_command {name args} {
    _record MUTATION BLOCKED NONE "SOURCE_TIME_VIVADO_COMMAND_${name}_PROHIBITED"
    error "Vivado command '$name' is unavailable during safe-load tracing."
}
foreach command {
    version get_property get_runs current_run current_project current_design
    get_filesets get_parts get_board_parts launch_runs wait_on_run open_run
    report_timing_summary report_timing report_clock_interaction report_clocks
    report_exceptions check_timing report_bus_skew report_utilization
    report_drc report_methodology report_cdc report_route_status
    write_bitstream write_hw_platform open_hw_manager connect_hw_server
    program_hw_devices
} {
    proc ::$command args [format {
        tailcall ::stage1e::safe_load_trace_v1::_blocked_vivado_command %s {*}$args
    } [list $command]]
}

proc ::stage1e::safe_load_trace_v1::_provider {
    provider command expected source_path
} {
    variable provider_owners
    variable provider_fingerprints
    set target [_node_for_path $source_path]
    set attempt [_begin PROVIDER $source_path $target $target \
        PROVIDER_OBSERVATION PROVIDER_OBSERVATION $provider $expected \
        INTERFACE_VERSION_CONFIRMED OBSERVED_SAFE_LOAD_TRACE \
        PROVIDER_INTERFACE $command]
    if {![llength [info commands $command]]} {
        _complete $attempt FAILED
        error "Safe-load provider command is missing: $provider"
    }
    if {![dict exists $provider_owners $command] ||
        [dict get $provider_owners $command] ne $source_path ||
        ![dict exists $provider_fingerprints $command] ||
        [dict get $provider_fingerprints $command] ne
            [_interface_fingerprint $command]} {
        _complete $attempt FAILED
        error "Safe-load provider command source was substituted: $provider"
    }
    set status [catch {uplevel #0 [list $command]} observed options]
    if {$status} {
        _complete $attempt FAILED
        return -options $options $observed
    }
    if {$observed ne $expected} {
        _complete $attempt FAILED
        error "Safe-load provider interface differs: $provider"
    }
    _complete $attempt LOADED
}

proc ::stage1e::safe_load_trace_v1::_source_relative {relative} {
    variable repository_root
    set path [file join $repository_root {*}[split $relative /]]
    source $path
}

proc ::stage1e::safe_load_trace_v1::_run_vivado {} {
    variable repository_root
    _source_relative \
        fpga/vivado/build/runtime/runner/stage1e_production_vivado_session_v1.tcl
    set prior_requester $::stage1e::safe_load_trace_v1::current_requester
    set ::stage1e::safe_load_trace_v1::current_requester VIVADO_RUNTIME_CONTRACT
    ::stage1e::vivado_runtime_contract_v1::configure_from_build_root \
        [file join $repository_root fpga vivado build]
    set ::stage1e::safe_load_trace_v1::current_requester $prior_requester
    _source_relative \
        fpga/vivado/build/runtime/collector/stage1e_production_vivado_collector_v1.tcl
    _attempt TCL_SOURCE \
        fpga/vivado/build/lib/stage1e_vivado_runtime_contract_v1.tcl \
        VIVADO_RUNTIME_CONTRACT VIVADO_RUNTIME_CONTRACT TCL_SOURCE TCL_SOURCE \
        VIVADO_RUNTIME_CONTRACT stage1e-vivado-runtime-common-interface-v1 \
        OPTIONAL_NOT_LOADED PROVIDER_ALREADY_LOADED_GUARDED_SOURCE \
        OBSERVED_SAFE_LOAD_TRACE PROVIDER_ALREADY_LOADED_GUARDED_SOURCE
    foreach specification {
        {VIVADO_SESSION_ASSEMBLY ::stage1e::production_vivado_session_v1::interface_version stage1e-production-vivado-session-interface-v1 fpga/vivado/build/runtime/runner/stage1e_production_vivado_session_v1.tcl}
        {RUNNER_INTERFACE ::stage1e::production_vivado_runner_v1::interface_version stage1e-production-vivado-runner-interface-v1 fpga/vivado/build/runtime/runner/stage1e_production_vivado_runner_v1.tcl}
        {COLLECTOR_INTERFACE ::stage1e::production_vivado_collector_v1::interface_version stage1e-production-vivado-collector-interface-v1 fpga/vivado/build/runtime/collector/stage1e_production_vivado_collector_v1.tcl}
        {IDENTITY_SERIALIZER_INTERFACE ::stage1e::production_evidence_serializer_v1::interface_version stage1e-production-evidence-serializer-interface-v1 fpga/vivado/build/runtime/identity/stage1e_production_evidence_serializer_v1.tcl}
        {VIVADO_CAPABILITY_OBSERVER_INTERFACE ::stage1e::production_vivado_observer_v1::interface_version stage1e-production-vivado-observer-interface-v1 fpga/vivado/build/runtime/observer/vivado/stage1e_production_vivado_observer_v1.tcl}
        {VIVADO_CONTROLLER_INTERFACE ::stage1e::production_vivado_controller_v1::interface_version stage1e-production-vivado-controller-interface-v1 fpga/vivado/build/controller/stage1e_production_vivado_controller_v1.tcl}
        {VIVADO_ADAPTER_INTERFACE ::stage1e::production_vivado_adapter_v1::interface_version stage1e-production-vivado-adapter-interface-v1 fpga/vivado/build/adapters/stage1e_production_vivado_adapter_v1.tcl}
        {VIVADO_RUNTIME_CONTRACT ::stage1e::vivado_runtime_contract_v1::interface_version stage1e-vivado-runtime-common-interface-v1 fpga/vivado/build/lib/stage1e_vivado_runtime_contract_v1.tcl}
        {EVIDENCE_PIPELINE_CONTRACT ::stage1e::evidence_pipeline_contract_v1::interface_version stage1e-evidence-pipeline-common-interface-v1 fpga/vivado/build/lib/stage1e_evidence_pipeline_contract_v1.tcl}
        {CANONICALIZATION_TCL ::stage1e::canonical_json_v1::interface_version stage1e-runtime-canonical-json-interface-v1 fpga/vivado/build/lib/stage1e_runtime_canonical_json_v1.tcl}
        {HASH_PROVIDER_TCL ::stage1e::canonical_json_v1::hash_provider_interface_version stage1e-runtime-sha256-provider-interface-v1 fpga/vivado/build/lib/stage1e_runtime_canonical_json_v1.tcl}
        {ATOMIC_PUBLICATION_TCL ::stage1e::atomic_publication_v1::interface_version stage1e-runtime-atomic-publication-interface-v1 fpga/vivado/build/lib/stage1e_runtime_atomic_publication_v1.tcl}
    } {
        lassign $specification provider command expected path
        _provider $provider $command $expected $path
    }
}

proc ::stage1e::safe_load_trace_v1::_run_postprocess {} {
    variable repository_root
    _source_relative \
        fpga/vivado/build/runtime/parser/stage1e_production_evidence_parser_v1.tcl
    _source_relative \
        fpga/vivado/build/controller/stage1e_production_evidence_controller_v1.tcl
    _source_relative \
        fpga/vivado/build/adapters/stage1e_production_evidence_adapter_v1.tcl
    _attempt TCL_SOURCE \
        fpga/vivado/build/lib/stage1e_evidence_pipeline_contract_v1.tcl \
        EVIDENCE_PIPELINE_CONTRACT EVIDENCE_PIPELINE_CONTRACT TCL_SOURCE TCL_SOURCE \
        EVIDENCE_PIPELINE_CONTRACT stage1e-evidence-pipeline-common-interface-v1 \
        OPTIONAL_NOT_LOADED PROVIDER_ALREADY_LOADED_GUARDED_SOURCE \
        OBSERVED_SAFE_LOAD_TRACE PROVIDER_ALREADY_LOADED_GUARDED_SOURCE
    set prior_requester $::stage1e::safe_load_trace_v1::current_requester
    set ::stage1e::safe_load_trace_v1::current_requester EVIDENCE_PIPELINE_CONTRACT
    ::stage1e::vivado_runtime_contract_v1::configure_from_build_root \
        [file join $repository_root fpga vivado build]
    set ::stage1e::safe_load_trace_v1::current_requester $prior_requester
    foreach specification {
        {PARSER_INTERFACE ::stage1e::production_evidence_parser_v1::interface_version stage1e-production-evidence-parser-interface-v1 fpga/vivado/build/runtime/parser/stage1e_production_evidence_parser_v1.tcl}
        {IDENTITY_SERIALIZER_INTERFACE ::stage1e::production_evidence_serializer_v1::interface_version stage1e-production-evidence-serializer-interface-v1 fpga/vivado/build/runtime/identity/stage1e_production_evidence_serializer_v1.tcl}
        {EVIDENCE_CONTROLLER_INTERFACE ::stage1e::production_evidence_controller_v1::interface_version stage1e-production-evidence-controller-interface-v1 fpga/vivado/build/controller/stage1e_production_evidence_controller_v1.tcl}
        {EVIDENCE_ADAPTER_INTERFACE ::stage1e::production_evidence_adapter_v1::interface_version stage1e-production-evidence-adapter-interface-v1 fpga/vivado/build/adapters/stage1e_production_evidence_adapter_v1.tcl}
        {EVIDENCE_PIPELINE_CONTRACT ::stage1e::evidence_pipeline_contract_v1::interface_version stage1e-evidence-pipeline-common-interface-v1 fpga/vivado/build/lib/stage1e_evidence_pipeline_contract_v1.tcl}
        {VIVADO_RUNTIME_CONTRACT ::stage1e::vivado_runtime_contract_v1::interface_version stage1e-vivado-runtime-common-interface-v1 fpga/vivado/build/lib/stage1e_vivado_runtime_contract_v1.tcl}
        {CANONICALIZATION_TCL ::stage1e::canonical_json_v1::interface_version stage1e-runtime-canonical-json-interface-v1 fpga/vivado/build/lib/stage1e_runtime_canonical_json_v1.tcl}
        {HASH_PROVIDER_TCL ::stage1e::canonical_json_v1::hash_provider_interface_version stage1e-runtime-sha256-provider-interface-v1 fpga/vivado/build/lib/stage1e_runtime_canonical_json_v1.tcl}
        {ATOMIC_PUBLICATION_TCL ::stage1e::atomic_publication_v1::interface_version stage1e-runtime-atomic-publication-interface-v1 fpga/vivado/build/lib/stage1e_runtime_atomic_publication_v1.tcl}
    } {
        lassign $specification provider command expected path
        _provider $provider $command $expected $path
    }
}

proc ::stage1e::safe_load_trace_v1::_write {} {
    variable records
    variable rehearsal_records
    variable output_path
    proc ::stage1e::safe_load_trace_v1::_write_one {path rows} {
        set channel [::stage1e::safe_load_trace_v1::open_original $path \
            {WRONLY CREAT EXCL}]
        fconfigure $channel -encoding utf-8 -translation lf
        try {
            foreach record $rows {
                set fields {}
                foreach key [lsort -dictionary [dict keys $record]] {
                    set value [string map [list "\t" {\\t} "\n" {\\n} \
                        "\r" {\\r} {|} {\\p}] [dict get $record $key]]
                    lappend fields "${key}=${value}"
                }
                puts $channel [join $fields |]
            }
        } finally {
            close $channel
        }
    }
    _write_one $output_path $records
    _write_one "${output_path}.rehearsal" $rehearsal_records
}

proc ::stage1e::safe_load_trace_v1::_critical_command_fingerprint {} {
    set result {}
    foreach command {source open file chan exec load socket cd rename exit} {
        if {[llength [info commands ::$command]]} {
            dict set result $command [info commands ::$command]
            if {[catch {info body ::$command} body] == 0} {
                dict set result "body:$command" $body
            }
        }
    }
    return $result
}

proc ::stage1e::safe_load_trace_v1::_main {arguments} {
    variable repository_root
    variable output_path
    variable scenario
    variable domain
    variable initial_cwd
    variable initial_auto_path
    variable initial_environment
    variable initial_files
    variable initial_commands
    if {[llength $arguments] != 6} {
        puts stderr {usage: trace --repository-root ROOT --output PATH --scenario VIVADO|POSTPROCESS}
        return 2
    }
    set values {}
    foreach {key value} $arguments { dict set values $key $value }
    foreach key {--repository-root --output --scenario} {
        if {![dict exists $values $key]} { puts stderr "missing $key"; return 2 }
    }
    set repository_root [file normalize [dict get $values --repository-root]]
    # Git-for-Windows Tcl may resolve the per-user AppData junction
    # inconsistently. Preserve the caller-supplied external path literally.
    set output_path [string map {\\ /} [dict get $values --output]]
    if {[string first "[string map {\\ /} $repository_root]/" \
        "[string map {\\ /} $output_path]/"] == 0} {
        puts stderr {Trace output must be external to the repository.}
        return 2
    }
    set selected [dict get $values --scenario]
    if {![file exists [file dirname $output_path]]} {
        ::stage1e::safe_load_trace_v1::file_original mkdir \
            [file dirname $output_path]
    }
    if {[file exists $output_path] || [file exists "${output_path}.rehearsal"]} {
        puts stderr {Trace output already exists.}
        return 2
    }
    set initial_cwd [pwd]
    set initial_auto_path $::auto_path
    set initial_environment [lsort [array get ::env]]
    set initial_files [list [_snapshot_tree $repository_root] \
        [_snapshot_tree [file dirname $output_path]]]
    set initial_commands [_critical_command_fingerprint]
    _install_process_state_traces
    if {$selected eq {VIVADO}} {
        set scenario VIVADO_DISCONNECTED_SAFE_LOAD
        set domain VIVADO_TCL
        set status [catch {_run_vivado} message options]
    } elseif {$selected eq {POSTPROCESS}} {
        set scenario POSTPROCESS_DISCONNECTED_SAFE_LOAD
        set domain HOST_POSTPROCESS_TCL
        set status [catch {_run_postprocess} message options]
    } else {
        puts stderr {Unknown trace scenario.}
        return 2
    }
    _remove_process_state_traces
    if {$status} {
        _record TRACE BLOCKED NONE $message NONE NONE TRACE NONE MUTATION NONE 0 \
            TRACE_FAILURE
    }
    if {[pwd] ne $initial_cwd || $::auto_path ne $initial_auto_path ||
        [lsort [array get ::env]] ne $initial_environment} {
        _record MUTATION BLOCKED NONE SOURCE_TIME_PROCESS_STATE_MUTATION NONE NONE \
            PROCESS_STATE_MUTATION NONE MUTATION NONE 0 SOURCE_TIME_MUTATION
        set status 1
        set message {Candidate changed cwd, auto_path, or environment.}
    }
    set final_files [list [_snapshot_tree $repository_root] \
        [_snapshot_tree [file dirname $output_path]]]
    if {[catch {
        _assert_snapshot_equal [lindex $initial_files 0] [lindex $final_files 0] {}
        _assert_snapshot_equal [lindex $initial_files 1] [lindex $final_files 1] \
            [list [file tail $output_path] "[file tail $output_path].rehearsal"]
        if {[_critical_command_fingerprint] ne $initial_commands} {
            error {Critical Tcl command/provider definitions changed.}
        }
    } snapshot_message]} {
        _record MUTATION BLOCKED NONE $snapshot_message NONE NONE \
            PROCESS_STATE_MUTATION NONE MUTATION NONE 0 SOURCE_TIME_MUTATION
        set status 1
        set message $snapshot_message
    }
    if {[catch {_write} write_message]} {
        puts stderr $write_message
        return 1
    }
    if {$status} { puts stderr $message; return 1 }
    puts "TCL_TRACE_RECORDS=[llength $::stage1e::safe_load_trace_v1::records] TCL_REHEARSAL_RECORDS=[llength $::stage1e::safe_load_trace_v1::rehearsal_records]"
    return 0
}

if {[file normalize [info script]] eq [file normalize $::argv0]} {
    ::stage1e::safe_load_trace_v1::exit_original \
        [::stage1e::safe_load_trace_v1::_main $::argv]
}
