namespace eval ::stage1d::configuration_loader {
    variable required_version_keys {
        schema_version
        controller_version
        controller_api_version
        execution_id_schema_version
        phase_evidence_schema_version
        decision_schema_version
        manifest_schema_version
    }
    variable required_keys {
        schema_version
        build_profile
        controller_version
        controller_api_version
        execution_id_schema_version
        phase_evidence_schema_version
        decision_schema_version
        manifest_schema_version
        phase_limit
    }
    variable phase2_section_keys [dict create \
        source_verification {
            required_paths
            tcl_paths
            controller_source_paths
            expected_controller_source_sha256
        } \
        environment {
            evidence_schema_version
            vivado_version
            sw_build
            ip_build
            part
            board_part
            required_ip_patterns
            custom_protection_ip
        } \
        workspace {
            ownership_schema_version
            stale_vivado_markers
        }]
}

proc ::stage1d::configuration_loader::validate_supported_versions {
    configuration
    supported_versions
} {
    variable required_version_keys

    if {[catch {dict size $supported_versions} supported_versions_error]} {
        error "Supported controller versions are not a dictionary: $supported_versions_error"
    }

    foreach version_key $required_version_keys {
        if {![dict exists $configuration $version_key]} {
            error "Configuration is missing version identity: $version_key"
        }
        if {![dict exists $supported_versions $version_key]} {
            error "Controller does not declare a supported value for: $version_key"
        }

        set configured_version [dict get $configuration $version_key]
        set supported_version [dict get $supported_versions $version_key]
        if {$configured_version ne $supported_version} {
            error "Unsupported $version_key: configured=$configured_version supported=$supported_version"
        }
    }

    return 1
}

proc ::stage1d::configuration_loader::load {configuration_path supported_versions} {
    variable required_keys
    variable phase2_section_keys

    set normalized_path [file normalize $configuration_path]
    if {![file exists $normalized_path] || ![file isfile $normalized_path]} {
        error "Configuration file not found: $normalized_path"
    }

    set channel [open $normalized_path r]
    fconfigure $channel -encoding utf-8 -translation auto
    set read_status [catch {read $channel} configuration_text read_options]
    set close_status [catch {close $channel} close_error]

    if {$read_status != 0} {
        return -options $read_options $configuration_text
    }
    if {$close_status != 0} {
        error "Unable to close configuration file: $close_error"
    }

    set configuration_text [string trim $configuration_text]
    if {$configuration_text eq {}} {
        error {Configuration file is empty.}
    }

    if {[catch {dict size $configuration_text} parse_error]} {
        error "Configuration is not a valid declarative Tcl dictionary: $parse_error"
    }

    set configuration $configuration_text
    foreach required_key $required_keys {
        if {![dict exists $configuration $required_key]} {
            error "Configuration is missing required key: $required_key"
        }
    }

    validate_supported_versions $configuration $supported_versions
    if {[dict get $configuration phase_limit] ne {WORKSPACE_READY}} {
        error "Phase 2 verification configuration must stop at WORKSPACE_READY, got: [dict get $configuration phase_limit]"
    }

    foreach section [dict keys $phase2_section_keys] {
        if {![dict exists $configuration $section]} {
            error "Configuration is missing Phase 2 section: $section"
        }
        if {[catch {dict size [dict get $configuration $section]} section_error]} {
            error "Configuration section $section is not a dictionary: $section_error"
        }
        foreach section_key [dict get $phase2_section_keys $section] {
            if {![dict exists $configuration $section $section_key]} {
                error "Configuration section $section is missing key: $section_key"
            }
        }
    }

    set expected_controller_hash [dict get \
        $configuration source_verification expected_controller_source_sha256]
    if {![regexp {^[0-9A-Fa-f]{64}$} $expected_controller_hash]} {
        error {Expected controller source SHA256 must contain 64 hexadecimal characters.}
    }

    dict set configuration configuration_path $normalized_path
    return $configuration
}
