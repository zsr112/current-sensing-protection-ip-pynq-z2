# Stage 1E Phase 2 reconstruction and synthesis entrypoint.
#
# This additive entrypoint preserves the historical WP-A skeleton source and
# behavior. Sourcing this file loads controller and adapter definitions only;
# no Vivado command, reconstruction operation, synthesis run, implementation,
# artifact operation, or board operation is invoked.

namespace eval ::stage1e::phase2_build {
    variable entrypoint_version STAGE1E-PHASE2-SYNTHESIS-BUILD-v1
    variable context_schema_version stage1e-phase2-controller-context-v1
    variable synthesis_evidence_contract_version \
        stage1e-synthesis-evidence-path-v1
    variable synthesis_evidence_leaf synthesis
    variable launcher_contract_version stage1e-vivado-launcher-cwd-v1
    variable launcher_lifetime_contract_version \
        stage1e-vivado-launcher-lifetime-v1
    variable launcher_state_relative_path .Xil
    variable launcher_windows_max_path_bytes 260
    variable launcher_windows_safety_margin_bytes 16
    # The Vivado session leaf includes a process/host token at runtime. The
    # reviewed placeholder below is deliberately longer than the Retry #20
    # value (Vivado-23148-illusion) and covers the observed SmartConnect output.
    variable reviewed_launcher_xil_descendant_paths {
        .Xil/Vivado-0000000000-stage1e-controlled/coregen/protection_system_smartconnect_0_0/sc_xtlm_protection_system_smartconnect_0_0.mem
    }
}

set stage1e_phase2_build_root [file normalize [file dirname [info script]]]
set stage1e_phase2_controller_root \
    [file join $stage1e_phase2_build_root controller]
set stage1e_phase2_library_root [file join $stage1e_phase2_build_root lib]

# The WP-A entrypoint normally executes its skeleton main procedure when run
# directly. Phase 2 reuses its reviewed readiness definitions without entering
# that historical execution path.
set stage1e_phase2_no_main_was_set \
    [info exists ::env(STAGE1E_CONTROLLER_NO_MAIN)]
if {$stage1e_phase2_no_main_was_set} {
    set stage1e_phase2_no_main_previous \
        $::env(STAGE1E_CONTROLLER_NO_MAIN)
}
set ::env(STAGE1E_CONTROLLER_NO_MAIN) 1
source [file join $stage1e_phase2_build_root stage1e_artifact_build.tcl]
if {$stage1e_phase2_no_main_was_set} {
    set ::env(STAGE1E_CONTROLLER_NO_MAIN) \
        $stage1e_phase2_no_main_previous
    unset stage1e_phase2_no_main_previous
} else {
    unset ::env(STAGE1E_CONTROLLER_NO_MAIN)
}
unset stage1e_phase2_no_main_was_set

set stage1e_phase2_modules [list \
    [file join $stage1e_phase2_library_root vivado_project.tcl] \
    [file join $stage1e_phase2_library_root bd_flow.tcl] \
    [file join $stage1e_phase2_build_root adapters \
        stage1e_ip_packaging.tcl] \
    [file join $stage1e_phase2_build_root adapters \
        stage1e_base_design.tcl] \
    [file join $stage1e_phase2_build_root adapters \
        stage1e_debug_design.tcl] \
    [file join $stage1e_phase2_build_root adapters \
        stage1e_mutation_bridge.tcl] \
    [file join $stage1e_phase2_build_root adapters \
        stage1e_build_target.tcl] \
    [file join $stage1e_phase2_build_root adapters stage1e_synthesis.tcl] \
    [file join $stage1e_phase2_controller_root \
        stage1e_phase2_controller.tcl]]

foreach stage1e_phase2_module_path $stage1e_phase2_modules {
    if {![file exists $stage1e_phase2_module_path] ||
        ![file isfile $stage1e_phase2_module_path]} {
        error "Required Stage 1E Phase 2 module not found: $stage1e_phase2_module_path"
    }
    source $stage1e_phase2_module_path
}

unset stage1e_phase2_module_path
unset stage1e_phase2_modules
unset stage1e_phase2_library_root
unset stage1e_phase2_controller_root
unset stage1e_phase2_build_root

proc ::stage1e::phase2_build::version {} {
    variable entrypoint_version
    return $entrypoint_version
}

proc ::stage1e::phase2_build::_canonical_path_components {path} {
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

proc ::stage1e::phase2_build::_path_is_equal_or_descendant {
    candidate_path
    parent_path
} {
    set candidate [_canonical_path_components $candidate_path]
    set parent [_canonical_path_components $parent_path]
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

proc ::stage1e::phase2_build::_launcher_require_dictionary {
    value
    label
} {
    if {[catch {dict size $value} dictionary_error]} {
        error "$label is not a dictionary: $dictionary_error"
    }
    return 1
}

proc ::stage1e::phase2_build::_launcher_same_path {
    first
    second
} {
    set first_components [_canonical_path_components $first]
    set second_components [_canonical_path_components $second]
    return [expr {$first_components eq $second_components}]
}

proc ::stage1e::phase2_build::_launcher_path_bytes {path} {
    set normalized [string map {\\ /} [file normalize $path]]
    return [string length [encoding convertto utf-8 $normalized]]
}

proc ::stage1e::phase2_build::_launcher_safe_relative_path {
    value
    label
} {
    set value [string map {\\ /} [string trim $value]]
    if {$value eq {} || [file pathtype $value] ne {relative}} {
        error "$label must be a relative path."
    }
    foreach component [file split $value] {
        if {$component in {. ..} || $component eq {}} {
            error "$label contains a disallowed path component."
        }
    }
    return $value
}

# Validate the identity that authorizes the Vivado launcher cwd. This is kept
# at the entrypoint boundary so an external runner cannot substitute its own
# directory, execution id, or ownership evidence after workspace creation.
proc ::stage1e::phase2_build::validate_launcher_workspace_identity {
    workspace_identity
} {
    _launcher_require_dictionary $workspace_identity {Workspace identity}
    foreach field {
        schema_version execution_id retry_number workspace_identifier
        workspace_path workspace_root evidence_dir ownership_evidence
        identity_sha256 git_commit git_tree
    } {
        if {![dict exists $workspace_identity $field]} {
            error "Workspace identity is missing launcher field: $field"
        }
    }
    if {[dict get $workspace_identity schema_version] ne \
        {stage1e-workspace-identity-v2}} {
        error {Vivado launcher requires workspace identity v2.}
    }
    set execution_id [string trim [dict get $workspace_identity execution_id]]
    if {$execution_id eq {} ||
        ![regexp {^[A-Za-z0-9._-]+$} $execution_id]} {
        error {Workspace identity execution_id is invalid for the launcher.}
    }
    set retry_number [string trim [dict get $workspace_identity retry_number]]
    if {![regexp {^[1-9][0-9]*$} $retry_number]} {
        error {Workspace identity retry_number is invalid for the launcher.}
    }
    if {[dict get $workspace_identity workspace_identifier] ne \
        "r$retry_number"} {
        error {Workspace identity retry-number binding is invalid for the launcher.}
    }
    foreach {value label pattern} [list \
        [dict get $workspace_identity git_commit] {Git commit} \
            {^[0-9A-Fa-f]{40}$} \
        [dict get $workspace_identity git_tree] {Git tree} \
            {^[0-9A-Fa-f]{40}$} \
        [dict get $workspace_identity identity_sha256] {Workspace identity hash} \
            {^[0-9A-Fa-f]{64}$}] {
        if {![regexp $pattern $value]} {
            error "$label is invalid for the launcher workspace identity."
        }
    }

    set workspace_root [dict get $workspace_identity workspace_root]
    set workspace_path [dict get $workspace_identity workspace_path]
    set evidence_dir [dict get $workspace_identity evidence_dir]
    foreach {path label} [list \
        $workspace_root workspace_root \
        $workspace_path workspace_path \
        $evidence_dir evidence_dir] {
        if {[file pathtype $path] ne {absolute}} {
            error "Workspace identity $label must be absolute for the launcher."
        }
    }
    set workspace_root [file normalize $workspace_root]
    set workspace_path [file normalize $workspace_path]
    set evidence_dir [file normalize $evidence_dir]
    if {![_launcher_same_path $workspace_path $workspace_root]} {
        error {Workspace identity workspace_path does not match workspace_root.}
    }
    if {![_path_is_equal_or_descendant $evidence_dir $workspace_root] ||
        [_launcher_same_path $evidence_dir $workspace_root] ||
        ![string equal -nocase [file tail $evidence_dir] {execution_state}]} {
        error {Workspace identity evidence_dir is outside execution_state.}
    }

    set ownership_relative [_launcher_safe_relative_path \
        [dict get $workspace_identity ownership_evidence] \
        {Workspace ownership evidence}]
    set ownership_path [file normalize [file join \
        $workspace_root $ownership_relative]]
    if {![_path_is_equal_or_descendant $ownership_path $evidence_dir] ||
        [_launcher_same_path $ownership_path $evidence_dir]} {
        error {Workspace ownership evidence escapes evidence_dir.}
    }

    # Recompute the identity digest from the exact serialized identity without
    # its digest field. A runner must not be able to provide a valid-looking
    # path with an unrelated execution identity.
    set unsigned_identity $workspace_identity
    dict unset unsigned_identity identity_sha256
    if {[catch {
        ::stage1d::source_check::sha256_text $unsigned_identity
    } calculated_hash hash_options]} {
        error "Unable to validate workspace identity hash: $calculated_hash"
    }
    if {![string equal -nocase $calculated_hash \
        [dict get $workspace_identity identity_sha256]]} {
        error {Workspace identity hash does not match its serialized fields.}
    }

    return [dict create \
        workspace_identity $workspace_identity \
        execution_id $execution_id \
        retry_number $retry_number \
        workspace_root $workspace_root \
        workspace_path $workspace_path \
        evidence_dir $evidence_dir \
        ownership_path $ownership_path \
        workspace_identity_hash \
            [string tolower [dict get $workspace_identity identity_sha256]]]
}

proc ::stage1e::phase2_build::launcher_working_directory {
    workspace_identity
} {
    return [dict get \
        [validate_launcher_workspace_identity $workspace_identity] workspace_root]
}

proc ::stage1e::phase2_build::launcher_cwd {workspace_identity} {
    return [launcher_working_directory $workspace_identity]
}

proc ::stage1e::phase2_build::launcher_path_budget {
    workspace_identity
} {
    variable launcher_state_relative_path
    variable launcher_windows_max_path_bytes
    variable launcher_windows_safety_margin_bytes
    variable reviewed_launcher_xil_descendant_paths
    set validated [validate_launcher_workspace_identity $workspace_identity]
    set workspace_root [dict get $validated workspace_root]
    set state_root [file normalize [file join $workspace_root \
        $launcher_state_relative_path]]
    if {![_path_is_equal_or_descendant $state_root $workspace_root] ||
        [_launcher_same_path $state_root $workspace_root]} {
        error {Vivado launcher state path escaped workspace_root.}
    }
    set usable_bytes [expr {$launcher_windows_max_path_bytes - 1}]
    set root_bytes [_launcher_path_bytes $workspace_root]
    set state_bytes [_launcher_path_bytes $state_root]
    set longest_relative_path {}
    set longest_path_bytes 0
    foreach relative_path $reviewed_launcher_xil_descendant_paths {
        set candidate [file normalize [file join \
            $workspace_root $relative_path]]
        if {![_path_is_equal_or_descendant $candidate $state_root] ||
            [_launcher_same_path $candidate $state_root]} {
            error {Reviewed Vivado launcher path escaped the .Xil root.}
        }
        set candidate_bytes [_launcher_path_bytes $candidate]
        if {$candidate_bytes > $longest_path_bytes} {
            set longest_path_bytes $candidate_bytes
            set longest_relative_path $relative_path
        }
    }
    set projected_bytes [expr {$longest_path_bytes + \
        $launcher_windows_safety_margin_bytes}]
    if {$projected_bytes > $usable_bytes} {
        error [join [list \
            {Vivado launcher workspace exceeds the Windows path budget.} \
            "workspace_bytes=$root_bytes" \
            "xil_root_bytes=$state_bytes" \
            "safety_margin_bytes=$launcher_windows_safety_margin_bytes" \
            "usable_bytes=$usable_bytes path=$workspace_root"] { }]
    }
    return [dict create \
        workspace_root $workspace_root \
        workspace_root_bytes $root_bytes \
        xil_root $state_root \
        xil_root_bytes $state_bytes \
        reviewed_xil_descendant_path_count \
            [llength $reviewed_launcher_xil_descendant_paths] \
        longest_reviewed_xil_relative_path $longest_relative_path \
        longest_reviewed_xil_path_bytes $longest_path_bytes \
        windows_max_path_bytes $launcher_windows_max_path_bytes \
        windows_path_safety_margin_bytes \
            $launcher_windows_safety_margin_bytes \
        projected_xil_path_bytes $projected_bytes \
        windows_usable_path_bytes $usable_bytes]
}

proc ::stage1e::phase2_build::validate_launcher_cwd {
    workspace_identity
    {observed_cwd {}}
    {allow_descendant 0}
} {
    set validated [validate_launcher_workspace_identity $workspace_identity]
    if {$observed_cwd eq {}} {
        set observed_cwd [pwd]
    }
    if {[file pathtype $observed_cwd] ne {absolute}} {
        error {Vivado launcher cwd must be an absolute path.}
    }
    set expected [dict get $validated workspace_root]
    set observed [file normalize $observed_cwd]
    if {$allow_descendant} {
        if {![_path_is_equal_or_descendant $observed $expected]} {
            error [join [list \
                {Vivado launcher cwd escaped the controlled workspace:} \
                "expected_descendant=$expected" "actual=$observed"] { }]
        }
    } elseif {![_launcher_same_path $observed $expected]} {
        error [join [list \
            {Vivado launcher cwd is not the controlled workspace:} \
            "expected=$expected" "actual=$observed"] { }]
    }
    set budget [launcher_path_budget $workspace_identity]
    return [dict merge $validated $budget [dict create \
        contract_version [launcher_contract_version] \
        expected_cwd $expected observed_cwd $observed \
        cwd_is_descendant 1]]
}

proc ::stage1e::phase2_build::validate_launcher_working_directory {
    workspace_identity
    {observed_cwd {}}
    {allow_descendant 0}
} {
    return [validate_launcher_cwd $workspace_identity $observed_cwd \
        $allow_descendant]
}

proc ::stage1e::phase2_build::_read_launcher_ownership {
    validated
} {
    set ownership_path [dict get $validated ownership_path]
    if {![file isfile $ownership_path]} {
        error "Workspace ownership evidence is unavailable: $ownership_path"
    }
    set channel [open $ownership_path r]
    fconfigure $channel -encoding utf-8 -translation auto
    set read_status [catch {read $channel} ownership_text read_options]
    set close_status [catch {close $channel} close_error]
    if {$read_status != 0} {
        return -options $read_options $ownership_text
    }
    if {$close_status != 0} {
        error "Unable to close workspace ownership evidence: $close_error"
    }
    if {[catch {dict size $ownership_text} ownership_error]} {
        error "Workspace ownership evidence is not a dictionary: $ownership_error"
    }
    foreach field {
        execution_id retry_number workspace_path workspace_identifier
        workspace_identity_schema_version workspace_identity_hash
    } {
        if {![dict exists $ownership_text $field]} {
            error "Workspace ownership evidence is missing: $field"
        }
    }
    if {[dict get $ownership_text execution_id] ne \
            [dict get $validated execution_id] ||
        [dict get $ownership_text retry_number] ne \
            [dict get $validated retry_number] ||
        [dict get $ownership_text workspace_identifier] ne \
            "r[dict get $validated retry_number]" ||
        ![_launcher_same_path [dict get $ownership_text workspace_path] \
            [dict get $validated workspace_root]] ||
        [dict get $ownership_text workspace_identity_schema_version] ne \
            {stage1e-workspace-identity-v2} ||
        ![string equal -nocase [dict get $ownership_text \
            workspace_identity_hash] [dict get $validated workspace_identity_hash]]} {
        error {Workspace ownership evidence does not match workspace identity.}
    }
    return $ownership_text
}

proc ::stage1e::phase2_build::enter_launcher_workspace {
    workspace_identity
} {
    set validated [validate_launcher_workspace_identity $workspace_identity]
    set workspace_root [dict get $validated workspace_root]
    if {![file isdirectory $workspace_root]} {
        error "Controlled launcher workspace is unavailable: $workspace_root"
    }
    _read_launcher_ownership $validated
    set previous_cwd [pwd]
    set change_status [catch {
        cd $workspace_root
        validate_launcher_cwd $workspace_identity [pwd]
    } change_error change_options]
    if {$change_status != 0} {
        catch {cd $previous_cwd}
        return -options $change_options $change_error
    }
    return [dict create \
        contract_version [launcher_contract_version] \
        previous_cwd $previous_cwd \
        launcher_cwd $workspace_root \
        workspace_identity_hash [dict get $validated workspace_identity_hash]]
}

proc ::stage1e::phase2_build::leave_launcher_workspace {
    launcher_state
} {
    _launcher_require_dictionary $launcher_state {Launcher state}
    foreach field {previous_cwd launcher_cwd} {
        if {![dict exists $launcher_state $field]} {
            error "Launcher state is missing: $field"
        }
    }
    set current_cwd [pwd]
    set containment_status [catch {
        if {![_path_is_equal_or_descendant $current_cwd \
            [dict get $launcher_state launcher_cwd]]} {
            error {Vivado launcher operation left the controlled workspace.}
        }
    } containment_error containment_options]
    set restore_status [catch {cd [dict get $launcher_state previous_cwd]} \
        restore_error restore_options]
    if {$containment_status != 0} {
        if {$restore_status != 0} {
            append containment_error "; cwd restore failed: $restore_error"
        }
        return -options $containment_options $containment_error
    }
    if {$restore_status != 0} {
        return -options $restore_options $restore_error
    }
    return [dict create restored_cwd [pwd]]
}

proc ::stage1e::phase2_build::with_launcher_workspace {
    workspace_identity
    command
} {
    if {[llength $command] == 0} {
        error {Launcher callback command must not be empty.}
    }
    set launcher_state [enter_launcher_workspace $workspace_identity]
    set callback_status [catch {
        uplevel #0 $command
    } callback_result callback_options]
    set leave_status [catch {
        leave_launcher_workspace $launcher_state
    } leave_error leave_options]
    if {$callback_status != 0} {
        if {$leave_status != 0} {
            append callback_result " (cwd restore failed: $leave_error)"
        }
        return -options $callback_options $callback_result
    }
    if {$leave_status != 0} {
        return -options $leave_options $leave_error
    }
    return $callback_result
}

proc ::stage1e::phase2_build::launcher_contract_version {} {
    variable launcher_contract_version
    return $launcher_contract_version
}

proc ::stage1e::phase2_build::launcher_lifetime_contract_version {} {
    variable launcher_lifetime_contract_version
    return $launcher_lifetime_contract_version
}

# Freeze a launcher lifetime that covers controller preparation, dispatch,
# bounded synthesis waiting, and orderly evidence/exit handling. The external
# process runner must consume this value; terminating Vivado earlier can leave
# the Project Mode run scheduler orphaned after launch_runs accepts the run.
proc ::stage1e::phase2_build::validate_launcher_lifetime_policy {
    synthesis_profile_policy
} {
    variable launcher_lifetime_contract_version
    _launcher_require_dictionary $synthesis_profile_policy \
        {Synthesis profile policy}
    if {![dict exists $synthesis_profile_policy job_policy]} {
        error {Synthesis profile policy is missing job_policy.}
    }
    set job_policy [dict get $synthesis_profile_policy job_policy]
    _launcher_require_dictionary $job_policy {Synthesis job policy}
    set required_fields {
        mode jobs dispatch_timeout_seconds
        dispatch_poll_interval_milliseconds wait_timeout_minutes
        pre_synthesis_budget_minutes shutdown_grace_minutes
        launcher_timeout_minutes
    }
    foreach field $required_fields {
        if {![dict exists $job_policy $field]} {
            error "Synthesis launcher lifetime policy is missing: $field"
        }
    }
    if {[dict get $job_policy mode] ne {LOCAL} ||
        ![string is integer -strict [dict get $job_policy jobs]] ||
        [dict get $job_policy jobs] < 1} {
        error {Synthesis launcher lifetime requires LOCAL positive-job policy.}
    }
    foreach field {
        dispatch_timeout_seconds dispatch_poll_interval_milliseconds
        wait_timeout_minutes pre_synthesis_budget_minutes
        shutdown_grace_minutes launcher_timeout_minutes
    } {
        if {![string is integer -strict [dict get $job_policy $field]] ||
            [dict get $job_policy $field] < 1} {
            error "Synthesis launcher lifetime field must be positive: $field"
        }
    }
    set dispatch_timeout_seconds \
        [dict get $job_policy dispatch_timeout_seconds]
    set poll_milliseconds \
        [dict get $job_policy dispatch_poll_interval_milliseconds]
    if {$poll_milliseconds > $dispatch_timeout_seconds * 1000} {
        error {Synthesis dispatch poll interval exceeds its timeout.}
    }
    set dispatch_budget_minutes \
        [expr {($dispatch_timeout_seconds + 59) / 60}]
    set required_launcher_minutes [expr {
        [dict get $job_policy pre_synthesis_budget_minutes] +
        $dispatch_budget_minutes +
        [dict get $job_policy wait_timeout_minutes] +
        [dict get $job_policy shutdown_grace_minutes]
    }]
    set launcher_timeout_minutes \
        [dict get $job_policy launcher_timeout_minutes]
    if {$launcher_timeout_minutes < $required_launcher_minutes} {
        error [join [list \
            {External Vivado launcher lifetime is shorter than the} \
            {controlled execution budget:} \
            "launcher=$launcher_timeout_minutes" \
            "required=$required_launcher_minutes"] { }]
    }
    return [dict create \
        contract_version $launcher_lifetime_contract_version \
        mode [dict get $job_policy mode] \
        jobs [dict get $job_policy jobs] \
        dispatch_timeout_seconds $dispatch_timeout_seconds \
        dispatch_poll_interval_milliseconds $poll_milliseconds \
        dispatch_budget_minutes $dispatch_budget_minutes \
        wait_timeout_minutes [dict get $job_policy wait_timeout_minutes] \
        pre_synthesis_budget_minutes \
            [dict get $job_policy pre_synthesis_budget_minutes] \
        shutdown_grace_minutes \
            [dict get $job_policy shutdown_grace_minutes] \
        required_launcher_timeout_minutes $required_launcher_minutes \
        launcher_timeout_minutes $launcher_timeout_minutes \
        do_not_terminate_while_wait_active 1]
}

proc ::stage1e::phase2_build::_plain_evidence_filename {value label} {
    set value [string trim $value]
    set canonical [string map {\\ /} $value]
    if {$value eq {} || [file pathtype $value] ne {relative} ||
        [string first {/} $canonical] >= 0 || $value in {. ..} ||
        ![regexp {^[A-Za-z0-9._-]+$} $value]} {
        error "$label must be a plain relative filename."
    }
    return $value
}

# Compose the only synthesis-evidence destination accepted by Phase 2. The
# profile's report_directory_role remains a logical role; it must never be
# joined directly to workspace_root. Every persisted synthesis evidence file
# is instead anchored below the identity-bound evidence_dir.
proc ::stage1e::phase2_build::synthesis_evidence_paths {
    workspace_identity
    synthesis_profile_policy
} {
    variable synthesis_evidence_contract_version
    variable synthesis_evidence_leaf
    if {[catch {dict size $workspace_identity} workspace_error]} {
        error "Workspace identity is not a dictionary: $workspace_error"
    }
    foreach field {schema_version workspace_root evidence_dir} {
        if {![dict exists $workspace_identity $field]} {
            error "Workspace identity is missing synthesis evidence field: $field"
        }
    }
    if {[dict get $workspace_identity schema_version] ne \
        {stage1e-workspace-identity-v2}} {
        error {Synthesis evidence requires workspace identity v2.}
    }
    set workspace_root [dict get $workspace_identity workspace_root]
    set evidence_root [dict get $workspace_identity evidence_dir]
    foreach {path label} [list \
        $workspace_root {workspace_root} $evidence_root {evidence_dir}] {
        if {[file pathtype $path] ne {absolute}} {
            error "Workspace identity $label must be an absolute path."
        }
    }
    set workspace_root [file normalize $workspace_root]
    set evidence_root [file normalize $evidence_root]
    if {![_path_is_equal_or_descendant $evidence_root $workspace_root] ||
        [_canonical_path_components $evidence_root] eq \
            [_canonical_path_components $workspace_root] ||
        ![string equal -nocase [file tail $evidence_root] {execution_state}]} {
        error [join [list \
            {Workspace evidence_dir must be the execution_state descendant} \
            {owned by workspace identity v2.}] { }]
    }

    if {[catch {dict size $synthesis_profile_policy} policy_error]} {
        error "Synthesis profile policy is not a dictionary: $policy_error"
    }
    foreach field {output_policy report_policy} {
        if {![dict exists $synthesis_profile_policy $field]} {
            error "Synthesis profile policy is missing: $field"
        }
    }
    set output_policy [dict get $synthesis_profile_policy output_policy]
    foreach field {report_directory_role run_log_relative_path} {
        if {![dict exists $output_policy $field]} {
            error "Synthesis output policy is missing: $field"
        }
    }
    set logical_role [string map {\\ /} [string trim \
        [dict get $output_policy report_directory_role]]]
    if {$logical_role ni {synthesis reports/synthesis}} {
        error {Synthesis report directory role is not the reviewed synthesis role.}
    }

    set report_names [dict get $synthesis_profile_policy report_policy]
    set evidence_directory [file normalize \
        [file join $evidence_root $synthesis_evidence_leaf]]
    if {![_path_is_equal_or_descendant $evidence_directory $evidence_root] ||
        [_canonical_path_components $evidence_directory] eq \
            [_canonical_path_components $evidence_root]} {
        error {Synthesis evidence directory escaped workspace evidence_dir.}
    }
    set report_paths [dict create]
    set observed_names {}
    foreach role {synthesis_report utilization_report message_report} {
        if {![dict exists $report_names $role]} {
            error "Synthesis report policy is missing: $role"
        }
        set filename [_plain_evidence_filename \
            [dict get $report_names $role] "Synthesis report $role"]
        if {$filename in $observed_names} {
            error {Synthesis evidence filenames must be unique.}
        }
        lappend observed_names $filename
        dict set report_paths $role \
            [file normalize [file join $evidence_directory $filename]]
    }
    set run_log_filename [_plain_evidence_filename \
        [dict get $output_policy run_log_relative_path] {Synthesis run log}]
    if {$run_log_filename in $observed_names} {
        error {Synthesis run log and report filenames must be distinct.}
    }
    return [dict create \
        schema_version $synthesis_evidence_contract_version \
        directory $evidence_directory \
        report_paths $report_paths \
        run_log_path [file normalize \
            [file join $evidence_directory $run_log_filename]]]
}

# The caller must supply the complete Phase 2 context, including an explicit
# same-execution authorization. Profile selection alone cannot authorize this
# procedure. The composed controller validates every identity and issues the
# narrower per-operation grants consumed by the adapters.
proc ::stage1e::phase2_build::run {
    context
    {operation_overrides {}}
} {
    variable context_schema_version
    if {[catch {dict size $context} dictionary_error]} {
        error "Stage 1E Phase 2 context is not a dictionary: $dictionary_error"
    }
    if {![dict exists $context context_schema_version] ||
        [dict get $context context_schema_version] ne \
            $context_schema_version} {
        error {Stage 1E Phase 2 context schema mismatch.}
    }
    if {![dict exists $context execution_authorization]} {
        error {Stage 1E Phase 2 execution authorization is required.}
    }
    return [::stage1e::phase2_controller::run \
        $context $operation_overrides]
}
