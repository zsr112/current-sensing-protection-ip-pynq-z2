# Stage 1E controlled-runtime schema foundation v1.
#
# This module validates synthetic or future identity records and the Run2
# effective implementation graph. It creates no execution, qualification,
# authorization, implementation result, artifact, or board authority.

namespace eval ::stage1e::runtime_schema {
    variable runtime_backend_identity_fields {
        schema_version
        backend_id
        backend_version
        status
        source_manifest
        controller_contract
        adapter_contract
        request_schema
        result_schema
        allowed_operations
        forbidden_operations
        report_contract
        message_contract
        host_requirements
        artifact_authority
        board_authority
    }
    variable policy_identity_fields {
        schema_version
        policy_id
        policy_document
        status
        runtime_backend_identity
        configuration_schema
        warning_policy_identity
        timing_exception_contract
        effective_graph_contract
        target
        part
        board_part
        vivado_version
    }
    variable configuration_identity_fields {
        schema_version
        configuration_id
        status
        runtime_backend_identity
        policy_identity
        run_name
        target
        top
        part
        board_part
        strategy
        jobs
        incremental_policy
        imported_checkpoint_policy
        operation_order
        effective_step_graph
        report_roles
        report_ledger_required
        artifact_authority
        board_authority
    }
    variable allowed_operations {
        opt_design
        place_design
        route_design
        implementation_reports
    }
    variable forbidden_operations {
        phys_opt_design
        power_opt_design
        write_bitstream
        write_hw_platform
        write_xsa
        export_hardware
        artifact_collection
        artifact_publication
        open_hw_manager
        connect_hw_server
        program_hw_devices
        board_access
    }
    variable effective_steps {
        opt_design
        place_design
        phys_opt_design
        route_design
        implementation_reports
    }
    variable runtime_source_roles {
        LAUNCHER
        RUNNER
        COLLECTOR
        PARSER
        IDENTITY
        OBSERVER
    }
    variable required_report_roles {
        TIMING_SUMMARY
        UTILIZATION
        DRC
        METHODOLOGY
        CLOCK_INTERACTION
        CONSTRAINT_COVERAGE
        MESSAGE_INVENTORY
        TIMING_EXCEPTION_INVENTORY
        EFFECTIVE_GRAPH_READBACK
    }
}

proc ::stage1e::runtime_schema::_raise {code message} {
    return -code error -errorcode \
        [list STAGE1E RUNTIME_SCHEMA $code] $message
}

proc ::stage1e::runtime_schema::require_dictionary {record label} {
    if {[catch {dict size $record} dictionary_error]} {
        _raise SCHEMA_INVALID \
            "$label is not a dictionary: $dictionary_error"
    }
    return 1
}

proc ::stage1e::runtime_schema::require_exact_fields {
    record
    fields
    label
} {
    require_dictionary $record $label
    set expected [lsort -dictionary $fields]
    set actual [lsort -dictionary [dict keys $record]]
    if {$expected ne $actual} {
        _raise IDENTITY_INCOMPLETE \
            "$label fields differ: expected=<$expected> actual=<$actual>"
    }
    foreach field $fields {
        if {[dict get $record $field] eq {}} {
            _raise IDENTITY_INCOMPLETE "$label has an empty field: $field"
        }
    }
    return 1
}

proc ::stage1e::runtime_schema::require_equal {expected actual label} {
    if {$expected ne $actual} {
        _raise CONTRACT_MISMATCH \
            "$label mismatch: expected=<$expected> actual=<$actual>"
    }
    return 1
}

proc ::stage1e::runtime_schema::require_exact_list {
    expected
    actual
    label
} {
    set expected [list {*}$expected]
    set actual [list {*}$actual]
    if {$expected ne $actual} {
        _raise UNAUTHORIZED_OPERATION \
            "$label differs: expected=<$expected> actual=<$actual>"
    }
    return 1
}

proc ::stage1e::runtime_schema::require_identity {value label} {
    if {[string toupper $value] in {
            UNKNOWN MISSING STALE NOT_ASSIGNED NOT_PRODUCED
        }} {
        _raise IDENTITY_INVALID "$label is a blocking identity value."
    }
    if {![llength [info commands \
            ::stage1e::runtime_identity::require_sha256]]} {
        _raise DEPENDENCY_MISSING \
            {Stage 1E runtime identity helpers are unavailable.}
    }
    return [::stage1e::runtime_identity::require_sha256 $value $label]
}

proc ::stage1e::runtime_schema::read_dictionary {path} {
    if {![file exists $path] || ![file isfile $path]} {
        _raise INPUT_MISSING "Dictionary file is missing: $path"
    }
    set channel [open $path r]
    fconfigure $channel -encoding utf-8 -translation auto
    set read_status [catch {read $channel} contents read_options]
    set close_status [catch {close $channel} close_error]
    if {$read_status != 0} {
        return -options $read_options $contents
    }
    if {$close_status != 0} {
        _raise INPUT_INVALID "Unable to close dictionary file: $close_error"
    }
    require_dictionary $contents "Dictionary file $path"
    return $contents
}

proc ::stage1e::runtime_schema::runtime_backend_identity_fields {} {
    variable runtime_backend_identity_fields
    return $runtime_backend_identity_fields
}

proc ::stage1e::runtime_schema::policy_identity_fields {} {
    variable policy_identity_fields
    return $policy_identity_fields
}

proc ::stage1e::runtime_schema::configuration_identity_fields {} {
    variable configuration_identity_fields
    return $configuration_identity_fields
}

proc ::stage1e::runtime_schema::allowed_operations {} {
    variable allowed_operations
    return $allowed_operations
}

proc ::stage1e::runtime_schema::forbidden_operations {} {
    variable forbidden_operations
    return $forbidden_operations
}

proc ::stage1e::runtime_schema::validate_effective_graph {graph} {
    variable effective_steps
    require_exact_fields $graph $effective_steps \
        {Implementation effective step graph}
    set expected [dict create \
        opt_design {ENABLED 1 1 Default synthesis} \
        place_design {ENABLED 1 2 Default opt_design} \
        phys_opt_design {DISABLED 0 0 NONE place_design} \
        route_design {ENABLED 1 3 Default place_design} \
        implementation_reports {ENABLED 1 4 READ_ONLY route_design}]
    foreach step $effective_steps {
        set definition [dict get $graph $step]
        require_exact_fields $definition {
            configured_state
            authorized
            sequence
            directive
            predecessor
            invocation_policy
        } "Effective step $step"
        lassign [dict get $expected $step] \
            state authorized sequence directive predecessor
        require_equal $state [dict get $definition configured_state] \
            "Effective step state $step"
        require_equal $authorized [dict get $definition authorized] \
            "Effective step authorization $step"
        require_equal $sequence [dict get $definition sequence] \
            "Effective step sequence $step"
        require_equal $directive [dict get $definition directive] \
            "Effective step directive $step"
        require_equal $predecessor [dict get $definition predecessor] \
            "Effective step predecessor $step"
        set invocation_policy [expr {
            $step eq {phys_opt_design} ? {PROHIBITED} : {REQUIRED}
        }]
        require_equal $invocation_policy \
            [dict get $definition invocation_policy] \
            "Effective step invocation policy $step"
    }
    return 1
}

proc ::stage1e::runtime_schema::validate_runtime_backend_identity {record} {
    variable runtime_backend_identity_fields
    variable allowed_operations
    variable forbidden_operations
    variable runtime_source_roles
    if {![llength [info commands ::stage1e::runtime_identity::validate]]} {
        _raise DEPENDENCY_MISSING \
            {Stage 1E runtime identity helpers are unavailable.}
    }
    require_exact_fields $record \
        [linsert $runtime_backend_identity_fields 1 identity_sha256] \
        {Runtime backend identity}
    require_equal stage1e-runtime-backend-identity-v1 \
        [dict get $record schema_version] {Runtime backend identity schema}
    if {[dict get $record status] ne {CURRENT_REVIEWED}} {
        _raise RUNTIME_STALE \
            {Runtime backend status is not CURRENT_REVIEWED.}
    }
    require_exact_list $allowed_operations [dict get $record \
        allowed_operations] {Runtime backend allowed operations}
    require_exact_list $forbidden_operations [dict get $record \
        forbidden_operations] {Runtime backend forbidden operations}
    foreach field {controller_contract adapter_contract report_contract \
            message_contract} {
        require_identity [dict get $record $field] \
            "Runtime backend $field"
    }
    set manifest [dict get $record source_manifest]
    if {![llength $manifest]} {
        _raise IDENTITY_INCOMPLETE \
            {Runtime backend source manifest is empty.}
    }
    set roles {}
    foreach entry $manifest {
        require_exact_fields $entry {role path sha256} \
            {Runtime backend source-manifest entry}
        if {[lsearch -exact $roles [dict get $entry role]] >= 0} {
            _raise SCHEMA_INVALID \
                {Runtime backend source manifest has a duplicate role.}
        }
        lappend roles [dict get $entry role]
        set source_path [string map {\\ /} [dict get $entry path]]
        if {[file pathtype $source_path] ne {relative}} {
            _raise SCHEMA_INVALID \
                {Runtime backend source path is not repository relative.}
        }
        foreach component [file split $source_path] {
            if {$component in {. ..}} {
                _raise SCHEMA_INVALID \
                    {Runtime backend source path has a disallowed component.}
            }
        }
        require_identity [dict get $entry sha256] \
            {Runtime backend source file identity}
    }
    require_exact_list $runtime_source_roles $roles \
        {Runtime backend source-manifest roles}
    foreach field {artifact_authority board_authority} {
        require_equal NONE [dict get $record $field] \
            "Runtime backend $field"
    }
    ::stage1e::runtime_identity::validate \
        $runtime_backend_identity_fields $record {Runtime backend identity}
    return 1
}

proc ::stage1e::runtime_schema::validate_policy_identity_v2 {record} {
    variable policy_identity_fields
    require_exact_fields $record [linsert $policy_identity_fields 1 \
        identity_sha256] {Implementation policy identity v2}
    require_equal stage1e-implementation-policy-identity-v2 \
        [dict get $record schema_version] \
        {Implementation policy identity schema}
    require_equal REVIEWED [dict get $record status] \
        {Implementation policy identity status}
    foreach field {
        runtime_backend_identity
        warning_policy_identity
        timing_exception_contract
        effective_graph_contract
    } {
        require_identity [dict get $record $field] \
            "Implementation policy $field"
    }
    require_equal stage1e-implementation-configuration-identity-v2 \
        [dict get $record configuration_schema] \
        {Implementation policy configuration schema}
    foreach {field expected} {
        target protection_system_wrapper
        part xc7z020clg400-1
        board_part tul.com.tw:pynq-z2:part0:1.0
        vivado_version 2024.1
    } {
        require_equal $expected [dict get $record $field] \
            "Implementation policy $field"
    }
    ::stage1e::runtime_identity::validate $policy_identity_fields $record \
        {Implementation policy identity v2}
    return 1
}

proc ::stage1e::runtime_schema::validate_configuration_identity_v2 {record} {
    variable configuration_identity_fields
    variable allowed_operations
    variable required_report_roles
    require_exact_fields $record [linsert $configuration_identity_fields 1 \
        identity_sha256] {Implementation configuration identity v2}
    require_equal stage1e-implementation-configuration-identity-v2 \
        [dict get $record schema_version] \
        {Implementation configuration identity schema}
    require_equal FROZEN [dict get $record status] \
        {Implementation configuration identity status}
    foreach field {runtime_backend_identity policy_identity} {
        require_identity [dict get $record $field] \
            "Implementation configuration $field"
    }
    require_exact_list $allowed_operations [dict get $record \
        operation_order] {Implementation configuration operation order}
    validate_effective_graph [dict get $record effective_step_graph]
    foreach {field expected} {
        run_name impl_1
        target protection_system_wrapper
        top protection_system_wrapper
        part xc7z020clg400-1
        board_part tul.com.tw:pynq-z2:part0:1.0
        strategy Vivado_Implementation_Defaults
        jobs 2
        incremental_policy DISABLED
        imported_checkpoint_policy PROHIBITED
    } {
        require_equal $expected [dict get $record $field] \
            "Implementation configuration $field"
    }
    require_exact_list $required_report_roles [dict get $record report_roles] \
        {Implementation configuration report roles}
    require_equal 1 [dict get $record report_ledger_required] \
        {Implementation report-ledger requirement}
    foreach field {artifact_authority board_authority} {
        require_equal NONE [dict get $record $field] \
            "Implementation configuration $field"
    }
    ::stage1e::runtime_identity::validate \
        $configuration_identity_fields $record \
        {Implementation configuration identity v2}
    return 1
}
