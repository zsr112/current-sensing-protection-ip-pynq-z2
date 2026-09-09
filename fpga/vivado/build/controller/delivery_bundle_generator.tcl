# Stage 1D immutable delivery-bundle generator.
#
# Source-time contract:
# - define deterministic data validation and bundle assembly procedures;
# - do not inspect ambient execution state;
# - do not invoke Vivado, lifecycle adapters, mutation, or artifact generation.

namespace eval ::stage1d::delivery_bundle_generator {
    variable generator_version STAGE1D-DELIVERY-BUNDLE-GENERATOR-v1
    variable generation_phase BUNDLE_GENERATION
    variable bundle_directory_name stage1d-dry-run-v1
    variable bundle_id stage1d-dry-run-v1
    variable profile_id stage1d_controlled_dry_run_v1
    variable profile_relative_path \
        profile/stage1d_controlled_dry_run_v1.dict

    variable request_fields {
        schema_version
        bundle_id
        profile_id
        profile_version
        source_revision
        source_identity
        environment_identity
        scope
        evidence_policy
        provenance
    }
    variable source_identity_fields {
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
    variable provenance_fields {
        source_revision
        generator_identity
        generation_timestamp
        review_provenance
    }
    variable required_checks {
        GENERATOR_SCHEMA_VALID
        GENERATOR_HASH_VALID
        GENERATOR_SOURCE_BINDING_VALID
        GENERATOR_ENVIRONMENT_BINDING_VALID
        GENERATOR_DETERMINISTIC_OUTPUT
        GENERATOR_REPRODUCIBILITY_TEST
        GENERATOR_NO_AMBIENT_DEPENDENCY
        GENERATOR_SIDE_EFFECT_FREE
    }
}

proc ::stage1d::delivery_bundle_generator::version {} {
    variable generator_version
    return $generator_version
}

proc ::stage1d::delivery_bundle_generator::required_checks {} {
    variable required_checks
    return $required_checks
}

proc ::stage1d::delivery_bundle_generator::_raise {
    check_name
    error_code
    message
} {
    return -code error \
        -errorcode [list STAGE1D DELIVERY_BUNDLE_GENERATOR \
            FAIL $check_name $error_code] \
        $message
}

proc ::stage1d::delivery_bundle_generator::_require_dependencies {} {
    set loader_procedures {
        supported_manifest_schema_version
        supported_profile_schema_version
        profile_fingerprint
        manifest_fingerprint
        serialize_profile
        serialize_manifest
        serialize_source_reference
        load
    }
    foreach procedure_name $loader_procedures {
        set qualified_name \
            ::stage1d::delivery_bundle_loader::$procedure_name
        if {[llength [info procs $qualified_name]] != 1} {
            _raise GENERATOR_SCHEMA_VALID GENERATOR_DEPENDENCY_MISSING \
                "Required delivery-bundle loader procedure is unavailable: $qualified_name"
        }
    }
    if {[llength [info procs \
        ::stage1d::source_check::sha256_text]] != 1} {
        _raise GENERATOR_HASH_VALID GENERATOR_DEPENDENCY_MISSING \
            {Required source_check::sha256_text procedure is unavailable.}
    }
}

proc ::stage1d::delivery_bundle_generator::_parse_dict {
    value
    label
    check_name
} {
    if {[catch {llength $value} word_count_error]} {
        _raise $check_name DECLARATIVE_DICTIONARY_INVALID \
            "$label is not a valid Tcl list: $word_count_error"
    }
    set word_count [llength $value]
    if {$word_count == 0 || ($word_count % 2) != 0} {
        _raise $check_name DECLARATIVE_DICTIONARY_INVALID \
            "$label must contain an even, nonzero number of words."
    }

    set parsed [dict create]
    for {set index 0} {$index < $word_count} {incr index 2} {
        set field [lindex $value $index]
        set field_value [lindex $value [expr {$index + 1}]]
        if {[string trim $field] eq {}} {
            _raise $check_name EMPTY_FIELD_NAME \
                "$label contains an empty field name."
        }
        if {[dict exists $parsed $field]} {
            _raise $check_name DUPLICATE_FIELD \
                "$label contains a duplicate field: $field"
        }
        dict set parsed $field $field_value
    }
    return $parsed
}

proc ::stage1d::delivery_bundle_generator::_require_exact_fields {
    value
    expected_fields
    label
    check_name
} {
    set actual_fields [dict keys $value]
    if {[lsort $actual_fields] ne [lsort $expected_fields]} {
        _raise $check_name FIELD_SET_INVALID \
            "$label fields are invalid: expected=[lsort $expected_fields] actual=[lsort $actual_fields]"
    }
}

proc ::stage1d::delivery_bundle_generator::_validate_safe_scalar {
    value
    label
    check_name
} {
    if {[string trim $value] eq {}} {
        _raise $check_name EMPTY_VALUE "$label is empty."
    }
    foreach {token description} [list \
        [format %c 0] {NUL byte} \
        {$} {variable substitution} \
        {[} {command substitution} \
        {]} {command substitution} \
        {;} {statement separation} \
        [format %c 13] {carriage return} \
        [format %c 10] {line feed} \
        [format %c 92] {backslash path or escape}] {
        if {[string first $token $value] >= 0} {
            _raise $check_name EXECUTABLE_OR_AMBIENT_VALUE_REJECTED \
                "$label contains forbidden $description syntax."
        }
    }
    if {[regexp {^[ 	]*(source|eval|uplevel|exec|proc)([ 	]|$)} \
        $value]} {
        _raise $check_name EXECUTABLE_STATEMENT_REJECTED \
            "$label contains a forbidden executable statement."
    }
    if {[regexp {^(~(/|$)|/|[A-Za-z]:/|//)} $value] ||
        [regexp {(^|[^A-Za-z0-9])([A-Za-z]:/|/(Users|home)/)} \
            $value]} {
        _raise $check_name ABSOLUTE_AUTHOR_PATH_REJECTED \
            "$label contains an absolute or author-local path."
    }
    return $value
}

proc ::stage1d::delivery_bundle_generator::_validate_identifier {
    value
    label
    check_name
} {
    _validate_safe_scalar $value $label $check_name
    if {![regexp {^[A-Za-z0-9][A-Za-z0-9._-]*$} $value]} {
        _raise $check_name IDENTIFIER_INVALID \
            "$label must be a stable identifier."
    }
    return $value
}

proc ::stage1d::delivery_bundle_generator::_validate_sha256 {
    value
    label
    check_name
} {
    if {![regexp {^[0-9a-f]{64}$} $value]} {
        _raise $check_name SHA256_INVALID \
            "$label must contain 64 lowercase hexadecimal characters."
    }
    return $value
}

proc ::stage1d::delivery_bundle_generator::_validate_source_revision {
    value
    label
    check_name
} {
    if {![regexp {^([0-9a-f]{40}|[0-9a-f]{64})$} $value]} {
        _raise $check_name SOURCE_REVISION_INVALID \
            "$label must be a full lowercase Git object identity."
    }
    return $value
}

proc ::stage1d::delivery_bundle_generator::_validate_relative_path {
    value
    label
    check_name
} {
    _validate_safe_scalar $value $label $check_name
    if {[file pathtype $value] ne {relative} ||
        [regexp {^[A-Za-z]:} $value] ||
        [string match {//*} $value]} {
        _raise $check_name ABSOLUTE_AUTHOR_PATH_REJECTED \
            "$label must be a canonical relative path."
    }
    foreach component [split $value /] {
        if {$component in {{} . ..}} {
            _raise $check_name AMBIENT_OR_TRAVERSAL_PATH_REJECTED \
                "$label contains an empty, ambient, or traversal component."
        }
        if {![regexp {^[A-Za-z0-9._-]+$} $component]} {
            _raise $check_name SOURCE_PATH_INVALID \
                "$label contains a nonportable path component."
        }
    }
    return [join [split $value /] /]
}

proc ::stage1d::delivery_bundle_generator::_validate_source_inventory {
    inventory
} {
    variable source_inventory_fields
    set check_name GENERATOR_SCHEMA_VALID
    if {[catch {llength $inventory} inventory_error] ||
        [llength $inventory] == 0} {
        _raise $check_name SOURCE_INVENTORY_INVALID \
            "source_inventory must be a nonempty list: $inventory_error"
    }

    set normalized {}
    set seen [dict create]
    foreach entry $inventory {
        set parsed [_parse_dict $entry {source inventory entry} \
            $check_name]
        _require_exact_fields $parsed $source_inventory_fields \
            {source inventory entry} $check_name
        set path [_validate_relative_path [dict get $parsed path] \
            {source inventory path} GENERATOR_NO_AMBIENT_DEPENDENCY]
        if {[dict exists $seen $path]} {
            _raise $check_name SOURCE_INVENTORY_DUPLICATE_PATH \
                "source_inventory contains a duplicate path: $path"
        }
        dict set seen $path 1
        set size [dict get $parsed size]
        if {![string is integer -strict $size] || $size < 0} {
            _raise $check_name SOURCE_INVENTORY_SIZE_INVALID \
                "Source inventory size is invalid for: $path"
        }
        set hash [_validate_sha256 [dict get $parsed sha256] \
            {source inventory SHA-256} $check_name]
        lappend normalized [dict create \
            path $path \
            size [expr {$size + 0}] \
            sha256 $hash]
    }
    return $normalized
}

proc ::stage1d::delivery_bundle_generator::_validate_source_identity {
    value
} {
    variable source_identity_fields
    set check_name GENERATOR_SCHEMA_VALID
    set parsed [_parse_dict $value {accepted source identity} $check_name]
    _require_exact_fields $parsed $source_identity_fields \
        {accepted source identity} $check_name

    set git_commit [_validate_source_revision \
        [dict get $parsed git_commit] \
        {accepted source identity git_commit} $check_name]
    set controller_hash [_validate_sha256 \
        [dict get $parsed controller_source_hash] \
        {accepted source identity controller_source_hash} $check_name]
    set configuration_hash [_validate_sha256 \
        [dict get $parsed configuration_hash] \
        {accepted source identity configuration_hash} $check_name]
    set inventory [_validate_source_inventory \
        [dict get $parsed source_inventory]]

    return [dict create \
        git_commit $git_commit \
        controller_source_hash $controller_hash \
        configuration_hash $configuration_hash \
        source_inventory $inventory]
}

proc ::stage1d::delivery_bundle_generator::_validate_environment_identity {
    value
} {
    variable environment_fields
    set check_name GENERATOR_ENVIRONMENT_BINDING_VALID
    set parsed [_parse_dict $value {accepted environment identity} \
        $check_name]
    _require_exact_fields $parsed $environment_fields \
        {accepted environment identity} $check_name

    set normalized [dict create]
    foreach field {vivado_version fpga_part board_part} {
        set field_value [_validate_safe_scalar [dict get $parsed $field] \
            "accepted environment identity $field" $check_name]
        dict set normalized $field $field_value
    }

    set identities [dict get $parsed required_ip_identities]
    if {[catch {llength $identities} identities_error] ||
        [llength $identities] == 0} {
        _raise $check_name REQUIRED_IP_IDENTITIES_INVALID \
            "required_ip_identities must be a nonempty list: $identities_error"
    }
    set normalized_identities {}
    set seen [dict create]
    foreach identity $identities {
        set identity [_validate_safe_scalar $identity \
            {required IP identity} $check_name]
        if {[dict exists $seen $identity]} {
            _raise $check_name REQUIRED_IP_IDENTITY_DUPLICATE \
                "Duplicate required IP identity: $identity"
        }
        dict set seen $identity 1
        lappend normalized_identities $identity
    }
    dict set normalized required_ip_identities $normalized_identities
    return $normalized
}

proc ::stage1d::delivery_bundle_generator::_validate_scope {value} {
    variable scope_fields
    set check_name GENERATOR_SCHEMA_VALID
    set parsed [_parse_dict $value {reviewed profile scope} $check_name]
    _require_exact_fields $parsed $scope_fields \
        {reviewed profile scope} $check_name
    if {[dict get $parsed phase_limit] ne {MUTATION_EXECUTE}} {
        _raise $check_name PROFILE_SCOPE_INVALID \
            {phase_limit must equal MUTATION_EXECUTE.}
    }
    foreach field {
        project_operations
        design_operations
        mutation_operations
    } {
        if {[dict get $parsed $field] ne {1}} {
            _raise $check_name PROFILE_SCOPE_INVALID \
                "Stage 1D scope field must equal canonical integer 1: $field"
        }
    }
    set normalized [dict create]
    foreach field $scope_fields {
        dict set normalized $field [dict get $parsed $field]
    }
    return $normalized
}

proc ::stage1d::delivery_bundle_generator::_validate_evidence_policy {
    value
} {
    variable evidence_policy_fields
    set check_name GENERATOR_SCHEMA_VALID
    set parsed [_parse_dict $value {evidence policy} $check_name]
    _require_exact_fields $parsed $evidence_policy_fields \
        {evidence policy} $check_name
    set normalized [dict create]
    foreach field $evidence_policy_fields {
        if {[dict get $parsed $field] ne {1}} {
            _raise $check_name EVIDENCE_POLICY_INVALID \
                "Stage 1D evidence policy field must equal canonical integer 1: $field"
        }
        dict set normalized $field 1
    }
    return $normalized
}

proc ::stage1d::delivery_bundle_generator::_validate_provenance {
    value
} {
    variable provenance_fields
    variable generator_version
    set check_name GENERATOR_SCHEMA_VALID
    set parsed [_parse_dict $value {generation provenance} $check_name]
    _require_exact_fields $parsed $provenance_fields \
        {generation provenance} $check_name

    set source_revision [_validate_source_revision \
        [dict get $parsed source_revision] \
        {generation provenance source_revision} $check_name]
    set generator_identity [_validate_identifier \
        [dict get $parsed generator_identity] \
        {generation provenance generator_identity} $check_name]
    if {$generator_identity ne $generator_version} {
        _raise $check_name GENERATOR_IDENTITY_MISMATCH \
            {generation provenance does not identify this generator version.}
    }
    set generation_timestamp [dict get $parsed generation_timestamp]
    _validate_safe_scalar $generation_timestamp \
        {generation provenance generation_timestamp} $check_name
    if {![regexp \
        {^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$} \
        $generation_timestamp]} {
        _raise $check_name GENERATION_TIMESTAMP_INVALID \
            {generation_timestamp must use YYYY-MM-DDTHH:MM:SSZ UTC form.}
    }
    set review_provenance [_validate_identifier \
        [dict get $parsed review_provenance] \
        {generation provenance review_provenance} $check_name]

    return [dict create \
        source_revision $source_revision \
        generator_identity $generator_identity \
        generation_timestamp $generation_timestamp \
        review_provenance $review_provenance]
}

proc ::stage1d::delivery_bundle_generator::_validate_request {request} {
    variable request_fields
    variable bundle_id
    variable profile_id

    set check_name GENERATOR_SCHEMA_VALID
    set parsed [_parse_dict $request {generation request} $check_name]
    _require_exact_fields $parsed $request_fields \
        {generation request} $check_name

    set schema_version [_validate_identifier \
        [dict get $parsed schema_version] schema_version $check_name]
    set manifest_schema \
        [::stage1d::delivery_bundle_loader::supported_manifest_schema_version]
    set profile_schema \
        [::stage1d::delivery_bundle_loader::supported_profile_schema_version]
    if {$schema_version ne $manifest_schema ||
        $schema_version ne $profile_schema} {
        _raise $check_name SCHEMA_VERSION_UNSUPPORTED \
            "Generator schema_version is unsupported: $schema_version"
    }

    set requested_bundle_id [_validate_identifier \
        [dict get $parsed bundle_id] bundle_id $check_name]
    if {$requested_bundle_id ne $bundle_id} {
        _raise $check_name BUNDLE_ID_INVALID \
            "The Stage 1D bundle_id must equal: $bundle_id"
    }
    set requested_profile_id [_validate_identifier \
        [dict get $parsed profile_id] profile_id $check_name]
    if {$requested_profile_id ne $profile_id} {
        _raise $check_name PROFILE_ID_INVALID \
            "The Stage 1D profile_id must equal: $profile_id"
    }
    set profile_version [_validate_identifier \
        [dict get $parsed profile_version] profile_version $check_name]
    set source_revision [_validate_source_revision \
        [dict get $parsed source_revision] source_revision \
        GENERATOR_SOURCE_BINDING_VALID]
    set source_identity [_validate_source_identity \
        [dict get $parsed source_identity]]
    if {$source_revision ne [dict get $source_identity git_commit]} {
        _raise GENERATOR_SOURCE_BINDING_VALID SOURCE_REVISION_MISMATCH \
            {source_revision must exactly equal accepted source_identity.git_commit.}
    }

    set environment_identity [_validate_environment_identity \
        [dict get $parsed environment_identity]]
    set scope [_validate_scope [dict get $parsed scope]]
    set evidence_policy [_validate_evidence_policy \
        [dict get $parsed evidence_policy]]
    set provenance [_validate_provenance [dict get $parsed provenance]]
    if {[dict get $provenance source_revision] ne $source_revision} {
        _raise GENERATOR_SOURCE_BINDING_VALID PROVENANCE_SOURCE_MISMATCH \
            {Provenance source_revision must equal the frozen source revision.}
    }

    return [dict create \
        schema_version $schema_version \
        bundle_id $requested_bundle_id \
        profile_id $requested_profile_id \
        profile_version $profile_version \
        source_revision $source_revision \
        source_identity $source_identity \
        environment_identity $environment_identity \
        scope $scope \
        evidence_policy $evidence_policy \
        provenance $provenance]
}

proc ::stage1d::delivery_bundle_generator::_prepare_documents {request} {
    variable profile_relative_path
    set request [_validate_request $request]

    set profile [dict create \
        schema_version [dict get $request schema_version] \
        profile_id [dict get $request profile_id] \
        profile_version [dict get $request profile_version] \
        profile_sha256 [string repeat 0 64] \
        source_revision [dict get $request source_revision] \
        environment_identity [dict get $request environment_identity] \
        scope [dict get $request scope] \
        evidence_policy [dict get $request evidence_policy]]
    set profile_hash \
        [::stage1d::delivery_bundle_loader::profile_fingerprint $profile]
    _validate_sha256 $profile_hash profile_sha256 GENERATOR_HASH_VALID
    dict set profile profile_sha256 $profile_hash

    set manifest [dict create \
        schema_version [dict get $request schema_version] \
        bundle_id [dict get $request bundle_id] \
        manifest_sha256 [string repeat 0 64] \
        source_revision [dict get $request source_revision] \
        source_identity [dict get $request source_identity] \
        profile_path $profile_relative_path \
        profile_sha256 $profile_hash \
        environment_identity [dict get $request environment_identity] \
        provenance [dict get $request provenance]]
    set manifest_hash \
        [::stage1d::delivery_bundle_loader::manifest_fingerprint $manifest]
    _validate_sha256 $manifest_hash manifest_sha256 GENERATOR_HASH_VALID
    dict set manifest manifest_sha256 $manifest_hash

    set source_reference [dict create \
        source_revision [dict get $request source_revision] \
        source_identity [dict get $request source_identity]]
    set documents [dict create \
        manifest.dict \
            [::stage1d::delivery_bundle_loader::serialize_manifest \
                $manifest] \
        $profile_relative_path \
            [::stage1d::delivery_bundle_loader::serialize_profile \
                $profile] \
        source_reference \
            [::stage1d::delivery_bundle_loader::serialize_source_reference \
                $source_reference]]

    return [dict create \
        request $request \
        profile $profile \
        manifest $manifest \
        source_reference $source_reference \
        documents $documents]
}

proc ::stage1d::delivery_bundle_generator::_canonical_components {path} {
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

proc ::stage1d::delivery_bundle_generator::_is_equal_or_descendant {
    candidate
    parent
} {
    set candidate_components [_canonical_components $candidate]
    set parent_components [_canonical_components $parent]
    if {[llength $candidate_components] < [llength $parent_components]} {
        return 0
    }
    for {set index 0} {$index < [llength $parent_components]} \
        {incr index} {
        if {[lindex $candidate_components $index] ne \
            [lindex $parent_components $index]} {
            return 0
        }
    }
    return 1
}

proc ::stage1d::delivery_bundle_generator::_validate_output_parent {
    output_parent
} {
    set check_name GENERATOR_NO_AMBIENT_DEPENDENCY
    if {[string trim $output_parent] eq {} ||
        [string first [format %c 0] $output_parent] >= 0 ||
        [string first {$} $output_parent] >= 0 ||
        [string first {[} $output_parent] >= 0 ||
        [string first {]} $output_parent] >= 0 ||
        [string first {;} $output_parent] >= 0 ||
        [file pathtype $output_parent] ne {absolute}} {
        _raise $check_name EXPLICIT_ABSOLUTE_OUTPUT_PARENT_REQUIRED \
            {output_parent must be an explicit absolute operational path.}
    }
    if {![file exists $output_parent] ||
        ![file isdirectory $output_parent]} {
        _raise $check_name OUTPUT_PARENT_UNAVAILABLE \
            {output_parent must identify an existing directory.}
    }
    if {[file type $output_parent] eq {link}} {
        _raise $check_name OUTPUT_PARENT_SYMLINK_REJECTED \
            {output_parent must not be a symbolic link.}
    }
    return [file normalize $output_parent]
}

proc ::stage1d::delivery_bundle_generator::_write_document {
    bundle_root
    relative_path
    content
} {
    set path [file normalize \
        [file join $bundle_root {*}[split $relative_path /]]]
    if {![_is_equal_or_descendant $path $bundle_root]} {
        _raise GENERATOR_NO_AMBIENT_DEPENDENCY \
            GENERATED_PATH_CONTAINMENT_FAILED \
            "Generated member escapes the bundle root: $relative_path"
    }
    file mkdir [file dirname $path]
    if {[catch {open $path {WRONLY CREAT EXCL}} channel]} {
        _raise GENERATOR_SIDE_EFFECT_FREE BUNDLE_MEMBER_CREATE_FAILED \
            "Unable to create bundle member $relative_path: $channel"
    }
    fconfigure $channel -encoding utf-8 -translation lf
    set write_status [catch {
        puts -nonewline $channel $content
    } write_error write_options]
    set close_status [catch {close $channel} close_error]
    if {$write_status != 0} {
        return -options $write_options $write_error
    }
    if {$close_status != 0} {
        _raise GENERATOR_SIDE_EFFECT_FREE BUNDLE_MEMBER_CLOSE_FAILED \
            "Unable to close bundle member $relative_path: $close_error"
    }
    return $relative_path
}

proc ::stage1d::delivery_bundle_generator::generate {
    output_parent
    generation_request
} {
    variable generator_version
    variable generation_phase
    variable bundle_directory_name
    variable profile_relative_path

    _require_dependencies
    set prepared [_prepare_documents $generation_request]
    set output_parent [_validate_output_parent $output_parent]
    set bundle_root [file normalize \
        [file join $output_parent $bundle_directory_name]]
    if {![_is_equal_or_descendant $bundle_root $output_parent] ||
        [file dirname $bundle_root] ne $output_parent} {
        _raise GENERATOR_NO_AMBIENT_DEPENDENCY \
            BUNDLE_ROOT_CONTAINMENT_FAILED \
            {The fixed bundle root is not contained by output_parent.}
    }
    if {[file exists $bundle_root]} {
        _raise GENERATOR_SIDE_EFFECT_FREE IMMUTABLE_BUNDLE_EXISTS \
            {The immutable Stage 1D bundle root already exists.}
    }

    set documents [dict get $prepared documents]
    file mkdir [file join $bundle_root profile]
    _write_document $bundle_root $profile_relative_path \
        [dict get $documents $profile_relative_path]
    _write_document $bundle_root source_reference \
        [dict get $documents source_reference]
    # Publish the manifest last so an incomplete write is never selectable as
    # a manifest-complete delivery bundle.
    _write_document $bundle_root manifest.dict \
        [dict get $documents manifest.dict]

    set request [dict get $prepared request]
    set loader_result [::stage1d::delivery_bundle_loader::load \
        $bundle_root \
        [dict get $request source_identity] \
        [dict get $request environment_identity]]
    if {[dict get $loader_result status] ne {PASS}} {
        set loader_error {generated bundle failed loader validation}
        if {[llength [dict get $loader_result errors]] != 0} {
            set loader_error [dict get \
                [lindex [dict get $loader_result errors] 0] message]
        }
        _raise GENERATOR_SCHEMA_VALID GENERATED_BUNDLE_REJECTED \
            "Generated bundle was rejected by the loader: $loader_error"
    }

    set expected_manifest [dict get $prepared manifest]
    set expected_profile [dict get $prepared profile]
    set loaded_bundle_identity [dict get $loader_result bundle_identity]
    if {[dict get $loaded_bundle_identity manifest_sha256] ne \
            [dict get $expected_manifest manifest_sha256] ||
        [dict get $loaded_bundle_identity profile_sha256] ne \
            [dict get $expected_profile profile_sha256]} {
        _raise GENERATOR_HASH_VALID GENERATED_HASH_REVALIDATION_FAILED \
            {Loader revalidation returned unexpected generated fingerprints.}
    }

    return [dict create \
        status PASS \
        phase $generation_phase \
        generator_version $generator_version \
        bundle_root $bundle_root \
        bundle_identity $loaded_bundle_identity \
        profile_identity [dict get $loader_result profile_identity] \
        source_identity [dict get $request source_identity] \
        environment_identity [dict get $request environment_identity] \
        validated_scope [dict get $request scope] \
        errors {} \
        warnings {} \
        outputs [dict create \
            manifest_path manifest.dict \
            profile_path $profile_relative_path \
            source_reference_path source_reference \
            authorization_assertion_generated 0 \
            side_effects [dict create \
                vivado_invoked 0 \
                project_opened 0 \
                bd_opened 0 \
                lifecycle_invoked 0 \
                mutation_invoked 0 \
                bd_validated 0 \
                bd_saved 0 \
                implementation_artifacts_generated 0]]]
}
