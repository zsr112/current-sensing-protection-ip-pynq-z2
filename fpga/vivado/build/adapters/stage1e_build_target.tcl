# Stage 1E WP-B3.7 build-target preparation adapter.
#
# This module is definition-only when sourced. It consumes the controller's
# existing project/BD ownership and prepares only the intermediate Vivado
# target (BD output products, HDL wrapper, and synthesis-top selection). It
# does not own lifecycle creation, topology, validation/save, mutation, build
# execution, final artifacts, or publication.

namespace eval ::stage1e::build_target {
    variable context_schema_version stage1e-build-target-context-v1
    variable result_schema_version stage1e-build-target-result-v1
    variable identity_schema_version stage1e-build-target-identity-v1
    variable operation_name stage1e::build_target::prepare
    variable phase_name WRAPPER_GENERATION
}

namespace eval ::stage1e::build_target::backend {}

# The source-check library only defines procedures and performs no Vivado
# operation. Reuse its reviewed SHA-256 implementation for target identity.
if {[llength [info commands ::stage1d::source_check::sha256_text]] == 0} {
    set ::stage1e::build_target::_source_check_path [file normalize \
        [file join [file dirname [info script]] .. lib source_check.tcl]]
    source $::stage1e::build_target::_source_check_path
    unset ::stage1e::build_target::_source_check_path
}

# Production calls are deliberately behind one namespace-local seam. Tests
# replace this procedure with an in-memory backend, so sourcing this file never
# resolves or invokes a Vivado command.
proc ::stage1e::build_target::backend::invoke {command arguments} {
    return [uplevel #0 [list $command {*}$arguments]]
}

proc ::stage1e::build_target::_invoke {command args} {
    return [::stage1e::build_target::backend::invoke $command $args]
}

proc ::stage1e::build_target::_get_or_default {
    dictionary
    key
    default_value
} {
    if {![catch {dict size $dictionary}] && [dict exists $dictionary $key]} {
        return [dict get $dictionary $key]
    }
    return $default_value
}

proc ::stage1e::build_target::_raise {
    status
    error_code
    error_class
    message
} {
    return -code error -errorcode [list \
        STAGE1E BUILD_TARGET $status $error_code $error_class] $message
}

proc ::stage1e::build_target::_decode_error {
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
        [lrange $tcl_error_code 0 1] eq {STAGE1E BUILD_TARGET}} {
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

proc ::stage1e::build_target::_error_record {decoded} {
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

proc ::stage1e::build_target::_cleanup_result {
    required
    completed
    disposition
} {
    return [dict create \
        owner stage1e::build_target \
        required $required \
        attempted 0 \
        completed $completed \
        disposition $disposition \
        errors {}]
}

proc ::stage1e::build_target::_context_execution_id {context} {
    if {![catch {dict size $context}] &&
        [dict exists $context execution_id]} {
        return [dict get $context execution_id]
    }
    return {}
}

proc ::stage1e::build_target::_result {
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
    {output_products_generated 0}
    {wrapper_generated 0}
} {
    variable result_schema_version
    variable operation_name
    variable phase_name
    set result [dict create \
        schema_version $result_schema_version \
        operation $operation_name \
        phase $phase_name \
        execution_id [_context_execution_id $context] \
        status $status \
        consumed_identities $consumed_identities \
        produced_identities $produced_identities \
        ownership_records $ownership_records \
        evidence_references $evidence_references \
        evidence $evidence_references \
        warnings $warnings \
        errors $errors \
        cleanup_result $cleanup_result \
        vivado_invoked $vivado_invoked \
        output_products_generated $output_products_generated \
        wrapper_generated $wrapper_generated \
        synthesis_performed 0 \
        implementation_performed 0 \
        artifacts_generated 0 \
        artifact_generation_performed 0 \
        artifact_publication_performed 0]
    if {[dict exists $produced_identities build_target_identity]} {
        dict set result build_target_identity \
            [dict get $produced_identities build_target_identity]
    }
    return $result
}

proc ::stage1e::build_target::_require_dictionary {value label} {
    if {[catch {dict size $value} dictionary_error]} {
        _raise FAIL CONTEXT_FIELD_INVALID CONTRACT \
            "$label must be a dictionary: $dictionary_error"
    }
}

proc ::stage1e::build_target::_require_keys {
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

proc ::stage1e::build_target::_canonical_components {path} {
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

proc ::stage1e::build_target::_paths_equal {first_path second_path} {
    return [expr {
        [_canonical_components $first_path] eq
            [_canonical_components $second_path]
    }]
}

proc ::stage1e::build_target::_is_equal_or_descendant {
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

proc ::stage1e::build_target::_is_identifier {value} {
    return [regexp {^[A-Za-z_][A-Za-z0-9_]*$} $value]
}

proc ::stage1e::build_target::_validate_hash {value label} {
    set digest [string tolower [string trim $value]]
    if {![regexp {^[0-9a-f]{64}$} $digest]} {
        _raise FAIL IDENTITY_HASH_INVALID IDENTITY \
            "$label must be a lowercase 64-character SHA-256 digest."
    }
    return $digest
}

proc ::stage1e::build_target::_validate_boolean {value label} {
    if {![string is boolean -strict $value]} {
        _raise FAIL BOOLEAN_INVALID CONTRACT "$label must be boolean."
    }
    return [expr {$value ? 1 : 0}]
}

proc ::stage1e::build_target::_validate_identity {
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
    if {[dict exists $identity status] &&
        [dict get $identity status] ne {PASS}} {
        _raise FAIL CONSUMED_IDENTITY_NOT_ACCEPTED IDENTITY \
            "$label is not an accepted PASS identity."
    }
    return $identity
}

proc ::stage1e::build_target::_identity_hash {identity label} {
    foreach key {identity_sha256 package_sha256 ip_repo_sha256 \
        design_sha256 mutation_sha256} {
        if {[dict exists $identity $key] &&
            [string trim [dict get $identity $key]] ne {}} {
            return [_validate_hash [dict get $identity $key] \
                "$label $key"]
        }
    }
    return [::stage1d::source_check::sha256_text $identity]
}

proc ::stage1e::build_target::_validate_authorization {
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
        [dict get $authorization capability] ne {wrapper_generation_enabled} ||
        ![_validate_boolean [dict get $authorization capability_enabled] \
            authorization.capability_enabled]} {
        _raise BLOCKED AUTHORIZATION_MISMATCH AUTHORIZATION \
            {Controller authorization does not permit build-target preparation.}
    }
}

proc ::stage1e::build_target::_validate_ownership {
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
        ![_validate_boolean [dict get $project identity_verified] \
            project_ownership.identity_verified] ||
        ![dict get $project identity_verified]} {
        _raise FAIL PROJECT_OWNER_INVALID OWNERSHIP \
            {Build-target preparation requires same-execution verified project ownership.}
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
        project_path
        part
        board_part
    } {project_ownership project_identity}
    if {![_paths_equal [dict get $project_identity project_path] $project_path] ||
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
            {Build-target preparation requires same-execution BD ownership.}
    }
    foreach field {opened identity_verified validated saved} {
        _validate_boolean [dict get $bd $field] "bd_ownership.$field"
    }
    if {![dict get $bd opened] || ![dict get $bd identity_verified] ||
        ![dict get $bd validated] || ![dict get $bd saved]} {
        _raise FAIL BD_OWNER_STATE_INVALID OWNERSHIP \
            {Build-target preparation requires an opened, verified, validated, saved BD.}
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

proc ::stage1e::build_target::_validate_bound_identity {
    identity
    label
    execution_id
    project
    bd
} {
    set normalized [_validate_identity $identity $label $execution_id]
    if {[dict exists $normalized project_path] &&
        ![_paths_equal [dict get $normalized project_path] \
            [dict get $project project_path]]} {
        _raise FAIL IDENTITY_PROJECT_MISMATCH IDENTITY \
            "$label is not bound to the owned project."
    }
    if {[dict exists $normalized bd_name] &&
        [dict get $normalized bd_name] ne [dict get $bd bd_name]} {
        _raise FAIL IDENTITY_BD_MISMATCH IDENTITY \
            "$label is not bound to the owned BD name."
    }
    if {[dict exists $normalized bd_path] &&
        ![_paths_equal [dict get $normalized bd_path] [dict get $bd bd_path]]} {
        _raise FAIL IDENTITY_BD_MISMATCH IDENTITY \
            "$label is not bound to the owned BD path."
    }
    if {[dict exists $normalized identity_sha256]} {
        dict set normalized identity_sha256 [_validate_hash \
            [dict get $normalized identity_sha256] "$label identity_sha256"]
    }
    return $normalized
}

proc ::stage1e::build_target::_validate_package_identity {
    identity execution_id project bd
} {
    set normalized [_validate_bound_identity $identity package_identity \
        $execution_id $project $bd]
    if {[dict exists $normalized schema_version] &&
        [dict get $normalized schema_version] ne \
            {stage1e-package-identity-v1}} {
        _raise FAIL PACKAGE_IDENTITY_SCHEMA_UNSUPPORTED IDENTITY \
            {Unsupported package_identity schema.}
    }
    if {![dict exists $normalized vlnv] ||
        [string trim [dict get $normalized vlnv]] eq {}} {
        _raise FAIL PACKAGE_IDENTITY_INCOMPLETE IDENTITY \
            {package_identity must contain VLNV.}
    }
    if {[dict exists $normalized ip_repo_identity]} {
        set repo_identity [_validate_identity \
            [dict get $normalized ip_repo_identity] ip_repo_identity \
            $execution_id]
        if {[dict exists $repo_identity vlnv] &&
            [dict get $repo_identity vlnv] ne [dict get $normalized vlnv]} {
            _raise FAIL PACKAGE_REPOSITORY_VLNV_MISMATCH IDENTITY \
                {Nested ip_repo_identity VLNV does not match package_identity.}
        }
        dict set normalized ip_repo_identity $repo_identity
    }
    foreach key {package_sha256 package_inventory_sha256 \
        source_inventory_sha256 component_metadata_sha256 \
        generated_inventory_sha256 component_xml_sha256} {
        if {[dict exists $normalized $key] &&
            [string trim [dict get $normalized $key]] ne {}} {
            dict set normalized $key [_validate_hash [dict get $normalized $key] \
                "package_identity $key"]
        }
    }
    return $normalized
}

proc ::stage1e::build_target::_validate_path_policy {
    policy workspace_root project_directory wrapper_name repository_root
} {
    if {[catch {dict size $policy}]} {
        set policy [dict create path $policy]
    }
    set path {}
    foreach key {path wrapper_path expected_path absolute_path} {
        if {[dict exists $policy $key] &&
            [string trim [dict get $policy $key]] ne {}} {
            set path [dict get $policy $key]
            break
        }
    }
    if {$path eq {} && [dict exists $policy relative_path]} {
        set base $workspace_root
        foreach base_key {base root base_directory output_root} {
            if {![dict exists $policy $base_key]} {
                continue
            }
            set base_value [dict get $policy $base_key]
            set base_name [string toupper $base_value]
            if {$base_name in {PROJECT PROJECT_DIRECTORY PROJECT_OUTPUT}} {
                set base $project_directory
            } elseif {[file pathtype $base_value] eq {absolute}} {
                set base [file normalize $base_value]
            }
            break
        }
        set path [file join $base [dict get $policy relative_path]]
    }
    if {$path eq {} && [dict exists $policy directory]} {
        set path [file join [dict get $policy directory] \
            [format {%s.v} $wrapper_name]]
    }
    if {$path eq {}} {
        _raise FAIL WRAPPER_PATH_POLICY_INCOMPLETE CONTRACT \
            {wrapper_path_policy must identify an explicit wrapper path.}
    }
    if {[file pathtype $path] ne {absolute}} {
        set path [file join $workspace_root $path]
    }
    set path [file normalize $path]
    if {[file extension $path] eq {}} {
        set extension .v
        if {[dict exists $policy extension] &&
            [string trim [dict get $policy extension]] ne {}} {
            set extension [dict get $policy extension]
        }
        append path $extension
    }
    if {![_is_equal_or_descendant $path $workspace_root]} {
        _raise FAIL WRAPPER_PATH_OUTSIDE_WORKSPACE WORKSPACE \
            {Wrapper path must remain within the execution workspace.}
    }
    if {$repository_root ne {} &&
        [_is_equal_or_descendant $path $repository_root]} {
        _raise FAIL WRAPPER_PATH_IN_REPOSITORY WORKSPACE \
            {Wrapper output must not be written inside the source repository.}
    }
    set expected_tail [format {%s%s} $wrapper_name [file extension $path]]
    if {[string tolower [file tail $path]] ne [string tolower $expected_tail]} {
        _raise FAIL WRAPPER_PATH_IDENTITY_INVALID IDENTITY \
            {Wrapper path filename does not match wrapper_name.}
    }
    dict set policy resolved_path $path
    dict set policy extension [file extension $path]
    return $policy
}

proc ::stage1e::build_target::_validate_top_policy {policy wrapper_name} {
    if {[catch {dict size $policy}]} {
        set policy [dict create top_module $policy]
    }
    set top $wrapper_name
    foreach key {top_module expected_top module} {
        if {[dict exists $policy $key] &&
            [string trim [dict get $policy $key]] ne {}} {
            set top [dict get $policy $key]
            break
        }
    }
    if {$top ne $wrapper_name || ![_is_identifier $top]} {
        _raise FAIL TOP_MODULE_POLICY_INVALID CONTRACT \
            {top_module_policy must select the configured wrapper name.}
    }
    set fileset sources_1
    foreach key {fileset source_fileset fileset_name} {
        if {[dict exists $policy $key] &&
            [string trim [dict get $policy $key]] ne {}} {
            set fileset [dict get $policy $key]
            break
        }
    }
    if {![_is_identifier $fileset]} {
        _raise FAIL FILESET_POLICY_INVALID CONTRACT \
            {top_module_policy fileset must be an identifier.}
    }
    dict set policy top_module $top
    dict set policy fileset $fileset
    return $policy
}

proc ::stage1e::build_target::_validate_output_policy {policy} {
    if {[catch {dict size $policy}]} {
        set policy [dict create target $policy]
    }
    set target all
    foreach key {target generation_target} {
        if {[dict exists $policy $key] &&
            [string trim [dict get $policy $key]] ne {}} {
            set target [dict get $policy $key]
            break
        }
    }
    if {[string trim $target] eq {}} {
        _raise FAIL OUTPUT_PRODUCT_POLICY_INVALID CONTRACT \
            {output_product_policy target must not be empty.}
    }
    if {[dict exists $policy enabled] &&
        ![_validate_boolean [dict get $policy enabled] \
            output_product_policy.enabled]} {
        _raise BLOCKED OUTPUT_PRODUCT_GENERATION_DISABLED CAPABILITY \
            {BD output-product generation is disabled by policy.}
    }
    set products [_get_or_default $policy products {}]
    foreach product $products {
        set extension [string tolower [file extension $product]]
        if {$extension in {.bit .hwh .xsa .ltx .dcp}} {
            _raise FAIL FINAL_ARTIFACT_ROLE_FORBIDDEN CONTRACT \
                "Final FPGA artifact is outside target preparation: $product"
        }
    }
    dict set policy target $target
    dict set policy products $products
    return $policy
}

proc ::stage1e::build_target::_validate_context {context} {
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
        package_identity
        base_design_identity
        debug_design_identity
        controlled_mutation_identity
        wrapper_name
        wrapper_path_policy
        top_module_policy
        output_product_policy
    } {build-target context}
    if {[dict get $context context_schema_version] ne $context_schema_version} {
        _raise FAIL CONTEXT_SCHEMA_UNSUPPORTED CONTRACT \
            {Unsupported build-target context schema.}
    }
    if {[dict get $context operation] ne $operation_name ||
        [dict get $context phase] ne $phase_name} {
        _raise FAIL OPERATION_MISMATCH CONTRACT \
            {Build-target operation or phase does not match the interface.}
    }
    set execution_id [dict get $context execution_id]
    if {[string trim $execution_id] eq {}} {
        _raise FAIL EXECUTION_ID_INVALID CONTRACT \
            {Build-target execution_id must not be empty.}
    }
    _validate_authorization [dict get $context authorization] $execution_id
    set source_identity [_validate_identity \
        [dict get $context source_identity] source_identity $execution_id]
    set environment_identity [_validate_identity \
        [dict get $context environment_identity] environment_identity $execution_id]
    set configuration_identity [_validate_identity \
        [dict get $context configuration_identity] configuration_identity \
        $execution_id]

    foreach path_field {workspace_root evidence_dir} {
        set path [dict get $context $path_field]
        if {[file pathtype $path] ne {absolute}} {
            _raise FAIL PATH_NOT_ABSOLUTE WORKSPACE \
                "Build-target $path_field must be an absolute path."
        }
        dict set context $path_field [file normalize $path]
    }
    set workspace_root [dict get $context workspace_root]
    set evidence_dir [dict get $context evidence_dir]
    if {![file isdirectory $workspace_root] ||
        ![file isdirectory $evidence_dir] ||
        ![_is_equal_or_descendant $evidence_dir $workspace_root]} {
        _raise FAIL WORKSPACE_CONTEXT_INVALID WORKSPACE \
            {Build-target workspace and evidence directories are unavailable or inconsistent.}
    }

    set ownership [_validate_ownership $context $execution_id $workspace_root]
    set project [dict get $ownership project_ownership]
    set bd [dict get $ownership bd_ownership]
    set package [_validate_package_identity \
        [dict get $context package_identity] $execution_id $project $bd]
    set base [_validate_bound_identity [dict get $context base_design_identity] \
        base_design_identity $execution_id $project $bd]
    set debug [_validate_bound_identity [dict get $context debug_design_identity] \
        debug_design_identity $execution_id $project $bd]
    set mutation [_validate_bound_identity \
        [dict get $context controlled_mutation_identity] \
        controlled_mutation_identity $execution_id $project $bd]

    set repository_root {}
    if {[dict exists $source_identity repository_root] &&
        [string trim [dict get $source_identity repository_root]] ne {}} {
        set repository_root [file normalize [dict get $source_identity repository_root]]
    }
    set wrapper_name [dict get $context wrapper_name]
    if {![_is_identifier $wrapper_name]} {
        _raise FAIL WRAPPER_NAME_INVALID CONTRACT \
            {wrapper_name must be a Verilog identifier.}
    }
    set project_directory [dict get [dict get $project project_identity] \
        project_directory]
    set wrapper_policy [_validate_path_policy \
        [dict get $context wrapper_path_policy] $workspace_root \
        $project_directory $wrapper_name $repository_root]
    set top_policy [_validate_top_policy \
        [dict get $context top_module_policy] $wrapper_name]
    set output_policy [_validate_output_policy \
        [dict get $context output_product_policy]]

    return [dict create \
        context $context \
        execution_id $execution_id \
        source_identity $source_identity \
        environment_identity $environment_identity \
        configuration_identity $configuration_identity \
        workspace_root $workspace_root \
        evidence_dir $evidence_dir \
        project_ownership $project \
        bd_ownership $bd \
        package_identity $package \
        base_design_identity $base \
        debug_design_identity $debug \
        controlled_mutation_identity $mutation \
        wrapper_name $wrapper_name \
        wrapper_path_policy $wrapper_policy \
        top_module_policy $top_policy \
        output_product_policy $output_policy]
}

proc ::stage1e::build_target::_read_property {property object label} {
    if {[catch {_invoke get_property $property $object} value options]} {
        _raise FAIL PROPERTY_READBACK_FAILED VIVADO \
            "$label property $property could not be read: $value"
    }
    return $value
}

proc ::stage1e::build_target::_verify_project_readback {validated} {
    set project [dict get $validated project_ownership]
    set handle [_invoke current_project]
    if {$handle ne [dict get $project project_handle]} {
        _raise FAIL PROJECT_OWNER_MISMATCH OWNERSHIP \
            "Current project does not match ownership: actual=$handle expected=[dict get $project project_handle]"
    }
    set expected [dict get $project project_identity]
    set readback [dict create \
        project_handle $handle \
        project_name [_read_property NAME $handle project] \
        project_directory [file normalize [_read_property DIRECTORY $handle project]] \
        part [_read_property PART $handle project] \
        board_part [_read_property BOARD_PART $handle project]]
    foreach key {project_name part board_part} {
        if {[dict get $readback $key] ne [dict get $expected $key]} {
            _raise FAIL PROJECT_IDENTITY_MISMATCH IDENTITY \
                "Project readback $key does not match ownership."
        }
    }
    if {![_paths_equal [dict get $readback project_directory] \
        [dict get $expected project_directory]]} {
        _raise FAIL PROJECT_IDENTITY_MISMATCH IDENTITY \
            {Project readback directory does not match ownership.}
    }
    set environment [dict get $validated environment_identity]
    foreach key {part board_part} {
        if {[dict exists $environment $key] &&
            [dict get $readback $key] ne [dict get $environment $key]} {
            _raise FAIL ENVIRONMENT_IDENTITY_MISMATCH IDENTITY \
                "Project readback does not match environment $key."
        }
    }
    return $readback
}

proc ::stage1e::build_target::_bd_object {validated} {
    set bd [dict get $validated bd_ownership]
    if {[dict exists $bd bd_handle] &&
        [string trim [dict get $bd bd_handle]] ne {}} {
        return [dict get $bd bd_handle]
    }
    set path [dict get $bd bd_path]
    set query_status [catch {
        _invoke get_files -quiet -all $path
    } files query_options]
    if {$query_status == 0 && [llength $files] == 1} {
        return [lindex $files 0]
    }
    if {$query_status == 0 && [llength $files] > 1} {
        _raise FAIL BD_FILE_AMBIGUOUS IDENTITY \
            {Owned BD path resolved to multiple files.}
    }
    # A source-only backend may not model get_files. The path remains the
    # controller-owned logical BD handle; Vivado accepts the equivalent file
    # object returned by get_files in production.
    return $path
}

proc ::stage1e::build_target::_verify_bd_readback {validated} {
    set bd [dict get $validated bd_ownership]
    set current [_invoke current_bd_design]
    if {$current ne [dict get $bd bd_name]} {
        _raise FAIL BD_OWNER_MISMATCH OWNERSHIP \
            "Current BD does not match ownership: actual=$current expected=[dict get $bd bd_name]"
    }
    return [dict create \
        bd_name $current \
        bd_path [dict get $bd bd_path] \
        opened [dict get $bd opened] \
        identity_verified [dict get $bd identity_verified] \
        validated [dict get $bd validated] \
        saved [dict get $bd saved]]
}

proc ::stage1e::build_target::_verify_package_readback {validated project_handle} {
    set package [dict get $validated package_identity]
    set evidence [dict create \
        vlnv [dict get $package vlnv] \
        package_identity_sha256 [_identity_hash $package package_identity]]
    set repo_path {}
    foreach key {ip_repo_path path} {
        if {[dict exists $package $key] &&
            [string trim [dict get $package $key]] ne {}} {
            set repo_path [file normalize [dict get $package $key]]
            break
        }
    }
    if {$repo_path ne {} && [llength [info commands ::get_ipdefs]] > 0} {
        set definitions [_invoke get_ipdefs -all -quiet [dict get $package vlnv]]
        if {[llength $definitions] != 1} {
            _raise FAIL PACKAGE_VLNV_UNAVAILABLE IDENTITY \
                {Accepted package VLNV is not uniquely visible in the catalog.}
        }
        set actual [_read_property VLNV [lindex $definitions 0] package]
        if {$actual ne [dict get $package vlnv]} {
            _raise FAIL PACKAGE_VLNV_MISMATCH IDENTITY \
                {Package VLNV readback does not match package_identity.}
        }
        dict set evidence catalog_vlnv $actual
    }
    if {$repo_path ne {}} {
        set repo_query [catch {
            _invoke get_property IP_REPO_PATHS $project_handle
        } repo_paths repo_options]
        if {$repo_query == 0 && [llength $repo_paths] != 0} {
            set found 0
            foreach candidate $repo_paths {
                if {[_paths_equal $candidate $repo_path] ||
                    [_is_equal_or_descendant $candidate $repo_path] ||
                    [_is_equal_or_descendant $repo_path $candidate]} {
                    set found 1
                    break
                }
            }
            if {!$found} {
                _raise FAIL PACKAGE_REPOSITORY_MISMATCH IDENTITY \
                    {Project IP repository readback does not contain accepted package repository.}
            }
            dict set evidence ip_repo_paths $repo_paths
        }
    }
    return $evidence
}

proc ::stage1e::build_target::_extract_path {value} {
    if {![catch {dict size $value}] && [dict exists $value wrapper_path]} {
        return [dict get $value wrapper_path]
    }
    foreach item $value {
        if {[string match -nocase *.v $item] ||
            [string match -nocase *.sv $item] ||
            [string match */* $item] || [string match {*\\*} $item]} {
            return $item
        }
    }
    return {}
}

proc ::stage1e::build_target::_verify_wrapper_readback {
    validated
    make_result
} {
    set expected [dict get [dict get $validated wrapper_path_policy] resolved_path]
    set returned [_extract_path $make_result]
    if {$returned ne {}} {
        if {[file pathtype $returned] ne {absolute}} {
            set returned [file join [dict get $validated workspace_root] $returned]
        }
        if {![_paths_equal $returned $expected]} {
            _raise FAIL WRAPPER_IDENTITY_MISMATCH IDENTITY \
                "make_wrapper returned an unexpected wrapper path: $returned"
        }
    }
    set wrapper_object $expected
    set query_status [catch {
        _invoke get_files -quiet -all $expected
    } files query_options]
    if {$query_status == 0 && [llength $files] > 1} {
        _raise FAIL WRAPPER_FILE_AMBIGUOUS IDENTITY \
            {Generated wrapper path resolves to multiple files.}
    }
    if {$query_status == 0 && [llength $files] == 1} {
        set wrapper_object [lindex $files 0]
    }
    set observed_name {}
    set property_status [catch {
        _invoke get_property NAME $wrapper_object
    } observed_name property_options]
    if {$property_status == 0 && [string trim $observed_name] ne {}} {
        set observed_path $observed_name
        if {[file pathtype $observed_path] ne {absolute} &&
            ![string equal -nocase [file tail $observed_path] \
                [file tail $expected]]} {
            _raise FAIL WRAPPER_IDENTITY_MISMATCH IDENTITY \
                "Wrapper readback name does not match expected path: $observed_name"
        }
        if {[file pathtype $observed_path] eq {absolute} &&
            ![_paths_equal $observed_path $expected]} {
            _raise FAIL WRAPPER_IDENTITY_MISMATCH IDENTITY \
                {Wrapper readback path does not match wrapper_path_policy.}
        }
    }
    return [dict create \
        wrapper_name [dict get $validated wrapper_name] \
        wrapper_path $expected \
        wrapper_object $wrapper_object \
        readback_name $observed_name \
        extension [file extension $expected]]
}

proc ::stage1e::build_target::_fileset_handle {fileset_name} {
    set status [catch {_invoke get_filesets -quiet $fileset_name} filesets options]
    if {$status == 0 && [llength $filesets] == 1} {
        return [list [lindex $filesets 0] $fileset_name]
    }
    set status [catch {_invoke current_fileset} current options]
    if {$status == 0 && [string trim $current] ne {}} {
        return [list $current $fileset_name]
    }
    return [list $fileset_name $fileset_name]
}

proc ::stage1e::build_target::_read_top {
    fileset_handle
    fileset_name
    expected_top
} {
    set status [catch {_invoke get_property TOP $fileset_handle} top options]
    if {$status != 0 || [string trim $top] eq {}} {
        set status [catch {_invoke get_property top $fileset_handle} top options]
    }
    if {$status != 0 || [string trim $top] eq {}} {
        _raise FAIL TOP_READBACK_UNAVAILABLE IDENTITY \
            {Unable to read back synthesis top from the accepted fileset.}
    }
    if {$top ne $expected_top} {
        _raise FAIL TOP_MODULE_IDENTITY_MISMATCH IDENTITY \
            "Synthesis top mismatch: actual=$top expected=$expected_top"
    }
    set fileset_name_readback $fileset_name
    set name_status [catch {
        _invoke get_property NAME $fileset_handle
    } observed_name name_options]
    if {$name_status == 0 && [string trim $observed_name] ne {}} {
        set fileset_name_readback $observed_name
    }
    return [dict create \
        name $fileset_name_readback \
        handle $fileset_handle \
        top $top]
}

proc ::stage1e::build_target::_execute {context validated} {
    set ownership_records [dict create \
        project_ownership [dict get $validated project_ownership] \
        bd_ownership [dict get $validated bd_ownership]]
    set consumed_identities [dict create \
        source_identity [dict get $validated source_identity] \
        environment_identity [dict get $validated environment_identity] \
        configuration_identity [dict get $validated configuration_identity] \
        project_ownership [dict get $validated project_ownership] \
        bd_ownership [dict get $validated bd_ownership] \
        package_identity [dict get $validated package_identity] \
        base_design_identity [dict get $validated base_design_identity] \
        debug_design_identity [dict get $validated debug_design_identity] \
        controlled_mutation_identity [dict get $validated controlled_mutation_identity] \
        wrapper_path_policy [dict get $validated wrapper_path_policy] \
        top_module_policy [dict get $validated top_module_policy] \
        output_product_policy [dict get $validated output_product_policy]]
    set vivado_invoked 1
    set state_changed 0
    set output_products_generated 0
    set wrapper_generated 0
    set execution_status [catch {
        set project_readback [_verify_project_readback $validated]
        set bd_readback [_verify_bd_readback $validated]
        set bd_object [_bd_object $validated]
        set package_readback [_verify_package_readback $validated \
            [dict get $validated project_ownership project_handle]]

        # Everything above is read-only. The first state-changing call is
        # output-product generation, after all context and live identities pass.
        set state_changed 1
        set output_target [dict get $validated output_product_policy target]
        set generated_products [_invoke generate_target $output_target $bd_object]
        set output_products_generated 1
        set make_result [_invoke make_wrapper -files $bd_object -top -force]
        set wrapper_generated 1
        set wrapper_readback [_verify_wrapper_readback $validated $make_result]
        set fileset_info [_fileset_handle \
            [dict get $validated top_module_policy fileset]]
        set fileset_handle [lindex $fileset_info 0]
        set fileset_name [lindex $fileset_info 1]
        _invoke add_files -norecurse -fileset $fileset_name \
            [dict get $wrapper_readback wrapper_path]
        _invoke set_property top [dict get $validated top_module_policy top_module] \
            $fileset_handle
        set fileset_readback [_read_top $fileset_handle $fileset_name \
            [dict get $validated top_module_policy top_module]]

        # Final readback confirms that target preparation did not change
        # lifecycle ownership or the accepted project/BD identity.
        set project_final [_verify_project_readback $validated]
        set bd_final [_verify_bd_readback $validated]
        set readback [dict create \
            project $project_final \
            bd $bd_final \
            package $package_readback \
            wrapper $wrapper_readback \
            fileset $fileset_readback \
            generated_products $generated_products]
        set policy_hash [::stage1d::source_check::sha256_text [list \
            [dict get $validated wrapper_path_policy] \
            [dict get $validated top_module_policy] \
            [dict get $validated output_product_policy]]]
        set readback_hash [::stage1d::source_check::sha256_text $readback]
        set identity_sha256 [::stage1d::source_check::sha256_text [list \
            [dict get $validated execution_id] \
            [dict get $validated source_identity] \
            [dict get $validated environment_identity] \
            [dict get $validated configuration_identity] \
            [_identity_hash [dict get $validated package_identity] package_identity] \
            [_identity_hash [dict get $validated base_design_identity] base_design_identity] \
            [_identity_hash [dict get $validated debug_design_identity] debug_design_identity] \
            [_identity_hash [dict get $validated controlled_mutation_identity] controlled_mutation_identity] \
            $policy_hash $readback_hash]]
        set build_target_identity [dict create \
            schema_version stage1e-build-target-identity-v1 \
            producer_operation stage1e::build_target::prepare \
            execution_id [dict get $validated execution_id] \
            project_path [dict get $validated project_ownership project_path] \
            bd_name [dict get $validated bd_ownership bd_name] \
            bd_path [dict get $validated bd_ownership bd_path] \
            package_identity_sha256 [_identity_hash \
                [dict get $validated package_identity] package_identity] \
            base_design_identity_sha256 [_identity_hash \
                [dict get $validated base_design_identity] base_design_identity] \
            debug_design_identity_sha256 [_identity_hash \
                [dict get $validated debug_design_identity] debug_design_identity] \
            controlled_mutation_identity_sha256 [_identity_hash \
                [dict get $validated controlled_mutation_identity] controlled_mutation_identity] \
            configuration_identity_sha256 [_identity_hash \
                [dict get $validated configuration_identity] configuration_identity] \
            environment_identity_sha256 [_identity_hash \
                [dict get $validated environment_identity] environment_identity] \
            source_identity_sha256 [_identity_hash \
                [dict get $validated source_identity] source_identity] \
            wrapper_name [dict get $validated wrapper_name] \
            wrapper_path [dict get $wrapper_readback wrapper_path] \
            top_module [dict get $fileset_readback top] \
            fileset [dict get $fileset_readback name] \
            output_product_policy_sha256 $policy_hash \
            readback_sha256 $readback_hash \
            identity_sha256 $identity_sha256]
        set evidence_references [dict create \
            project_readback $project_final \
            bd_readback $bd_final \
            package_readback $package_readback \
            wrapper_readback $wrapper_readback \
            fileset_readback $fileset_readback \
            generated_products $generated_products \
            output_product_policy_sha256 $policy_hash \
            readback_sha256 $readback_hash]
    } execution_error execution_options]

    if {$execution_status != 0} {
        set decoded [_decode_error $execution_error $execution_options \
            BUILD_TARGET_PREPARATION_FAILED VIVADO]
        if {$state_changed} {
            set cleanup_result [_cleanup_result 1 0 \
                CONTROLLER_CLEANUP_REQUIRED]
        } else {
            set cleanup_result [_cleanup_result 0 1 NOT_REQUIRED]
        }
        return [_result [dict get $decoded status] $context \
            $consumed_identities {} $ownership_records {} {} \
            [list [_error_record $decoded]] $cleanup_result $vivado_invoked \
            $output_products_generated $wrapper_generated]
    }
    return [_result PASS $context $consumed_identities \
        [dict create build_target_identity $build_target_identity] \
        $ownership_records $evidence_references {} {} \
        [_cleanup_result 0 1 NOT_REQUIRED] $vivado_invoked \
        $output_products_generated $wrapper_generated]
}

proc ::stage1e::build_target::prepare {context} {
    set validation_status [catch {
        _validate_context $context
    } validated validation_options]
    if {$validation_status != 0} {
        set decoded [_decode_error $validated $validation_options \
            BUILD_TARGET_CONTEXT_INVALID CONTRACT]
        return [_result [dict get $decoded status] $context {} {} {} {} {} \
            [list [_error_record $decoded]] \
            [_cleanup_result 0 1 NOT_REQUIRED] 0]
    }
    return [_execute $context $validated]
}
