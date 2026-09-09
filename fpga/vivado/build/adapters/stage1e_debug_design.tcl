# Stage 1E WP-B debug-topology adapter.
#
# This module is definition-only when sourced.  It consumes the project and
# block-design ownership established by the lifecycle adapters, applies one
# controller-authorized System ILA topology, and returns those ownership
# records unchanged.  It does not own lifecycle, validation/save, Stage 1D
# mutation, build execution, or FPGA artifact generation.

namespace eval ::stage1e::debug_design {
    variable context_schema_version stage1e-debug-design-context-v1
    variable result_schema_version stage1e-debug-design-result-v1
    variable operation_name stage1e::debug_design::apply
    variable phase_name BD_GENERATION
}

namespace eval ::stage1e::debug_design::backend {}

# Reuse the controlled source-verification SHA-256 implementation.  Sourcing
# this dependency defines procedures only and performs no Vivado operation.
if {[llength [info commands ::stage1d::source_check::sha256_text]] == 0} {
    set ::stage1e::debug_design::_source_check_path [file normalize \
        [file join [file dirname [info script]] .. lib source_check.tcl]]
    source $::stage1e::debug_design::_source_check_path
    unset ::stage1e::debug_design::_source_check_path
}

# The backend is the only command boundary.  Source-only tests replace this
# one procedure with an isolated in-memory Vivado model.
proc ::stage1e::debug_design::backend::invoke {command arguments} {
    return [uplevel #0 [list $command {*}$arguments]]
}

proc ::stage1e::debug_design::_invoke {command args} {
    return [::stage1e::debug_design::backend::invoke $command $args]
}

proc ::stage1e::debug_design::_get_or_default {
    dictionary
    key
    default_value
} {
    if {![catch {dict size $dictionary}] && [dict exists $dictionary $key]} {
        return [dict get $dictionary $key]
    }
    return $default_value
}

proc ::stage1e::debug_design::_raise {
    status
    error_code
    error_class
    message
} {
    return -code error -errorcode [list \
        STAGE1E DEBUG_DESIGN $status $error_code $error_class] $message
}

proc ::stage1e::debug_design::_decode_error {
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
        [lrange $tcl_error_code 0 1] eq {STAGE1E DEBUG_DESIGN}} {
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

proc ::stage1e::debug_design::_error_record {decoded} {
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

proc ::stage1e::debug_design::_cleanup_result {
    required
    completed
    disposition
} {
    return [dict create \
        owner stage1e::debug_design \
        required $required \
        attempted 0 \
        completed $completed \
        disposition $disposition \
        errors {}]
}

proc ::stage1e::debug_design::_context_execution_id {context} {
    if {![catch {dict size $context}] && [dict exists $context execution_id]} {
        return [dict get $context execution_id]
    }
    return {}
}

proc ::stage1e::debug_design::_result {
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
    topology_mutated
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
        topology_mutated $topology_mutated \
        lifecycle_ownership_created 0 \
        project_opened 0 \
        project_created 0 \
        bd_created 0 \
        bd_validated 0 \
        bd_saved 0 \
        controlled_mutation_invoked 0 \
        mutation_invoked 0 \
        synthesis_performed 0 \
        implementation_performed 0 \
        artifacts_generated 0 \
        artifact_generation_performed 0 \
        artifact_publication_performed 0]
}

proc ::stage1e::debug_design::_require_dictionary {value label} {
    if {[catch {dict size $value} dictionary_error]} {
        _raise FAIL CONTEXT_FIELD_INVALID CONTRACT \
            "$label must be a dictionary: $dictionary_error"
    }
}

proc ::stage1e::debug_design::_require_keys {
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

proc ::stage1e::debug_design::_canonical_components {path} {
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

proc ::stage1e::debug_design::_paths_equal {first_path second_path} {
    return [expr {
        [_canonical_components $first_path] eq
            [_canonical_components $second_path]
    }]
}

proc ::stage1e::debug_design::_is_equal_or_descendant {
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

proc ::stage1e::debug_design::_is_identifier {value} {
    return [regexp {^[A-Za-z_][A-Za-z0-9_]*$} $value]
}

proc ::stage1e::debug_design::_validate_object_path {path label} {
    set value [string trim $path]
    if {![regexp {^[A-Za-z_][A-Za-z0-9_]*/[A-Za-z_][A-Za-z0-9_]*$} \
        $value]} {
        _raise FAIL POLICY_OBJECT_PATH_INVALID CONTRACT \
            "$label is not a BD object path: $path"
    }
    return $value
}

proc ::stage1e::debug_design::_validate_hash {value label} {
    set digest [string tolower [string trim $value]]
    if {![regexp {^[0-9a-f]{64}$} $digest]} {
        _raise FAIL IDENTITY_HASH_INVALID IDENTITY \
            "$label must be a SHA-256 hexadecimal digest."
    }
    return $digest
}

proc ::stage1e::debug_design::_validate_authorization {
    authorization
    execution_id
} {
    variable operation_name
    variable phase_name
    _require_keys $authorization {
        status
        authority
        execution_id
        operation
        phase
        capability
        capability_enabled
    } authorization
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
            {Controller authorization does not permit debug topology.}
    }
}

proc ::stage1e::debug_design::_validate_identity {
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

proc ::stage1e::debug_design::_validate_ownership {
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
    } project_ownership
    if {[dict get $project owner] ne {vivado_project} ||
        [dict get $project execution_id] ne $execution_id ||
        [string trim [dict get $project project_handle]] eq {} ||
        ![string is boolean -strict [dict get $project identity_verified]] ||
        ![dict get $project identity_verified]} {
        _raise FAIL PROJECT_OWNER_INVALID OWNERSHIP \
            {Debug topology requires same-execution verified project ownership.}
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
    set project_identity [dict get $project project_identity]
    _require_keys $project_identity {
        project_name
        project_directory
        part
        board_part
    } {project_ownership project_identity}
    if {![_paths_equal [dict get $project_identity project_path] \
        $project_path] ||
        ![_paths_equal [dict get $project_identity project_directory] \
            [file dirname $project_path]]} {
        _raise FAIL PROJECT_IDENTITY_MISMATCH IDENTITY \
            {Project ownership identity does not match its path.}
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
    } bd_ownership
    if {[dict get $bd owner] ne {bd_flow} ||
        [dict get $bd execution_id] ne $execution_id ||
        ![_paths_equal [dict get $bd project_path] $project_path]} {
        _raise FAIL BD_OWNER_INVALID OWNERSHIP \
            {Debug topology requires same-execution BD ownership.}
    }
    foreach field {opened identity_verified validated saved} {
        if {![string is boolean -strict [dict get $bd $field]]} {
            _raise FAIL BD_OWNER_INVALID OWNERSHIP \
                "bd_ownership state is not boolean: $field"
        }
    }
    if {![dict get $bd opened] || ![dict get $bd identity_verified] ||
        [dict get $bd validated] || [dict get $bd saved]} {
        _raise FAIL BD_OWNER_STATE_INVALID OWNERSHIP \
            {Debug topology requires an open, verified, unvalidated, unsaved BD.}
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
            {Owned BD path must be an execution-contained matching .bd path.}
    }
    dict set bd project_path $project_path
    dict set bd bd_path $bd_path
    return [dict create project_ownership $project bd_ownership $bd]
}

proc ::stage1e::debug_design::_validate_base_identity {
    identity
    execution_id
    project_ownership
    bd_ownership
} {
    _require_keys $identity {
        schema_version
        producer_operation
        execution_id
        project_path
        bd_name
        bd_path
        topology_policy_sha256
        policy_bundle_sha256
        readback_sha256
        identity_sha256
    } base_design_identity
    if {[dict get $identity schema_version] ne
        {stage1e-base-design-identity-v1} ||
        [dict get $identity producer_operation] ne
            {stage1e::base_design::apply} ||
        [dict get $identity execution_id] ne $execution_id ||
        ![_paths_equal [dict get $identity project_path] \
            [dict get $project_ownership project_path]] ||
        [dict get $identity bd_name] ne [dict get $bd_ownership bd_name] ||
        ![_paths_equal [dict get $identity bd_path] \
            [dict get $bd_ownership bd_path]]} {
        _raise FAIL BASE_DESIGN_IDENTITY_MISMATCH IDENTITY \
            {base_design_identity is not bound to the owned same-execution BD.}
    }
    foreach field {
        topology_policy_sha256
        policy_bundle_sha256
        readback_sha256
        identity_sha256
    } {
        dict set identity $field [_validate_hash \
            [dict get $identity $field] "base_design_identity $field"]
    }
    if {[dict exists $identity status] && [dict get $identity status] ne {PASS}} {
        _raise FAIL BASE_DESIGN_NOT_ACCEPTED IDENTITY \
            {base_design_identity is not an accepted PASS identity.}
    }
    return $identity
}

proc ::stage1e::debug_design::_validate_debug_policy {policy} {
    _require_keys $policy {
        schema_version
        policy_id
        source_reference
        sha256
        enabled
        clock_source
        reset_source
        ready_observation_clock_domain
        adc_src_clock_domain
        destination_clock_domain
        clocks_identical_in_current_profile
        acceptance_evidence_scope
        distinct_clock_debug_policy
        direct_async_ready_observation_as_cdc_proof
    } debug_policy
    if {[dict get $policy schema_version] ne
        {stage1e-debug-policy-reference-v1}} {
        _raise FAIL DEBUG_POLICY_SCHEMA_UNSUPPORTED CONTRACT \
            {Unsupported debug_policy schema.}
    }
    if {![string is boolean -strict [dict get $policy enabled]]} {
        _raise FAIL DEBUG_POLICY_ENABLED_INVALID CONTRACT \
            {debug_policy enabled must be boolean.}
    }
    if {![dict get $policy enabled]} {
        _raise BLOCKED DEBUG_DISABLED AUTHORIZATION \
            {Debug topology is disabled by policy.}
    }
    foreach field {policy_id source_reference} {
        if {[string trim [dict get $policy $field]] eq {}} {
            _raise FAIL DEBUG_POLICY_INVALID CONTRACT \
                "debug_policy $field must not be empty."
        }
    }
    dict set policy sha256 [_validate_hash [dict get $policy sha256] \
        {debug_policy sha256}]
    dict set policy clock_source [_validate_object_path \
        [dict get $policy clock_source] {debug_policy clock_source}]
    dict set policy reset_source [_validate_object_path \
        [dict get $policy reset_source] {debug_policy reset_source}]
    if {[dict get $policy clock_source] ne
            {processing_system7_0/FCLK_CLK0} ||
        [dict get $policy ready_observation_clock_domain] ne {ACLK} ||
        [dict get $policy adc_src_clock_domain] ne {FCLK_CLK0} ||
        [dict get $policy destination_clock_domain] ne {FCLK_CLK0} ||
        ![string is boolean -strict \
            [dict get $policy clocks_identical_in_current_profile]] ||
        ![dict get $policy clocks_identical_in_current_profile] ||
        [dict get $policy acceptance_evidence_scope] ne
            {CURRENT_IDENTICAL_CLOCKS_ONLY} ||
        [dict get $policy distinct_clock_debug_policy] ne
            {SOURCE_DOMAIN_ILA_OR_SYNCHRONIZED_OBSERVATION} ||
        ![string is boolean -strict [dict get $policy \
            direct_async_ready_observation_as_cdc_proof]] ||
        [dict get $policy direct_async_ready_observation_as_cdc_proof]} {
        _raise FAIL READY_OBSERVATION_BOUNDARY_INVALID CONTRACT \
            {ACLK ready observation is valid only for the current identical-clock profile; distinct clocks require source-domain ILA or synchronized observation.}
    }
    if {[dict exists $policy reset_polarity] &&
        [string trim [dict get $policy reset_polarity]] eq {}} {
        _raise FAIL DEBUG_POLICY_INVALID CONTRACT \
            {debug_policy reset_polarity must not be empty.}
    }
    return $policy
}

proc ::stage1e::debug_design::_validate_system_ila_identity {identity} {
    _require_keys $identity {
        schema_version
        cell_name
        vlnv
        properties
    } system_ila_identity
    if {[dict get $identity schema_version] ne
        {stage1e-system-ila-identity-v1}} {
        _raise FAIL SYSTEM_ILA_SCHEMA_UNSUPPORTED CONTRACT \
            {Unsupported system_ila_identity schema.}
    }
    set name [dict get $identity cell_name]
    if {![_is_identifier $name]} {
        _raise FAIL SYSTEM_ILA_NAME_INVALID IDENTITY \
            {System ILA cell name is invalid.}
    }
    set vlnv [string trim [dict get $identity vlnv]]
    if {![regexp {^[^:*?\[\]]+:[^:*?\[\]]+:[^:*?\[\]]+:[^:*?\[\]]+$} \
        $vlnv] || ![string match {xilinx.com:ip:system_ila:*} $vlnv]} {
        _raise FAIL SYSTEM_ILA_VLNV_INVALID IDENTITY \
            {System ILA VLNV must be an exact Xilinx system_ila identity.}
    }
    set properties [dict get $identity properties]
    _require_dictionary $properties {system_ila_identity properties}
    foreach {property expected} {
        CONFIG.C_MON_TYPE MIX
        CONFIG.C_PROBE_WIDTH_PROPAGATION MANUAL
        CONFIG.C_NUM_MONITOR_SLOTS 1
        CONFIG.C_SLOT_0_INTF_TYPE xilinx.com:interface:aximm_rtl:1.0
        CONFIG.C_SLOT_0_AXI_PROTOCOL AXI4LITE
        CONFIG.C_NUM_OF_PROBES 12
        CONFIG.C_DATA_DEPTH 4096
    } {
        if {![dict exists $properties $property] ||
            ![_values_equal [dict get $properties $property] $expected]} {
            _raise FAIL SYSTEM_ILA_CONFIGURATION_INVALID CONTRACT \
                "System ILA property $property must be $expected."
        }
    }
    return [dict create schema_version [dict get $identity schema_version] \
        cell_name $name vlnv $vlnv properties $properties]
}

proc ::stage1e::debug_design::_validate_monitor_policy {policy system_name} {
    _require_keys $policy {schema_version target monitor} \
        monitor_interface_policy
    if {[dict get $policy schema_version] ne
        {stage1e-debug-monitor-interface-policy-v1}} {
        _raise FAIL MONITOR_POLICY_SCHEMA_UNSUPPORTED CONTRACT \
            {Unsupported monitor_interface_policy schema.}
    }
    set target [_validate_object_path [dict get $policy target] \
        {monitor_interface_policy target}]
    set monitor [_validate_object_path [dict get $policy monitor] \
        {monitor_interface_policy monitor}]
    if {$monitor ne "$system_name/SLOT_0_AXI"} {
        _raise FAIL MONITOR_PIN_IDENTITY_INVALID IDENTITY \
            {Monitor interface must be the configured System ILA SLOT_0_AXI.}
    }
    if {[dict exists $policy expected_net_members]} {
        set members [dict get $policy expected_net_members]
    } else {
        set members [list $target]
    }
    if {[llength $members] == 0} {
        _raise FAIL MONITOR_NET_POLICY_INVALID CONTRACT \
            {Monitor policy must name at least one existing interface member.}
    }
    set normalized {}
    set seen [dict create]
    foreach member $members {
        set member [_validate_object_path $member \
            {monitor_interface_policy expected_net_members member}]
        if {[dict exists $seen $member]} {
            _raise FAIL MONITOR_NET_POLICY_INVALID CONTRACT \
                "Duplicate monitor net member: $member"
        }
        dict set seen $member 1
        lappend normalized $member
    }
    if {[lsearch -exact $normalized $target] < 0} {
        lappend normalized $target
    }
    dict set policy target $target
    dict set policy monitor $monitor
    dict set policy expected_net_members $normalized
    return $policy
}

proc ::stage1e::debug_design::_validate_probe_schema {
    schema
    width_expectations
    system_name
} {
    _require_keys $schema {schema_version probes} probe_schema
    if {[dict get $schema schema_version] ne
        {stage1e-debug-probe-schema-v1}} {
        _raise FAIL PROBE_SCHEMA_UNSUPPORTED CONTRACT \
            {Unsupported probe_schema schema.}
    }
    set probes [dict get $schema probes]
    if {[llength $probes] != 12} {
        _raise FAIL PROBE_SCHEMA_INVALID CONTRACT \
            {The reviewed Stage 2D mixed System ILA requires exactly 12 probes.}
    }
    set normalized {}
    set index 0
    foreach probe $probes {
        _require_keys $probe {index source probe width} probe_schema_entry
        if {![string is integer -strict [dict get $probe index]] ||
            [dict get $probe index] != $index} {
            _raise FAIL PROBE_ORDER_INVALID CONTRACT \
                {Probe indices must be contiguous and ordered from zero.}
        }
        set source [_validate_object_path [dict get $probe source] \
            {probe source}]
        set probe_path [_validate_object_path [dict get $probe probe] \
            {probe destination}]
        if {$probe_path ne "$system_name/probe$index"} {
            _raise FAIL PROBE_IDENTITY_INVALID IDENTITY \
                "Probe $index destination is not the configured System ILA pin."
        }
        set width [dict get $probe width]
        if {![string is integer -strict $width] || $width <= 0} {
            _raise FAIL PROBE_WIDTH_POLICY_INVALID CONTRACT \
                "Probe $index width must be a positive integer."
        }
        if {$index == 2 &&
            ($source ne {protection_ip_axi_lite_0/adc_sample_ch1} || $width != 12)} {
            _raise FAIL PROBE2_MAPPING_INVALID IDENTITY \
                {Probe 2 must map protection_ip_axi_lite_0/adc_sample_ch1 at width 12.}
        }
        if {$index == 11 &&
            ($source ne {protection_ip_axi_lite_0/adc_sample_ready} || $width != 1)} {
            _raise FAIL PROBE11_MAPPING_INVALID IDENTITY \
                {Probe 11 must map protection_ip_axi_lite_0/adc_sample_ready at width 1.}
        }
        lappend normalized [dict create \
            index $index source $source probe $probe_path width $width]
        incr index
    }
    set widths {}
    if {[catch {dict size $width_expectations}]} {
        set widths $width_expectations
    } elseif {[dict exists $width_expectations widths]} {
        set widths [dict get $width_expectations widths]
    } elseif {[dict exists $width_expectations probe_widths]} {
        set widths [dict get $width_expectations probe_widths]
    } elseif {[dict exists $width_expectations expected_widths]} {
        set widths [dict get $width_expectations expected_widths]
    } else {
        _raise FAIL WIDTH_EXPECTATION_INVALID CONTRACT \
            {width_expectations must contain widths.}
    }
    if {[llength $widths] != [llength $normalized]} {
        _raise FAIL WIDTH_EXPECTATION_INVALID CONTRACT \
            {width_expectations count does not match probe_schema.}
    }
    set expected_widths {}
    for {set i 0} {$i < [llength $normalized]} {incr i} {
        set expected [lindex $widths $i]
        if {![string is integer -strict $expected] || $expected <= 0 ||
            $expected != [dict get [lindex $normalized $i] width]} {
            _raise FAIL PROBE_WIDTH_POLICY_MISMATCH CONTRACT \
                "Probe width expectation does not match probe_schema at index $i."
        }
        lappend expected_widths $expected
    }
    return [dict create \
        schema_version [dict get $schema schema_version] \
        probes $normalized widths $expected_widths]
}

proc ::stage1e::debug_design::_validate_context {context} {
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
        base_design_identity
        debug_policy
        system_ila_identity
        monitor_interface_policy
        probe_schema
        width_expectations
    } {debug-design context}
    if {[dict get $context context_schema_version] ne $context_schema_version} {
        _raise FAIL CONTEXT_SCHEMA_UNSUPPORTED CONTRACT \
            {Unsupported debug-design context schema.}
    }
    if {[dict get $context operation] ne $operation_name ||
        [dict get $context phase] ne $phase_name} {
        _raise FAIL OPERATION_MISMATCH CONTRACT \
            {Debug operation or phase does not match the interface.}
    }
    set execution_id [dict get $context execution_id]
    if {[string trim $execution_id] eq {}} {
        _raise FAIL EXECUTION_ID_INVALID CONTRACT \
            {Debug execution_id must not be empty.}
    }
    _validate_authorization [dict get $context authorization] $execution_id
    set source_identity [_validate_identity \
        [dict get $context source_identity] source_identity $execution_id]
    set environment_identity [_validate_identity \
        [dict get $context environment_identity] environment_identity $execution_id]
    set configuration_identity [_validate_identity \
        [dict get $context configuration_identity] \
        configuration_identity $execution_id]

    foreach path_field {workspace_root evidence_dir} {
        set path [dict get $context $path_field]
        if {[file pathtype $path] ne {absolute}} {
            _raise FAIL PATH_NOT_ABSOLUTE WORKSPACE \
                "Debug $path_field must be absolute."
        }
        dict set context $path_field [file normalize $path]
    }
    set workspace_root [dict get $context workspace_root]
    set evidence_dir [dict get $context evidence_dir]
    if {![file isdirectory $workspace_root] ||
        ![file isdirectory $evidence_dir] ||
        ![_is_equal_or_descendant $evidence_dir $workspace_root]} {
        _raise FAIL WORKSPACE_CONTEXT_INVALID WORKSPACE \
            {Debug workspace and evidence directories are unavailable or inconsistent.}
    }

    set ownership [_validate_ownership $context $execution_id $workspace_root]
    set project_ownership [dict get $ownership project_ownership]
    set bd_ownership [dict get $ownership bd_ownership]
    set base_identity [_validate_base_identity \
        [dict get $context base_design_identity] $execution_id \
        $project_ownership $bd_ownership]
    set debug_policy [_validate_debug_policy [dict get $context debug_policy]]
    set system_identity [_validate_system_ila_identity \
        [dict get $context system_ila_identity]]
    set monitor_policy [_validate_monitor_policy \
        [dict get $context monitor_interface_policy] \
        [dict get $system_identity cell_name]]
    set probe_schema [_validate_probe_schema \
        [dict get $context probe_schema] \
        [dict get $context width_expectations] \
        [dict get $system_identity cell_name]]
    set width_expectations [dict create \
        schema_version stage1e-debug-width-expectations-v1 \
        widths [dict get $probe_schema widths]]

    return [dict create \
        context $context \
        execution_id $execution_id \
        source_identity $source_identity \
        environment_identity $environment_identity \
        configuration_identity $configuration_identity \
        workspace_root $workspace_root \
        evidence_dir $evidence_dir \
        project_ownership $project_ownership \
        bd_ownership $bd_ownership \
        base_design_identity $base_identity \
        debug_policy $debug_policy \
        system_ila_identity $system_identity \
        monitor_interface_policy $monitor_policy \
        probe_schema $probe_schema \
        width_expectations $width_expectations]
}

proc ::stage1e::debug_design::_require_single_object {objects label} {
    if {[llength $objects] != 1} {
        _raise FAIL VIVADO_OBJECT_CARDINALITY VIVADO \
            "$label must resolve to exactly one object; found [llength $objects]."
    }
    return [lindex $objects 0]
}

proc ::stage1e::debug_design::_require_cell {name} {
    return [_require_single_object [_invoke get_bd_cells -quiet $name] \
        "BD cell $name"]
}

proc ::stage1e::debug_design::_require_pin {path} {
    return [_require_single_object [_invoke get_bd_pins -quiet $path] \
        "BD pin $path"]
}

proc ::stage1e::debug_design::_require_intf_pin {path} {
    return [_require_single_object [_invoke get_bd_intf_pins -quiet $path] \
        "BD interface pin $path"]
}

proc ::stage1e::debug_design::_values_equal {actual expected} {
    if {![catch {expr {wide($actual)}} actual_number] &&
        ![catch {expr {wide($expected)}} expected_number]} {
        return [expr {$actual_number == $expected_number}]
    }
    return [expr {$actual eq $expected}]
}

proc ::stage1e::debug_design::_assert_property {
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

proc ::stage1e::debug_design::_verify_live_ownership {validated} {
    set project [dict get $validated project_ownership]
    set expected_project [dict get $project project_handle]
    set current_project [_invoke current_project]
    if {$current_project ne $expected_project} {
        _raise FAIL PROJECT_OWNER_MISMATCH OWNERSHIP \
            "Current project does not match ownership: actual=$current_project expected=$expected_project"
    }
    set current_bd [_invoke current_bd_design]
    if {$current_bd ne [dict get $validated bd_ownership bd_name]} {
        _raise FAIL BD_OWNER_MISMATCH OWNERSHIP \
            "Current BD does not match ownership: actual=$current_bd expected=[dict get $validated bd_ownership bd_name]"
    }
    set project_identity [dict get $project project_identity]
    set readback [dict create \
        project_name [_invoke get_property NAME $current_project] \
        project_directory [file normalize [_invoke get_property DIRECTORY $current_project]] \
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
        if {[dict exists [dict get $validated environment_identity] $key] &&
            [dict get $readback $key] ne \
                [dict get $validated environment_identity $key]} {
            _raise FAIL ENVIRONMENT_IDENTITY_MISMATCH IDENTITY \
                "Current project does not match environment $key."
        }
    }
    return [dict merge $readback [dict create bd_name $current_bd]]
}

proc ::stage1e::debug_design::_resolve_ila {identity} {
    set expected [dict get $identity vlnv]
    set definition [_require_single_object \
        [_invoke get_ipdefs -all -quiet $expected] \
        {System ILA IP definition}]
    set actual [_invoke get_property VLNV $definition]
    if {$actual ne $expected} {
        _raise FAIL SYSTEM_ILA_VLNV_MISMATCH IDENTITY \
            "System ILA VLNV mismatch: actual=$actual expected=$expected"
    }
    return [dict create expected $expected actual $actual definition $definition]
}

proc ::stage1e::debug_design::_assert_pin_available {path label} {
    return [_require_pin $path]
}

proc ::stage1e::debug_design::_assert_intf_available {path label} {
    return [_require_intf_pin $path]
}

proc ::stage1e::debug_design::_assert_scalar_sink_unconnected {object path} {
    set nets [_invoke get_bd_nets -quiet -of_objects $object]
    if {[llength $nets] != 0} {
        _raise FAIL DEBUG_SINK_ALREADY_CONNECTED OWNERSHIP \
            "Debug sink is already connected: $path"
    }
}

proc ::stage1e::debug_design::_assert_interface_sink_unconnected {
    object
    path
} {
    set nets [_invoke get_bd_intf_nets -quiet -of_objects $object]
    if {[llength $nets] != 0} {
        _raise FAIL DEBUG_SINK_ALREADY_CONNECTED OWNERSHIP \
            "Debug interface sink is already connected: $path"
    }
}

proc ::stage1e::debug_design::_existing_net {object path} {
    set nets [_invoke get_bd_nets -quiet -of_objects $object]
    if {[llength $nets] > 1} {
        _raise FAIL DEBUG_SOURCE_AMBIGUOUS IDENTITY \
            "Debug source has multiple scalar nets: $path"
    }
    return $nets
}

proc ::stage1e::debug_design::_net_name {path} {
    set name $path
    regsub -all {[^A-Za-z0-9_]} $name _ name
    return "dbg_$name"
}

proc ::stage1e::debug_design::_connect_scalar {
    source_path
    sink_path
} {
    set source [_require_pin $source_path]
    set sink [_require_pin $sink_path]
    _assert_scalar_sink_unconnected $sink $sink_path
    set nets [_existing_net $source $source_path]
    if {[llength $nets] == 0} {
        set name [_net_name $source_path]
        if {[llength [_invoke get_bd_nets -quiet $name]] != 0} {
            _raise FAIL DEBUG_NET_ALREADY_EXISTS OWNERSHIP \
                "Debug net name already exists: $name"
        }
        set net [_invoke create_bd_net $name]
        _invoke connect_bd_net -net $net $source
    } else {
        set net [lindex $nets 0]
    }
    _invoke connect_bd_net -net $net $sink
    return $net
}

proc ::stage1e::debug_design::_connect_interface {
    target_path
    monitor_path
    expected_members
} {
    set target [_require_intf_pin $target_path]
    set monitor [_require_intf_pin $monitor_path]
    _assert_interface_sink_unconnected $monitor $monitor_path
    set nets [_invoke get_bd_intf_nets -quiet -of_objects $target]
    if {[llength $nets] != 1} {
        _raise FAIL MONITOR_SOURCE_UNCONNECTED IDENTITY \
            "AXI monitor target must have exactly one existing interface net: $target_path"
    }
    set net [lindex $nets 0]
    foreach member_path $expected_members {
        set member [_require_intf_pin $member_path]
        set member_nets [_invoke get_bd_intf_nets -quiet -of_objects $member]
        if {[llength $member_nets] != 1 || $member_nets ne $nets} {
            _raise FAIL MONITOR_NET_IDENTITY_MISMATCH IDENTITY \
                "Expected interface member is not on the target net: $member_path"
        }
    }
    _invoke connect_bd_intf_net $target $monitor
    return $net
}

proc ::stage1e::debug_design::_pin_width {pin path} {
    set left [_invoke get_property LEFT $pin]
    set right [_invoke get_property RIGHT $pin]
    if {$left eq {} && $right eq {}} {
        return 1
    }
    if {$left eq {} || $right eq {} ||
        [catch {expr {abs(int($left) - int($right)) + 1}} width]} {
        _raise FAIL PROBE_WIDTH_READBACK_INVALID IDENTITY \
            "Cannot determine probe width for $path."
    }
    return $width
}

proc ::stage1e::debug_design::_system_ila_with_probe_widths {
    identity
    probes
} {
    set properties [dict get $identity properties]
    foreach probe $probes {
        set index [dict get $probe index]
        set width [dict get $probe width]
        set property "CONFIG.C_PROBE${index}_WIDTH"
        if {[dict exists $properties $property] &&
            ![_values_equal [dict get $properties $property] $width]} {
            _raise FAIL PROBE_WIDTH_POLICY_MISMATCH CONTRACT \
                "System ILA $property conflicts with probe schema width $width."
        }
        dict set properties $property $width
    }
    dict set identity properties $properties
    return $identity
}

proc ::stage1e::debug_design::_read_system_ila_properties {
    cell
    name
    properties
} {
    set readback [dict create]
    dict for {property expected} $properties {
        dict set readback $property [_assert_property $cell $property \
            $expected "System ILA $name"]
    }
    return $readback
}

proc ::stage1e::debug_design::_configure_system_ila {
    cell
    identity
    probes
} {
    set configured [_system_ila_with_probe_widths $identity $probes]
    set properties [dict get $configured properties]
    set name [dict get $configured cell_name]

    # Vivado 2024.1 defaults to interface monitoring and native probe-width
    # propagation AUTO.  Establish MIX mode first so the native-probe controls
    # are active before selecting manual width propagation.
    set mode_properties [dict create CONFIG.C_MON_TYPE \
        [dict get $properties CONFIG.C_MON_TYPE]]
    _invoke set_property -dict $mode_properties $cell
    _read_system_ila_properties $cell $name $mode_properties

    # AUTO disables C_PROBE<n>_WIDTH and retains width 1.  Establish and verify
    # manual propagation and probe cardinality before requesting any individual
    # widths.
    set enablement_properties [dict create]
    foreach property {
        CONFIG.C_PROBE_WIDTH_PROPAGATION
        CONFIG.C_NUM_OF_PROBES
    } {
        dict set enablement_properties $property [dict get $properties $property]
    }
    _invoke set_property -dict $enablement_properties $cell
    _read_system_ila_properties $cell $name $enablement_properties

    # Configure every native probe explicitly while width parameters are still
    # mutable, then fail closed if Vivado ignored or altered any requested
    # value.  No pin lookup or connection is permitted before this readback.
    set width_properties [dict create]
    foreach probe $probes {
        set index [dict get $probe index]
        set property "CONFIG.C_PROBE${index}_WIDTH"
        dict set width_properties $property [dict get $properties $property]
    }
    _invoke set_property -dict $width_properties $cell
    _read_system_ila_properties $cell $name $width_properties

    set remaining_properties [dict create]
    dict for {property value} $properties {
        if {![dict exists $mode_properties $property] &&
            ![dict exists $enablement_properties $property] &&
            ![dict exists $width_properties $property]} {
            dict set remaining_properties $property $value
        }
    }
    if {[dict size $remaining_properties] != 0} {
        _invoke set_property -dict $remaining_properties $cell
        _read_system_ila_properties $cell $name $remaining_properties
    }
    return $configured
}

proc ::stage1e::debug_design::_assert_connection_widths {
    source
    source_path
    sink
    sink_path
    expected_width
} {
    set source_width [_pin_width $source $source_path]
    if {$source_width != $expected_width} {
        _raise FAIL PROBE_SOURCE_WIDTH_MISMATCH IDENTITY \
            "Probe source width mismatch at $source_path: actual=$source_width expected=$expected_width"
    }
    set sink_width [_pin_width $sink $sink_path]
    if {$sink_width != $expected_width} {
        _raise FAIL PROBE_WIDTH_MISMATCH IDENTITY \
            "Probe width mismatch at $sink_path: actual=$sink_width expected=$expected_width"
    }
    return [dict create source_width $source_width sink_width $sink_width]
}

proc ::stage1e::debug_design::_read_scalar_connection {
    source_path
    sink_path
    expected_width
} {
    set source [_require_pin $source_path]
    set sink [_require_pin $sink_path]
    set source_nets [_invoke get_bd_nets -quiet -of_objects $source]
    set sink_nets [_invoke get_bd_nets -quiet -of_objects $sink]
    if {[llength $source_nets] != 1 || $source_nets ne $sink_nets} {
        _raise FAIL DEBUG_SCALAR_CONNECTION_MISMATCH IDENTITY \
            "Debug scalar connection readback mismatch: $source_path -> $sink_path"
    }
    set widths [_assert_connection_widths \
        $source $source_path $sink $sink_path $expected_width]
    set net [lindex $source_nets 0]
    return [dict create source $source_path sink $sink_path \
        net [_invoke get_property NAME $net] \
        source_width [dict get $widths source_width] \
        sink_width [dict get $widths sink_width] \
        width [dict get $widths sink_width]]
}

proc ::stage1e::debug_design::_read_interface_connection {
    target_path
    monitor_path
    expected_net
} {
    set target [_require_intf_pin $target_path]
    set monitor [_require_intf_pin $monitor_path]
    set target_nets [_invoke get_bd_intf_nets -quiet -of_objects $target]
    set monitor_nets [_invoke get_bd_intf_nets -quiet -of_objects $monitor]
    if {[llength $target_nets] != 1 || $target_nets ne $monitor_nets ||
        [lindex $target_nets 0] ne $expected_net} {
        _raise FAIL DEBUG_INTERFACE_CONNECTION_MISMATCH IDENTITY \
            "Debug interface connection readback mismatch."
    }
    set net [lindex $target_nets 0]
    return [dict create target $target_path monitor $monitor_path \
        net [_invoke get_property NAME $net]]
}

proc ::stage1e::debug_design::_read_cell {
    cell
    identity
} {
    set name [dict get $identity cell_name]
    set actual_vlnv [_assert_property $cell VLNV [dict get $identity vlnv] \
        "System ILA $name"]
    set properties [dict create]
    foreach property [dict keys [dict get $identity properties]] {
        dict set properties $property [_assert_property $cell $property \
            [dict get $identity properties $property] "System ILA $name"]
    }
    return [dict create name $name object $cell vlnv $actual_vlnv \
        properties $properties]
}

proc ::stage1e::debug_design::_execute {context validated} {
    set ownership_records [dict create \
        project_ownership [dict get $validated project_ownership] \
        bd_ownership [dict get $validated bd_ownership]]
    set consumed_identities [dict create \
        source_identity [dict get $validated source_identity] \
        environment_identity [dict get $validated environment_identity] \
        configuration_identity [dict get $validated configuration_identity] \
        project_ownership [dict get $validated project_ownership] \
        bd_ownership [dict get $validated bd_ownership] \
        base_design_identity [dict get $validated base_design_identity] \
        debug_policy [dict get $validated debug_policy] \
        system_ila_identity [dict get $validated system_ila_identity] \
        monitor_interface_policy [dict get $validated monitor_interface_policy] \
        probe_schema [dict get $validated probe_schema] \
        width_expectations [dict get $validated width_expectations]]
    set vivado_invoked 1
    set topology_started 0
    set execution_status [catch {
        set lifecycle_readback [_verify_live_ownership $validated]
        set system_identity [dict get $validated system_ila_identity]
        set name [dict get $system_identity cell_name]
        if {[llength [_invoke get_bd_cells -quiet $name]] != 0} {
            _raise FAIL DEBUG_CELL_ALREADY_EXISTS OWNERSHIP \
                "System ILA cell already exists: $name"
        }
        set resolved_ila [_resolve_ila $system_identity]

        set probes [dict get [dict get $validated probe_schema] probes]
        set monitor_policy [dict get $validated monitor_interface_policy]
        set debug_policy [dict get $validated debug_policy]
        _assert_intf_available [dict get $monitor_policy target] \
            {AXI monitor target}
        _assert_pin_available [dict get $debug_policy clock_source] \
            {Debug clock source}
        _assert_pin_available [dict get $debug_policy reset_source] \
            {Debug reset source}
        foreach probe $probes {
            _assert_pin_available [dict get $probe source] \
                "Probe source [dict get $probe index]"
        }
        set target [_require_intf_pin [dict get $monitor_policy target]]
        set target_nets [_invoke get_bd_intf_nets -quiet -of_objects $target]
        if {[llength $target_nets] != 1} {
            _raise FAIL MONITOR_SOURCE_UNCONNECTED IDENTITY \
                {AXI monitor target has no unique existing interface net.}
        }

        set topology_started 1
        set cell [_invoke create_bd_cell -type ip \
            -vlnv [dict get $resolved_ila actual] $name]
        if {$cell ne [_require_cell $name]} {
            _raise FAIL DEBUG_CELL_HANDLE_MISMATCH IDENTITY \
                {Created System ILA handle does not match readback.}
        }
        set configured_system_identity \
            [_configure_system_ila $cell $system_identity $probes]
        set cell_readback [_read_cell $cell $configured_system_identity]

        set clock_pin [_require_pin "$name/clk"]
        set reset_pin [_require_pin "$name/resetn"]
        set monitor_pin [_require_intf_pin "$name/SLOT_0_AXI"]
        _connect_scalar [dict get $debug_policy clock_source] "$name/clk"
        _connect_scalar [dict get $debug_policy reset_source] "$name/resetn"
        set monitor_net [_connect_interface \
            [dict get $monitor_policy target] \
            [dict get $monitor_policy monitor] \
            [dict get $monitor_policy expected_net_members]]

        set validated_probes {}
        foreach probe $probes {
            set source_path [dict get $probe source]
            set sink_path [dict get $probe probe]
            set source [_require_pin $source_path]
            set sink [_require_pin $sink_path]
            _assert_connection_widths $source $source_path \
                $sink $sink_path [dict get $probe width]
            lappend validated_probes $probe
        }

        set probe_connections {}
        foreach probe $validated_probes {
            _connect_scalar [dict get $probe source] [dict get $probe probe]
        }

        set monitor_readback [_read_interface_connection \
            [dict get $monitor_policy target] \
            [dict get $monitor_policy monitor] $monitor_net]
        set clock_readback [_read_scalar_connection \
            [dict get $debug_policy clock_source] "$name/clk" 1]
        set reset_readback [_read_scalar_connection \
            [dict get $debug_policy reset_source] "$name/resetn" 1]
        if {[dict exists $debug_policy reset_polarity]} {
            set reset_source_pin [_require_pin [dict get $debug_policy reset_source]]
            set reset_polarity [_assert_property $reset_source_pin \
                CONFIG.POLARITY [dict get $debug_policy reset_polarity] \
                {Debug reset source}]
        } else {
            set reset_polarity {}
        }
        foreach probe $probes {
            lappend probe_connections [_read_scalar_connection \
                [dict get $probe source] [dict get $probe probe] \
                [dict get $probe width]]
        }
        set topology_readback [dict create \
            lifecycle $lifecycle_readback \
            system_ila $cell_readback \
            monitor_interface $monitor_readback \
            clock $clock_readback \
            reset [dict merge $reset_readback [dict create polarity $reset_polarity]] \
            probes $probe_connections]
        set policy_bundle [list \
            [dict get $validated debug_policy] \
            [dict get $validated system_ila_identity] \
            [dict get $validated monitor_interface_policy] \
            [dict get $validated probe_schema] \
            [dict get $validated width_expectations]]
        set policy_bundle_sha256 [::stage1d::source_check::sha256_text $policy_bundle]
        set readback_sha256 [::stage1d::source_check::sha256_text $topology_readback]
        set identity_sha256 [::stage1d::source_check::sha256_text [list \
            [dict get $validated execution_id] \
            [dict get $validated bd_ownership bd_path] \
            [dict get $validated base_design_identity identity_sha256] \
            [dict get $validated debug_policy sha256] \
            $policy_bundle_sha256 $readback_sha256]]
        set debug_identity [dict create \
            schema_version stage1e-debug-design-identity-v1 \
            producer_operation stage1e::debug_design::apply \
            execution_id [dict get $validated execution_id] \
            project_path [dict get $validated project_ownership project_path] \
            bd_name [dict get $validated bd_ownership bd_name] \
            bd_path [dict get $validated bd_ownership bd_path] \
            base_design_identity_sha256 [dict get \
                $validated base_design_identity identity_sha256] \
            debug_policy_sha256 [dict get $validated debug_policy sha256] \
            policy_bundle_sha256 $policy_bundle_sha256 \
            readback_sha256 $readback_sha256 \
            identity_sha256 $identity_sha256 \
            system_ila_name [dict get $system_identity cell_name] \
            system_ila_vlnv [dict get $system_identity vlnv] \
            probe_widths [dict get [dict get $validated probe_schema] widths]]
        set evidence_references [dict create \
            lifecycle_readback $lifecycle_readback \
            topology_readback $topology_readback \
            policy_bundle_sha256 $policy_bundle_sha256 \
            readback_sha256 $readback_sha256]
    } execution_error execution_options]

    if {$execution_status != 0} {
        set decoded [_decode_error $execution_error $execution_options \
            DEBUG_APPLY_FAILED VIVADO]
        if {$topology_started} {
            set cleanup_result [_cleanup_result 1 0 \
                CONTROLLER_CLEANUP_REQUIRED]
        } else {
            set cleanup_result [_cleanup_result 0 1 NOT_REQUIRED]
        }
        return [_result [dict get $decoded status] $context \
            $consumed_identities {} $ownership_records {} {} \
            [list [_error_record $decoded]] $cleanup_result \
            $vivado_invoked 0]
    }
    return [_result PASS $context $consumed_identities \
        [dict create debug_design_identity $debug_identity] \
        $ownership_records $evidence_references {} {} \
        [_cleanup_result 0 1 NOT_REQUIRED] $vivado_invoked 1]
}

proc ::stage1e::debug_design::apply {context} {
    set validation_status [catch {
        _validate_context $context
    } validated validation_options]
    if {$validation_status != 0} {
        set decoded [_decode_error $validated $validation_options \
            DEBUG_CONTEXT_INVALID CONTRACT]
        return [_result [dict get $decoded status] $context {} {} {} {} {} \
            [list [_error_record $decoded]] \
            [_cleanup_result 0 1 NOT_REQUIRED] 0 0]
    }
    return [_execute $context $validated]
}
