# Stage 1E WP-B base block-design topology adapter.
#
# This module is definition-only when sourced. It consumes existing project
# and BD ownership, applies only the controller-authorized base topology, and
# returns those ownership records unchanged. It does not own project/BD
# lifecycle, validation, save, mutation, build execution, or FPGA artifacts.

namespace eval ::stage1e::base_design {
    variable context_schema_version stage1e-base-design-context-v1
    variable result_schema_version stage1e-base-design-result-v1
    variable operation_name stage1e::base_design::apply
    variable phase_name BD_GENERATION
    variable required_vlnv_roles {
        processing_system7
        smartconnect
        protection
        reset
        constant
    }
    variable required_cell_roles {
        processing_system7
        reset
        smartconnect
        protection
        sample_valid_const
        i_ch1_const
        i_ch2_const
        dcm_locked_const
    }
    variable address_readback_max_attempts 3
}

namespace eval ::stage1e::base_design::backend {}

# Reuse the controlled source-verification SHA-256 implementation. Loading the
# dependency defines procedures only and invokes no Vivado command.
if {[llength [info commands ::stage1d::source_check::sha256_text]] == 0} {
    set ::stage1e::base_design::_source_check_path [file normalize \
        [file join [file dirname [info script]] .. lib source_check.tcl]]
    source $::stage1e::base_design::_source_check_path
    unset ::stage1e::base_design::_source_check_path
}

proc ::stage1e::base_design::backend::invoke {command arguments} {
    return [uplevel #0 [list $command {*}$arguments]]
}

proc ::stage1e::base_design::_invoke {command args} {
    return [::stage1e::base_design::backend::invoke $command $args]
}

proc ::stage1e::base_design::_get_or_default {
    dictionary
    key
    default_value
} {
    if {![catch {dict size $dictionary}] && [dict exists $dictionary $key]} {
        return [dict get $dictionary $key]
    }
    return $default_value
}

proc ::stage1e::base_design::_raise {
    status
    error_code
    error_class
    message
} {
    return -code error -errorcode [list \
        STAGE1E BASE_DESIGN $status $error_code $error_class] $message
}

proc ::stage1e::base_design::_decode_error {
    message
    options
    default_code
    default_class
} {
    set status FAIL
    set error_code $default_code
    set error_class $default_class
    set underlying_error [_get_or_default $options -errorinfo $message]
    set tcl_error_code [_get_or_default $options -errorcode {}]
    if {[llength $tcl_error_code] >= 5 &&
        [lrange $tcl_error_code 0 1] eq {STAGE1E BASE_DESIGN}} {
        set status [lindex $tcl_error_code 2]
        set error_code [lindex $tcl_error_code 3]
        set error_class [lindex $tcl_error_code 4]
    } elseif {[lrange $tcl_error_code 0 2] eq {TCL LOOKUP COMMAND}} {
        set status BLOCKED
        set error_code VIVADO_COMMAND_UNAVAILABLE
        set error_class ENVIRONMENT
    }
    return [dict create \
        status $status \
        error_code $error_code \
        error_class $error_class \
        message $message \
        underlying_error $underlying_error]
}

proc ::stage1e::base_design::_error_record {decoded} {
    variable operation_name
    variable phase_name
    set code [dict get $decoded error_code]
    set class [dict get $decoded error_class]
    return [dict create \
        code $code \
        error_code $code \
        class $class \
        category $class \
        operation $operation_name \
        phase $phase_name \
        message [dict get $decoded message] \
        underlying_error [dict get $decoded underlying_error] \
        evidence_references {}]
}

proc ::stage1e::base_design::_cleanup_result {
    required
    completed
    disposition
} {
    return [dict create \
        owner stage1e::base_design \
        required $required \
        attempted 0 \
        completed $completed \
        disposition $disposition \
        errors {}]
}

proc ::stage1e::base_design::_context_execution_id {context} {
    if {![catch {dict size $context}] &&
        [dict exists $context execution_id]} {
        return [dict get $context execution_id]
    }
    return {}
}

proc ::stage1e::base_design::_result {
    status
    context
    consumed_identities
    produced_identities
    ownership_records
    evidence_references
    warnings
    errors
    cleanup_result
    vivado_invoked
} {
    variable result_schema_version
    variable operation_name
    variable phase_name
    return [dict create \
        schema_version $result_schema_version \
        operation $operation_name \
        phase $phase_name \
        execution_id [_context_execution_id $context] \
        status $status \
        consumed_identities $consumed_identities \
        produced_identities $produced_identities \
        ownership_records $ownership_records \
        evidence_references $evidence_references \
        warnings $warnings \
        errors $errors \
        cleanup_result $cleanup_result \
        vivado_invoked $vivado_invoked \
        lifecycle_ownership_created 0 \
        project_opened 0 \
        project_created 0 \
        bd_created 0 \
        bd_validated 0 \
        bd_saved 0 \
        mutation_invoked 0 \
        synthesis_performed 0 \
        implementation_performed 0 \
        artifacts_generated 0 \
        artifact_generation_performed 0 \
        artifact_publication_performed 0]
}

proc ::stage1e::base_design::_require_dictionary {value label} {
    if {[catch {dict size $value} dictionary_error]} {
        _raise FAIL CONTEXT_FIELD_INVALID CONTRACT \
            "$label must be a dictionary: $dictionary_error"
    }
}

proc ::stage1e::base_design::_require_keys {
    dictionary
    required_keys
    label
} {
    _require_dictionary $dictionary $label
    foreach key $required_keys {
        if {![dict exists $dictionary $key]} {
            _raise FAIL CONTEXT_FIELD_MISSING CONTRACT \
                "$label is missing required key: $key"
        }
    }
}

proc ::stage1e::base_design::_canonical_components {path} {
    set components [file split [file normalize $path]]
    if {$::tcl_platform(platform) ne {windows}} {
        return $components
    }
    set canonical {}
    foreach component $components {
        lappend canonical [string tolower $component]
    }
    return $canonical
}

proc ::stage1e::base_design::_paths_equal {first_path second_path} {
    return [expr {
        [_canonical_components $first_path] eq
            [_canonical_components $second_path]
    }]
}

proc ::stage1e::base_design::_is_equal_or_descendant {
    candidate_path
    parent_path
} {
    set candidate [_canonical_components $candidate_path]
    set parent [_canonical_components $parent_path]
    if {[llength $candidate] < [llength $parent]} {
        return 0
    }
    for {set index 0} {$index < [llength $parent]} {incr index} {
        if {[lindex $candidate $index] ne [lindex $parent $index]} {
            return 0
        }
    }
    return 1
}

proc ::stage1e::base_design::_is_identifier {value} {
    return [regexp {^[A-Za-z_][A-Za-z0-9_]*$} $value]
}

proc ::stage1e::base_design::_validate_object_path {path label} {
    set value [string trim $path]
    if {![regexp {^[A-Za-z_][A-Za-z0-9_]*/[A-Za-z_][A-Za-z0-9_]*$} \
        $value]} {
        _raise FAIL POLICY_OBJECT_PATH_INVALID CONTRACT \
            "$label is not a cell/object path: $path"
    }
    return $value
}

proc ::stage1e::base_design::_validate_authorization {
    authorization
    execution_id
} {
    variable operation_name
    variable phase_name
    if {[catch {dict size $authorization} authorization_error]} {
        _raise BLOCKED AUTHORIZATION_INVALID AUTHORIZATION \
            "authorization must be a dictionary: $authorization_error"
    }
    foreach key {
        status
        authority
        execution_id
        operation
        phase
        capability
        capability_enabled
    } {
        if {![dict exists $authorization $key]} {
            _raise BLOCKED AUTHORIZATION_INCOMPLETE AUTHORIZATION \
                "authorization is missing required key: $key"
        }
    }
    if {[dict get $authorization status] ne {AUTHORIZED} ||
        [dict get $authorization authority] ne {controller_core} ||
        [dict get $authorization execution_id] ne $execution_id ||
        [dict get $authorization operation] ne $operation_name ||
        [dict get $authorization phase] ne $phase_name ||
        [dict get $authorization capability] ne {bd_generation_enabled} ||
        ![string is boolean -strict \
            [dict get $authorization capability_enabled]] ||
        ![dict get $authorization capability_enabled]} {
        _raise BLOCKED AUTHORIZATION_MISMATCH AUTHORIZATION \
            {Controller authorization does not permit base-design topology.}
    }
}

proc ::stage1e::base_design::_validate_identity {
    identity
    label
    execution_id
} {
    _require_dictionary $identity $label
    if {[dict size $identity] == 0} {
        _raise FAIL IDENTITY_MISSING IDENTITY "$label must not be empty."
    }
    if {[dict exists $identity execution_id] &&
        [dict get $identity execution_id] ne $execution_id} {
        _raise FAIL CONSUMED_IDENTITY_EXECUTION_MISMATCH IDENTITY \
            "$label belongs to another execution."
    }
    return $identity
}

proc ::stage1e::base_design::_validate_topology_policy {
    policy
    execution_id
} {
    _require_keys $policy {
        schema_version
        policy_id
        source_reference
        sha256
    } {topology_policy}
    if {[dict get $policy schema_version] ne
        {stage1e-topology-policy-reference-v1}} {
        _raise FAIL TOPOLOGY_POLICY_SCHEMA_UNSUPPORTED CONTRACT \
            {Unsupported topology_policy schema.}
    }
    foreach field {policy_id source_reference} {
        if {[string trim [dict get $policy $field]] eq {}} {
            _raise FAIL TOPOLOGY_POLICY_INVALID CONTRACT \
                "topology_policy $field must not be empty."
        }
    }
    set digest [string tolower [dict get $policy sha256]]
    if {![regexp {^[0-9a-f]{64}$} $digest]} {
        _raise FAIL TOPOLOGY_POLICY_HASH_INVALID IDENTITY \
            {topology_policy sha256 is invalid.}
    }
    if {[dict exists $policy execution_id] &&
        [dict get $policy execution_id] ne $execution_id} {
        _raise FAIL TOPOLOGY_POLICY_EXECUTION_MISMATCH IDENTITY \
            {topology_policy belongs to another execution.}
    }
    dict set policy sha256 $digest
    return $policy
}

proc ::stage1e::base_design::_validate_vlnv_map {vlnv_map} {
    variable required_vlnv_roles
    _require_dictionary $vlnv_map expected_vlnv_map
    if {[lsort -dictionary [dict keys $vlnv_map]] ne
        [lsort -dictionary $required_vlnv_roles]} {
        _raise FAIL VLNV_MAP_INVALID CONTRACT \
            {expected_vlnv_map must declare exactly the required IP roles.}
    }
    set normalized [dict create]
    foreach role $required_vlnv_roles {
        set vlnv [string trim [dict get $vlnv_map $role]]
        if {![regexp {^[^:*?\[\]]+:[^:*?\[\]]+:[^:*?\[\]]+:[^:*?\[\]]+$} \
            $vlnv]} {
            _raise FAIL VLNV_EXPECTATION_INVALID CONTRACT \
                "Expected VLNV must be exact for role $role: $vlnv"
        }
        dict set normalized $role $vlnv
    }
    return $normalized
}

proc ::stage1e::base_design::_validate_properties {properties label} {
    _require_dictionary $properties $label
    foreach property [dict keys $properties] {
        if {[string trim $property] eq {}} {
            _raise FAIL CELL_PROPERTY_INVALID CONTRACT \
                "$label contains an empty property name."
        }
    }
    return $properties
}

proc ::stage1e::base_design::_validate_cell_policy {
    policy
    vlnv_map
} {
    variable required_cell_roles
    _require_keys $policy {
        schema_version
        creation_order
        instances
        board_automation
    } {cell_policy}
    if {[dict get $policy schema_version] ne
        {stage1e-base-cell-policy-v1}} {
        _raise FAIL CELL_POLICY_SCHEMA_UNSUPPORTED CONTRACT \
            {Unsupported cell_policy schema.}
    }
    set creation_order [dict get $policy creation_order]
    if {[lrange $creation_order 0 end] ne \
        [lrange $required_cell_roles 0 end]} {
        _raise FAIL CELL_CREATION_ORDER_INVALID CONTRACT \
            {cell_policy creation_order does not match the reviewed base flow.}
    }
    set instances [dict get $policy instances]
    _require_dictionary $instances {cell_policy instances}
    if {[lsort -dictionary [dict keys $instances]] ne
        [lsort -dictionary $required_cell_roles]} {
        _raise FAIL CELL_POLICY_INVALID CONTRACT \
            {cell_policy must declare exactly the reviewed base cell roles.}
    }

    set expected_role_map [dict create \
        processing_system7 processing_system7 \
        reset reset \
        smartconnect smartconnect \
        protection protection \
        sample_valid_const constant \
        i_ch1_const constant \
        i_ch2_const constant \
        dcm_locked_const constant]
    set names [dict create]
    foreach role $required_cell_roles {
        set instance [dict get $instances $role]
        _require_keys $instance {name vlnv_role properties} \
            "cell_policy instance $role"
        set name [dict get $instance name]
        if {![_is_identifier $name]} {
            _raise FAIL CELL_NAME_INVALID CONTRACT \
                "Invalid cell name for role $role: $name"
        }
        if {[dict exists $names $name]} {
            _raise FAIL CELL_NAME_DUPLICATE CONTRACT \
                "Duplicate configured cell name: $name"
        }
        dict set names $name 1
        set vlnv_role [dict get $instance vlnv_role]
        if {$vlnv_role ne [dict get $expected_role_map $role] ||
            ![dict exists $vlnv_map $vlnv_role]} {
            _raise FAIL CELL_VLNV_ROLE_INVALID CONTRACT \
                "Cell role $role has unexpected VLNV role: $vlnv_role"
        }
        dict set instance properties [_validate_properties \
            [dict get $instance properties] \
            "cell_policy properties for $role"]
        dict set instances $role $instance
    }

    set automation [dict get $policy board_automation]
    _require_keys $automation {
        cell_role
        rule
        config
        expected_external_interfaces
    } {cell_policy board_automation}
    if {[dict get $automation cell_role] ne {processing_system7} ||
        [string trim [dict get $automation rule]] eq {} ||
        [string trim [dict get $automation config]] eq {} ||
        [llength [dict get $automation expected_external_interfaces]] == 0} {
        _raise FAIL BOARD_AUTOMATION_POLICY_INVALID CONTRACT \
            {cell_policy board_automation is incomplete or unexpected.}
    }
    foreach external [dict get $automation expected_external_interfaces] {
        if {![_is_identifier $external]} {
            _raise FAIL EXTERNAL_INTERFACE_NAME_INVALID CONTRACT \
                "Invalid external interface name: $external"
        }
    }
    dict set policy instances $instances
    return $policy
}

proc ::stage1e::base_design::_validate_connection_list {
    connections
    label
    expected_count
} {
    if {[llength $connections] != $expected_count} {
        _raise FAIL CONNECTION_POLICY_INVALID CONTRACT \
            "$label must contain exactly $expected_count connections."
    }
    set normalized {}
    set seen [dict create]
    foreach connection $connections {
        _require_keys $connection {source sink} "$label connection"
        set source [_validate_object_path \
            [dict get $connection source] "$label source"]
        set sink [_validate_object_path \
            [dict get $connection sink] "$label sink"]
        set key [list $source $sink]
        if {[dict exists $seen $key]} {
            _raise FAIL CONNECTION_POLICY_DUPLICATE CONTRACT \
                "$label contains a duplicate connection: $source -> $sink"
        }
        dict set seen $key 1
        lappend normalized [dict create source $source sink $sink]
    }
    return $normalized
}

proc ::stage1e::base_design::_validate_interface_policy {policy} {
    _require_keys $policy {
        schema_version
        required_external_interfaces
        interface_connections
        stimulus_connections
    } {interface_policy}
    if {[dict get $policy schema_version] ne
        {stage1e-base-interface-policy-v1}} {
        _raise FAIL INTERFACE_POLICY_SCHEMA_UNSUPPORTED CONTRACT \
            {Unsupported interface_policy schema.}
    }
    if {[llength [dict get $policy required_external_interfaces]] != 2} {
        _raise FAIL EXTERNAL_INTERFACE_POLICY_INVALID CONTRACT \
            {interface_policy must require exactly DDR and FIXED_IO interfaces.}
    }
    foreach external [dict get $policy required_external_interfaces] {
        if {![_is_identifier $external]} {
            _raise FAIL EXTERNAL_INTERFACE_NAME_INVALID CONTRACT \
                "Invalid required external interface: $external"
        }
    }
    dict set policy interface_connections [_validate_connection_list \
        [dict get $policy interface_connections] \
        {interface_policy interface_connections} 2]
    dict set policy stimulus_connections [_validate_connection_list \
        [dict get $policy stimulus_connections] \
        {interface_policy stimulus_connections} 3]
    return $policy
}

proc ::stage1e::base_design::_validate_clock_policy {policy} {
    _require_keys $policy {
        schema_version
        frequency_hz
        frequency_property
        source
        sinks
    } {clock_policy}
    if {[dict get $policy schema_version] ne
        {stage1e-base-clock-policy-v1}} {
        _raise FAIL CLOCK_POLICY_SCHEMA_UNSUPPORTED CONTRACT \
            {Unsupported clock_policy schema.}
    }
    set frequency [dict get $policy frequency_hz]
    if {![string is integer -strict $frequency] || $frequency <= 0} {
        _raise FAIL CLOCK_FREQUENCY_INVALID CONTRACT \
            {clock_policy frequency_hz must be a positive integer.}
    }
    if {[string trim [dict get $policy frequency_property]] eq {}} {
        _raise FAIL CLOCK_PROPERTY_INVALID CONTRACT \
            {clock_policy frequency_property must not be empty.}
    }
    set source [_validate_object_path \
        [dict get $policy source] {clock_policy source}]
    set sinks [dict get $policy sinks]
    if {[llength $sinks] != 5} {
        _raise FAIL CLOCK_SINK_POLICY_INVALID CONTRACT \
            {clock_policy must contain exactly five reviewed clock sinks.}
    }
    set normalized_sinks {}
    foreach sink $sinks {
        lappend normalized_sinks [_validate_object_path \
            $sink {clock_policy sink}]
    }
    dict set policy source $source
    dict set policy sinks $normalized_sinks
    return $policy
}

proc ::stage1e::base_design::_validate_reset_policy {policy} {
    _require_keys $policy {
        schema_version
        connections
        polarity_checks
    } {reset_policy}
    if {[dict get $policy schema_version] ne
        {stage1e-base-reset-policy-v1}} {
        _raise FAIL RESET_POLICY_SCHEMA_UNSUPPORTED CONTRACT \
            {Unsupported reset_policy schema.}
    }
    dict set policy connections [_validate_connection_list \
        [dict get $policy connections] {reset_policy connections} 4]
    set checks [dict get $policy polarity_checks]
    if {[llength $checks] == 0} {
        _raise FAIL RESET_POLARITY_POLICY_INVALID CONTRACT \
            {reset_policy must contain polarity readback checks.}
    }
    set normalized {}
    foreach check $checks {
        _require_keys $check {path property expected} \
            {reset_policy polarity check}
        set path [_validate_object_path [dict get $check path] \
            {reset polarity path}]
        if {[string trim [dict get $check property]] eq {} ||
            [string trim [dict get $check expected]] eq {}} {
            _raise FAIL RESET_POLARITY_POLICY_INVALID CONTRACT \
                {Reset polarity property and expected value must not be empty.}
        }
        lappend normalized [dict create \
            path $path \
            property [dict get $check property] \
            expected [dict get $check expected]]
    }
    dict set policy polarity_checks $normalized
    return $policy
}

proc ::stage1e::base_design::_wide_integer {value label} {
    if {[catch {expr {wide($value)}} normalized]} {
        _raise FAIL ADDRESS_VALUE_INVALID CONTRACT \
            "$label is not an integer: $value"
    }
    return $normalized
}

proc ::stage1e::base_design::_validate_address_policy {policy} {
    _require_keys $policy {
        schema_version
        address_space
        target_segment
        offset
        range
    } {address_policy}
    if {[dict get $policy schema_version] ne
        {stage1e-base-address-policy-v1}} {
        _raise FAIL ADDRESS_POLICY_SCHEMA_UNSUPPORTED CONTRACT \
            {Unsupported address_policy schema.}
    }
    dict set policy address_space [_validate_object_path \
        [dict get $policy address_space] {address_policy address_space}]
    set segment [string trim [dict get $policy target_segment]]
    if {![regexp {^[A-Za-z_][A-Za-z0-9_]*/[A-Za-z_][A-Za-z0-9_]*/[A-Za-z_][A-Za-z0-9_]*$} \
        $segment]} {
        _raise FAIL ADDRESS_SEGMENT_PATH_INVALID CONTRACT \
            {address_policy target_segment is invalid.}
    }
    dict set policy target_segment $segment
    set offset [_wide_integer [dict get $policy offset] \
        {address_policy offset}]
    set range [_wide_integer [dict get $policy range] \
        {address_policy range}]
    if {$offset < 0 || $range <= 0} {
        _raise FAIL ADDRESS_VALUE_INVALID CONTRACT \
            {Address offset must be nonnegative and range must be positive.}
    }
    dict set policy offset $offset
    dict set policy range $range
    return $policy
}

proc ::stage1e::base_design::_validate_profile_policy {policy} {
    _require_keys $policy {
        schema_version
        profile
        profile_class
        production_authority
        demo_test_only
        valid_value
        functional_adc_stimulus
        valid_source_exists
        ready_consumed
        no_overwrite_when_ready_low
        transaction_pulse_bounded
    } profile_policy
    if {[dict get $policy schema_version] ne
        {stage2d-stimulus-profile-policy-v1}} {
        _raise FAIL PROFILE_POLICY_SCHEMA_UNSUPPORTED CONTRACT \
            {Unsupported Stage 2D stimulus profile policy schema.}
    }
    foreach field {
        production_authority
        demo_test_only
        functional_adc_stimulus
        valid_source_exists
        ready_consumed
        no_overwrite_when_ready_low
        transaction_pulse_bounded
    } {
        if {![string is boolean -strict [dict get $policy $field]]} {
            _raise FAIL PROFILE_POLICY_BOOLEAN_INVALID CONTRACT \
                "profile_policy $field must be boolean."
        }
    }
    if {![dict get $policy production_authority] ||
        [dict get $policy demo_test_only]} {
        _raise FAIL PROFILE_AUTHORITY_INVALID CONTRACT \
            {The production base-design policy cannot be demo/test-only.}
    }
    if {[dict get $policy profile_class] ne {SAFE_INERT} ||
        [dict get $policy profile] ne {SAFE_INERT}} {
        _raise FAIL PROFILE_CLASS_UNSUPPORTED CONTRACT \
            {The current production base design supports only SAFE_INERT.}
    }
    if {![string is integer -strict [dict get $policy valid_value]] ||
        [dict get $policy valid_value] != 0 ||
        [dict get $policy functional_adc_stimulus] ||
        ![dict get $policy valid_source_exists] ||
        [dict get $policy ready_consumed] ||
        [dict get $policy no_overwrite_when_ready_low] ||
        [dict get $policy transaction_pulse_bounded]} {
        _raise FAIL SAFE_INERT_PROFILE_INVALID CONTRACT \
            {SAFE_INERT requires valid=0, an inert source, and no functional transaction claim.}
    }
    return $policy
}

proc ::stage1e::base_design::_validate_ownership {
    context
    execution_id
    workspace_root
} {
    set project [dict get $context project_ownership]
    _require_keys $project {
        owner
        execution_id
        project_handle
        project_path
        identity_verified
        project_identity
    } {project_ownership}
    if {[dict get $project owner] ne {vivado_project} ||
        [dict get $project execution_id] ne $execution_id ||
        [string trim [dict get $project project_handle]] eq {} ||
        ![string is boolean -strict \
            [dict get $project identity_verified]] ||
        ![dict get $project identity_verified]} {
        _raise FAIL PROJECT_OWNER_INVALID OWNERSHIP \
            {Base design requires same-execution verified project ownership.}
    }
    set project_path [dict get $project project_path]
    if {[file pathtype $project_path] ne {absolute}} {
        _raise FAIL PROJECT_PATH_INVALID WORKSPACE \
            {project_ownership project_path must be absolute.}
    }
    set project_path [file normalize $project_path]
    if {![_is_equal_or_descendant $project_path $workspace_root] ||
        ![string equal -nocase [file extension $project_path] {.xpr}]} {
        _raise FAIL PROJECT_PATH_INVALID WORKSPACE \
            {Owned project path must be an execution-contained .xpr path.}
    }
    dict set project project_path $project_path

    set bd [dict get $context bd_ownership]
    _require_keys $bd {
        owner
        execution_id
        project_path
        bd_name
        bd_path
        opened
        identity_verified
        validated
        saved
    } {bd_ownership}
    if {[dict get $bd owner] ne {bd_flow} ||
        [dict get $bd execution_id] ne $execution_id ||
        ![_paths_equal [dict get $bd project_path] $project_path]} {
        _raise FAIL BD_OWNER_INVALID OWNERSHIP \
            {Base design requires same-execution BD ownership for the project.}
    }
    foreach field {opened identity_verified validated saved} {
        if {![string is boolean -strict [dict get $bd $field]]} {
            _raise FAIL BD_OWNER_INVALID OWNERSHIP \
                "bd_ownership state is not boolean: $field"
        }
    }
    if {![dict get $bd opened] ||
        ![dict get $bd identity_verified] ||
        [dict get $bd validated] ||
        [dict get $bd saved]} {
        _raise FAIL BD_OWNER_STATE_INVALID OWNERSHIP \
            {Base design requires an open, verified, unvalidated, unsaved BD.}
    }
    if {![_is_identifier [dict get $bd bd_name]]} {
        _raise FAIL BD_IDENTITY_INVALID IDENTITY \
            {bd_ownership bd_name is invalid.}
    }
    set bd_path [dict get $bd bd_path]
    if {[file pathtype $bd_path] ne {absolute}} {
        _raise FAIL BD_PATH_INVALID WORKSPACE \
            {bd_ownership bd_path must be absolute.}
    }
    set bd_path [file normalize $bd_path]
    if {![_is_equal_or_descendant $bd_path $workspace_root] ||
        ![string equal -nocase [file extension $bd_path] {.bd}] ||
        [file rootname [file tail $bd_path]] ne [dict get $bd bd_name]} {
        _raise FAIL BD_PATH_INVALID WORKSPACE \
            {Owned BD path is not an execution-contained matching .bd path.}
    }
    dict set bd project_path $project_path
    dict set bd bd_path $bd_path
    return [dict create project_ownership $project bd_ownership $bd]
}

proc ::stage1e::base_design::_validate_context {context} {
    variable context_schema_version
    variable operation_name
    variable phase_name
    _require_keys $context {
        context_schema_version
        operation
        phase
        execution_id
        authorization
        source_identity
        environment_identity
        configuration_identity
        workspace_root
        evidence_dir
        project_ownership
        bd_ownership
        profile_policy
        topology_policy
        expected_vlnv_map
        cell_policy
        interface_policy
        clock_policy
        reset_policy
        address_policy
    } {base-design context}

    if {[dict get $context context_schema_version] ne
        $context_schema_version} {
        _raise FAIL CONTEXT_SCHEMA_UNSUPPORTED CONTRACT \
            {Unsupported base-design context schema.}
    }
    if {[dict get $context operation] ne $operation_name ||
        [dict get $context phase] ne $phase_name} {
        _raise FAIL OPERATION_MISMATCH CONTRACT \
            {Base-design operation or phase does not match the interface.}
    }
    set execution_id [dict get $context execution_id]
    if {[string trim $execution_id] eq {}} {
        _raise FAIL EXECUTION_ID_INVALID CONTRACT \
            {Base-design execution_id must not be empty.}
    }
    _validate_authorization [dict get $context authorization] $execution_id

    set source_identity [_validate_identity \
        [dict get $context source_identity] source_identity $execution_id]
    set environment_identity [_validate_identity \
        [dict get $context environment_identity] \
        environment_identity $execution_id]
    set configuration_identity [_validate_identity \
        [dict get $context configuration_identity] \
        configuration_identity $execution_id]

    foreach path_field {workspace_root evidence_dir} {
        set path [dict get $context $path_field]
        if {[file pathtype $path] ne {absolute}} {
            _raise FAIL PATH_NOT_ABSOLUTE WORKSPACE \
                "Base-design $path_field must be absolute."
        }
        dict set context $path_field [file normalize $path]
    }
    set workspace_root [dict get $context workspace_root]
    set evidence_dir [dict get $context evidence_dir]
    if {![file isdirectory $workspace_root] ||
        ![file isdirectory $evidence_dir] ||
        ![_is_equal_or_descendant $evidence_dir $workspace_root]} {
        _raise FAIL WORKSPACE_CONTEXT_INVALID WORKSPACE \
            {Base-design workspace and evidence directories are unavailable or inconsistent.}
    }

    set ownership [_validate_ownership \
        $context $execution_id $workspace_root]
    set profile_policy [_validate_profile_policy \
        [dict get $context profile_policy]]
    set topology_policy [_validate_topology_policy \
        [dict get $context topology_policy] $execution_id]
    set vlnv_map [_validate_vlnv_map \
        [dict get $context expected_vlnv_map]]
    set cell_policy [_validate_cell_policy \
        [dict get $context cell_policy] $vlnv_map]
    set configured_valid [dict get $cell_policy instances \
        sample_valid_const properties CONFIG.CONST_VAL]
    if {![_values_equal $configured_valid \
        [dict get $profile_policy valid_value]]} {
        _raise FAIL PROFILE_VALID_VALUE_MISMATCH CONTRACT \
            {sample_valid_const differs from the declared profile policy.}
    }
    set interface_policy [_validate_interface_policy \
        [dict get $context interface_policy]]
    set clock_policy [_validate_clock_policy \
        [dict get $context clock_policy]]
    set reset_policy [_validate_reset_policy \
        [dict get $context reset_policy]]
    set address_policy [_validate_address_policy \
        [dict get $context address_policy]]

    return [dict create \
        context $context \
        execution_id $execution_id \
        source_identity $source_identity \
        environment_identity $environment_identity \
        configuration_identity $configuration_identity \
        workspace_root $workspace_root \
        evidence_dir $evidence_dir \
        project_ownership [dict get $ownership project_ownership] \
        bd_ownership [dict get $ownership bd_ownership] \
        profile_policy $profile_policy \
        topology_policy $topology_policy \
        expected_vlnv_map $vlnv_map \
        cell_policy $cell_policy \
        interface_policy $interface_policy \
        clock_policy $clock_policy \
        reset_policy $reset_policy \
        address_policy $address_policy]
}

proc ::stage1e::base_design::_require_single_object {
    objects
    label
} {
    if {[llength $objects] != 1} {
        _raise FAIL VIVADO_OBJECT_CARDINALITY VIVADO \
            "$label must resolve to exactly one object; found [llength $objects]."
    }
    return [lindex $objects 0]
}

proc ::stage1e::base_design::_require_cell {name} {
    return [_require_single_object [_invoke get_bd_cells -quiet $name] \
        "BD cell $name"]
}

proc ::stage1e::base_design::_require_pin {path} {
    return [_require_single_object [_invoke get_bd_pins -quiet $path] \
        "BD pin $path"]
}

proc ::stage1e::base_design::_require_intf_pin {path} {
    return [_require_single_object [_invoke get_bd_intf_pins -quiet $path] \
        "BD interface pin $path"]
}

proc ::stage1e::base_design::_require_addr_space {path} {
    return [_require_single_object [_invoke get_bd_addr_spaces -quiet $path] \
        "BD address space $path"]
}

proc ::stage1e::base_design::_require_addr_segment {path} {
    return [_require_single_object [_invoke get_bd_addr_segs -quiet $path] \
        "BD address segment $path"]
}

proc ::stage1e::base_design::_values_equal {actual expected} {
    if {![catch {expr {wide($actual)}} actual_number] &&
        ![catch {expr {wide($expected)}} expected_number]} {
        return [expr {$actual_number == $expected_number}]
    }
    return [expr {$actual eq $expected}]
}

proc ::stage1e::base_design::_address_values_equal {actual expected} {
    set numbers {}
    foreach value [list $actual $expected] {
        set normalized [string trim $value]
        if {[regexp -nocase {^([0-9]+)([KMG])$} \
            $normalized -> magnitude suffix]} {
            switch -nocase -- $suffix {
                K { set multiplier 1024 }
                M { set multiplier [expr {1024 * 1024}] }
                G { set multiplier [expr {1024 * 1024 * 1024}] }
            }
            lappend numbers \
                [expr {wide($magnitude) * wide($multiplier)}]
        } elseif {![catch {expr {wide($normalized)}} number]} {
            lappend numbers $number
        } else {
            return 0
        }
    }
    return [expr {[lindex $numbers 0] == [lindex $numbers 1]}]
}

proc ::stage1e::base_design::_assert_property {
    object
    property
    expected
    label
} {
    set actual [_invoke get_property $property $object]
    if {![_values_equal $actual $expected]} {
        _raise FAIL PROPERTY_READBACK_MISMATCH IDENTITY \
            "$label $property mismatch: actual=$actual expected=$expected"
    }
    return $actual
}

proc ::stage1e::base_design::_verify_live_ownership {validated} {
    set project [dict get $validated project_ownership]
    set expected_project [dict get $project project_handle]
    set current_project [_invoke current_project]
    if {$current_project ne $expected_project} {
        _raise FAIL PROJECT_OWNER_MISMATCH OWNERSHIP \
            "Current project does not match ownership: actual=$current_project expected=$expected_project"
    }
    set current_bd [_invoke current_bd_design]
    set expected_bd [dict get $validated bd_ownership bd_name]
    if {$current_bd ne $expected_bd} {
        _raise FAIL BD_OWNER_MISMATCH OWNERSHIP \
            "Current BD does not match ownership: actual=$current_bd expected=$expected_bd"
    }

    set project_identity [dict get $project project_identity]
    foreach key {project_name project_directory part board_part} {
        if {![dict exists $project_identity $key]} {
            _raise FAIL PROJECT_IDENTITY_INCOMPLETE IDENTITY \
                "project_identity is missing: $key"
        }
    }
    set readback [dict create \
        project_name [_invoke get_property NAME $current_project] \
        project_directory [file normalize \
            [_invoke get_property DIRECTORY $current_project]] \
        part [_invoke get_property PART $current_project] \
        board_part [_invoke get_property BOARD_PART $current_project]]
    foreach key {project_name part board_part} {
        if {[dict get $readback $key] ne [dict get $project_identity $key]} {
            _raise FAIL PROJECT_IDENTITY_MISMATCH IDENTITY \
                "Current project $key does not match ownership."
        }
    }
    if {![_paths_equal [dict get $readback project_directory] \
        [dict get $project_identity project_directory]]} {
        _raise FAIL PROJECT_IDENTITY_MISMATCH IDENTITY \
            {Current project directory does not match ownership.}
    }
    foreach key {part board_part} {
        if {![dict exists [dict get $validated environment_identity] $key] ||
            [dict get $readback $key] ne
                [dict get $validated environment_identity $key]} {
            _raise FAIL ENVIRONMENT_IDENTITY_MISMATCH IDENTITY \
                "Current project does not match environment $key."
        }
    }
    dict set readback bd_name $current_bd
    return $readback
}

proc ::stage1e::base_design::_assert_empty_bd {} {
    foreach command {
        get_bd_cells
        get_bd_ports
        get_bd_intf_ports
        get_bd_nets
        get_bd_intf_nets
        get_bd_addr_segs
    } {
        set objects [_invoke $command -quiet]
        if {[llength $objects] != 0} {
            _raise FAIL BD_NOT_EMPTY OWNERSHIP \
                "Base topology requires an empty BD; $command found objects."
        }
    }
}

proc ::stage1e::base_design::_resolve_vlnvs {vlnv_map} {
    set resolved [dict create]
    foreach role [dict keys $vlnv_map] {
        set expected [dict get $vlnv_map $role]
        set definition [_require_single_object \
            [_invoke get_ipdefs -all -quiet $expected] \
            "IP definition for $role"]
        set actual [_invoke get_property VLNV $definition]
        if {$actual ne $expected} {
            _raise FAIL VLNV_MISMATCH IDENTITY \
                "Resolved VLNV mismatch for $role: actual=$actual expected=$expected"
        }
        dict set resolved $role [dict create \
            expected $expected \
            actual $actual \
            definition $definition]
    }
    return $resolved
}

proc ::stage1e::base_design::_create_cells {
    cell_policy
    resolved_vlnvs
} {
    set instances [dict get $cell_policy instances]
    set cells [dict create]
    foreach role [dict get $cell_policy creation_order] {
        set specification [dict get $instances $role]
        set vlnv_role [dict get $specification vlnv_role]
        set vlnv [dict get $resolved_vlnvs $vlnv_role actual]
        set name [dict get $specification name]
        set cell [_invoke create_bd_cell -type ip -vlnv $vlnv $name]
        set readback_cell [_require_cell $name]
        if {$cell ne $readback_cell} {
            _raise FAIL CELL_HANDLE_MISMATCH IDENTITY \
                "Created cell handle mismatch for $name."
        }
        set actual_vlnv [_invoke get_property VLNV $cell]
        if {$actual_vlnv ne $vlnv} {
            _raise FAIL CELL_VLNV_MISMATCH IDENTITY \
                "Created cell VLNV mismatch for $name: actual=$actual_vlnv expected=$vlnv"
        }
        dict set cells $role $cell
    }
    return $cells
}

proc ::stage1e::base_design::_apply_board_automation {
    cell_policy
    cells
} {
    set policy [dict get $cell_policy board_automation]
    set cell [dict get $cells [dict get $policy cell_role]]
    _invoke apply_bd_automation \
        -rule [dict get $policy rule] \
        -config [dict get $policy config] \
        $cell
}

proc ::stage1e::base_design::_configure_cells {
    cell_policy
    cells
} {
    set instances [dict get $cell_policy instances]
    foreach role [dict get $cell_policy creation_order] {
        set properties [dict get $instances $role properties]
        set cell [dict get $cells $role]
        if {[dict size $properties] != 0} {
            _invoke set_property -dict $properties $cell
        }
    }
}

proc ::stage1e::base_design::_verify_external_interfaces {
    external_names
} {
    set readback [dict create]
    foreach name $external_names {
        set ports [_invoke get_bd_ports -quiet $name]
        set interfaces [_invoke get_bd_intf_ports -quiet $name]
        if {[llength $ports] + [llength $interfaces] != 1} {
            _raise FAIL EXTERNAL_INTERFACE_MISMATCH IDENTITY \
                "External interface $name did not resolve uniquely."
        }
        if {[llength $interfaces] == 1} {
            dict set readback $name [dict create \
                type interface object [lindex $interfaces 0]]
        } else {
            dict set readback $name [dict create \
                type port object [lindex $ports 0]]
        }
    }
    return $readback
}

proc ::stage1e::base_design::_connect_interface {connection} {
    set source_path [dict get $connection source]
    set sink_path [dict get $connection sink]
    set source [_require_intf_pin $source_path]
    set sink [_require_intf_pin $sink_path]
    _invoke connect_bd_intf_net $source $sink
}

proc ::stage1e::base_design::_connect_scalar {connection} {
    set source_path [dict get $connection source]
    set sink_path [dict get $connection sink]
    set source [_require_pin $source_path]
    set sink [_require_pin $sink_path]
    _invoke connect_bd_net $source $sink
}

proc ::stage1e::base_design::_interface_connection_readback {connection} {
    set source [_require_intf_pin [dict get $connection source]]
    set sink [_require_intf_pin [dict get $connection sink]]
    set source_nets [_invoke get_bd_intf_nets -quiet -of_objects $source]
    set sink_nets [_invoke get_bd_intf_nets -quiet -of_objects $sink]
    if {[llength $source_nets] != 1 || $source_nets ne $sink_nets} {
        _raise FAIL INTERFACE_CONNECTION_MISMATCH IDENTITY \
            "Interface connection readback mismatch: [dict get $connection source] -> [dict get $connection sink]"
    }
    set net [lindex $source_nets 0]
    return [dict merge $connection [dict create \
        net [_invoke get_property NAME $net]]]
}

proc ::stage1e::base_design::_scalar_connection_readback {connection} {
    set source [_require_pin [dict get $connection source]]
    set sink [_require_pin [dict get $connection sink]]
    set source_nets [_invoke get_bd_nets -quiet -of_objects $source]
    set sink_nets [_invoke get_bd_nets -quiet -of_objects $sink]
    if {[llength $source_nets] != 1 || $source_nets ne $sink_nets} {
        _raise FAIL SCALAR_CONNECTION_MISMATCH IDENTITY \
            "Scalar connection readback mismatch: [dict get $connection source] -> [dict get $connection sink]"
    }
    set net [lindex $source_nets 0]
    return [dict merge $connection [dict create \
        net [_invoke get_property NAME $net]]]
}

proc ::stage1e::base_design::_cell_readback {
    cell_policy
    resolved_vlnvs
    cells
} {
    set readback [dict create]
    set instances [dict get $cell_policy instances]
    foreach role [dict get $cell_policy creation_order] {
        set specification [dict get $instances $role]
        set name [dict get $specification name]
        set cell [_require_cell $name]
        set expected_vlnv [dict get $resolved_vlnvs \
            [dict get $specification vlnv_role] actual]
        set actual_vlnv [_assert_property \
            $cell VLNV $expected_vlnv "BD cell $name"]
        set property_readback [dict create]
        foreach property [dict keys [dict get $specification properties]] {
            dict set property_readback $property [_assert_property \
                $cell $property \
                [dict get $specification properties $property] \
                "BD cell $name"]
        }
        dict set readback $role [dict create \
            name $name \
            object $cell \
            vlnv $actual_vlnv \
            properties $property_readback]
    }
    return $readback
}

proc ::stage1e::base_design::_apply_and_read_clock {policy} {
    set source_path [dict get $policy source]
    foreach sink_path [dict get $policy sinks] {
        _connect_scalar [dict create source $source_path sink $sink_path]
    }
    set source [_require_pin $source_path]
    set actual_frequency [_assert_property \
        $source [dict get $policy frequency_property] \
        [dict get $policy frequency_hz] {Base clock source}]
    set connections {}
    foreach sink_path [dict get $policy sinks] {
        lappend connections [_scalar_connection_readback [dict create \
            source $source_path sink $sink_path]]
    }
    return [dict create \
        source $source_path \
        frequency_hz $actual_frequency \
        connections $connections]
}

proc ::stage1e::base_design::_apply_and_read_resets {policy} {
    foreach connection [dict get $policy connections] {
        _connect_scalar $connection
    }
    set connections {}
    foreach connection [dict get $policy connections] {
        lappend connections [_scalar_connection_readback $connection]
    }
    set polarities {}
    foreach check [dict get $policy polarity_checks] {
        set pin [_require_pin [dict get $check path]]
        set actual [_assert_property \
            $pin [dict get $check property] [dict get $check expected] \
            "Reset pin [dict get $check path]"]
        lappend polarities [dict merge $check [dict create actual $actual]]
    }
    return [dict create \
        connections $connections \
        polarity_readback $polarities]
}

proc ::stage1e::base_design::_apply_and_read_address {policy} {
    set address_space [_require_addr_space [dict get $policy address_space]]
    set target_segment_path [dict get $policy target_segment]
    set target_segment [_require_addr_segment $target_segment_path]
    _invoke assign_bd_address \
        -target_address_space $address_space \
        -offset [dict get $policy offset] \
        -range [dict get $policy range] \
        $target_segment

    set target_cell [lindex [split $target_segment_path /] 0]
    set mapped_pattern [format {*/SEG_%s_*} $target_cell]
    variable address_readback_max_attempts
    set mapped_segment {}
    set actual_offset {}
    set actual_range {}
    for {set attempt 1} {$attempt <= $address_readback_max_attempts} \
        {incr attempt} {
        set matches {}
        foreach candidate [_invoke get_bd_addr_segs \
            -quiet -of_objects $address_space] {
            if {[string match $mapped_pattern $candidate]} {
                lappend matches $candidate
            }
        }
        if {[llength $matches] > 1} {
            _raise FAIL VIVADO_OBJECT_CARDINALITY VIVADO \
                "Mapped protection address segment must resolve to exactly one object; found [llength $matches]."
        }
        if {[llength $matches] == 0} {
            continue
        }

        set mapped_segment [lindex $matches 0]
        set actual_offset [_invoke get_property OFFSET $mapped_segment]
        set actual_range [_invoke get_property RANGE $mapped_segment]
        if {[string trim $actual_offset] eq {} ||
            [string trim $actual_range] eq {}} {
            continue
        }
        break
    }

    if {$mapped_segment eq {}} {
        _raise FAIL VIVADO_OBJECT_CARDINALITY VIVADO \
            {Mapped protection address segment must resolve to exactly one object; found 0.}
    }
    if {[string trim $actual_offset] eq {}} {
        _raise FAIL PROPERTY_READBACK_MISMATCH IDENTITY \
            {Protection address segment OFFSET is empty after address assignment.}
    }
    if {[string trim $actual_range] eq {}} {
        _raise FAIL PROPERTY_READBACK_MISMATCH IDENTITY \
            {Protection address segment RANGE is empty after address assignment.}
    }
    if {![_address_values_equal $actual_offset [dict get $policy offset]]} {
        _raise FAIL PROPERTY_READBACK_MISMATCH IDENTITY \
            "Protection address segment OFFSET mismatch: actual=$actual_offset expected=[dict get $policy offset]"
    }
    if {![_address_values_equal $actual_range [dict get $policy range]]} {
        _raise FAIL PROPERTY_READBACK_MISMATCH IDENTITY \
            "Protection address segment RANGE mismatch: actual=$actual_range expected=[dict get $policy range]"
    }
    return [dict create \
        address_space [dict get $policy address_space] \
        target_segment $target_segment_path \
        assigned_segment $mapped_segment \
        offset $actual_offset \
        range $actual_range]
}

proc ::stage1e::base_design::_execute {context validated} {
    set ownership_records [dict create \
        project_ownership [dict get $validated project_ownership] \
        bd_ownership [dict get $validated bd_ownership]]
    set consumed_identities [dict create \
        source_identity [dict get $validated source_identity] \
        environment_identity [dict get $validated environment_identity] \
        configuration_identity [dict get $validated configuration_identity] \
        project_ownership [dict get $validated project_ownership] \
        bd_ownership [dict get $validated bd_ownership] \
        profile_policy [dict get $validated profile_policy] \
        topology_policy [dict get $validated topology_policy] \
        expected_vlnv_map [dict get $validated expected_vlnv_map] \
        cell_policy [dict get $validated cell_policy] \
        interface_policy [dict get $validated interface_policy] \
        clock_policy [dict get $validated clock_policy] \
        reset_policy [dict get $validated reset_policy] \
        address_policy [dict get $validated address_policy]]
    set vivado_invoked 1
    set mutation_started 0

    set execution_status [catch {
        set lifecycle_readback [_verify_live_ownership $validated]
        _assert_empty_bd
        set resolved_vlnvs [_resolve_vlnvs \
            [dict get $validated expected_vlnv_map]]

        set mutation_started 1
        set cells [_create_cells \
            [dict get $validated cell_policy] $resolved_vlnvs]
        _apply_board_automation [dict get $validated cell_policy] $cells
        _configure_cells [dict get $validated cell_policy] $cells

        set automation [dict get \
            $validated cell_policy board_automation]
        set external_readback [_verify_external_interfaces \
            [dict get $automation expected_external_interfaces]]

        set interface_policy [dict get $validated interface_policy]
        foreach connection [dict get \
            $interface_policy interface_connections] {
            _connect_interface $connection
        }
        foreach connection [dict get \
            $interface_policy stimulus_connections] {
            _connect_scalar $connection
        }

        set clock_readback [_apply_and_read_clock \
            [dict get $validated clock_policy]]
        set reset_readback [_apply_and_read_resets \
            [dict get $validated reset_policy]]
        set address_readback [_apply_and_read_address \
            [dict get $validated address_policy]]

        set cell_readback [_cell_readback \
            [dict get $validated cell_policy] $resolved_vlnvs $cells]
        set interface_readback {}
        foreach connection [dict get \
            $interface_policy interface_connections] {
            lappend interface_readback \
                [_interface_connection_readback $connection]
        }
        set stimulus_readback {}
        foreach connection [dict get \
            $interface_policy stimulus_connections] {
            lappend stimulus_readback \
                [_scalar_connection_readback $connection]
        }

        set topology_readback [dict create \
            lifecycle $lifecycle_readback \
            resolved_vlnvs $resolved_vlnvs \
            cells $cell_readback \
            external_interfaces $external_readback \
            interface_connections $interface_readback \
            stimulus_connections $stimulus_readback \
            clock $clock_readback \
            reset $reset_readback \
            address $address_readback]
        set policy_bundle [list \
            [dict get $validated profile_policy] \
            [dict get $validated topology_policy] \
            [dict get $validated expected_vlnv_map] \
            [dict get $validated cell_policy] \
            [dict get $validated interface_policy] \
            [dict get $validated clock_policy] \
            [dict get $validated reset_policy] \
            [dict get $validated address_policy]]
        set policy_bundle_sha256 \
            [::stage1d::source_check::sha256_text $policy_bundle]
        set readback_sha256 [::stage1d::source_check::sha256_text \
            $topology_readback]
        set identity_sha256 [::stage1d::source_check::sha256_text [list \
            [dict get $validated execution_id] \
            [dict get $validated bd_ownership bd_path] \
            [dict get $validated topology_policy sha256] \
            $policy_bundle_sha256 \
            $readback_sha256]]
        set base_design_identity [dict create \
            schema_version stage1e-base-design-identity-v1 \
            producer_operation stage1e::base_design::apply \
            execution_id [dict get $validated execution_id] \
            project_path [dict get $validated project_ownership project_path] \
            bd_name [dict get $validated bd_ownership bd_name] \
            bd_path [dict get $validated bd_ownership bd_path] \
            topology_policy_sha256 \
                [dict get $validated topology_policy sha256] \
            policy_bundle_sha256 $policy_bundle_sha256 \
            readback_sha256 $readback_sha256 \
            identity_sha256 $identity_sha256]
        set evidence_references [dict create \
            lifecycle_readback $lifecycle_readback \
            topology_readback $topology_readback \
            policy_bundle_sha256 $policy_bundle_sha256 \
            readback_sha256 $readback_sha256]
    } execution_error execution_options]

    if {$execution_status != 0} {
        set decoded [_decode_error $execution_error $execution_options \
            BASE_DESIGN_APPLY_FAILED VIVADO]
        if {$mutation_started} {
            set cleanup_result [_cleanup_result \
                1 0 PROJECT_CLEANUP_REQUIRED]
        } else {
            set cleanup_result [_cleanup_result 0 1 NOT_REQUIRED]
        }
        return [_result \
            [dict get $decoded status] $context $consumed_identities \
            {} $ownership_records {} {} \
            [list [_error_record $decoded]] $cleanup_result $vivado_invoked]
    }

    return [_result PASS $context $consumed_identities \
        [dict create base_design_identity $base_design_identity] \
        $ownership_records $evidence_references {} {} \
        [_cleanup_result 0 1 NOT_REQUIRED] $vivado_invoked]
}

proc ::stage1e::base_design::apply {context} {
    set validation_status [catch {
        _validate_context $context
    } validated validation_options]
    if {$validation_status != 0} {
        set decoded [_decode_error $validated $validation_options \
            BASE_DESIGN_CONTEXT_INVALID CONTRACT]
        return [_result \
            [dict get $decoded status] $context {} {} {} {} {} \
            [list [_error_record $decoded]] \
            [_cleanup_result 0 1 NOT_REQUIRED] 0]
    }
    return [_execute $context $validated]
}
