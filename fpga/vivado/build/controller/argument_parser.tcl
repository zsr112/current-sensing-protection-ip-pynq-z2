namespace eval ::stage1d::argument_parser {
    variable option_map [dict create \
        --repository-root repository_root \
        --build-workspace build_workspace \
        --artifact-storage artifact_storage \
        --configuration configuration_path \
        --delivery-manifest delivery_manifest_path \
        --environment-evidence environment_evidence_path \
        --git-commit candidate_git_commit]
}

proc ::stage1d::argument_parser::usage {} {
    return [join [list \
        {Usage: stage1d_artifact_build.tcl -tclargs <options>} \
        {} \
        {Required options:} \
        {  --repository-root <path>} \
        {  --build-workspace <path>} \
        {  --artifact-storage <path>} \
        {  --configuration <path>} \
        {  --git-commit <full-or-candidate-commit>} \
        {} \
        {Phase 2 verification option:} \
        {  --environment-evidence <declarative-dict-path>} \
        {} \
        {Controlled execution option:} \
        {  --delivery-manifest <path>} \
        {} \
        {Other options:} \
        {  --help}] "\n"]
}

proc ::stage1d::argument_parser::parse {arguments} {
    variable option_map

    set parsed [dict create \
        help 0 \
        environment_evidence_path {} \
        delivery_manifest_path {}]
    set seen [dict create]
    set argument_count [llength $arguments]
    set index 0

    while {$index < $argument_count} {
        set option [lindex $arguments $index]

        if {$option eq {--help}} {
            if {[dict exists $seen $option]} {
                error "Duplicate option: $option"
            }
            dict set seen $option 1
            dict set parsed help 1
            incr index
            continue
        }

        if {![dict exists $option_map $option]} {
            error "Unknown option: $option"
        }
        if {[dict exists $seen $option]} {
            error "Duplicate option: $option"
        }

        incr index
        if {$index >= $argument_count} {
            error "Missing value for option: $option"
        }

        set value [lindex $arguments $index]
        if {$value eq {}} {
            error "Empty value for option: $option"
        }

        dict set seen $option 1
        dict set parsed [dict get $option_map $option] $value
        incr index
    }

    if {[dict get $parsed help]} {
        return $parsed
    }

    foreach required_key {
        repository_root
        build_workspace
        artifact_storage
        configuration_path
        candidate_git_commit
    } {
        if {![dict exists $parsed $required_key]} {
            error "Missing required controller input: $required_key"
        }
    }

    return $parsed
}
