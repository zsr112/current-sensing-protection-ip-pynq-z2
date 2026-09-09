source [file join [file dirname [info script]] \
    stage1e_runtime_test_support.tcl]

namespace eval ::stage1e::runtime_static_test {}

proc ::stage1e::runtime_static_test::read_text {path} {
    set channel [open $path r]
    fconfigure $channel -encoding utf-8 -translation auto
    set text [read $channel]
    close $channel
    return $text
}

proc ::stage1e::runtime_static_test::count_literal {text needle} {
    if {$needle eq {}} { error {Cannot count an empty literal.} }
    set count 0
    set start 0
    while {1} {
        set index [string first $needle $text $start]
        if {$index < 0} { return $count }
        incr count
        set start [expr {$index + [string length $needle]}]
    }
}

set root [::stage1e::runtime_test::repository_root]
set required_paths {
    fpga/vivado/build/runtime/README.md
    fpga/vivado/build/runtime/launcher/stage1e_runtime_launcher.psm1
    fpga/vivado/build/runtime/runner/stage1e_runtime_runner.tcl
    fpga/vivado/build/runtime/collector/stage1e_runtime_collector.tcl
    fpga/vivado/build/runtime/parser/stage1e_runtime_parser.tcl
    fpga/vivado/build/runtime/identity/stage1e_runtime_identity.tcl
    fpga/vivado/build/runtime/observer/stage1e_runtime_observer.tcl
    fpga/vivado/build/lib/stage1e_runtime_schema.tcl
    fpga/vivado/build/controller/stage1e_phase3_implementation_controller_v2.tcl
    fpga/vivado/build/adapters/stage1e_implementation_v2.tcl
    fpga/vivado/build/config/stage1e_phase3_implementation_framework_v2.dict
    fpga/vivado/build/config/stage1e_implementation_configuration_v2.dict
    fpga/vivado/build/config/stage1e_implementation_warning_policy_v2.dict
    docs/design/stage1e_implementation_policy_v2.md
}
set prt02_schema_paths {
    fpga/vivado/build/lib/stage1e_runtime_request_envelope_v1.schema.json
    fpga/vivado/build/lib/stage1e_runtime_result_envelope_v1.schema.json
    fpga/vivado/build/lib/stage1e_runtime_failure_record_v1.schema.json
    fpga/vivado/build/lib/stage1e_runtime_vivado_authorization_consumption_receipt_v1.schema.json
    fpga/vivado/build/lib/stage1e_runtime_host_common_v1.schema.json
    fpga/vivado/build/lib/stage1e_runtime_host_component_result_v1.schema.json
    fpga/vivado/build/lib/stage1e_runtime_host_heartbeat_event_v1.schema.json
    fpga/vivado/build/lib/stage1e_runtime_host_launcher_request_v1.schema.json
    fpga/vivado/build/lib/stage1e_runtime_host_preflight_observation_v1.schema.json
    fpga/vivado/build/lib/stage1e_runtime_host_process_instance_v1.schema.json
    fpga/vivado/build/lib/stage1e_runtime_host_process_ledger_v1.schema.json
    fpga/vivado/build/lib/stage1e_runtime_host_requirements_v1.schema.json
    fpga/vivado/build/lib/stage1e_runtime_host_timeout_termination_ledger_v1.schema.json
}
set prt02_source_paths {
    fpga/vivado/build/lib/stage1e_runtime_canonical_json_v1.psm1
    fpga/vivado/build/lib/stage1e_runtime_canonical_json_v1.tcl
    fpga/vivado/build/lib/stage1e_runtime_envelope_contract_v1.psm1
    fpga/vivado/build/lib/stage1e_runtime_envelope_contract_v1.tcl
    fpga/vivado/build/lib/stage1e_runtime_atomic_publication_v1.psm1
    fpga/vivado/build/lib/stage1e_runtime_atomic_publication_v1.tcl
    fpga/vivado/build/runtime/entrypoint/stage1e_production_runtime_entrypoint_v1.ps1
}
set prt02_host_source_paths {
    fpga/vivado/build/lib/stage1e_host_boundary_contract_v1.psm1
    fpga/vivado/build/lib/stage1e_windows_process_control_v1.cs
    fpga/vivado/build/lib/stage1e_windows_process_control_v1.psm1
    fpga/vivado/build/runtime/launcher/stage1e_production_runtime_launcher_v1.psm1
    fpga/vivado/build/runtime/observer/host/stage1e_production_host_observer_v1.psm1
}
set prt02_host_test_paths {
    fpga/vivado/build/tests/fixtures/stage1e_host_mock_child_v1.cs
    fpga/vivado/build/tests/stage1e_prt02_host_test_support.psm1
    fpga/vivado/build/tests/stage1e_prt02_host_schema_tests.ps1
    fpga/vivado/build/tests/stage1e_prt02_host_process_control_tests.ps1
    fpga/vivado/build/tests/stage1e_prt02_host_observer_tests.ps1
    fpga/vivado/build/tests/stage1e_prt02_host_launcher_tests.ps1
    fpga/vivado/build/tests/stage1e_prt02_host_static_tests.ps1
}
set prt02_vivado_config_paths {
    fpga/vivado/build/config/stage1e_vivado_runtime_record_contract_v1.dict
    fpga/vivado/build/config/stage1e_vivado_runtime_command_contract_v1.dict
    fpga/vivado/build/config/stage1e_vivado_runtime_property_map_v1.dict
}
set prt02_vivado_source_paths {
    fpga/vivado/build/lib/stage1e_vivado_runtime_contract_v1.tcl
    fpga/vivado/build/controller/stage1e_production_vivado_controller_v1.tcl
    fpga/vivado/build/adapters/stage1e_production_vivado_adapter_v1.tcl
    fpga/vivado/build/runtime/observer/vivado/stage1e_production_vivado_observer_v1.tcl
    fpga/vivado/build/runtime/runner/stage1e_production_vivado_runner_v1.tcl
    fpga/vivado/build/runtime/runner/stage1e_production_vivado_session_v1.tcl
}
set prt02_vivado_test_paths {
    fpga/vivado/build/tests/fixtures/stage1e_vivado_command_model_v1.tcl
    fpga/vivado/build/tests/stage1e_prt02_vivado_test_support_v1.tcl
    fpga/vivado/build/tests/stage1e_prt02_vivado_contract_tests.tcl
    fpga/vivado/build/tests/stage1e_prt02_vivado_controller_tests.tcl
    fpga/vivado/build/tests/stage1e_prt02_vivado_observer_tests.tcl
    fpga/vivado/build/tests/stage1e_prt02_vivado_runner_tests.tcl
    fpga/vivado/build/tests/stage1e_prt02_vivado_integration_tests.tcl
    fpga/vivado/build/tests/stage1e_prt02_vivado_static_tests.tcl
}
set prt02_evidence_config_paths {
    fpga/vivado/build/config/stage1e_report_contract_v1.dict
    fpga/vivado/build/config/stage1e_message_contract_v1.dict
    fpga/vivado/build/config/stage1e_parser_format_profiles_v1.dict
    fpga/vivado/build/config/stage1e_evidence_record_contract_v1.dict
}
set prt02_evidence_source_paths {
    fpga/vivado/build/lib/stage1e_evidence_pipeline_contract_v1.tcl
    fpga/vivado/build/runtime/collector/stage1e_production_vivado_collector_v1.tcl
    fpga/vivado/build/runtime/parser/stage1e_production_evidence_parser_v1.tcl
    fpga/vivado/build/runtime/identity/stage1e_production_evidence_serializer_v1.tcl
    fpga/vivado/build/controller/stage1e_production_evidence_controller_v1.tcl
    fpga/vivado/build/adapters/stage1e_production_evidence_adapter_v1.tcl
}
set prt02_evidence_test_paths {
    fpga/vivado/build/tests/fixtures/stage1e_evidence_collector_command_model_v1.tcl
    fpga/vivado/build/tests/stage1e_prt02_evidence_test_support_v1.tcl
    fpga/vivado/build/tests/stage1e_prt02_evidence_contract_tests.tcl
    fpga/vivado/build/tests/stage1e_prt02_evidence_collector_tests.tcl
    fpga/vivado/build/tests/stage1e_prt02_evidence_parser_tests.tcl
    fpga/vivado/build/tests/stage1e_prt02_evidence_serializer_tests.tcl
    fpga/vivado/build/tests/stage1e_prt02_evidence_integration_tests.tcl
    fpga/vivado/build/tests/stage1e_prt02_evidence_static_tests.tcl
}
set prt02_dependency_config_paths {
    fpga/vivado/build/config/stage1e_runtime_dependency_contract_v1.dict
    fpga/vivado/build/config/stage1e_runtime_provider_contract_v1.dict
    fpga/vivado/build/config/stage1e_runtime_external_capability_contract_v1.dict
    fpga/vivado/build/config/stage1e_runtime_declared_graph_v1.dict
}
set prt02_dependency_source_paths {
    fpga/vivado/build/dependency/stage1e_runtime_dependency_closure_v1.psm1
    fpga/vivado/build/dependency/stage1e_tcl_dependency_discovery_v1.tcl
    fpga/vivado/build/dependency/stage1e_host_safe_load_trace_v1.ps1
    fpga/vivado/build/dependency/stage1e_tcl_safe_load_trace_v1.tcl
    fpga/vivado/build/dependency/stage1e_hash_bootstrap_v1.tcl
    fpga/vivado/build/runtime/assembly/stage1e_runtime_assembly_ledger_v1.psm1
    fpga/vivado/build/runtime/assembly/stage1e_runtime_assembly_ledger_v1.tcl
}
set prt02_dependency_test_paths {
    fpga/vivado/build/tests/stage1e_prt02_dependency_closure_tests.ps1
    fpga/vivado/build/tests/stage1e_prt02_dependency_closure_tests.tcl
}
set required_paths [concat $required_paths $prt02_schema_paths \
    $prt02_source_paths $prt02_host_source_paths $prt02_host_test_paths \
    $prt02_vivado_config_paths $prt02_vivado_source_paths \
    $prt02_vivado_test_paths $prt02_evidence_config_paths \
    $prt02_evidence_source_paths $prt02_evidence_test_paths \
    $prt02_dependency_config_paths $prt02_dependency_source_paths \
    $prt02_dependency_test_paths]

::stage1e::runtime_test::run_case expected_runtime_structure {
    foreach relative_path $required_paths {
        set absolute [file join $root {*}[split $relative_path /]]
        ::stage1e::runtime_test::assert_true \
            {[file exists $absolute] && [file isfile $absolute]} \
            "Missing required foundation file: $relative_path"
    }
}

::stage1e::runtime_test::run_case prt02_unique_exact_entry_point {
    set entry_directory [file join $root fpga vivado build runtime entrypoint]
    set entries [glob -nocomplain -types f -directory $entry_directory *]
    ::stage1e::runtime_test::assert_equal 1 [llength $entries] \
        {Production entry-point directory does not contain exactly one file}
    ::stage1e::runtime_test::assert_equal \
        stage1e_production_runtime_entrypoint_v1.ps1 \
        [file tail [lindex $entries 0]] \
        {Unexpected production entry-point filename}

    set text [::stage1e::runtime_static_test::read_text [lindex $entries 0]]
    set preamble_end [string first {$ErrorActionPreference} $text]
    ::stage1e::runtime_test::assert_true {$preamble_end > 0} \
        {Entry-point parameter preamble is missing}
    set preamble [string range $text 0 [expr {$preamble_end - 1}]]
    ::stage1e::runtime_test::assert_equal 2 \
        [regexp -all {\[string\]\$[A-Za-z][A-Za-z0-9]*} $preamble] \
        {Entry point does not expose exactly two typed public parameters}
    foreach parameter {RequestPath ExpectedRequestIdentity} {
        ::stage1e::runtime_test::assert_equal 1 \
            [::stage1e::runtime_static_test::count_literal $preamble \
                "\[string\]\$$parameter"] \
            "Entry-point parameter is missing or duplicated: $parameter"
    }
    ::stage1e::runtime_test::assert_true \
        {[string first {PositionalBinding = $false} $preamble] >= 0} \
        {Entry point permits positional binding}
    foreach forbidden {Alias ValueFromPipeline ValueFromRemainingArguments} {
        ::stage1e::runtime_test::assert_true \
            {[string first $forbidden $preamble] < 0} \
            "Entry point exposes a forbidden parameter feature: $forbidden"
    }
    ::stage1e::runtime_test::assert_true \
        {![regexp {(^|[^A-Za-z])Position[ \t]*=} $preamble]} \
        {Entry point exposes a positional parameter attribute}
}

::stage1e::runtime_test::run_case prt02_b_connection_boundary_is_disconnected {
    set entry_path [file join $root fpga vivado build runtime entrypoint \
        stage1e_production_runtime_entrypoint_v1.ps1]
    set entry_text [::stage1e::runtime_static_test::read_text $entry_path]
    foreach prohibited {
        stage1e_production_runtime_launcher_v1.psm1
        stage1e_production_host_observer_v1.psm1
        stage1e_windows_process_control_v1.psm1
    } {
        ::stage1e::runtime_test::assert_true \
            {[string first $prohibited $entry_text] < 0} \
            "PRT02-B production candidate is connected at the entry point: $prohibited"
    }
    foreach literal {
        {PRODUCTION_CONTROLLER_NOT_IMPLEMENTED}
        {dependency_closure_state = 'PARTIAL_FOUNDATION'}
        {process_effect = 'NOT_STARTED'}
    } {
        ::stage1e::runtime_test::assert_true \
            {[string first $literal $entry_text] >= 0} \
            "PRT02-A stop boundary changed: $literal"
    }
}

::stage1e::runtime_test::run_case prt02_e_dependency_boundary_is_disconnected {
    set graph_path [file join $root fpga vivado build config \
        stage1e_runtime_declared_graph_v1.dict]
    set graph_text [::stage1e::runtime_static_test::read_text $graph_path]
    dict size $graph_text
    ::stage1e::runtime_test::assert_equal \
        PUBLIC_RUNTIME_ASSEMBLY_NOT_CONNECTED \
        [dict get $graph_text assembly_state] \
        {PRT02-E declaration connects the public runtime assembly}
    foreach state_field {source_identity_state runtime_backend_identity_state} {
        ::stage1e::runtime_test::assert_equal NOT_CREATED \
            [dict get $graph_text $state_field] \
            "PRT02-E declaration created an identity: $state_field"
    }
    ::stage1e::runtime_test::assert_equal PROHIBITED \
        [dict get $graph_text digest_population] \
        {PRT02-E declaration permits populated source digests}

    set legacy_found 0
    foreach node [dict get $graph_text nodes] {
        if {[dict get $node node_id] eq {LEGACY_SOURCE_CHECK}} {
            set legacy_found 1
            ::stage1e::runtime_test::assert_equal NON_RUNTIME_SOURCE \
                [dict get $node node_class] \
                {source_check.tcl is not classified as non-runtime}
            ::stage1e::runtime_test::assert_equal \
                HISTORICAL_NON_PRODUCTION [dict get $node termination] \
                {source_check.tcl has an admitted runtime termination}
        }
    }
    ::stage1e::runtime_test::assert_true {$legacy_found} \
        {source_check.tcl disposition is absent}
    foreach edge [dict get $graph_text edges] {
        ::stage1e::runtime_test::assert_true {
            [dict get $edge from] ne {LEGACY_SOURCE_CHECK} &&
            [dict get $edge to] ne {LEGACY_SOURCE_CHECK}} \
            {source_check.tcl is reachable from the candidate graph}
    }

    set entry_text [::stage1e::runtime_static_test::read_text [file join \
        $root fpga vivado build runtime entrypoint \
        stage1e_production_runtime_entrypoint_v1.ps1]]
    ::stage1e::runtime_test::assert_true {
        [string first {stage1e_runtime_assembly_ledger_v1} $entry_text] < 0} \
        {PRT02-E pre-dispatch ledger is connected to the public entry point}
    set collector_text [::stage1e::runtime_static_test::read_text [file join \
        $root fpga vivado build runtime collector \
        stage1e_production_vivado_collector_v1.tcl]]
    ::stage1e::runtime_test::assert_true {
        [string first {ACTUAL_VIVADO_REPORT_COMMANDS_NOT_QUALIFIED} \
            $collector_text] >= 0} \
        {PRT02-D production report qualification block is absent}

    foreach relative_path $prt02_dependency_source_paths {
        set dependency_text [string tolower \
            [::stage1e::runtime_static_test::read_text \
                [file join $root {*}[split $relative_path /]]]]
        foreach forbidden {
            vivado.exe xilinx_vivado {where vivado} {where.exe vivado}
        } {
            ::stage1e::runtime_test::assert_true {
                [string first $forbidden $dependency_text] < 0} \
                "PRT02-E dependency tooling locates Vivado: $relative_path"
        }
    }
}

::stage1e::runtime_test::run_case prt02_b_versioned_candidate_surface {
    set launcher_directory [file join $root fpga vivado build runtime launcher]
    set launchers [lsort [glob -nocomplain -types f -directory \
        $launcher_directory *]]
    set expected_launchers [lsort [list \
        [file join $launcher_directory stage1e_runtime_launcher.psm1] \
        [file join $launcher_directory \
            stage1e_production_runtime_launcher_v1.psm1]]]
    ::stage1e::runtime_test::assert_equal $expected_launchers $launchers \
        {Launcher directory differs from the mock plus versioned candidate set}

    set host_observer_directory [file join $root fpga vivado build runtime \
        observer host]
    set host_observers [glob -nocomplain -types f -directory \
        $host_observer_directory *]
    ::stage1e::runtime_test::assert_equal 1 [llength $host_observers] \
        {Host-observer directory does not contain exactly one candidate}
    ::stage1e::runtime_test::assert_equal \
        stage1e_production_host_observer_v1.psm1 \
        [file tail [lindex $host_observers 0]] \
        {Unexpected production host-observer filename}
}

::stage1e::runtime_test::run_case prt02_b_source_review_amendments_are_explicit {
    set provider [::stage1e::runtime_static_test::read_text [file join $root \
        fpga vivado build lib stage1e_windows_process_control_v1.cs]]
    foreach required {
        STARTUPINFOEX InitializeProcThreadAttributeList
        UpdateProcThreadAttribute DeleteProcThreadAttributeList
        PROC_THREAD_ATTRIBUTE_HANDLE_LIST EXTENDED_STARTUPINFO_PRESENT
        CreateIoCompletionPort GetQueuedCompletionStatus
        JobObjectAssociateCompletionPortInformation
        JOB_OBJECT_MSG_NEW_PROCESS JOB_OBJECT_MSG_EXIT_PROCESS
        JOB_OBJECT_MSG_ABNORMAL_EXIT_PROCESS
        JOB_OBJECT_MSG_ACTIVE_PROCESS_LIMIT
        JOB_OBJECT_MSG_ACTIVE_PROCESS_ZERO ObservationHandleAvailable
    } {
        ::stage1e::runtime_test::assert_true \
            {[string first $required $provider] >= 0} \
            "PRT02-B source-review primitive is missing: $required"
    }
    set adapter [::stage1e::runtime_static_test::read_text [file join $root \
        fpga vivado build lib stage1e_windows_process_control_v1.psm1]]
    ::stage1e::runtime_test::assert_true \
        {[string first \
            {$maximumProcesses += [int64]$topologyRequirement.maximum_count} \
            $adapter] >= 0 && [string first {        32)} $adapter] < 0} \
        {Execution-specific process limit is not the exact topology sum}
    set launcher [::stage1e::runtime_static_test::read_text [file join $root \
        fpga vivado build runtime launcher \
        stage1e_production_runtime_launcher_v1.psm1]]
    foreach required {
        PROCESS_STARTUP_TIMEOUT_PRE_RESUME
        TOTAL_LIFETIME_TIMEOUT_PRE_RESUME
        HEARTBEAT_TRAILING_PARTIAL
    } {
        ::stage1e::runtime_test::assert_true \
            {[string first $required $launcher] >= 0} \
            "PRT02-B launcher amendment is missing: $required"
    }
}

::stage1e::runtime_test::run_case prt02_controlled_load_graph {
    set entry_path [file join $root fpga vivado build runtime entrypoint \
        stage1e_production_runtime_entrypoint_v1.ps1]
    set entry_text [::stage1e::runtime_static_test::read_text $entry_path]
    foreach module {
        stage1e_runtime_canonical_json_v1.psm1
        stage1e_runtime_envelope_contract_v1.psm1
        stage1e_runtime_atomic_publication_v1.psm1
    } {
        ::stage1e::runtime_test::assert_equal 1 \
            [::stage1e::runtime_static_test::count_literal $entry_text $module] \
            "Entry-point controlled module is missing or duplicated: $module"
    }
    ::stage1e::runtime_test::assert_equal 1 \
        [regexp -all -line {^[ \t]*Import-Module[ \t]} $entry_text] \
        {Entry point contains an alternate module import}
    ::stage1e::runtime_test::assert_true \
        {[string first {Import-Module -Name $modulePath -Force -ErrorAction Stop} \
            $entry_text] >= 0} \
        {Entry point does not import through its controlled literal path}

    foreach relative_path {
        fpga/vivado/build/lib/stage1e_runtime_envelope_contract_v1.psm1
        fpga/vivado/build/lib/stage1e_runtime_atomic_publication_v1.psm1
    } {
        set text [::stage1e::runtime_static_test::read_text \
            [file join $root {*}[split $relative_path /]]]
        ::stage1e::runtime_test::assert_equal 1 \
            [regexp -all -line {^[ \t]*Import-Module[ \t]} $text] \
            "Unexpected PowerShell import count in $relative_path"
        ::stage1e::runtime_test::assert_true \
            {[string first \
                {Import-Module -Name $canonicalModule -Force -ErrorAction Stop} \
                $text] >= 0} \
            "PowerShell module import is not script-root controlled: $relative_path"
    }
    foreach relative_path {
        fpga/vivado/build/lib/stage1e_runtime_envelope_contract_v1.tcl
        fpga/vivado/build/lib/stage1e_runtime_atomic_publication_v1.tcl
    } {
        set text [::stage1e::runtime_static_test::read_text \
            [file join $root {*}[split $relative_path /]]]
        ::stage1e::runtime_test::assert_equal 1 \
            [regexp -all -line {^[ \t]*source[ \t]} $text] \
            "Unexpected Tcl source count in $relative_path"
        ::stage1e::runtime_test::assert_true \
            {[string first {[file dirname [info script]]} $text] >= 0 &&
             [string first {stage1e_runtime_canonical_json_v1.tcl} $text] >= 0} \
            "Tcl module source is not script-root controlled: $relative_path"
    }
}

::stage1e::runtime_test::run_case prt02_source_review_states_are_explicit {
    set entry_path [file join $root fpga vivado build runtime entrypoint \
        stage1e_production_runtime_entrypoint_v1.ps1]
    set entry_text [::stage1e::runtime_static_test::read_text $entry_path]
    foreach {literal expected} {
        {status = 'NOT_EVALUATED'} 1
        {dependency_closure_state = 'PARTIAL_FOUNDATION'} 1
        {UNIQUE_ASSEMBLY_ROOT} 1
    } {
        ::stage1e::runtime_test::assert_equal $expected \
            [::stage1e::runtime_static_test::count_literal \
                $entry_text $literal] \
            "Entry-point foundation state differs: $literal"
    }
    foreach prohibited {
        {status = 'CLEAR'}
        {dependency_closure_state = 'CLOSED'}
    } {
        ::stage1e::runtime_test::assert_true \
            {[string first $prohibited $entry_text] < 0} \
            "Entry point claims a production-complete state: $prohibited"
    }
    ::stage1e::runtime_test::assert_true \
        {[string first \
            {(ConvertTo-Stage1EEntryCanonicalPath $entryPath) $entryInterfaceVersion} \
            $entry_text] >= 0} \
        {ENTRY_POINT root record lacks its exact path/interface binding}

    set result_schema [::stage1e::runtime_static_test::read_text [file join \
        $root fpga vivado build lib \
        stage1e_runtime_result_envelope_v1.schema.json]]
    foreach required {NOT_EVALUATED PARTIAL_FOUNDATION CLOSED} {
        ::stage1e::runtime_test::assert_true \
            {[string first $required $result_schema] >= 0} \
            "Result schema lacks amended state: $required"
    }

    foreach relative_path {
        fpga/vivado/build/lib/stage1e_runtime_envelope_contract_v1.psm1
        fpga/vivado/build/lib/stage1e_runtime_envelope_contract_v1.tcl
    } {
        set contract_text [::stage1e::runtime_static_test::read_text \
            [file join $root {*}[split $relative_path /]]]
        foreach required {
            log_root journal_root temporary_root cache_root request_root
            source_root workspace_root evidence_root
        } {
            ::stage1e::runtime_test::assert_true \
                {[string first $required $contract_text] >= 0} \
                "Path ownership field is absent from $relative_path: $required"
        }
    }
}

::stage1e::runtime_test::run_case prt02_schema_ownership_is_singular {
    set schema_directory [file join $root fpga vivado build lib]
    set observed [lsort [glob -nocomplain -types f -directory \
        $schema_directory stage1e_runtime_*_v1.schema.json]]
    set expected {}
    foreach relative_path $prt02_schema_paths {
        lappend expected [file join $root {*}[split $relative_path /]]
    }
    set expected [lsort $expected]
    ::stage1e::runtime_test::assert_equal $expected $observed \
        {Request/result/failure schema file ownership differs}
    foreach path $observed {
        set text [::stage1e::runtime_static_test::read_text $path]
        ::stage1e::runtime_test::assert_true \
            {[string first {"x-stage1e-canonical-order"} $text] >= 0} \
            "Schema lacks canonical-order metadata: [file tail $path]"
        ::stage1e::runtime_test::assert_true \
            {[string first {"additionalProperties": true} $text] < 0 &&
             [string first {"additionalProperties": false} $text] >= 0} \
            "Schema is not exact-field closed: [file tail $path]"
    }
    foreach relative_path {
        fpga/vivado/build/lib/stage1e_runtime_canonical_json_v1.psm1
        fpga/vivado/build/lib/stage1e_runtime_canonical_json_v1.tcl
    } {
        set text [::stage1e::runtime_static_test::read_text \
            [file join $root {*}[split $relative_path /]]]
        ::stage1e::runtime_test::assert_true \
            {[string first {x-stage1e-canonical-order} $text] >= 0} \
            "Canonical encoder does not consume schema order: $relative_path"
        ::stage1e::runtime_test::assert_true \
            {![regexp -nocase \
                {(request|result|failure)[_-]?(fields|order)[ \t]*=} $text]} \
            "Codec carries a private envelope field list: $relative_path"
    }
}

::stage1e::runtime_test::run_case prt02_codecs_have_no_ambient_authority {
    foreach relative_path {
        fpga/vivado/build/lib/stage1e_runtime_canonical_json_v1.psm1
        fpga/vivado/build/lib/stage1e_runtime_canonical_json_v1.tcl
    } {
        set text [::stage1e::runtime_static_test::read_text \
            [file join $root {*}[split $relative_path /]]]
        foreach forbidden {
            convertfrom-json convertto-json {package require} auto_path
            newtonsoft javascriptserializer system.text.json
        } {
            ::stage1e::runtime_test::assert_true \
                {[string first $forbidden [string tolower $text]] < 0} \
                "Ambient JSON authority found in $relative_path: $forbidden"
        }
        ::stage1e::runtime_test::assert_true \
            {![regexp -nocase {\[regex\]|-match|-replace|regexp|regsub} $text]} \
            "Regular-expression JSON parsing found in $relative_path"
    }
}

::stage1e::runtime_test::run_case prt02_remains_disjoint_from_mock_modules {
    foreach relative_path [concat $prt02_source_paths \
            $prt02_host_source_paths $prt02_vivado_source_paths] {
        set text [::stage1e::runtime_static_test::read_text \
            [file join $root {*}[split $relative_path /]]]
        foreach legacy {
            stage1e_runtime_launcher.psm1 stage1e_runtime_runner.tcl
            stage1e_runtime_collector.tcl stage1e_runtime_parser.tcl
            stage1e_runtime_identity.tcl stage1e_runtime_observer.tcl
            stage1e_phase3_implementation_controller_v2.tcl
            stage1e_implementation_v2.tcl
        } {
            ::stage1e::runtime_test::assert_true \
                {[string first $legacy $text] < 0} \
                "PRT02-A source reaches an admitted mock module: $legacy"
        }
    }
}

::stage1e::runtime_test::run_case historical_constants_absent {
    foreach relative_path $required_paths {
        set absolute [file join $root {*}[split $relative_path /]]
        set text [::stage1e::runtime_static_test::read_text $absolute]
        if {[regexp -nocase {(^|[^a-z0-9])r23([^a-z0-9]|$)} $text]} {
            error "Historical runtime token found in $relative_path"
        }
        if {[regexp {STAGE1E-[0-9]{8}-[0-9]{6}} $text]} {
            error "Historical execution identifier found in $relative_path"
        }
        set standard_vector_source [expr {$relative_path eq \
            {fpga/vivado/build/dependency/stage1e_runtime_dependency_closure_v1.psm1}}]
        if {!$standard_vector_source &&
            [regexp -nocase {(^|[^0-9a-f])[0-9a-f]{64}([^0-9a-f]|$)} \
                $text]} {
            error "Embedded SHA-256 constant found in $relative_path"
        }
    }
}

::stage1e::runtime_test::run_case forbidden_executable_commands_absent {
    set executable_paths {
        fpga/vivado/build/runtime/launcher/stage1e_runtime_launcher.psm1
        fpga/vivado/build/runtime/runner/stage1e_runtime_runner.tcl
        fpga/vivado/build/runtime/collector/stage1e_runtime_collector.tcl
        fpga/vivado/build/runtime/parser/stage1e_runtime_parser.tcl
        fpga/vivado/build/runtime/observer/stage1e_runtime_observer.tcl
        fpga/vivado/build/controller/stage1e_phase3_implementation_controller_v2.tcl
        fpga/vivado/build/adapters/stage1e_implementation_v2.tcl
    }
    set executable_paths [concat $executable_paths $prt02_source_paths \
        $prt02_host_source_paths $prt02_vivado_source_paths]
    set command_names {
        opt_design place_design phys_opt_design route_design
        report_timing_summary report_timing report_drc report_methodology
        report_cdc report_clock_interaction report_utilization report_power
        report_exceptions report_route_status
        write_bitstream write_hw_platform write_xsa export_hardware
        open_hw_manager connect_hw_server program_hw_devices
    }
    foreach relative_path $executable_paths {
        set absolute [file join $root {*}[split $relative_path /]]
        set text [::stage1e::runtime_static_test::read_text $absolute]
        if {[regexp -nocase \
                {start-process|processstartinfo|system\.diagnostics\.process|invoke-expression|get-command[^\n]*vivado|(^|[[:space:]])exec[[:space:]].*vivado} \
                $text]} {
            error "Process-level Vivado dispatch found in $relative_path"
        }
        foreach line [split $text "\n"] {
            set trimmed [string trim $line]
            if {$trimmed eq {} || [string index $trimmed 0] eq {#}} {
                continue
            }
            foreach command $command_names {
                set bracket_invocation 0
                if {[string index $trimmed 0] eq "\["} {
                    set bracket_invocation [regexp \
                        [format {^%s([[:space:]]|\])} $command] \
                        [string range $trimmed 1 end]]
                }
                set direct_invocation [regexp \
                    [format {^%s[[:space:]]+-} $command] $trimmed]
                if {$bracket_invocation || $direct_invocation} {
                    error "Direct tool command $command found in $relative_path"
                }
            }
        }
    }
}

::stage1e::runtime_test::run_case option_a_is_structurally_frozen {
    set configuration [::stage1e::runtime_schema::read_dictionary [file join \
        $root fpga vivado build config \
        stage1e_implementation_configuration_v2.dict]]
    ::stage1e::runtime_schema::validate_effective_graph \
        [dict get $configuration effective_step_graph]
    ::stage1e::runtime_test::assert_equal DISABLED \
        [dict get $configuration tool_configuration phys_opt_state] \
        {Physical optimization is not disabled}
    ::stage1e::runtime_test::assert_true \
        {[lsearch -exact [dict get $configuration operation_order] \
            phys_opt_design] < 0} \
        {Physical optimization appears in the executable order}
}

::stage1e::runtime_test::run_case policy_v2_required_sections_are_present {
    set policy_path [file join $root docs design \
        stage1e_implementation_policy_v2.md]
    set policy [::stage1e::runtime_static_test::read_text $policy_path]
    foreach heading {
        {## Controlled Runtime Backend Binding}
        {## Effective Implementation Flow}
        {## Effective Graph Readback}
        {## Warning Disposition Interface}
        {## Timing Acceptance and Exception Inventory}
        {## Implementation Report Ledger}
        {## Artifact and Board Boundary}
        {## Remaining Work Before Q0-Q5}
    } {
        ::stage1e::runtime_test::assert_true \
            {[string first $heading $policy] >= 0} \
            "Policy v2 heading is missing: $heading"
    }
    ::stage1e::runtime_test::assert_true \
        {[regexp {does not[[:space:]]+authorize Q0-Q5 qualification} \
            $policy]} \
        {Policy v2 does not state its non-authorization boundary}
}

::stage1e::runtime_test::finish
