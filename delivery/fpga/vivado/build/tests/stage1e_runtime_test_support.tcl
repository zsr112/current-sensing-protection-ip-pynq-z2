# Shared non-Vivado support for the Stage 1E controlled-runtime tests.

namespace eval ::stage1e::runtime_test {
    variable passed 0
    variable failed 0
    variable repository_root [file normalize [file join \
        [file dirname [info script]] .. .. .. ..]]
}

proc ::stage1e::runtime_test::repository_root {} {
    variable repository_root
    return $repository_root
}

proc ::stage1e::runtime_test::source_runtime_foundation {} {
    set root [repository_root]
    foreach relative_path {
        fpga/vivado/build/lib/source_check.tcl
        fpga/vivado/build/runtime/identity/stage1e_runtime_identity.tcl
        fpga/vivado/build/lib/stage1e_runtime_schema.tcl
        fpga/vivado/build/runtime/runner/stage1e_runtime_runner.tcl
        fpga/vivado/build/runtime/collector/stage1e_runtime_collector.tcl
        fpga/vivado/build/runtime/parser/stage1e_runtime_parser.tcl
        fpga/vivado/build/runtime/observer/stage1e_runtime_observer.tcl
        fpga/vivado/build/controller/stage1e_phase3_implementation_controller_v2.tcl
        fpga/vivado/build/adapters/stage1e_implementation_v2.tcl
    } {
        source [file join $root {*}[split $relative_path /]]
    }
}

proc ::stage1e::runtime_test::assert_true {condition message} {
    if {![uplevel 1 [list expr $condition]]} {
        error $message
    }
}

proc ::stage1e::runtime_test::assert_equal {expected actual message} {
    if {$expected ne $actual} {
        error "$message: expected=<$expected> actual=<$actual>"
    }
}

proc ::stage1e::runtime_test::assert_error {script errorcode_pattern} {
    set status [catch {uplevel 1 $script} message options]
    if {$status == 0} {
        error "Expected failure matching $errorcode_pattern, but command passed."
    }
    set code [join [dict get $options -errorcode] /]
    if {![string match $errorcode_pattern $code]} {
        error "Wrong failure: expected=<$errorcode_pattern> actual=<$code> message=<$message>"
    }
    return 1
}

proc ::stage1e::runtime_test::run_case {name script} {
    variable passed
    variable failed
    set status [catch {uplevel 1 $script} message options]
    if {$status == 0} {
        incr passed
        puts "PASS $name"
        return
    }
    incr failed
    puts "FAIL $name: $message"
    if {[dict exists $options -errorinfo]} {
        puts [dict get $options -errorinfo]
    }
}

proc ::stage1e::runtime_test::finish {} {
    variable passed
    variable failed
    puts "SUMMARY passed=$passed failed=$failed"
    if {$failed != 0} {
        error "Stage 1E controlled-runtime test failures: $failed"
    }
    return $passed
}

proc ::stage1e::runtime_test::synthetic_hash {character} {
    if {![regexp {^[1-9a-f]$} $character]} {
        error {Synthetic hash character must be a nonzero hexadecimal digit.}
    }
    return [string repeat $character 64]
}

proc ::stage1e::runtime_test::effective_graph {} {
    return [dict create \
        opt_design [dict create configured_state ENABLED authorized 1 \
            sequence 1 directive Default predecessor synthesis \
            invocation_policy REQUIRED] \
        place_design [dict create configured_state ENABLED authorized 1 \
            sequence 2 directive Default predecessor opt_design \
            invocation_policy REQUIRED] \
        phys_opt_design [dict create configured_state DISABLED authorized 0 \
            sequence 0 directive NONE predecessor place_design \
            invocation_policy PROHIBITED] \
        route_design [dict create configured_state ENABLED authorized 1 \
            sequence 3 directive Default predecessor place_design \
            invocation_policy REQUIRED] \
        implementation_reports [dict create configured_state ENABLED \
            authorized 1 sequence 4 directive READ_ONLY \
            predecessor route_design invocation_policy REQUIRED]]
}

proc ::stage1e::runtime_test::make_runtime_identity {} {
    set manifest [list \
        [dict create role LAUNCHER path mock/launcher \
            sha256 [synthetic_hash 1]] \
        [dict create role RUNNER path mock/runner \
            sha256 [synthetic_hash 2]] \
        [dict create role COLLECTOR path mock/collector \
            sha256 [synthetic_hash 3]] \
        [dict create role PARSER path mock/parser \
            sha256 [synthetic_hash 4]] \
        [dict create role IDENTITY path mock/identity \
            sha256 [synthetic_hash 5]] \
        [dict create role OBSERVER path mock/observer \
            sha256 [synthetic_hash 6]]]
    set payload [dict create \
        schema_version stage1e-runtime-backend-identity-v1 \
        backend_id stage1e_controlled_runtime_v1 \
        backend_version 1 \
        status CURRENT_REVIEWED \
        source_manifest $manifest \
        controller_contract [synthetic_hash 7] \
        adapter_contract [synthetic_hash 8] \
        request_schema stage1e-runtime-request-v1 \
        result_schema stage1e-runtime-result-v1 \
        allowed_operations [::stage1e::runtime_schema::allowed_operations] \
        forbidden_operations [::stage1e::runtime_schema::forbidden_operations] \
        report_contract [synthetic_hash 9] \
        message_contract [synthetic_hash a] \
        host_requirements WINDOWS64_REVIEWED_HOST \
        artifact_authority NONE \
        board_authority NONE]
    return [::stage1e::runtime_identity::attach \
        [::stage1e::runtime_schema::runtime_backend_identity_fields] $payload]
}

proc ::stage1e::runtime_test::make_policy_identity {runtime_identity} {
    set payload [dict create \
        schema_version stage1e-implementation-policy-identity-v2 \
        policy_id stage1e_implementation_policy_v2 \
        policy_document docs/design/stage1e_implementation_policy_v2.md \
        status REVIEWED \
        runtime_backend_identity [dict get $runtime_identity identity_sha256] \
        configuration_schema stage1e-implementation-configuration-identity-v2 \
        warning_policy_identity [synthetic_hash 8] \
        timing_exception_contract [synthetic_hash 9] \
        effective_graph_contract [synthetic_hash a] \
        target protection_system_wrapper \
        part xc7z020clg400-1 \
        board_part tul.com.tw:pynq-z2:part0:1.0 \
        vivado_version 2024.1]
    return [::stage1e::runtime_identity::attach \
        [::stage1e::runtime_schema::policy_identity_fields] $payload]
}

proc ::stage1e::runtime_test::make_configuration_identity {
    runtime_identity
    policy_identity
} {
    set payload [dict create \
        schema_version stage1e-implementation-configuration-identity-v2 \
        configuration_id stage1e_implementation_configuration_v2 \
        status FROZEN \
        runtime_backend_identity [dict get $runtime_identity identity_sha256] \
        policy_identity [dict get $policy_identity identity_sha256] \
        run_name impl_1 \
        target protection_system_wrapper \
        top protection_system_wrapper \
        part xc7z020clg400-1 \
        board_part tul.com.tw:pynq-z2:part0:1.0 \
        strategy Vivado_Implementation_Defaults \
        jobs 2 \
        incremental_policy DISABLED \
        imported_checkpoint_policy PROHIBITED \
        operation_order [::stage1e::runtime_schema::allowed_operations] \
        effective_step_graph [effective_graph] \
        report_roles [::stage1e::runtime_collector::report_roles] \
        report_ledger_required 1 \
        artifact_authority NONE \
        board_authority NONE]
    return [::stage1e::runtime_identity::attach \
        [::stage1e::runtime_schema::configuration_identity_fields] $payload]
}

proc ::stage1e::runtime_test::identity_fixture {} {
    set runtime [make_runtime_identity]
    set policy [make_policy_identity $runtime]
    set configuration [make_configuration_identity $runtime $policy]
    return [dict create runtime $runtime policy $policy \
        configuration $configuration]
}

::stage1e::runtime_test::source_runtime_foundation
