# Stage 1E WP-B IP packaging adapter.
#
# This module is definition-only when sourced. It accepts one explicit,
# controller-authorized context and owns only the temporary IP packaging
# lifecycle. It does not own project reconstruction, block-design work, build
# execution, FPGA artifact generation, or controller continuation decisions.

namespace eval ::stage1e::ip_packaging {
    variable context_schema_version stage1e-ip-packaging-context-v1
    variable result_schema_version stage1e-ip-packaging-result-v1
    variable package_inventory_schema_version \
        stage1e-ip-package-inventory-v1
    variable operation_name stage1e::ip_packaging::run
    variable phase_name IP_PACKAGING
}

namespace eval ::stage1e::ip_packaging::backend {}

# Reuse the existing source-verification SHA-256 implementation. Loading this
# dependency defines Tcl procedures only and performs no Vivado operation.
if {[llength [info commands ::stage1d::source_check::sha256_file]] == 0} {
    set ::stage1e::ip_packaging::_source_check_path [file normalize \
        [file join [file dirname [info script]] .. lib source_check.tcl]]
    source $::stage1e::ip_packaging::_source_check_path
    unset ::stage1e::ip_packaging::_source_check_path
}

# The single backend boundary keeps production command selection internal to
# the adapter and lets source-only tests replace one procedure with an isolated
# mock. Controller context cannot select or modify this backend.
proc ::stage1e::ip_packaging::backend::invoke {command arguments} {
    return [uplevel #0 [list $command {*}$arguments]]
}

# Vivado project handles carry an internal object representation that can be
# lost when current_project is stored and later passed back as a plain project
# name. Keep project property operations at this narrow production boundary so
# Vivado evaluates the explicit project object in the same command.
proc ::stage1e::ip_packaging::backend::set_current_project_property {
    property
    value
} {
    return [set_property $property $value [current_project]]
}

proc ::stage1e::ip_packaging::backend::get_current_project_property {
    property
} {
    return [get_property $property [current_project]]
}

# A fileset name is a lookup key, not a Vivado object. Resolve the object in
# the same command that consumes it so the Vivado Tcl object representation is
# not reduced to the plain name returned by current_fileset.
proc ::stage1e::ip_packaging::backend::set_fileset_property {
    fileset_name
    property
    value
} {
    return [set_property $property $value [get_filesets $fileset_name]]
}

proc ::stage1e::ip_packaging::backend::get_fileset_property {
    fileset_name
    property
} {
    return [get_property $property [get_filesets $fileset_name]]
}

proc ::stage1e::ip_packaging::_invoke {command args} {
    return [::stage1e::ip_packaging::backend::invoke $command $args]
}

# Vivado 2024.1 raises Coretcl 2-88 when current_project is queried in an
# empty session. Treat only that exact, expected condition as an empty handle.
# An existing handle remains an ownership conflict, and every other query
# failure remains fail-closed.
proc ::stage1e::ip_packaging::_is_no_open_project_error {
    message
    options
} {
    set expected \
        {ERROR: [Coretcl 2-88] No projects are currently open.}
    if {[string trim $message] eq $expected} {
        return 1
    }
    if {[dict exists $options -errorinfo]} {
        foreach line [split [dict get $options -errorinfo] "\n"] {
            if {[string trim $line] eq $expected} {
                return 1
            }
        }
    }
    return 0
}

proc ::stage1e::ip_packaging::_query_current_project_allow_empty {} {
    set query_status [catch {
        _invoke current_project
    } project query_options]
    if {$query_status == 0} {
        return $project
    }
    if {[_is_no_open_project_error $project $query_options]} {
        return {}
    }
    _raise FAIL PACKAGING_PROJECT_QUERY_FAILED VIVADO \
        "Unable to query the current Vivado project: $project"
}

proc ::stage1e::ip_packaging::_get_or_default {
    dictionary
    key
    default_value
} {
    if {![catch {dict size $dictionary}] && [dict exists $dictionary $key]} {
        return [dict get $dictionary $key]
    }
    return $default_value
}

proc ::stage1e::ip_packaging::_raise {
    status
    error_code
    error_class
    message
} {
    return -code error -errorcode [list \
        STAGE1E IP_PACKAGING $status $error_code $error_class] $message
}

proc ::stage1e::ip_packaging::_decode_error {
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
        [lrange $tcl_error_code 0 1] eq {STAGE1E IP_PACKAGING}} {
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

proc ::stage1e::ip_packaging::_error_record {decoded} {
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

proc ::stage1e::ip_packaging::_default_cleanup_result {} {
    return [dict create \
        owner stage1e::ip_packaging \
        required 0 \
        attempted 0 \
        completed 1 \
        project_closed 0 \
        removed_paths {} \
        errors {}]
}

proc ::stage1e::ip_packaging::_context_execution_id {context} {
    if {![catch {dict size $context}] &&
        [dict exists $context execution_id]} {
        return [dict get $context execution_id]
    }
    return {}
}

proc ::stage1e::ip_packaging::_result {
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
        artifacts_generated 0 \
        artifact_generation_performed 0 \
        artifact_publication_performed 0]
}

proc ::stage1e::ip_packaging::_require_dictionary {value label} {
    if {[catch {dict size $value} dictionary_error]} {
        _raise FAIL CONTEXT_FIELD_INVALID CONTRACT \
            "$label must be a dictionary: $dictionary_error"
    }
}

proc ::stage1e::ip_packaging::_require_keys {
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

proc ::stage1e::ip_packaging::_canonical_components {path} {
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

proc ::stage1e::ip_packaging::_is_equal_or_descendant {
    candidate_path
    parent_path
} {
    set candidate_components [_canonical_components $candidate_path]
    set parent_components [_canonical_components $parent_path]
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

proc ::stage1e::ip_packaging::_is_strict_descendant {
    candidate_path
    parent_path
} {
    return [expr {
        [_is_equal_or_descendant $candidate_path $parent_path] &&
        [llength [_canonical_components $candidate_path]] >
        [llength [_canonical_components $parent_path]]
    }]
}

proc ::stage1e::ip_packaging::_paths_overlap {first_path second_path} {
    return [expr {
        [_is_equal_or_descendant $first_path $second_path] ||
        [_is_equal_or_descendant $second_path $first_path]
    }]
}

proc ::stage1e::ip_packaging::_directory_entries {path} {
    set entries {}
    foreach entry [glob -nocomplain -directory $path -- * .*] {
        if {[file tail $entry] in {. ..}} {
            continue
        }
        if {$entry ni $entries} {
            lappend entries $entry
        }
    }
    return $entries
}

proc ::stage1e::ip_packaging::_normalize_relative_path {relative_path label} {
    set canonical [string map {\\ /} $relative_path]
    if {[string trim $canonical] eq {} ||
        [file pathtype $canonical] ne {relative}} {
        _raise FAIL SOURCE_PATH_INVALID SOURCE \
            "$label must be a nonempty repository-relative path: $relative_path"
    }
    foreach component [file split $canonical] {
        if {$component in {. ..}} {
            _raise FAIL SOURCE_PATH_INVALID SOURCE \
                "$label contains a disallowed path component: $relative_path"
        }
    }
    return [join [file split $canonical] /]
}

proc ::stage1e::ip_packaging::_resolve_source_path {
    repository_root
    relative_path
} {
    set absolute_path [file normalize [file join \
        $repository_root {*}[split $relative_path /]]]
    if {![_is_strict_descendant $absolute_path $repository_root]} {
        _raise FAIL SOURCE_PATH_ESCAPE SOURCE \
            "Package source escapes repository_root: $relative_path"
    }
    return $absolute_path
}

proc ::stage1e::ip_packaging::_validate_sha256 {digest label} {
    if {![regexp {^[0-9A-Fa-f]{64}$} $digest]} {
        _raise FAIL SOURCE_HASH_INVALID SOURCE \
            "$label must be a 64-character SHA-256 digest."
    }
    return [string tolower $digest]
}

proc ::stage1e::ip_packaging::_normalize_vlnv {expectation} {
    if {![catch {dict size $expectation}]} {
        _require_keys $expectation {vendor library name version} \
            vlnv_expectation
        set vendor [dict get $expectation vendor]
        set library [dict get $expectation library]
        set name [dict get $expectation name]
        set version [dict get $expectation version]
    } else {
        set components [split $expectation :]
        if {[llength $components] != 4} {
            _raise FAIL VLNV_EXPECTATION_INVALID CONTRACT \
                {vlnv_expectation must be a dictionary or four-part VLNV.}
        }
        lassign $components vendor library name version
    }

    foreach value [list $vendor $library $name $version] label \
        {vendor library name version} {
        if {![regexp {^[A-Za-z0-9_.-]+$} $value]} {
            _raise FAIL VLNV_EXPECTATION_INVALID CONTRACT \
                "VLNV $label contains unsupported characters: $value"
        }
    }
    return [dict create \
        vendor $vendor \
        library $library \
        name $name \
        version $version \
        vlnv "$vendor:$library:$name:$version"]
}

proc ::stage1e::ip_packaging::_validate_authorization {
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
        [dict get $authorization capability] ne \
            {ip_packaging_enabled} ||
        ![string is boolean -strict \
            [dict get $authorization capability_enabled]] ||
        ![dict get $authorization capability_enabled]} {
        _raise BLOCKED AUTHORIZATION_MISMATCH AUTHORIZATION \
            {Controller authorization does not permit this IP packaging operation.}
    }
}

proc ::stage1e::ip_packaging::_validate_source_inventory {
    repository_root
    source_inventory
    package_source_paths
} {
    if {[catch {llength $source_inventory}]} {
        _raise FAIL SOURCE_INVENTORY_INVALID SOURCE \
            {source_inventory must be a Tcl list.}
    }

    set normalized_inventory {}
    set inventory_by_path [dict create]
    foreach entry $source_inventory {
        _require_keys $entry {path sha256} {source inventory entry}
        set relative_path [_normalize_relative_path \
            [dict get $entry path] {source inventory path}]
        if {[dict exists $inventory_by_path $relative_path]} {
            _raise FAIL SOURCE_INVENTORY_DUPLICATE SOURCE \
                "Duplicate source inventory path: $relative_path"
        }
        set normalized_entry [dict create \
            path $relative_path \
            sha256 [_validate_sha256 [dict get $entry sha256] \
                "source inventory SHA-256 for $relative_path"]]
        if {[dict exists $entry size]} {
            set size [dict get $entry size]
            if {![string is integer -strict $size] || $size < 0} {
                _raise FAIL SOURCE_SIZE_INVALID SOURCE \
                    "Source inventory size is invalid for $relative_path."
            }
            dict set normalized_entry size $size
        }
        dict set inventory_by_path $relative_path $normalized_entry
        lappend normalized_inventory $normalized_entry
    }

    set approved_inventory {}
    set approved_files {}
    set seen_paths [dict create]
    foreach requested_path $package_source_paths {
        set relative_path [_normalize_relative_path \
            $requested_path {package source path}]
        if {[dict exists $seen_paths $relative_path]} {
            _raise FAIL PACKAGE_INVENTORY_DUPLICATE SOURCE \
                "Duplicate package source path: $relative_path"
        }
        dict set seen_paths $relative_path 1
        if {![dict exists $inventory_by_path $relative_path]} {
            _raise BLOCKED PACKAGE_SOURCE_NOT_APPROVED SOURCE \
                "Package source is absent from the accepted source inventory: $relative_path"
        }
        set absolute_path [_resolve_source_path $repository_root $relative_path]
        if {![file exists $absolute_path] || ![file isfile $absolute_path]} {
            _raise BLOCKED PACKAGE_SOURCE_MISSING DEPENDENCY \
                "Approved package source file is unavailable: $relative_path"
        }
        set entry [dict get $inventory_by_path $relative_path]
        if {[dict exists $entry size] &&
            [file size $absolute_path] != [dict get $entry size]} {
            _raise FAIL PACKAGE_SOURCE_SIZE_MISMATCH SOURCE \
                "Package source size does not match accepted inventory: $relative_path"
        }
        set actual_hash [::stage1d::source_check::sha256_file $absolute_path]
        if {$actual_hash ne [dict get $entry sha256]} {
            _raise FAIL PACKAGE_SOURCE_HASH_MISMATCH SOURCE \
                "Package source hash does not match accepted inventory: $relative_path"
        }
        lappend approved_inventory $entry
        lappend approved_files $absolute_path
    }
    if {[llength $approved_inventory] == 0} {
        _raise FAIL PACKAGE_INVENTORY_EMPTY SOURCE \
            {package_inventory must select at least one approved source file.}
    }

    return [dict create \
        source_inventory $normalized_inventory \
        source_inventory_hash \
            [::stage1d::source_check::aggregate_inventory_hash \
                $normalized_inventory] \
        approved_inventory $approved_inventory \
        approved_inventory_hash \
            [::stage1d::source_check::aggregate_inventory_hash \
                $approved_inventory] \
        approved_files $approved_files]
}

proc ::stage1e::ip_packaging::_validate_positive_integer {value label} {
    if {![string is integer -strict $value] || $value <= 0} {
        _raise FAIL PACKAGE_INVENTORY_INVALID CONTRACT \
            "$label must be a positive integer."
    }
}

proc ::stage1e::ip_packaging::_read_source_text {path} {
    set channel [open $path r]
    fconfigure $channel -encoding utf-8 -translation auto
    set read_status [catch {read $channel} text read_options]
    set close_status [catch {close $channel} close_error]
    if {$read_status != 0} {
        return -options $read_options $text
    }
    if {$close_status != 0} {
        _raise FAIL PACKAGE_SOURCE_READ_FAILED SOURCE \
            "Unable to close package source after reading: $close_error"
    }
    return $text
}

proc ::stage1e::ip_packaging::_strip_verilog_comments {text} {
    regsub -all {(?s)/\*.*?\*/} $text { } text
    regsub -all {//[^\r\n]*} $text { } text
    # Synthesis attributes may legally precede an instantiation. They are
    # metadata, not module tokens, so remove them before dependency parsing.
    regsub -all {(?s)\(\*.*?\*\)} $text { } text
    return $text
}

# Fail before Vivado is invoked when the configured top directly instantiates
# an RTL module whose definition is absent from the approved package sources.
# This is intentionally a source-only packaging-context check; Vivado compile
# order is not used as a substitute for an authoritative source inventory.
proc ::stage1e::ip_packaging::_validate_top_dependency_closure {
    repository_root
    package_inventory
} {
    set definitions [dict create]
    set source_text_by_path [dict create]
    foreach relative_path [dict get $package_inventory source_paths] {
        set extension [string tolower [file extension $relative_path]]
        if {$extension ni {.v .sv}} {
            continue
        }
        set absolute_path [_resolve_source_path $repository_root $relative_path]
        set source_text [_strip_verilog_comments \
            [_read_source_text $absolute_path]]
        dict set source_text_by_path $relative_path $source_text
        set definition_matches [regexp -all -inline -- \
            {\mmodule\M[ \t\r\n]+([A-Za-z_][A-Za-z0-9_$]*)} $source_text]
        foreach {match module_name} $definition_matches {
            dict lappend definitions $module_name $relative_path
        }
    }

    set top_module [dict get $package_inventory top_module]
    if {![dict exists $definitions $top_module]} {
        _raise BLOCKED PACKAGE_TOP_MODULE_MISSING SOURCE \
            "Configured package top has no definition in source_paths: $top_module"
    }
    set top_paths [lsort -unique [dict get $definitions $top_module]]
    if {[llength $top_paths] != 1} {
        _raise FAIL PACKAGE_TOP_MODULE_AMBIGUOUS SOURCE \
            "Configured package top must have exactly one source definition: $top_module"
    }

    set top_text [dict get $source_text_by_path [lindex $top_paths 0]]
    set instantiation_pattern \
        {(?m)^[ \t]*([A-Za-z_][A-Za-z0-9_$]*)[ \t\r\n]+(?:#[ \t\r\n]*\(|[A-Za-z_][A-Za-z0-9_$]*[ \t\r\n]*\()}
    set non_module_tokens {
        always assign begin buf bufif0 bufif1 case casex casez else end
        endcase endfunction endgenerate endmodule endtask for force forever
        function generate if initial inout input integer localparam module
        nand negedge nor not or output parameter posedge reg release repeat
        task tran tranif0 tranif1 tri wait while wire xnor xor and
    }
    set direct_dependencies {}
    foreach {match module_name} \
        [regexp -all -inline -- $instantiation_pattern $top_text] {
        if {$module_name in $non_module_tokens} {
            continue
        }
        # Deliberately undefined parameter-error sentinels are elaboration
        # guards, not package dependencies. Their stable prefix is verified by
        # the stage-specific negative elaboration tests.
        if {[string match {STAGE*_PARAMETER_ERROR_*} $module_name]} {
            continue
        }
        if {![dict exists $definitions $module_name]} {
            _raise BLOCKED PACKAGE_SOURCE_DEPENDENCY_MISSING SOURCE \
                "Configured top $top_module instantiates $module_name, but no package source defines $module_name."
        }
        if {$module_name ne $top_module && $module_name ni $direct_dependencies} {
            lappend direct_dependencies $module_name
        }
    }
    return [dict create \
        status PASS \
        top_module $top_module \
        top_source [lindex $top_paths 0] \
        direct_dependencies [lsort -dictionary $direct_dependencies]]
}

proc ::stage1e::ip_packaging::_validate_package_inventory {
    package_inventory
} {
    variable package_inventory_schema_version

    _require_keys $package_inventory {
        schema_version
        source_paths
        constraint_paths
        header_paths
        project_name
        top_module
        part
        board_part
        target_language
        component_metadata
        user_parameters
        axi_interface
        address_block
    } package_inventory

    if {[dict get $package_inventory schema_version] ne \
        $package_inventory_schema_version} {
        _raise FAIL PACKAGE_INVENTORY_SCHEMA_UNSUPPORTED CONTRACT \
            {Unsupported Stage 1E package inventory schema.}
    }
    foreach field {project_name top_module} {
        if {![regexp {^[A-Za-z_][A-Za-z0-9_]*$} \
            [dict get $package_inventory $field]]} {
            _raise FAIL PACKAGE_INVENTORY_INVALID CONTRACT \
                "package_inventory $field is not a valid Tcl/HDL identifier."
        }
    }
    foreach field {part board_part target_language} {
        if {[string trim [dict get $package_inventory $field]] eq {}} {
            _raise FAIL PACKAGE_INVENTORY_INVALID CONTRACT \
                "package_inventory $field must not be empty."
        }
    }
    if {[dict get $package_inventory target_language] ne {Verilog}} {
        _raise FAIL PACKAGE_LANGUAGE_UNSUPPORTED CONTRACT \
            {The protection IP packaging adapter requires target_language Verilog.}
    }

    set normalized_source_paths {}
    foreach path [dict get $package_inventory source_paths] {
        lappend normalized_source_paths [_normalize_relative_path \
            $path {package source path}]
    }
    set normalized_constraint_paths {}
    foreach path [dict get $package_inventory constraint_paths] {
        set normalized [_normalize_relative_path \
            $path {package constraint path}]
        if {[string tolower [file extension $normalized]] ne {.xdc}} {
            _raise FAIL PACKAGE_CONSTRAINT_EXTENSION CONTRACT \
                "Package constraint is not an XDC file: $normalized"
        }
        if {$normalized in $normalized_source_paths ||
            $normalized in $normalized_constraint_paths} {
            _raise FAIL PACKAGE_INVENTORY_DUPLICATE CONTRACT \
                "Duplicate package source/constraint path: $normalized"
        }
        lappend normalized_constraint_paths $normalized
    }
    if {[llength $normalized_constraint_paths] == 0} {
        _raise FAIL PACKAGE_CONSTRAINTS_EMPTY CONTRACT \
            {The asynchronous ADC package requires its Stage 2D CDC XDC authority.}
    }
    set normalized_header_paths {}
    foreach path [dict get $package_inventory header_paths] {
        set normalized [_normalize_relative_path $path {package header path}]
        if {$normalized ni $normalized_source_paths} {
            _raise FAIL PACKAGE_HEADER_NOT_SOURCE CONTRACT \
                "Package header is not present in source_paths: $normalized"
        }
        lappend normalized_header_paths $normalized
    }

    set component_metadata [dict get $package_inventory component_metadata]
    _require_keys $component_metadata {
        display_name
        description
        vendor_display_name
        company_url
        supported_families
        taxonomy
    } {package component_metadata}
    foreach key {
        display_name
        description
        vendor_display_name
        company_url
        supported_families
        taxonomy
    } {
        if {[string trim [dict get $component_metadata $key]] eq {}} {
            _raise FAIL COMPONENT_METADATA_INVALID CONTRACT \
                "Package component metadata is empty: $key"
        }
    }

    set user_parameters [dict get $package_inventory user_parameters]
    _require_keys $user_parameters {
        DATA_WIDTH
        CNT_WIDTH
        AXI_ADDR_WIDTH
        AXI_DATA_WIDTH
        HEALTH_CNT_WIDTH
        ADC_FIFO_ADDR_WIDTH
    } {package user_parameters}
    foreach name [dict keys $user_parameters] {
        _validate_positive_integer [dict get $user_parameters $name] \
            "Package user parameter $name"
    }
    if {[dict get $user_parameters DATA_WIDTH] < 1 ||
        [dict get $user_parameters ADC_FIFO_ADDR_WIDTH] < 2} {
        _raise FAIL PACKAGE_PARAMETER_GUARD CONTRACT \
            {DATA_WIDTH must be at least 1 and ADC_FIFO_ADDR_WIDTH at least 2.}
    }

    set axi [dict get $package_inventory axi_interface]
    _require_keys $axi {
        name
        clock_name
        reset_name
        address_width
        data_width
        clock_frequency_hz
        port_map
    } {package axi_interface}
    foreach field {name clock_name reset_name} {
        if {![regexp {^[A-Za-z_][A-Za-z0-9_]*$} [dict get $axi $field]]} {
            _raise FAIL AXI_INTERFACE_INVALID CONTRACT \
                "AXI interface field is not an identifier: $field"
        }
    }
    foreach field {address_width data_width clock_frequency_hz} {
        _validate_positive_integer [dict get $axi $field] \
            "AXI interface $field"
    }
    _require_dictionary [dict get $axi port_map] {AXI port_map}
    if {[dict size [dict get $axi port_map]] == 0} {
        _raise FAIL AXI_PORT_MAP_EMPTY CONTRACT \
            {AXI port_map must not be empty.}
    }
    if {[dict get $user_parameters AXI_ADDR_WIDTH] != \
        [dict get $axi address_width] ||
        [dict get $user_parameters AXI_DATA_WIDTH] != \
        [dict get $axi data_width]} {
        _raise FAIL AXI_PARAMETER_MISMATCH CONTRACT \
            {AXI interface widths do not match packaged RTL parameters.}
    }

    set address_block [dict get $package_inventory address_block]
    _require_keys $address_block {
        memory_map_name
        name
        base_address
        range
        width
        usage
    } {package address_block}
    foreach field {memory_map_name name usage} {
        if {[string trim [dict get $address_block $field]] eq {}} {
            _raise FAIL ADDRESS_BLOCK_INVALID CONTRACT \
                "Address block field must not be empty: $field"
        }
    }
    foreach field {base_address range width} {
        set value [dict get $address_block $field]
        if {![string is entier -strict $value] || $value < 0} {
            _raise FAIL ADDRESS_BLOCK_INVALID CONTRACT \
                "Address block field must be a nonnegative integer: $field"
        }
    }
    if {[dict get $address_block range] <= 0 ||
        [dict get $address_block width] <= 0 ||
        [dict get $address_block width] != [dict get $axi data_width]} {
        _raise FAIL ADDRESS_BLOCK_INVALID CONTRACT \
            {Address block range/width is inconsistent with the AXI interface.}
    }

    dict set package_inventory source_paths $normalized_source_paths
    dict set package_inventory constraint_paths $normalized_constraint_paths
    dict set package_inventory header_paths $normalized_header_paths
    return $package_inventory
}

proc ::stage1e::ip_packaging::_canonical_package_inventory {
    package_inventory
} {
    set records {}
    foreach key {
        schema_version
        project_name
        top_module
        part
        board_part
        target_language
    } {
        lappend records [list package $key [dict get $package_inventory $key]]
    }
    foreach path [dict get $package_inventory source_paths] {
        lappend records [list source_path $path]
    }
    foreach path [dict get $package_inventory constraint_paths] {
        lappend records [list constraint_path $path]
    }
    foreach path [dict get $package_inventory header_paths] {
        lappend records [list header_path $path]
    }
    foreach section {component_metadata user_parameters axi_interface address_block} {
        set values [dict get $package_inventory $section]
        foreach key [lsort -dictionary [dict keys $values]] {
            if {$section eq {axi_interface} && $key eq {port_map}} {
                set port_map [dict get $values $key]
                foreach logical [lsort -dictionary [dict keys $port_map]] {
                    lappend records [list axi_port $logical \
                        [dict get $port_map $logical]]
                }
            } else {
                lappend records [list $section $key [dict get $values $key]]
            }
        }
    }
    return [join $records "\n"]
}

proc ::stage1e::ip_packaging::_validate_context {context} {
    variable context_schema_version
    variable operation_name

    _require_keys $context {
        context_schema_version
        operation
        execution_id
        authorization
        repository_root
        source_inventory
        package_inventory
        workspace_root
        packaging_workspace
        ip_repo_path
        vlnv_expectation
    } {IP packaging context}

    if {[dict get $context context_schema_version] ne \
        $context_schema_version} {
        _raise FAIL CONTEXT_SCHEMA_UNSUPPORTED CONTRACT \
            {Unsupported Stage 1E IP packaging context schema.}
    }
    if {[dict get $context operation] ne $operation_name} {
        _raise FAIL OPERATION_MISMATCH CONTRACT \
            {IP packaging context operation does not match the adapter interface.}
    }
    set execution_id [dict get $context execution_id]
    if {[string trim $execution_id] eq {}} {
        _raise FAIL EXECUTION_ID_INVALID CONTRACT \
            {IP packaging execution_id must not be empty.}
    }
    _validate_authorization [dict get $context authorization] $execution_id

    foreach path_field {
        repository_root
        workspace_root
        packaging_workspace
        ip_repo_path
    } {
        set path [dict get $context $path_field]
        if {[file pathtype $path] ne {absolute}} {
            _raise FAIL PATH_NOT_ABSOLUTE WORKSPACE \
                "IP packaging $path_field must be an absolute path."
        }
        dict set context $path_field [file normalize $path]
    }
    set repository_root [dict get $context repository_root]
    set workspace_root [dict get $context workspace_root]
    set packaging_workspace [dict get $context packaging_workspace]
    set ip_repo_path [dict get $context ip_repo_path]

    if {![file isdirectory $repository_root]} {
        _raise BLOCKED REPOSITORY_UNAVAILABLE DEPENDENCY \
            {IP packaging repository_root is unavailable.}
    }
    if {![file isdirectory $workspace_root]} {
        _raise BLOCKED WORKSPACE_UNAVAILABLE DEPENDENCY \
            {IP packaging workspace_root is unavailable.}
    }
    if {[_paths_overlap $repository_root $workspace_root]} {
        _raise FAIL REPOSITORY_WORKSPACE_OVERLAP WORKSPACE \
            {IP packaging workspace must be external to the source repository.}
    }
    foreach path [list $packaging_workspace $ip_repo_path] label \
        {packaging_workspace ip_repo_path} {
        if {![_is_strict_descendant $path $workspace_root]} {
            _raise FAIL PATH_CONTAINMENT_VIOLATION WORKSPACE \
                "$label must be a strict descendant of workspace_root."
        }
    }
    if {[_paths_overlap $packaging_workspace $ip_repo_path]} {
        _raise FAIL PACKAGING_PATH_OVERLAP WORKSPACE \
            {packaging_workspace and ip_repo_path must not overlap.}
    }
    if {[file exists $packaging_workspace]} {
        _raise FAIL PACKAGING_WORKSPACE_STALE WORKSPACE \
            {packaging_workspace must not exist before packaging begins.}
    }
    if {[file exists $ip_repo_path]} {
        if {![file isdirectory $ip_repo_path]} {
            _raise FAIL IP_REPO_PATH_INVALID WORKSPACE \
                {ip_repo_path exists and is not a directory.}
        }
        if {[llength [_directory_entries $ip_repo_path]] != 0} {
            _raise FAIL IP_REPO_NOT_EMPTY WORKSPACE \
                {ip_repo_path must be absent or empty before packaging begins.}
        }
    }

    set vlnv [_normalize_vlnv [dict get $context vlnv_expectation]]
    set package_inventory [_validate_package_inventory \
        [dict get $context package_inventory]]
    set source_validation [_validate_source_inventory \
        $repository_root \
        [dict get $context source_inventory] \
        [concat \
            [dict get $package_inventory source_paths] \
            [dict get $package_inventory constraint_paths]]]
    dict set source_validation top_dependency_closure \
        [_validate_top_dependency_closure $repository_root $package_inventory]
    set ip_output_dir [file normalize [file join \
        $ip_repo_path [dict get $vlnv name]]]
    if {![_is_strict_descendant $ip_output_dir $ip_repo_path]} {
        _raise FAIL IP_OUTPUT_PATH_INVALID WORKSPACE \
            {Packaged IP output does not remain within ip_repo_path.}
    }
    if {[file exists $ip_output_dir]} {
        _raise FAIL IP_OUTPUT_STALE WORKSPACE \
            {Packaged IP output directory already exists.}
    }

    set package_inventory_hash [::stage1d::source_check::sha256_text \
        [_canonical_package_inventory $package_inventory]]
    set component_metadata_records {}
    foreach key [lsort -dictionary [dict keys \
        [dict get $package_inventory component_metadata]]] {
        lappend component_metadata_records [list \
            $key [dict get $package_inventory component_metadata $key]]
    }
    set component_metadata_hash [::stage1d::source_check::sha256_text \
        [join $component_metadata_records "\n"]]

    return [dict create \
        context $context \
        execution_id $execution_id \
        repository_root $repository_root \
        workspace_root $workspace_root \
        packaging_workspace $packaging_workspace \
        ip_repo_path $ip_repo_path \
        ip_output_dir $ip_output_dir \
        vlnv $vlnv \
        package_inventory $package_inventory \
        package_inventory_hash $package_inventory_hash \
        component_metadata_hash $component_metadata_hash \
        source_validation $source_validation]
}

proc ::stage1e::ip_packaging::_require_single_object {
    objects
    label
} {
    if {[llength $objects] != 1} {
        _raise FAIL VIVADO_OBJECT_CARDINALITY VIVADO \
            "$label must resolve to exactly one Vivado object; found [llength $objects]."
    }
    return [lindex $objects 0]
}

proc ::stage1e::ip_packaging::_read_core_identity {
    core
    label
} {
    # A Vivado IP-XACT core handle is opaque and its string representation can
    # contain whitespace. Prove object cardinality from the scalar VLNV
    # readback instead of applying Tcl list operations to the handle itself.
    set vlnv_values [_invoke get_property VLNV $core]
    set core_count [llength $vlnv_values]
    if {$core_count == 0} {
        _raise FAIL PACKAGED_CORE_IDENTITY_INVALID IDENTITY \
            "$label has no VLNV identity."
    }
    if {$core_count != 1} {
        _raise FAIL PACKAGED_CORE_AMBIGUOUS IDENTITY \
            "$label resolved to multiple Vivado cores; found $core_count VLNV identities."
    }
    foreach vlnv_value $vlnv_values {
        set observed_vlnv [string trim $vlnv_value]
    }
    if {![regexp {^[A-Za-z0-9_.-]+:[A-Za-z0-9_.-]+:[A-Za-z0-9_.-]+:[A-Za-z0-9_.-]+$} \
        $observed_vlnv]} {
        _raise FAIL PACKAGED_CORE_IDENTITY_INVALID IDENTITY \
            "$label has an invalid VLNV identity: <$observed_vlnv>"
    }

    set identity [dict create]
    foreach property {vendor library name version} {
        set values [_invoke get_property $property $core]
        if {[llength $values] != 1} {
            _raise FAIL PACKAGED_CORE_AMBIGUOUS IDENTITY \
                "$label does not have exactly one $property value."
        }
        foreach property_value $values {
            set value [string trim $property_value]
        }
        if {![regexp {^[A-Za-z0-9_.-]+$} $value]} {
            _raise FAIL PACKAGED_CORE_IDENTITY_INVALID IDENTITY \
                "$label has an invalid $property identity: <$value>"
        }
        dict set identity $property $value
    }
    set assembled_vlnv [join [list \
        [dict get $identity vendor] \
        [dict get $identity library] \
        [dict get $identity name] \
        [dict get $identity version]] :]
    if {$observed_vlnv ne $assembled_vlnv} {
        _raise FAIL PACKAGED_CORE_IDENTITY_INVALID IDENTITY \
            "$label identity fields do not match VLNV: fields=$assembled_vlnv vlnv=$observed_vlnv"
    }
    dict set identity vlnv $observed_vlnv
    return $identity
}

proc ::stage1e::ip_packaging::_resolve_target_core {validated core} {
    set expected [dict get $validated vlnv]
    if {[string trim $core] eq {}} {
        _raise FAIL PACKAGED_CORE_NOT_FOUND VIVADO \
            {IP-XACT packaging did not bind a current core.}
    }

    # package_project -set_current true creates and binds one current core.
    # Identity readback proves that the opaque handle represents exactly one
    # object and avoids the unsupported get_cores -from project lookup.
    set identity [_read_core_identity $core {Packaged IP current core}]
    foreach property {vendor library} {
        if {[dict get $identity $property] ne \
            [dict get $expected $property]} {
            _raise FAIL VLNV_MISMATCH IDENTITY \
                "Packaged IP initial identity mismatch: actual=[dict get $identity vlnv] expected_vendor_library=[dict get $expected vendor]:[dict get $expected library]"
        }
    }
    return [dict create core $core initial_identity $identity]
}

proc ::stage1e::ip_packaging::_persist_core {validated core} {
    _invoke ipx::save_core $core

    # Read back the complete identity after save so package acceptance remains
    # bound to the persisted core rather than only to pre-save metadata.
    set saved_identity [_read_core_identity $core {Saved packaged IP core}]
    set expected_vlnv [dict get $validated vlnv vlnv]
    if {[dict get $saved_identity vlnv] ne $expected_vlnv} {
        _raise FAIL VLNV_MISMATCH IDENTITY \
            "Saved packaged IP VLNV mismatch: actual=[dict get $saved_identity vlnv] expected=$expected_vlnv"
    }

    set component_xml [file normalize [file join \
        [dict get $validated ip_output_dir] component.xml]]
    if {![file exists $component_xml] || ![file isfile $component_xml] ||
        [file size $component_xml] == 0} {
        _raise FAIL COMPONENT_XML_MISSING OUTPUT \
            {Saved packaged IP component.xml is missing or empty.}
    }
    return [dict create \
        component_xml $component_xml \
        saved_core_identity $saved_identity \
        core_persisted 1]
}

proc ::stage1e::ip_packaging::_assert_property {
    object
    property
    expected
    label
    {nocase 0}
} {
    set actual [_invoke get_property $property $object]
    if {$nocase} {
        set matches [string equal -nocase $actual $expected]
    } else {
        set matches [expr {$actual eq $expected}]
    }
    if {!$matches} {
        _raise FAIL COMPONENT_METADATA_MISMATCH IDENTITY \
            "$label property mismatch: property=$property actual=<$actual> expected=<$expected>"
    }
    return $actual
}

proc ::stage1e::ip_packaging::_assert_current_project_property {
    property
    expected
    label
    {nocase 0}
} {
    set actual [::stage1e::ip_packaging::backend::get_current_project_property \
        $property]
    if {$nocase} {
        set matches [string equal -nocase $actual $expected]
    } else {
        set matches [expr {$actual eq $expected}]
    }
    if {!$matches} {
        _raise FAIL COMPONENT_METADATA_MISMATCH IDENTITY \
            "$label property mismatch: property=$property actual=<$actual> expected=<$expected>"
    }
    return $actual
}

proc ::stage1e::ip_packaging::_assert_fileset_property {
    fileset_name
    property
    expected
    label
    {nocase 0}
} {
    set actual [::stage1e::ip_packaging::backend::get_fileset_property \
        $fileset_name $property]
    if {$nocase} {
        set matches [string equal -nocase $actual $expected]
    } else {
        set matches [expr {$actual eq $expected}]
    }
    if {!$matches} {
        _raise FAIL COMPONENT_METADATA_MISMATCH IDENTITY \
            "$label property mismatch: property=$property actual=<$actual> expected=<$expected>"
    }
    return $actual
}

proc ::stage1e::ip_packaging::_assert_numeric_property {
    object
    property
    expected
    label
} {
    set actual [_invoke get_property $property $object]
    if {![string is entier -strict $actual] ||
        [expr {$actual}] != [expr {$expected}]} {
        _raise FAIL COMPONENT_METADATA_MISMATCH IDENTITY \
            "$label numeric property mismatch: property=$property actual=<$actual> expected=<$expected>"
    }
    return $actual
}

proc ::stage1e::ip_packaging::_ensure_bus_interface {
    core
    name
    bus_vlnv
    abstraction_vlnv
    mode
} {
    set objects [_invoke ipx::get_bus_interfaces \
        $name -of_objects $core -quiet]
    if {[llength $objects] == 0} {
        set object [_invoke ipx::add_bus_interface $name $core]
    } else {
        set object [_require_single_object $objects "Bus interface $name"]
    }
    _invoke set_property bus_type_vlnv $bus_vlnv $object
    _invoke set_property abstraction_type_vlnv $abstraction_vlnv $object
    _invoke set_property interface_mode $mode $object
    _assert_property $object bus_type_vlnv $bus_vlnv "Bus interface $name"
    _assert_property $object abstraction_type_vlnv $abstraction_vlnv \
        "Bus interface $name"
    _assert_property $object interface_mode $mode "Bus interface $name" 1
    return $object
}

proc ::stage1e::ip_packaging::_ensure_port_map {
    bus_interface
    logical_name
    physical_name
} {
    set objects [_invoke ipx::get_port_maps \
        $logical_name -of_objects $bus_interface -quiet]
    if {[llength $objects] == 0} {
        set object [_invoke ipx::add_port_map \
            $logical_name $bus_interface]
    } else {
        set object [_require_single_object $objects \
            "Port map $logical_name"]
    }
    _invoke set_property physical_name $physical_name $object
    _assert_property $object physical_name $physical_name \
        "Port map $logical_name"
    return $object
}

proc ::stage1e::ip_packaging::_set_bus_parameter {
    bus_interface
    name
    value
} {
    set objects [_invoke ipx::get_bus_parameters \
        $name -of_objects $bus_interface -quiet]
    if {[llength $objects] == 0} {
        set object [_invoke ipx::add_bus_parameter $name $bus_interface]
    } else {
        set object [_require_single_object $objects \
            "Bus parameter $name"]
    }
    _invoke set_property value $value $object
    _assert_property $object value $value "Bus parameter $name"
    return $object
}

proc ::stage1e::ip_packaging::_stage_implementation_constraints {
    core
    constraint_files
} {
    set synthesis [_require_single_object \
        [_invoke ipx::get_file_groups xilinx_anylanguagesynthesis \
            -of_objects $core -quiet] \
        {Packaged IP synthesis file group}]
    set implementation_groups [_invoke ipx::get_file_groups \
        xilinx_implementation -of_objects $core -quiet]
    if {[llength $implementation_groups] == 0} {
        set implementation [_invoke ipx::add_file_group \
            xilinx_implementation -type implementation $core]
    } else {
        set implementation [_require_single_object $implementation_groups \
            {Packaged IP implementation file group}]
    }

    foreach source $constraint_files {
        set relative_path "src/[file tail $source]"
        set synthesis_files [_invoke ipx::get_files $relative_path \
            -of_objects $synthesis -quiet]
        if {[llength $synthesis_files] > 1} {
            _raise FAIL PACKAGED_CONSTRAINT_DUPLICATE IP_XACT \
                "Constraint is duplicated in the synthesis file group: $relative_path"
        }
        if {[llength $synthesis_files] == 1} {
            _invoke ipx::remove_file $relative_path $synthesis
        }

        set implementation_files [_invoke ipx::get_files $relative_path \
            -of_objects $implementation -quiet]
        if {[llength $implementation_files] == 0} {
            set implementation_file [_invoke ipx::add_file \
                $relative_path $implementation]
        } elseif {[llength $implementation_files] == 1} {
            set implementation_file [lindex $implementation_files 0]
        } else {
            _raise FAIL PACKAGED_CONSTRAINT_DUPLICATE IP_XACT \
                "Constraint is duplicated in the implementation file group: $relative_path"
        }
        _invoke set_property type xdc $implementation_file
        _invoke set_property processing_order late $implementation_file
        _assert_property $implementation_file type xdc \
            "Implementation constraint $relative_path"
        _assert_property $implementation_file processing_order late \
            "Implementation constraint $relative_path"

        set occurrence_count 0
        set owning_groups {}
        foreach group [_invoke ipx::get_file_groups -of_objects $core] {
            set files [_invoke ipx::get_files $relative_path \
                -of_objects $group -quiet]
            incr occurrence_count [llength $files]
            if {[llength $files] != 0} {
                lappend owning_groups [_invoke get_property NAME $group]
            }
        }
        if {$occurrence_count != 1 ||
            $owning_groups ne {xilinx_implementation}} {
            _raise FAIL PACKAGED_CONSTRAINT_SCOPE IP_XACT \
                "Constraint must occur exactly once and only in xilinx_implementation: $relative_path"
        }
    }
}

proc ::stage1e::ip_packaging::_configure_component {
    validated
    core
} {
    set vlnv [dict get $validated vlnv]
    set package_inventory [dict get $validated package_inventory]
    set component_metadata [dict get $package_inventory component_metadata]

    foreach property {vendor library name version} {
        _invoke set_property $property [dict get $vlnv $property] $core
    }
    foreach property {
        display_name
        description
        vendor_display_name
        company_url
        supported_families
    } {
        _invoke set_property $property \
            [dict get $component_metadata $property] $core
    }

    set observed_identity [_read_core_identity $core \
        {Configured packaged IP core}]
    set observed_vlnv [dict get $observed_identity vlnv]
    if {$observed_vlnv ne [dict get $vlnv vlnv]} {
        _raise FAIL VLNV_MISMATCH IDENTITY \
            "Packaged IP VLNV mismatch: actual=$observed_vlnv expected=[dict get $vlnv vlnv]"
    }
    foreach property {
        display_name
        description
        vendor_display_name
        company_url
        supported_families
    } {
        _assert_property $core $property \
            [dict get $component_metadata $property] \
            "Packaged component metadata $property"
    }
    _assert_property $core taxonomy \
        [dict get $component_metadata taxonomy] \
        {Packaged component metadata taxonomy}

    set user_parameters [dict get $package_inventory user_parameters]
    foreach parameter_name [lsort -dictionary [dict keys $user_parameters]] {
        set parameter [_require_single_object \
            [_invoke ipx::get_user_parameters \
                $parameter_name -of_objects $core -quiet] \
            "User parameter $parameter_name"]
        set value [dict get $user_parameters $parameter_name]
        _invoke set_property value $value $parameter
        _invoke set_property value_format long $parameter
        _assert_numeric_property $parameter value $value \
            "User parameter $parameter_name"
        if {$parameter_name eq {DATA_WIDTH}} {
            set minimum 1
            set maximum 1024
        } elseif {$parameter_name eq {ADC_FIFO_ADDR_WIDTH}} {
            set minimum 2
            set maximum 16
        } else {
            continue
        }
        _invoke set_property value_validation_type range_long $parameter
        _invoke set_property value_validation_range_minimum $minimum $parameter
        _invoke set_property value_validation_range_maximum $maximum $parameter
        _assert_property $parameter value_validation_type range_long \
            "User parameter $parameter_name validation type"
        _assert_numeric_property $parameter \
            value_validation_range_minimum $minimum \
            "User parameter $parameter_name minimum"
        _assert_numeric_property $parameter \
            value_validation_range_maximum $maximum \
            "User parameter $parameter_name maximum"
    }

    set axi [dict get $package_inventory axi_interface]
    set axi_name [dict get $axi name]
    set clock_name [dict get $axi clock_name]
    set reset_name [dict get $axi reset_name]
    set axi_interface [_ensure_bus_interface \
        $core $axi_name \
        xilinx.com:interface:aximm:1.0 \
        xilinx.com:interface:aximm_rtl:1.0 \
        slave]
    _invoke set_property display_name $axi_name $axi_interface
    _set_bus_parameter $axi_interface PROTOCOL AXI4LITE
    _set_bus_parameter $axi_interface DATA_WIDTH [dict get $axi data_width]
    _set_bus_parameter $axi_interface ADDR_WIDTH [dict get $axi address_width]
    dict for {logical physical} [dict get $axi port_map] {
        _ensure_port_map $axi_interface $logical $physical
    }

    set clock_interface [_ensure_bus_interface \
        $core $clock_name \
        xilinx.com:signal:clock:1.0 \
        xilinx.com:signal:clock_rtl:1.0 \
        slave]
    _ensure_port_map $clock_interface CLK $clock_name
    _set_bus_parameter $clock_interface ASSOCIATED_BUSIF $axi_name
    _set_bus_parameter $clock_interface ASSOCIATED_RESET $reset_name
    _set_bus_parameter $clock_interface FREQ_HZ \
        [dict get $axi clock_frequency_hz]

    set reset_interface [_ensure_bus_interface \
        $core $reset_name \
        xilinx.com:signal:reset:1.0 \
        xilinx.com:signal:reset_rtl:1.0 \
        slave]
    _ensure_port_map $reset_interface RST $reset_name
    _set_bus_parameter $reset_interface POLARITY ACTIVE_LOW

    set address_policy [dict get $package_inventory address_block]
    set memory_map_name [dict get $address_policy memory_map_name]
    set memory_maps [_invoke ipx::get_memory_maps \
        $memory_map_name -of_objects $core -quiet]
    if {[llength $memory_maps] == 0} {
        set memory_map [_invoke ipx::add_memory_map $memory_map_name $core]
    } else {
        set memory_map [_require_single_object $memory_maps \
            "Memory map $memory_map_name"]
    }
    _invoke set_property slave_memory_map_ref $memory_map_name $axi_interface
    _assert_property $axi_interface slave_memory_map_ref $memory_map_name \
        {AXI slave memory-map reference}

    set address_name [dict get $address_policy name]
    set address_blocks [_invoke ipx::get_address_blocks \
        $address_name -of_objects $memory_map -quiet]
    if {[llength $address_blocks] == 0} {
        set address_block [_invoke ipx::add_address_block \
            $address_name $memory_map]
    } else {
        set address_block [_require_single_object $address_blocks \
            "Address block $address_name"]
    }
    foreach property {base_address range width} {
        _invoke set_property $property \
            [dict get $address_policy $property] $address_block
        _assert_numeric_property $address_block $property \
            [dict get $address_policy $property] \
            "Address block $address_name"
    }
    _invoke set_property usage [dict get $address_policy usage] $address_block
    _assert_property $address_block usage \
        [dict get $address_policy usage] "Address block $address_name" 1

    return [dict create \
        observed_vlnv $observed_vlnv \
        component_metadata_verified 1 \
        user_parameter_count [dict size $user_parameters] \
        axi_port_map_count [dict size [dict get $axi port_map]] \
        address_block_verified 1]
}

proc ::stage1e::ip_packaging::_relative_path {root path} {
    set normalized_root [file normalize $root]
    set normalized_path [file normalize $path]
    if {![_is_strict_descendant $normalized_path $normalized_root]} {
        _raise FAIL GENERATED_PATH_ESCAPE WORKSPACE \
            "Generated package path escapes output root: $path"
    }
    set root_components [file split $normalized_root]
    set path_components [file split $normalized_path]
    return [join [lrange $path_components [llength $root_components] end] /]
}

proc ::stage1e::ip_packaging::_collect_files {root {directory {}}} {
    if {$directory eq {}} {
        set directory $root
    }
    set files {}
    foreach entry [_directory_entries $directory] {
        set normalized [file normalize $entry]
        if {![_is_equal_or_descendant $normalized $root]} {
            _raise FAIL GENERATED_PATH_ESCAPE WORKSPACE \
                "Generated package member escapes output root: $entry"
        }
        if {[file isdirectory $normalized]} {
            foreach nested [_collect_files $root $normalized] {
                lappend files $nested
            }
        } elseif {[file isfile $normalized]} {
            lappend files $normalized
        } else {
            _raise FAIL GENERATED_MEMBER_INVALID WORKSPACE \
                "Generated package member is not a regular file: $entry"
        }
    }
    return $files
}

proc ::stage1e::ip_packaging::_generated_inventory {ip_output_dir} {
    set paths [_collect_files $ip_output_dir]
    set indexed [dict create]
    foreach path $paths {
        set relative [_relative_path $ip_output_dir $path]
        dict set indexed $relative [dict create \
            path $relative \
            size [file size $path] \
            sha256 [::stage1d::source_check::sha256_file $path]]
    }
    set inventory {}
    foreach relative [lsort -dictionary [dict keys $indexed]] {
        lappend inventory [dict get $indexed $relative]
    }
    return $inventory
}

proc ::stage1e::ip_packaging::_cleanup_failure {
    validated
    project_open
    may_own_project
    ip_repo_preexisting
} {
    set cleanup_errors {}
    set removed_paths {}
    set project_closed 0

    if {$project_open} {
        if {[catch {_invoke close_project} close_error close_options]} {
            lappend cleanup_errors [dict create \
                code PACKAGING_PROJECT_CLOSE_FAILED \
                message $close_error \
                underlying_error [_get_or_default \
                    $close_options -errorinfo $close_error]]
        } else {
            set project_closed 1
        }
    } elseif {$may_own_project} {
        if {[catch {_query_current_project_allow_empty} current_project \
            query_options]} {
            lappend cleanup_errors [dict create \
                code PACKAGING_PROJECT_QUERY_FAILED \
                message $current_project \
                underlying_error [_get_or_default \
                    $query_options -errorinfo $current_project]]
        } elseif {$current_project ne {}} {
            if {[catch {_invoke close_project} close_error close_options]} {
                lappend cleanup_errors [dict create \
                    code PACKAGING_PROJECT_CLOSE_FAILED \
                    message $close_error \
                    underlying_error [_get_or_default \
                        $close_options -errorinfo $close_error]]
            } else {
                set project_closed 1
            }
        }
    }

    foreach path [list \
        [dict get $validated ip_output_dir] \
        [dict get $validated packaging_workspace]] {
        if {[file exists $path]} {
            if {[catch {file delete -force -- $path} delete_error \
                delete_options]} {
                lappend cleanup_errors [dict create \
                    code PACKAGING_PATH_CLEANUP_FAILED \
                    path $path \
                    message $delete_error \
                    underlying_error [_get_or_default \
                        $delete_options -errorinfo $delete_error]]
            } else {
                lappend removed_paths $path
            }
        }
    }

    set ip_repo_path [dict get $validated ip_repo_path]
    if {!$ip_repo_preexisting && [file isdirectory $ip_repo_path] &&
        [llength [_directory_entries $ip_repo_path]] == 0} {
        if {[catch {file delete -- $ip_repo_path} delete_error \
            delete_options]} {
            lappend cleanup_errors [dict create \
                code IP_REPO_CLEANUP_FAILED \
                path $ip_repo_path \
                message $delete_error \
                underlying_error [_get_or_default \
                    $delete_options -errorinfo $delete_error]]
        } else {
            lappend removed_paths $ip_repo_path
        }
    }

    return [dict create \
        owner stage1e::ip_packaging \
        required 1 \
        attempted 1 \
        completed [expr {[llength $cleanup_errors] == 0}] \
        project_closed $project_closed \
        removed_paths $removed_paths \
        errors $cleanup_errors]
}

proc ::stage1e::ip_packaging::_execute {context validated} {
    set execution_id [dict get $validated execution_id]
    set package_inventory [dict get $validated package_inventory]
    set source_validation [dict get $validated source_validation]
    set vlnv [dict get $validated vlnv]
    set packaging_workspace [dict get $validated packaging_workspace]
    set ip_repo_path [dict get $validated ip_repo_path]
    set ip_output_dir [dict get $validated ip_output_dir]
    set ip_repo_preexisting [file exists $ip_repo_path]
    set project_open 0
    set may_own_project 0
    set vivado_invoked 0

    set consumed_identities [dict create \
        source_inventory [dict create \
            sha256 [dict get $source_validation source_inventory_hash] \
            approved_sha256 \
                [dict get $source_validation approved_inventory_hash] \
            approved_count [llength \
                [dict get $source_validation approved_inventory]]] \
        package_inventory [dict create \
            sha256 [dict get $validated package_inventory_hash] \
            schema_version [dict get $package_inventory schema_version]] \
        vlnv_expectation $vlnv \
        workspace [dict create \
            workspace_root [dict get $validated workspace_root] \
            packaging_workspace $packaging_workspace \
            ip_repo_path $ip_repo_path]]

    set execution_status [catch {
        file mkdir [file dirname $packaging_workspace]
        file mkdir $ip_repo_path

        set vivado_invoked 1
        set existing_project [_query_current_project_allow_empty]
        if {$existing_project ne {}} {
            _raise BLOCKED PACKAGING_SESSION_OCCUPIED OWNERSHIP \
                {Vivado already has a current project; IP packaging will not assume its ownership.}
        }
        set may_own_project 1
        _invoke create_project \
            [dict get $package_inventory project_name] \
            $packaging_workspace \
            -part [dict get $package_inventory part]
        set project_open 1
        _require_single_object [_invoke current_project] \
            {Temporary packaging project}
        ::stage1e::ip_packaging::backend::set_current_project_property \
            board_part [dict get $package_inventory board_part]
        ::stage1e::ip_packaging::backend::set_current_project_property \
            target_language [dict get $package_inventory target_language]
        _assert_current_project_property board_part \
            [dict get $package_inventory board_part] \
            {Temporary packaging project}
        _assert_current_project_property target_language \
            [dict get $package_inventory target_language] \
            {Temporary packaging project}

        set approved_source_files {}
        foreach relative_path [dict get $package_inventory source_paths] {
            lappend approved_source_files [_resolve_source_path \
                [dict get $validated repository_root] $relative_path]
        }
        set approved_constraint_files {}
        foreach relative_path [dict get $package_inventory constraint_paths] {
            lappend approved_constraint_files [_resolve_source_path \
                [dict get $validated repository_root] $relative_path]
        }
        _invoke add_files -norecurse -fileset sources_1 $approved_source_files
        _invoke add_files -norecurse -fileset constrs_1 $approved_constraint_files
        foreach constraint_file $approved_constraint_files {
            set constraint_object [_require_single_object \
                [_invoke get_files -quiet $constraint_file] \
                "CDC constraint source $constraint_file"]
            foreach {property value} {
                file_type XDC
                USED_IN_SYNTHESIS false
                USED_IN_IMPLEMENTATION true
                PROCESSING_ORDER LATE
            } {
                _invoke set_property $property $value $constraint_object
                _assert_property $constraint_object $property $value \
                    "CDC constraint source $constraint_file"
            }
        }
        foreach header_path [dict get $package_inventory header_paths] {
            set header_file [_resolve_source_path \
                [dict get $validated repository_root] $header_path]
            set header_object [_require_single_object \
                [_invoke get_files -quiet $header_file] \
                "Header source $header_path"]
            _invoke set_property file_type {Verilog Header} $header_object
            _assert_property $header_object file_type {Verilog Header} \
                "Header source $header_path"
        }
        set fileset_name [string trim [_invoke current_fileset]]
        _require_single_object \
            [_invoke get_filesets -quiet $fileset_name] \
            {Packaging source fileset}
        ::stage1e::ip_packaging::backend::set_fileset_property \
            $fileset_name top [dict get $package_inventory top_module]
        _assert_fileset_property $fileset_name top \
            [dict get $package_inventory top_module] \
            {Packaging source fileset}
        _invoke update_compile_order -fileset $fileset_name

        set component_metadata [dict get \
            $package_inventory component_metadata]
        _invoke ipx::package_project \
            -root_dir $ip_output_dir \
            -vendor [dict get $vlnv vendor] \
            -library [dict get $vlnv library] \
            -taxonomy [dict get $component_metadata taxonomy] \
            -import_files \
            -set_current true
        # Vivado 2024.1 package_project creates the IP-XACT core and binds it
        # through -set_current true. Retrieve that singular opaque object
        # directly; get_cores -from project does not enumerate it in this flow.
        set packaged_core [_invoke ipx::current_core]
        set core_resolution [_resolve_target_core $validated $packaged_core]
        set core [dict get $core_resolution core]
        _stage_implementation_constraints $core $approved_constraint_files
        set metadata_evidence [_configure_component $validated $core]
        dict set metadata_evidence initial_core_identity \
            [dict get $core_resolution initial_identity]

        _invoke ipx::create_xgui_files $core
        _invoke ipx::update_checksums $core
        set integrity_result [_invoke ipx::check_integrity $core]
        set persistence_evidence [_persist_core $validated $core]
        dict set metadata_evidence saved_core_identity \
            [dict get $persistence_evidence saved_core_identity]
        dict set metadata_evidence core_persisted \
            [dict get $persistence_evidence core_persisted]

        _invoke close_project
        set project_open 0

        set component_xml [dict get $persistence_evidence component_xml]
        set generated_inventory [_generated_inventory $ip_output_dir]
        if {[llength $generated_inventory] == 0} {
            _raise FAIL PACKAGE_OUTPUT_EMPTY OUTPUT \
                {Packaged IP output inventory is empty.}
        }
        set generated_inventory_hash \
            [::stage1d::source_check::aggregate_inventory_hash \
                $generated_inventory]
        set component_xml_hash \
            [::stage1d::source_check::sha256_file $component_xml]

        set package_digest [::stage1d::source_check::sha256_text [join [list \
            [list execution_id $execution_id] \
            [list vlnv [dict get $vlnv vlnv]] \
            [list source_inventory_hash \
                [dict get $source_validation approved_inventory_hash]] \
            [list package_inventory_hash \
                [dict get $validated package_inventory_hash]] \
            [list component_metadata_hash \
                [dict get $validated component_metadata_hash]] \
            [list generated_inventory_hash $generated_inventory_hash] \
            [list component_xml_sha256 $component_xml_hash]] "\n"]]
        set package_identity [dict create \
            schema_version stage1e-package-identity-v1 \
            execution_id $execution_id \
            vlnv [dict get $vlnv vlnv] \
            top_module [dict get $package_inventory top_module] \
            source_inventory_sha256 \
                [dict get $source_validation approved_inventory_hash] \
            package_inventory_sha256 \
                [dict get $validated package_inventory_hash] \
            component_metadata_sha256 \
                [dict get $validated component_metadata_hash] \
            generated_inventory_sha256 $generated_inventory_hash \
            component_xml_sha256 $component_xml_hash \
            package_sha256 $package_digest]
        set ip_repo_digest [::stage1d::source_check::sha256_text [join [list \
            [list execution_id $execution_id] \
            [list ip_repo_path $ip_repo_path] \
            [list vlnv [dict get $vlnv vlnv]] \
            [list package_sha256 $package_digest]] "\n"]]
        set ip_repo_identity [dict create \
            schema_version stage1e-ip-repo-identity-v1 \
            execution_id $execution_id \
            path $ip_repo_path \
            packaged_ip_path $ip_output_dir \
            vlnv [dict get $vlnv vlnv] \
            package_sha256 $package_digest \
            ip_repo_sha256 $ip_repo_digest]

        set produced_identities [dict create \
            package_identity $package_identity \
            ip_repo_identity $ip_repo_identity]
        set evidence_references [dict create \
            component_xml $component_xml \
            generated_inventory $generated_inventory \
            integrity_result $integrity_result \
            metadata_readback $metadata_evidence]
        set ownership_records [dict create \
            packaging_project [dict create \
                owner stage1e::ip_packaging \
                execution_id $execution_id \
                project_path $packaging_workspace \
                state RELEASED \
                project_closed 1]]
    } execution_error execution_options]

    if {$execution_status != 0} {
        set cleanup_result [_cleanup_failure \
            $validated $project_open $may_own_project \
            $ip_repo_preexisting]
        set decoded [_decode_error \
            $execution_error $execution_options \
            IP_PACKAGING_EXECUTION_FAILED VIVADO]
        if {![dict get $cleanup_result completed]} {
            dict set decoded status FAIL
        }
        return [_result \
            [dict get $decoded status] \
            $context \
            $consumed_identities \
            {} \
            {} \
            {} \
            {} \
            [list [_error_record $decoded]] \
            $cleanup_result \
            $vivado_invoked]
    }

    set cleanup_result [dict create \
        owner stage1e::ip_packaging \
        required 1 \
        attempted 1 \
        completed 1 \
        project_closed 1 \
        removed_paths {} \
        errors {}]
    return [_result PASS $context \
        $consumed_identities \
        $produced_identities \
        $ownership_records \
        $evidence_references \
        {} \
        {} \
        $cleanup_result \
        $vivado_invoked]
}

proc ::stage1e::ip_packaging::run {context} {
    set validation_status [catch {
        _validate_context $context
    } validated validation_options]
    if {$validation_status != 0} {
        set decoded [_decode_error \
            $validated $validation_options \
            IP_PACKAGING_CONTEXT_INVALID CONTRACT]
        return [_result \
            [dict get $decoded status] \
            $context \
            {} \
            {} \
            {} \
            {} \
            {} \
            [list [_error_record $decoded]] \
            [_default_cleanup_result] \
            0]
    }
    return [_execute $context $validated]
}
