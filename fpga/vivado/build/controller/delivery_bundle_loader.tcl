# Stage 1D immutable delivery-bundle loader.
#
# Source-time contract:
# - define data-only parsing and validation procedures;
# - do not discover a bundle or profile from ambient state;
# - do not invoke Vivado, lifecycle adapters, mutation, or artifact generation.

namespace eval ::stage1d::delivery_bundle_loader {
    variable loader_version STAGE1D-DELIVERY-BUNDLE-LOADER-v1
    variable validation_phase BUNDLE_INPUT_VALIDATION
    variable manifest_schema_version v1
    variable profile_schema_version v1

    variable manifest_fields {
        schema_version
        bundle_id
        manifest_sha256
        source_revision
        source_identity
        profile_path
        profile_sha256
        environment_identity
        provenance
    }
    variable manifest_hash_fields {
        schema_version
        bundle_id
        source_revision
        source_identity
        profile_path
        profile_sha256
        environment_identity
        provenance
    }
    variable profile_fields {
        schema_version
        profile_id
        profile_version
        profile_sha256
        source_revision
        environment_identity
        scope
        evidence_policy
    }
    variable profile_hash_fields {
        schema_version
        profile_id
        profile_version
        source_revision
        environment_identity
        scope
        evidence_policy
    }
    variable source_reference_fields {
        source_revision
        source_identity
    }
    variable source_identity_required_fields {
        git_commit
        controller_source_hash
        configuration_hash
        source_inventory
    }
    variable source_inventory_fields {path size sha256}
    variable environment_fields {
        vivado_version
        fpga_part
        board_part
        required_ip_identities
    }
    variable scope_fields {
        phase_limit
        project_operations
        design_operations
        mutation_operations
    }
    variable evidence_policy_fields {
        require_execution_id
        require_source_identity
        require_environment_identity
        require_evidence_dir
    }
    variable required_checks {
        BUNDLE_MANIFEST_SCHEMA_VALID
        BUNDLE_MANIFEST_HASH_VALID
        BUNDLE_PATH_CONTAINMENT_VALID
        PROFILE_SCHEMA_VERSION_SUPPORTED
        PROFILE_REQUIRED_FIELDS_VALID
        PROFILE_HASH_VALID
        PROFILE_SCOPE_VALID
        PROFILE_ENVIRONMENT_BINDING_VALID
        PROFILE_PARSE_SIDE_EFFECT_FREE
        PROFILE_SOURCE_BINDING_VALID
    }
}

proc ::stage1d::delivery_bundle_loader::version {} {
    variable loader_version
    return $loader_version
}

proc ::stage1d::delivery_bundle_loader::supported_manifest_schema_version {} {
    variable manifest_schema_version
    return $manifest_schema_version
}

proc ::stage1d::delivery_bundle_loader::supported_profile_schema_version {} {
    variable profile_schema_version
    return $profile_schema_version
}

proc ::stage1d::delivery_bundle_loader::required_checks {} {
    variable required_checks
    return $required_checks
}

proc ::stage1d::delivery_bundle_loader::_new_check_state {} {
    variable required_checks
    set checks [dict create]
    foreach check_name $required_checks {
        dict set checks $check_name NOT_RUN
    }
    return $checks
}

proc ::stage1d::delivery_bundle_loader::_component_results {checks} {
    variable required_checks
    set results {}
    foreach check_name $required_checks {
        lappend results [dict create \
            check $check_name \
            status [dict get $checks $check_name]]
    }
    return $results
}

proc ::stage1d::delivery_bundle_loader::_raise {
    status
    check_name
    error_code
    message
} {
    return -code error \
        -errorcode [list STAGE1D DELIVERY_BUNDLE_LOADER \
            $status $check_name $error_code] \
        $message
}

proc ::stage1d::delivery_bundle_loader::_error_record {
    check_name
    error_code
    message
    status
} {
    variable validation_phase
    set recoverability FIX_BUNDLE
    if {$status eq {BLOCKED}} {
        set recoverability PROVIDE_COMPATIBLE_BUNDLE
    }
    return [dict create \
        error_code $error_code \
        category INPUT_VALIDATION \
        phase_name $validation_phase \
        check $check_name \
        message $message \
        underlying_error {} \
        evidence_references {} \
        recoverability $recoverability]
}

proc ::stage1d::delivery_bundle_loader::_result {
    status
    checks
    bundle_identity
    profile_identity
    source_identity
    environment_identity
    validated_scope
    errors
    warnings
    outputs
} {
    variable validation_phase
    variable required_checks

    foreach check_name $required_checks {
        dict set outputs $check_name \
            [expr {[dict get $checks $check_name] eq {PASS}}]
    }
    dict set outputs side_effects [dict create \
        vivado_invoked 0 \
        project_opened 0 \
        bd_opened 0 \
        lifecycle_invoked 0 \
        mutation_invoked 0 \
        bd_validated 0 \
        bd_saved 0 \
        artifacts_generated 0]
    dict set outputs STATIC_SIDE_EFFECT_FREE 1

    return [dict create \
        status $status \
        phase $validation_phase \
        bundle_identity $bundle_identity \
        profile_identity $profile_identity \
        source_identity $source_identity \
        environment_identity $environment_identity \
        validated_scope $validated_scope \
        component_results [_component_results $checks] \
        errors $errors \
        warnings $warnings \
        outputs $outputs]
}

proc ::stage1d::delivery_bundle_loader::_read_text_file {
    path
    label
    check_name
    {missing_status BLOCKED}
} {
    if {![file exists $path] || ![file isfile $path]} {
        _raise $missing_status $check_name FILE_NOT_FOUND \
            "$label is not an existing regular file."
    }

    if {[catch {open $path r} channel]} {
        _raise FAIL $check_name FILE_OPEN_FAILED \
            "Unable to open $label: $channel"
    }
    fconfigure $channel -encoding utf-8 -translation auto
    set read_status [catch {read $channel} content read_options]
    set close_status [catch {close $channel} close_error]
    if {$read_status != 0} {
        return -options $read_options $content
    }
    if {$close_status != 0} {
        _raise FAIL $check_name FILE_CLOSE_FAILED \
            "Unable to close $label: $close_error"
    }
    if {[string trim $content] eq {}} {
        _raise FAIL $check_name EMPTY_DECLARATIVE_FILE \
            "$label is empty."
    }
    return $content
}

proc ::stage1d::delivery_bundle_loader::_reject_executable_syntax {
    text
    label
    check_name
} {
    if {[string first [format %c 0] $text] >= 0} {
        _raise FAIL $check_name NUL_BYTE_REJECTED \
            "$label contains a NUL byte."
    }

    foreach {token description} [list \
        {$} {variable substitution} \
        {[} {command substitution} \
        {]} {command substitution} \
        {;} {statement separation}] {
        if {[string first $token $text] >= 0} {
            _raise FAIL $check_name EXECUTABLE_SYNTAX_REJECTED \
                "$label contains forbidden $description syntax."
        }
    }

    if {[regexp -line \
        {^[ \t]*(source|eval|uplevel|exec|proc)([ \t]|$)} $text]} {
        _raise FAIL $check_name EXECUTABLE_STATEMENT_REJECTED \
            "$label contains a forbidden executable statement."
    }
}

proc ::stage1d::delivery_bundle_loader::_parse_declarative_dict {
    text
    label
    check_name
} {
    _reject_executable_syntax $text $label $check_name
    set text [string trim $text]
    if {[catch {llength $text} word_count_error]} {
        _raise FAIL $check_name DECLARATIVE_PARSE_FAILED \
            "$label is not a valid declarative Tcl list: $word_count_error"
    }
    set word_count [llength $text]
    if {$word_count == 0 || ($word_count % 2) != 0} {
        _raise FAIL $check_name DECLARATIVE_DICTIONARY_INVALID \
            "$label must contain an even, nonzero number of dictionary words."
    }

    set parsed [dict create]
    for {set index 0} {$index < $word_count} {incr index 2} {
        set key [lindex $text $index]
        set value [lindex $text [expr {$index + 1}]]
        if {[string trim $key] eq {}} {
            _raise FAIL $check_name EMPTY_FIELD_NAME \
                "$label contains an empty field name."
        }
        if {[dict exists $parsed $key]} {
            _raise FAIL $check_name DUPLICATE_FIELD \
                "$label contains a duplicate field: $key"
        }
        dict set parsed $key $value
    }
    return $parsed
}

proc ::stage1d::delivery_bundle_loader::_require_exact_fields {
    value
    expected_fields
    label
    check_name
} {
    set actual_fields [dict keys $value]
    if {[lsort $actual_fields] ne [lsort $expected_fields]} {
        _raise FAIL $check_name FIELD_SET_INVALID \
            "$label fields are invalid: expected=[lsort $expected_fields] actual=[lsort $actual_fields]"
    }
}

proc ::stage1d::delivery_bundle_loader::_validate_identifier {
    value
    label
    check_name
} {
    if {![regexp {^[A-Za-z0-9][A-Za-z0-9._-]*$} $value]} {
        _raise FAIL $check_name IDENTIFIER_INVALID \
            "$label must be a nonempty stable identifier."
    }
    return $value
}

proc ::stage1d::delivery_bundle_loader::_validate_sha256 {
    value
    label
    check_name
} {
    if {![regexp {^[0-9a-f]{64}$} $value]} {
        _raise FAIL $check_name SHA256_INVALID \
            "$label must contain exactly 64 lowercase hexadecimal characters."
    }
    return $value
}

proc ::stage1d::delivery_bundle_loader::_validate_source_revision {
    value
    label
    check_name
} {
    if {![regexp {^([0-9a-f]{40}|[0-9a-f]{64})$} $value]} {
        _raise FAIL $check_name SOURCE_REVISION_INVALID \
            "$label must be a full lowercase Git object identity."
    }
    return $value
}

proc ::stage1d::delivery_bundle_loader::_validate_logical_relative_path {
    path
    label
    check_name
} {
    if {$path eq {} || [string first [format %c 92] $path] >= 0 ||
        [file pathtype $path] ne {relative} ||
        [regexp {^[A-Za-z]:} $path] ||
        [string match {//*} $path]} {
        _raise FAIL $check_name ABSOLUTE_OR_AMBIENT_PATH_REJECTED \
            "$label must be a canonical relative path."
    }
    set components [split $path /]
    foreach component $components {
        if {$component in {{} . ..}} {
            _raise FAIL $check_name TRAVERSAL_PATH_REJECTED \
                "$label contains an empty, current-directory, or traversal component."
        }
    }
    return [join $components /]
}

proc ::stage1d::delivery_bundle_loader::_canonical_components {path} {
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

proc ::stage1d::delivery_bundle_loader::_is_equal_or_descendant {
    candidate
    parent
} {
    set candidate_components [_canonical_components $candidate]
    set parent_components [_canonical_components $parent]
    if {[llength $candidate_components] < [llength $parent_components]} {
        return 0
    }
    for {set index 0} {$index < [llength $parent_components]} {incr index} {
        if {[lindex $candidate_components $index] ne \
            [lindex $parent_components $index]} {
            return 0
        }
    }
    return 1
}

proc ::stage1d::delivery_bundle_loader::_resolve_bundle_file {
    bundle_root
    relative_path
    label
    check_name
    {missing_status BLOCKED}
} {
    set relative_path [_validate_logical_relative_path \
        $relative_path $label $check_name]
    set components [split $relative_path /]
    set cursor $bundle_root
    foreach component $components {
        set candidate [file join $cursor $component]
        if {[file exists $candidate] && [file type $candidate] eq {link}} {
            set link_target [file normalize $candidate]
            if {![_is_equal_or_descendant $link_target $bundle_root]} {
                _raise FAIL $check_name ESCAPING_SYMLINK_REJECTED \
                    "$label resolves through a symlink outside the bundle root."
            }
            set cursor $link_target
        } else {
            set cursor $candidate
        }
    }

    set resolved [file normalize $cursor]
    if {![_is_equal_or_descendant $resolved $bundle_root]} {
        _raise FAIL $check_name PATH_CONTAINMENT_FAILED \
            "$label escapes the selected bundle root."
    }
    if {![file exists $resolved] || ![file isfile $resolved]} {
        _raise $missing_status $check_name BUNDLE_MEMBER_NOT_FOUND \
            "$label is not an existing regular bundle member."
    }
    return [list $relative_path $resolved]
}

proc ::stage1d::delivery_bundle_loader::_validate_source_inventory {
    inventory
    check_name
} {
    set inventory_error {}
    if {[catch {llength $inventory} inventory_error] ||
        [llength $inventory] == 0} {
        _raise FAIL $check_name SOURCE_INVENTORY_INVALID \
            "source_identity source_inventory must be a nonempty list: $inventory_error"
    }

    variable source_inventory_fields
    set normalized {}
    set seen [dict create]
    foreach entry $inventory {
        set parsed [_parse_declarative_dict $entry \
            {source inventory entry} $check_name]
        _require_exact_fields $parsed $source_inventory_fields \
            {source inventory entry} $check_name
        set path [_validate_logical_relative_path \
            [dict get $parsed path] {source inventory path} $check_name]
        if {[dict exists $seen $path]} {
            _raise FAIL $check_name SOURCE_INVENTORY_DUPLICATE_PATH \
                "source_identity contains a duplicate inventory path: $path"
        }
        dict set seen $path 1
        set size [dict get $parsed size]
        if {![string is integer -strict $size] || $size < 0} {
            _raise FAIL $check_name SOURCE_INVENTORY_SIZE_INVALID \
                "Source inventory size is invalid for: $path"
        }
        set hash [_validate_sha256 [dict get $parsed sha256] \
            {source inventory SHA-256} $check_name]
        lappend normalized [dict create \
            path $path \
            size $size \
            sha256 $hash]
    }
    return $normalized
}

proc ::stage1d::delivery_bundle_loader::_validate_source_identity {
    value
    label
    check_name
    {allow_additional_fields 0}
} {
    variable source_identity_required_fields
    set parsed [_parse_declarative_dict $value $label $check_name]
    if {!$allow_additional_fields} {
        _require_exact_fields $parsed $source_identity_required_fields \
            $label $check_name
    }
    foreach required_field $source_identity_required_fields {
        if {![dict exists $parsed $required_field]} {
            _raise FAIL $check_name SOURCE_IDENTITY_FIELD_MISSING \
                "$label is missing required field: $required_field"
        }
    }
    dict set parsed git_commit [_validate_source_revision \
        [dict get $parsed git_commit] "$label git_commit" $check_name]
    dict set parsed controller_source_hash [_validate_sha256 \
        [dict get $parsed controller_source_hash] \
        "$label controller_source_hash" $check_name]
    dict set parsed configuration_hash [_validate_sha256 \
        [dict get $parsed configuration_hash] \
        "$label configuration_hash" $check_name]
    dict set parsed source_inventory [_validate_source_inventory \
        [dict get $parsed source_inventory] $check_name]
    return $parsed
}

proc ::stage1d::delivery_bundle_loader::_validate_environment_identity {
    value
    label
    check_name
    {status FAIL}
} {
    variable environment_fields
    if {[catch {
        set parsed [_parse_declarative_dict $value $label $check_name]
        _require_exact_fields $parsed $environment_fields $label $check_name
    } parse_error parse_options]} {
        if {$status eq {FAIL}} {
            return -options $parse_options $parse_error
        }
        _raise $status $check_name ENVIRONMENT_IDENTITY_INVALID $parse_error
    }

    foreach field {vivado_version fpga_part board_part} {
        if {[string trim [dict get $parsed $field]] eq {}} {
            _raise $status $check_name ENVIRONMENT_FIELD_EMPTY \
                "$label field is empty: $field"
        }
    }
    set identities [dict get $parsed required_ip_identities]
    set identities_error {}
    if {[catch {llength $identities} identities_error] ||
        [llength $identities] == 0} {
        _raise $status $check_name REQUIRED_IP_IDENTITIES_INVALID \
            "$label required_ip_identities must be a nonempty list: $identities_error"
    }
    set normalized_identities {}
    set seen [dict create]
    foreach identity $identities {
        if {[string trim $identity] eq {} || [dict exists $seen $identity]} {
            _raise $status $check_name REQUIRED_IP_IDENTITY_INVALID \
                "$label contains an empty or duplicate required IP identity."
        }
        dict set seen $identity 1
        lappend normalized_identities $identity
    }
    dict set parsed required_ip_identities $normalized_identities
    return $parsed
}

proc ::stage1d::delivery_bundle_loader::_validate_scope {value} {
    variable scope_fields
    set check_name PROFILE_SCOPE_VALID
    set parsed [_parse_declarative_dict $value {profile scope} $check_name]
    _require_exact_fields $parsed $scope_fields {profile scope} $check_name

    if {[dict get $parsed phase_limit] ne {MUTATION_EXECUTE}} {
        _raise BLOCKED $check_name PROFILE_PHASE_LIMIT_INVALID \
            {Profile phase_limit must equal MUTATION_EXECUTE.}
    }
    foreach field {
        project_operations
        design_operations
        mutation_operations
    } {
        if {[dict get $parsed $field] ne {1}} {
            _raise BLOCKED $check_name PROFILE_PERMISSION_INVALID \
                "Profile permission must equal canonical integer 1: $field"
        }
    }
    return $parsed
}

proc ::stage1d::delivery_bundle_loader::_validate_evidence_policy {
    value
    check_name
} {
    variable evidence_policy_fields
    set parsed [_parse_declarative_dict \
        $value {profile evidence_policy} $check_name]
    _require_exact_fields $parsed $evidence_policy_fields \
        {profile evidence_policy} $check_name
    foreach field $evidence_policy_fields {
        if {[dict get $parsed $field] ne {1}} {
            _raise FAIL $check_name EVIDENCE_POLICY_INVALID \
                "Stage 1D evidence policy field must equal canonical integer 1: $field"
        }
    }
    return $parsed
}

proc ::stage1d::delivery_bundle_loader::_canonical_source_inventory {
    inventory
} {
    variable source_inventory_fields
    set normalized {}
    foreach entry $inventory {
        set canonical_entry {}
        foreach field $source_inventory_fields {
            lappend canonical_entry $field [dict get $entry $field]
        }
        lappend normalized $canonical_entry
    }
    return $normalized
}

proc ::stage1d::delivery_bundle_loader::_canonical_source_identity {
    identity
} {
    set canonical {}
    foreach field [lsort [dict keys $identity]] {
        set value [dict get $identity $field]
        if {$field eq {source_inventory}} {
            set value [_canonical_source_inventory $value]
        }
        lappend canonical $field $value
    }
    return $canonical
}

proc ::stage1d::delivery_bundle_loader::_canonical_environment_identity {
    identity
} {
    variable environment_fields
    set canonical {}
    foreach field $environment_fields {
        set value [dict get $identity $field]
        if {$field eq {required_ip_identities}} {
            set value [lrange $value 0 end]
        }
        lappend canonical $field $value
    }
    return $canonical
}

proc ::stage1d::delivery_bundle_loader::_canonical_ordered_dict {
    value
    fields
} {
    set canonical {}
    foreach field $fields {
        lappend canonical $field [dict get $value $field]
    }
    return $canonical
}

proc ::stage1d::delivery_bundle_loader::_canonical_sorted_dict {value} {
    set canonical {}
    foreach field [lsort [dict keys $value]] {
        lappend canonical $field [dict get $value $field]
    }
    return $canonical
}

proc ::stage1d::delivery_bundle_loader::_profile_field_value {
    profile
    field
} {
    variable scope_fields
    variable evidence_policy_fields
    switch -- $field {
        environment_identity {
            return [_canonical_environment_identity \
                [dict get $profile $field]]
        }
        scope {
            return [_canonical_ordered_dict \
                [dict get $profile $field] $scope_fields]
        }
        evidence_policy {
            return [_canonical_ordered_dict \
                [dict get $profile $field] $evidence_policy_fields]
        }
        default {
            return [dict get $profile $field]
        }
    }
}

proc ::stage1d::delivery_bundle_loader::_manifest_field_value {
    manifest
    field
} {
    switch -- $field {
        source_identity {
            return [_canonical_source_identity \
                [dict get $manifest $field]]
        }
        environment_identity {
            return [_canonical_environment_identity \
                [dict get $manifest $field]]
        }
        provenance {
            return [_canonical_sorted_dict [dict get $manifest $field]]
        }
        default {
            return [dict get $manifest $field]
        }
    }
}

proc ::stage1d::delivery_bundle_loader::canonical_profile_payload {profile} {
    variable profile_hash_fields
    set payload {}
    foreach field $profile_hash_fields {
        append payload $field { } \
            [list [_profile_field_value $profile $field]] "\n"
    }
    return $payload
}

proc ::stage1d::delivery_bundle_loader::serialize_profile {profile} {
    variable profile_fields
    set document {}
    foreach field $profile_fields {
        append document $field { } \
            [list [_profile_field_value $profile $field]] "\n"
    }
    return $document
}

proc ::stage1d::delivery_bundle_loader::canonical_manifest_payload {manifest} {
    variable manifest_hash_fields
    set payload {}
    foreach field $manifest_hash_fields {
        append payload $field { } \
            [list [_manifest_field_value $manifest $field]] "\n"
    }
    return $payload
}

proc ::stage1d::delivery_bundle_loader::serialize_manifest {manifest} {
    variable manifest_fields
    set document {}
    foreach field $manifest_fields {
        append document $field { } \
            [list [_manifest_field_value $manifest $field]] "\n"
    }
    return $document
}

proc ::stage1d::delivery_bundle_loader::serialize_source_reference {
    source_reference
} {
    variable source_reference_fields
    set document {}
    foreach field $source_reference_fields {
        set value [dict get $source_reference $field]
        if {$field eq {source_identity}} {
            set value [_canonical_source_identity $value]
        }
        append document $field { } [list $value] "\n"
    }
    return $document
}

proc ::stage1d::delivery_bundle_loader::_sha256_text {text} {
    if {[llength [info procs ::stage1d::source_check::sha256_text]] != 1} {
        error {Stage 1D source_check::sha256_text is unavailable.}
    }
    return [::stage1d::source_check::sha256_text $text]
}

proc ::stage1d::delivery_bundle_loader::profile_fingerprint {profile} {
    return [_sha256_text [canonical_profile_payload $profile]]
}

proc ::stage1d::delivery_bundle_loader::manifest_fingerprint {manifest} {
    return [_sha256_text [canonical_manifest_payload $manifest]]
}

proc ::stage1d::delivery_bundle_loader::_validate_manifest_schema {
    manifest
} {
    variable manifest_fields
    variable manifest_schema_version
    set check_name BUNDLE_MANIFEST_SCHEMA_VALID

    _require_exact_fields $manifest $manifest_fields \
        {bundle manifest} $check_name
    if {[dict get $manifest schema_version] ne $manifest_schema_version} {
        _raise FAIL $check_name MANIFEST_SCHEMA_VERSION_UNSUPPORTED \
            "Unsupported bundle manifest schema_version: [dict get $manifest schema_version]"
    }
    dict set manifest bundle_id [_validate_identifier \
        [dict get $manifest bundle_id] bundle_id $check_name]
    dict set manifest manifest_sha256 [_validate_sha256 \
        [dict get $manifest manifest_sha256] manifest_sha256 $check_name]
    dict set manifest source_revision [_validate_source_revision \
        [dict get $manifest source_revision] source_revision $check_name]
    dict set manifest profile_sha256 [_validate_sha256 \
        [dict get $manifest profile_sha256] profile_sha256 $check_name]
    if {[string trim [dict get $manifest profile_path]] eq {}} {
        _raise FAIL $check_name PROFILE_PATH_EMPTY \
            {Bundle manifest profile_path is empty.}
    }
    dict set manifest source_identity [_validate_source_identity \
        [dict get $manifest source_identity] \
        {bundle manifest source_identity} $check_name]
    dict set manifest environment_identity [_validate_environment_identity \
        [dict get $manifest environment_identity] \
        {bundle manifest environment_identity} $check_name]
    set provenance [_parse_declarative_dict \
        [dict get $manifest provenance] \
        {bundle manifest provenance} $check_name]
    if {[dict size $provenance] == 0} {
        _raise FAIL $check_name PROVENANCE_EMPTY \
            {Bundle manifest provenance is empty.}
    }
    dict set manifest provenance $provenance
    return $manifest
}

proc ::stage1d::delivery_bundle_loader::_validate_profile_required_fields {
    profile
} {
    variable profile_fields
    variable scope_fields
    set check_name PROFILE_REQUIRED_FIELDS_VALID

    _require_exact_fields $profile $profile_fields \
        {executable profile} $check_name
    dict set profile profile_id [_validate_identifier \
        [dict get $profile profile_id] profile_id $check_name]
    dict set profile profile_version [_validate_identifier \
        [dict get $profile profile_version] profile_version $check_name]
    dict set profile profile_sha256 [_validate_sha256 \
        [dict get $profile profile_sha256] profile_sha256 $check_name]
    dict set profile source_revision [_validate_source_revision \
        [dict get $profile source_revision] source_revision $check_name]
    dict set profile environment_identity [_validate_environment_identity \
        [dict get $profile environment_identity] \
        {profile environment_identity} $check_name]
    set scope [_parse_declarative_dict \
        [dict get $profile scope] {profile scope} $check_name]
    _require_exact_fields $scope $scope_fields {profile scope} $check_name
    dict set profile scope $scope
    dict set profile evidence_policy [_validate_evidence_policy \
        [dict get $profile evidence_policy] $check_name]
    return $profile
}

proc ::stage1d::delivery_bundle_loader::_validate_source_reference {
    source_reference
} {
    variable source_reference_fields
    set check_name PROFILE_SOURCE_BINDING_VALID
    _require_exact_fields $source_reference $source_reference_fields \
        source_reference $check_name
    dict set source_reference source_revision [_validate_source_revision \
        [dict get $source_reference source_revision] \
        {source_reference source_revision} $check_name]
    dict set source_reference source_identity [_validate_source_identity \
        [dict get $source_reference source_identity] \
        {source_reference source_identity} $check_name]
    return $source_reference
}

proc ::stage1d::delivery_bundle_loader::_source_identity_matches {
    declared
    accepted
} {
    foreach field [dict keys $declared] {
        if {![dict exists $accepted $field] ||
            [dict get $declared $field] ne [dict get $accepted $field]} {
            return 0
        }
    }
    return 1
}

proc ::stage1d::delivery_bundle_loader::_load {
    selected_bundle_root
    accepted_source_identity
    accepted_environment_identity
    checks_variable
} {
    upvar 1 $checks_variable checks
    variable profile_schema_version

    if {[string trim $selected_bundle_root] eq {} ||
        ![file exists $selected_bundle_root] ||
        ![file isdirectory $selected_bundle_root]} {
        _raise BLOCKED BUNDLE_MANIFEST_SCHEMA_VALID BUNDLE_NOT_SELECTED \
            {The explicitly selected delivery bundle root is unavailable.}
    }
    set bundle_root [file normalize $selected_bundle_root]

    lassign [_resolve_bundle_file $bundle_root manifest.dict \
        manifest.dict BUNDLE_MANIFEST_SCHEMA_VALID] \
        manifest_relative manifest_path
    set manifest_text [_read_text_file $manifest_path \
        manifest.dict BUNDLE_MANIFEST_SCHEMA_VALID]
    set manifest [_parse_declarative_dict $manifest_text \
        {bundle manifest} BUNDLE_MANIFEST_SCHEMA_VALID]
    set manifest [_validate_manifest_schema $manifest]
    dict set checks BUNDLE_MANIFEST_SCHEMA_VALID PASS

    set calculated_manifest_hash [manifest_fingerprint $manifest]
    if {$calculated_manifest_hash ne [dict get $manifest manifest_sha256]} {
        _raise FAIL BUNDLE_MANIFEST_HASH_VALID MANIFEST_HASH_MISMATCH \
            "Bundle manifest SHA-256 mismatch: calculated=$calculated_manifest_hash recorded=[dict get $manifest manifest_sha256]"
    }
    dict set checks BUNDLE_MANIFEST_HASH_VALID PASS

    set declared_profile_path [dict get $manifest profile_path]
    set canonical_profile_path [_validate_logical_relative_path \
        $declared_profile_path profile_path BUNDLE_PATH_CONTAINMENT_VALID]
    set profile_components [split $canonical_profile_path /]
    if {[llength $profile_components] < 2 ||
        [lindex $profile_components 0] ne {profile}} {
        _raise FAIL BUNDLE_PATH_CONTAINMENT_VALID PROFILE_DIRECTORY_REQUIRED \
            {profile_path must identify a file below the bundle profile/ directory.}
    }
    lassign [_resolve_bundle_file $bundle_root $canonical_profile_path \
        {selected executable profile} BUNDLE_PATH_CONTAINMENT_VALID] \
        profile_relative profile_path
    lassign [_resolve_bundle_file $bundle_root source_reference \
        source_reference BUNDLE_PATH_CONTAINMENT_VALID] \
        source_reference_relative source_reference_path
    dict set checks BUNDLE_PATH_CONTAINMENT_VALID PASS

    set profile_text [_read_text_file $profile_path \
        {selected executable profile} PROFILE_PARSE_SIDE_EFFECT_FREE]
    set profile [_parse_declarative_dict $profile_text \
        {selected executable profile} PROFILE_PARSE_SIDE_EFFECT_FREE]
    dict set checks PROFILE_PARSE_SIDE_EFFECT_FREE PASS

    set profile [_validate_profile_required_fields $profile]
    dict set checks PROFILE_REQUIRED_FIELDS_VALID PASS

    if {[dict get $profile schema_version] ne $profile_schema_version} {
        _raise FAIL PROFILE_SCHEMA_VERSION_SUPPORTED \
            PROFILE_SCHEMA_VERSION_UNSUPPORTED \
            "Unsupported executable profile schema_version: [dict get $profile schema_version]"
    }
    dict set checks PROFILE_SCHEMA_VERSION_SUPPORTED PASS

    set calculated_profile_hash [profile_fingerprint $profile]
    if {$calculated_profile_hash ne [dict get $profile profile_sha256] ||
        $calculated_profile_hash ne [dict get $manifest profile_sha256]} {
        _raise FAIL PROFILE_HASH_VALID PROFILE_HASH_MISMATCH \
            "Executable profile SHA-256 mismatch: calculated=$calculated_profile_hash profile=[dict get $profile profile_sha256] manifest=[dict get $manifest profile_sha256]"
    }
    dict set checks PROFILE_HASH_VALID PASS

    set validated_scope [_validate_scope [dict get $profile scope]]
    dict set profile scope $validated_scope
    dict set checks PROFILE_SCOPE_VALID PASS

    set accepted_environment [_validate_environment_identity \
        $accepted_environment_identity {accepted environment identity} \
        PROFILE_ENVIRONMENT_BINDING_VALID BLOCKED]
    set manifest_environment [dict get $manifest environment_identity]
    set profile_environment [dict get $profile environment_identity]
    if {$manifest_environment ne $profile_environment ||
        $profile_environment ne $accepted_environment} {
        _raise BLOCKED PROFILE_ENVIRONMENT_BINDING_VALID \
            PROFILE_ENVIRONMENT_MISMATCH \
            {Manifest, profile, and accepted preflight environment identities do not match exactly.}
    }
    dict set checks PROFILE_ENVIRONMENT_BINDING_VALID PASS

    set source_reference_text [_read_text_file $source_reference_path \
        source_reference PROFILE_SOURCE_BINDING_VALID]
    set source_reference [_parse_declarative_dict $source_reference_text \
        source_reference PROFILE_SOURCE_BINDING_VALID]
    set source_reference [_validate_source_reference $source_reference]
    set accepted_source [_validate_source_identity $accepted_source_identity \
        {accepted source identity} PROFILE_SOURCE_BINDING_VALID 1]
    set manifest_source [dict get $manifest source_identity]
    set manifest_revision [dict get $manifest source_revision]
    set profile_revision [dict get $profile source_revision]
    set accepted_revision [dict get $accepted_source git_commit]
    if {$manifest_revision ne $profile_revision ||
        $manifest_revision ne $accepted_revision ||
        [dict get $manifest_source git_commit] ne $manifest_revision ||
        [dict get $source_reference source_revision] ne $manifest_revision ||
        [dict get $source_reference source_identity] ne $manifest_source ||
        ![_source_identity_matches $manifest_source $accepted_source]} {
        _raise BLOCKED PROFILE_SOURCE_BINDING_VALID \
            PROFILE_SOURCE_BINDING_MISMATCH \
            {Manifest, profile, source reference, and accepted source identities do not match exactly.}
    }
    dict set checks PROFILE_SOURCE_BINDING_VALID PASS

    set bundle_identity [dict create \
        bundle_id [dict get $manifest bundle_id] \
        manifest_sha256 [dict get $manifest manifest_sha256] \
        source_revision $manifest_revision \
        profile_path $profile_relative \
        profile_sha256 $calculated_profile_hash]
    set profile_identity [dict create \
        profile_id [dict get $profile profile_id] \
        profile_version [dict get $profile profile_version] \
        profile_sha256 $calculated_profile_hash \
        source_revision $profile_revision]
    set outputs [dict create \
        validated_manifest $manifest \
        validated_profile $profile \
        manifest_path $manifest_relative \
        profile_path $profile_relative \
        source_reference_path $source_reference_relative \
        source_reference_verified 1 \
        authorization_assertion_generated 0]
    return [_result PASS $checks $bundle_identity $profile_identity \
        $manifest_source $profile_environment $validated_scope {} {} $outputs]
}

proc ::stage1d::delivery_bundle_loader::load {
    selected_bundle_root
    accepted_source_identity
    accepted_environment_identity
} {
    set checks [_new_check_state]
    set load_status [catch {
        _load $selected_bundle_root $accepted_source_identity \
            $accepted_environment_identity checks
    } result load_options]
    if {$load_status == 0} {
        return $result
    }

    set status FAIL
    set check_name BUNDLE_MANIFEST_SCHEMA_VALID
    set error_code DELIVERY_BUNDLE_LOADER_INTERNAL_ERROR
    set error_code_list {}
    if {[dict exists $load_options -errorcode]} {
        set error_code_list [dict get $load_options -errorcode]
    }
    if {[llength $error_code_list] == 5 &&
        [lrange $error_code_list 0 1] eq \
            {STAGE1D DELIVERY_BUNDLE_LOADER}} {
        set status [lindex $error_code_list 2]
        set check_name [lindex $error_code_list 3]
        set error_code [lindex $error_code_list 4]
    }
    if {[dict exists $checks $check_name]} {
        dict set checks $check_name $status
    }
    set error_record [_error_record \
        $check_name $error_code $result $status]
    return [_result $status $checks {} {} {} {} {} \
        [list $error_record] {} [dict create \
            authorization_assertion_generated 0]]
}
