# Source-only tests for the Stage 1E WP-C2 synthesis adapter.
#
# The backend below is an in-memory Vivado-shaped model. It records the
# synthesis-only command boundary and writes isolated text evidence files;
# no Vivado executable, project/BD lifecycle command, implementation command,
# FPGA artifact command, board command, PYNQ command, or MMIO operation runs.

namespace eval ::stage1e::synthesis_adapter_tests {
    variable pass_count 0
    variable fail_count 0
    variable test_root {}
    variable invocation_log {}
    variable forbidden_count 0
    variable current_project project::stage1e_synthesis
    variable current_bd protection_system
    variable fileset_object fileset::sources_1
    variable run_object run::synth_1
    variable properties [dict create]
    variable launched 0
    variable dispatch_behavior START
    variable wait_behavior COMPLETE
    variable after_count 0
    variable output_directory {}
    variable begin_marker_path {}
    variable run_log_path {}
    variable run_log_source_path {}
    variable message_database_path {}
    variable report_payloads [dict create]
    variable message_api_available 1
    variable message_database_missing 0
    variable message_report_missing 0
    variable message_write_error 0
    variable message_report_text {}
    variable synthesis_report_missing 0
    variable utilization_report_missing 0
}

set stage1e_synthesis_test_dir [file normalize [file dirname [info script]]]
set stage1e_synthesis_adapter [file normalize [file join \
    $stage1e_synthesis_test_dir .. adapters stage1e_synthesis.tcl]]

# Sourcing is the definition-only check. Replace the production backend before
# any test invokes the adapter.
source $stage1e_synthesis_adapter
rename ::stage1e::synthesis::backend::invoke \
    ::stage1e::synthesis::backend::_production_invoke
proc ::stage1e::synthesis::backend::invoke {command arguments} {
    return [::stage1e::synthesis_adapter_tests::mock_invoke \
        $command $arguments]
}

proc ::stage1e::synthesis_adapter_tests::fail {message} {
    error "TEST FAILURE: $message"
}

proc ::stage1e::synthesis_adapter_tests::assert_true {
    condition
    message
} {
    if {!$condition} {
        fail $message
    }
}

proc ::stage1e::synthesis_adapter_tests::assert_equal {
    expected
    actual
    message
} {
    if {$expected ne $actual} {
        fail "$message: expected=<$expected> actual=<$actual>"
    }
}

proc ::stage1e::synthesis_adapter_tests::assert_status {
    result
    expected
    message
} {
    if {[catch {dict size $result} dictionary_error]} {
        fail "$message is not a dictionary: $dictionary_error"
    }
    if {![dict exists $result status] ||
        [dict get $result status] ne $expected} {
        fail "$message: expected=<$expected> actual=<[dict get $result status]> errors=<[dict get $result errors]>"
    }
}

proc ::stage1e::synthesis_adapter_tests::first_error_code {result} {
    if {![dict exists $result errors] ||
        [llength [dict get $result errors]] == 0} {
        fail {Expected a structured synthesis error record.}
    }
    return [dict get [lindex [dict get $result errors] 0] code]
}

proc ::stage1e::synthesis_adapter_tests::run_case {name body} {
    variable pass_count
    variable fail_count
    set case_status [catch {uplevel 1 $body} case_error case_options]
    if {$case_status == 0} {
        incr pass_count
        puts "$name: PASS"
        return
    }
    incr fail_count
    puts stderr "$name: FAIL: $case_error"
    if {[dict exists $case_options -errorinfo]} {
        puts stderr [dict get $case_options -errorinfo]
    }
}

proc ::stage1e::synthesis_adapter_tests::temporary_base {} {
    foreach variable_name {STAGE1E_TEST_TEMP_ROOT TEMP TMP TMPDIR} {
        if {[info exists ::env($variable_name)] &&
            [string trim $::env($variable_name)] ne {}} {
            set canonical [string map {\\ /} $::env($variable_name)]
            if {$::tcl_platform(platform) eq {windows} &&
                [regexp {^[A-Za-z]:/} $canonical]} {
                set canonical "//?/$canonical"
            }
            return [file normalize $canonical]
        }
    }
    error {No external temporary directory is available for synthesis tests.}
}

proc ::stage1e::synthesis_adapter_tests::prepare_suite {} {
    variable test_root
    set test_root [file normalize [file join [temporary_base] \
        "stage1e_synthesis_tests_[pid]_[clock clicks]"]]
    if {![string match {stage1e_synthesis_tests_*} [file tail $test_root]]} {
        error "Unsafe synthesis test root: $test_root"
    }
    file mkdir $test_root
}

proc ::stage1e::synthesis_adapter_tests::safe_cleanup {} {
    variable test_root
    if {$test_root eq {} || ![file exists $test_root]} {
        return
    }
    if {![string match {stage1e_synthesis_tests_*} [file tail $test_root]]} {
        error "Refusing unsafe synthesis test cleanup: $test_root"
    }
    file delete -force -- $test_root
}

proc ::stage1e::synthesis_adapter_tests::write_file {path contents} {
    file mkdir [file dirname $path]
    set channel [open $path w]
    fconfigure $channel -encoding utf-8 -translation lf
    puts $channel $contents
    close $channel
}

proc ::stage1e::synthesis_adapter_tests::valid_message_report {
    {message_lines {{INFO: [Synth 8-1000] Mock synthesis completed.}}}
} {
    return [join [concat [list \
        {####################################################################################} \
        {# Generated by Vivado 2024.1 built on 'mock' by 'test'} \
        {# Command Used: write_messages -message_db mock/vivado.pb -file mock/messages.rpt} \
        {####################################################################################} \
        {}] $message_lines] "\n"]
}

proc ::stage1e::synthesis_adapter_tests::reset_mock {} {
    variable invocation_log
    variable forbidden_count
    variable properties
    variable launched
    variable dispatch_behavior
    variable wait_behavior
    variable after_count
    variable output_directory
    variable begin_marker_path
    variable run_log_path
    variable run_log_source_path
    variable message_database_path
    variable report_payloads
    variable message_api_available
    variable message_database_missing
    variable message_report_missing
    variable message_write_error
    variable message_report_text
    variable synthesis_report_missing
    variable utilization_report_missing
    set invocation_log {}
    set forbidden_count 0
    set properties [dict create]
    set launched 0
    set dispatch_behavior START
    set wait_behavior COMPLETE
    set after_count 0
    set output_directory {}
    set begin_marker_path {}
    set run_log_path {}
    set run_log_source_path {}
    set message_database_path {}
    set report_payloads [dict create]
    set message_api_available 1
    set message_database_missing 0
    set message_report_missing 0
    set message_write_error 0
    set message_report_text [valid_message_report]
    set synthesis_report_missing 0
    set utilization_report_missing 0
}

proc ::stage1e::synthesis_adapter_tests::start_mock_dispatch {} {
    variable launched
    variable dispatch_behavior
    variable properties
    variable begin_marker_path
    variable run_log_source_path
    if {!$launched || $dispatch_behavior eq {STALL}} {
        return
    }
    dict set properties run::synth_1 STATUS {Running synth_design}
    dict set properties run::synth_1 JOB_ID local-job-1
    if {$dispatch_behavior ne {NO_PROGRESS}} {
        dict set properties run::synth_1 PROGRESS {1%}
    }
    if {$dispatch_behavior ne {NO_BEGIN}} {
        write_file $begin_marker_path {<Process Pid="1234"/>}
    }
    if {$dispatch_behavior ne {NO_LOG}} {
        write_file $run_log_source_path {mock synthesis run log}
    }
}

proc ::stage1e::synthesis_adapter_tests::mock_invoke {command arguments} {
    variable invocation_log
    variable forbidden_count
    variable properties
    variable launched
    variable dispatch_behavior
    variable wait_behavior
    variable after_count
    variable output_directory
    variable begin_marker_path
    variable run_log_path
    variable run_log_source_path
    variable message_database_path
    variable report_payloads
    variable message_api_available
    variable message_database_missing
    variable message_report_missing
    variable message_write_error
    variable message_report_text
    variable synthesis_report_missing
    variable utilization_report_missing

    lappend invocation_log [linsert $arguments 0 $command]
    set forbidden {
        create_project open_project close_project
        create_bd_design open_bd_design close_bd_design
        validate_bd_design save_bd_design
        stage1d_controlled_stimulus::apply
        get_messages report_messages
        launch_runs_impl wait_on_run_impl open_run_impl
        synth_design opt_design place_design route_design
        write_bitstream write_debug_probes write_hw_platform
        write_xsa export_hardware generate_target make_wrapper
        add_files exit
        pynq mmio read_bitstream
    }
    if {$command in $forbidden} {
        incr forbidden_count
        error "Forbidden command invoked: $command"
    }

    switch -- $command {
        info {
            if {$arguments ne {commands write_messages}} {
                error "Unexpected message API probe: $arguments"
            }
            if {$message_api_available} {
                return [list write_messages]
            }
            return {}
        }
        current_project { return project::stage1e_synthesis }
        current_bd_design { return protection_system }
        get_filesets { return [list fileset::sources_1] }
        get_runs { return [list run::synth_1] }
        get_property {
            set property [string toupper [lindex $arguments 0]]
            set object [lindex $arguments 1]
            if {[dict exists $properties $object $property]} {
                return [dict get $properties $object $property]
            }
            error "Mock property missing: $property on $object"
        }
        set_property {
            set property [string toupper [lindex $arguments 0]]
            set value [lindex $arguments 1]
            set object [lindex $arguments 2]
            dict set properties $object $property $value
            return {}
        }
        launch_runs {
            set run [lindex $arguments 0]
            if {$run ne {run::synth_1}} {
                error "Unexpected synthesis run: $run"
            }
            set jobs_index [lsearch -exact $arguments {-jobs}]
            if {$jobs_index < 0 || [lindex $arguments [incr jobs_index]] ne {2}} {
                error "Unexpected synthesis job policy: $arguments"
            }
            set launched 1
            file mkdir $output_directory
            dict set properties run::synth_1 STATUS {Queued...}
            dict set properties run::synth_1 PROGRESS {0%}
            dict set properties run::synth_1 JOB_ID {}
            return {}
        }
        after {
            if {[llength $arguments] != 1 ||
                ![string is integer -strict [lindex $arguments 0]] ||
                [lindex $arguments 0] < 1} {
                error "Unexpected dispatch poll: $arguments"
            }
            incr after_count
            start_mock_dispatch
            return {}
        }
        wait_on_run {
            set timeout_index [lsearch -exact $arguments {-timeout}]
            if {$timeout_index < 0 ||
                [lindex $arguments [expr {$timeout_index + 1}]] ne {60} ||
                [lindex $arguments end] ne {run::synth_1}} {
                error "Unexpected bounded synthesis wait: $arguments"
            }
            if {$wait_behavior eq {TIMEOUT}} {
                return {}
            }
            if {$wait_behavior eq {FAILED}} {
                dict set properties run::synth_1 STATUS {synth_design ERROR}
                dict set properties run::synth_1 PROGRESS {100%}
                return {}
            }
            if {$wait_behavior ne {COMPLETE}} {
                error "Unexpected mock wait behavior: $wait_behavior"
            }
            dict set properties run::synth_1 STATUS {synth_design Complete!}
            dict set properties run::synth_1 PROGRESS {100%}
            dict set properties run::synth_1 JOB_ID {}
            catch {file delete -force -- $begin_marker_path}
            if {!$message_database_missing} {
                write_file $message_database_path {mock Vivado message database}
            }
            return {}
        }
        open_run { return {} }
        report_design_analysis {
            set file_index [lsearch -exact $arguments {-file}]
            if {$file_index < 0 || [llength $arguments] != 2 ||
                [lsearch -exact $arguments {-force}] >= 0} {
                error "Vivado 2024.1 report_design_analysis contract mismatch: $arguments"
            }
            set path [lindex $arguments [expr {$file_index + 1}]]
            if {!$synthesis_report_missing} {
                write_file $path {mock synthesis report}
            }
            dict set report_payloads synthesis_report $path
            return {}
        }
        report_utilization {
            set path [lindex $arguments [expr {[lsearch -exact $arguments {-file}] + 1}]]
            if {!$utilization_report_missing} {
                write_file $path {mock utilization report}
            }
            dict set report_payloads utilization_report $path
            return {}
        }
        write_messages {
            if {$message_write_error} {
                error {Mock write_messages API failure}
            }
            set database_index [lsearch -exact $arguments {-message_db}]
            set file_index [lsearch -exact $arguments {-file}]
            if {$database_index < 0 || $file_index < 0 ||
                [lindex $arguments [expr {$database_index + 1}]] ne \
                    $message_database_path ||
                [lsearch -exact $arguments {-severity}] < 0 ||
                [lsearch -exact $arguments {-suppression}] < 0 ||
                [lsearch -exact $arguments {-modified_severity}] < 0 ||
                [lsearch -exact $arguments {-verbose}] < 0 ||
                [lsearch -exact $arguments {-force}] >= 0 ||
                [lsearch -exact $arguments {-quiet}] >= 0} {
                error "Unexpected write_messages contract: $arguments"
            }
            set path [lindex $arguments [expr {$file_index + 1}]]
            if {!$message_report_missing} {
                write_file $path $message_report_text
            }
            dict set report_payloads message_report $path
            return $path
        }
        default {
            error "Unexpected mock Vivado command: $command $arguments"
        }
    }
}

proc ::stage1e::synthesis_adapter_tests::valid_context {name} {
    variable test_root
    variable properties
    variable output_directory
    variable begin_marker_path
    variable run_log_path
    variable run_log_source_path
    variable message_database_path
    variable current_project
    variable current_bd
    variable fileset_object
    variable run_object

    set execution_id "STAGE1E-SYNTHESIS-$name"
    set workspace_root [file normalize [file join $test_root executions $name]]
    set evidence_dir [file join $workspace_root execution_state]
    set report_dir [file join $evidence_dir synthesis]
    set project_directory [file join $workspace_root project]
    set project_path [file join $project_directory stage1e_design.xpr]
    set bd_path [file join $project_directory project.srcs sources_1 bd \
        protection_system protection_system.bd]
    set wrapper_path [file join $project_directory project.gen sources_1 bd \
        protection_system hdl stage1e_design_wrapper.v]
    set output_directory [file join $workspace_root project.runs synth_1]
    set begin_marker_path \
        [file join $output_directory .Vivado_Synthesis.begin.rst]
    set run_log_path [file join $report_dir runme.log]
    set run_log_source_path [file join $output_directory runme.log]
    set message_database_path [file join $output_directory vivado.pb]
    set repository_root [file normalize [file join $test_root repository]]
    file mkdir $report_dir
    file mkdir $project_directory
    file mkdir [file dirname $bd_path]
    file mkdir [file dirname $wrapper_path]
    file mkdir $output_directory
    write_file $project_path {mock Vivado project}
    write_file $bd_path {mock BD}
    write_file $wrapper_path {module stage1e_design_wrapper; endmodule}

    set project_identity [dict create \
        project_name stage1e_synthesis \
        project_directory [file normalize $project_directory] \
        project_path [file normalize $project_path] \
        part xc7z020clg400-1 \
        board_part tul.com.tw:pynq-z2:part0:1.0]
    set project_ownership [dict create \
        owner vivado_project execution_id $execution_id \
        project_handle $current_project \
        project_path [file normalize $project_path] \
        identity_verified 1 project_identity $project_identity]
    set bd_ownership [dict create \
        owner bd_flow execution_id $execution_id \
        project_path [file normalize $project_path] \
        bd_name protection_system bd_path [file normalize $bd_path] \
        opened 1 identity_verified 1 validated 1 saved 1]

    dict set properties $current_project NAME stage1e_synthesis
    dict set properties $current_project DIRECTORY \
        [file normalize $project_directory]
    dict set properties $current_project PART xc7z020clg400-1
    dict set properties $current_project BOARD_PART \
        tul.com.tw:pynq-z2:part0:1.0
    dict set properties $fileset_object NAME sources_1
    dict set properties $fileset_object TOP stage1e_design_wrapper
    dict set properties $run_object NAME synth_1
    dict set properties $run_object DIRECTORY [file normalize $output_directory]
    dict set properties $run_object STATUS {Not started}
    dict set properties $run_object PROGRESS {0%}
    dict set properties $run_object JOB_ID {}
    dict set properties $run_object IS_SYNTHESIS 1
    dict set properties $run_object STRATEGY {Vivado Synthesis Defaults}
    dict set properties $run_object {STEPS.SYNTH_DESIGN.ARGS.DIRECTIVE} Default

    set hash_a [string repeat a 64]
    set source_identity [dict create \
        schema_version stage1e-source-identity-v1 \
        execution_id $execution_id repository_root $repository_root \
        git_commit [string repeat 2 40] \
        source_inventory_sha256 [string repeat b 64] \
        identity_sha256 $hash_a]
    set configuration_identity [dict create \
        schema_version stage1e-configuration-identity-v1 \
        execution_id $execution_id sha256 [string repeat c 64] \
        identity_sha256 [string repeat d 64]]
    set environment_identity [dict create \
        schema_version stage1e-environment-identity-v1 \
        execution_id $execution_id vivado_version 2024.1 \
        part xc7z020clg400-1 \
        board_part tul.com.tw:pynq-z2:part0:1.0 \
        ip_identities {processing_system7 smartconnect protection_ip}]
    set retry_number 15
    set workspace_identifier r15
    set git_tree [string repeat 3 40]
    set ownership_reference execution_state/ownership.dict
    set workspace_identity [dict create \
        schema_version stage1e-workspace-identity-v2 \
        execution_id $execution_id \
        retry_number $retry_number \
        git_commit [dict get $source_identity git_commit] \
        git_tree $git_tree \
        workspace_identifier $workspace_identifier \
        workspace_path [file normalize $workspace_root] \
        workspace_root [file normalize $workspace_root] \
        evidence_dir [file normalize $evidence_dir] \
        synthesis_output_dir [file normalize $output_directory] \
        ownership_evidence $ownership_reference]
    dict set workspace_identity identity_sha256 \
        [::stage1d::source_check::sha256_text $workspace_identity]
    set ownership [dict create \
        ownership_schema_version v1 \
        execution_identifier $execution_id \
        execution_id $execution_id \
        retry_number $retry_number \
        git_commit [dict get $workspace_identity git_commit] \
        git_tree $git_tree \
        workspace_role ACTIVE_BUILD_WORKSPACE \
        workspace_path [file normalize $workspace_root] \
        workspace_identifier $workspace_identifier \
        workspace_identity_schema_version \
            [dict get $workspace_identity schema_version] \
        workspace_identity_hash \
            [dict get $workspace_identity identity_sha256]]
    write_file [file join $workspace_root $ownership_reference] $ownership
    set source_hash [::stage1e::synthesis::_identity_hash \
        $source_identity source_identity]
    set configuration_hash [::stage1e::synthesis::_identity_hash \
        $configuration_identity configuration_identity]
    set environment_hash [::stage1e::synthesis::_identity_hash \
        $environment_identity environment_identity]
    set build_target [dict create \
        schema_version stage1e-build-target-identity-v1 \
        producer_operation stage1e::build_target::prepare \
        execution_id $execution_id acceptance_state ACCEPTED \
        project_path [file normalize $project_path] \
        bd_name protection_system bd_path [file normalize $bd_path] \
        wrapper_path [file normalize $wrapper_path] \
        top_module stage1e_design_wrapper fileset sources_1 \
        source_identity_sha256 $source_hash \
        configuration_identity_sha256 $configuration_hash \
        environment_identity_sha256 $environment_hash \
        identity_sha256 [string repeat f 64]]
    set report_paths [dict create \
        synthesis_report [file join $report_dir synthesis.rpt] \
        utilization_report [file join $report_dir utilization.rpt] \
        message_report [file join $report_dir messages.rpt]]
    set job_policy [dict create \
        mode LOCAL jobs 2 \
        dispatch_timeout_seconds 300 \
        dispatch_poll_interval_milliseconds 1000 \
        wait_timeout_minutes 60 \
        pre_synthesis_budget_minutes 45 \
        shutdown_grace_minutes 10 \
        launcher_timeout_minutes 120]
    set launcher_lifetime_policy [dict create \
        contract_version stage1e-vivado-launcher-lifetime-v1 \
        mode LOCAL jobs 2 \
        dispatch_timeout_seconds 300 \
        dispatch_poll_interval_milliseconds 1000 \
        dispatch_budget_minutes 5 \
        wait_timeout_minutes 60 \
        pre_synthesis_budget_minutes 45 \
        shutdown_grace_minutes 10 \
        required_launcher_timeout_minutes 120 \
        launcher_timeout_minutes 120 \
        do_not_terminate_while_wait_active 1]
    set policy [dict create \
        schema_version stage1e-synthesis-policy-v1 \
        run_name synth_1 \
        strategy {Vivado Synthesis Defaults} \
        directives [dict create {STEPS.SYNTH_DESIGN.ARGS.DIRECTIVE} Default] \
        seed_policy [dict create mode NOT_APPLICABLE] \
        job_policy $job_policy \
        incremental_synthesis_policy [dict create enabled 0 checkpoint {}] \
        output_directory [file normalize $output_directory] \
        fileset sources_1 top_module stage1e_design_wrapper \
        allowed_initial_statuses [list {Not started}] \
        accepted_terminal_statuses [list {synth_design Complete!}] \
        report_paths $report_paths run_log_path [file normalize $run_log_path] \
        warning_policy [dict create \
            schema_version stage1e-synthesis-warning-policy-v1 \
            unknown_disposition REJECTED dispositions [dict create]]]
    return [dict create \
        context_schema_version stage1e-synthesis-context-v1 \
        operation stage1e::synthesis::run phase SYNTHESIS \
        execution_id $execution_id \
        authorization [dict create \
            status AUTHORIZED authority controller_core \
            execution_id $execution_id operation stage1e::synthesis::run \
            phase SYNTHESIS capability synthesis_enabled capability_enabled 1] \
        workspace_identity $workspace_identity \
        launcher_lifetime_policy $launcher_lifetime_policy \
        build_target_identity $build_target \
        source_identity $source_identity \
        configuration_identity $configuration_identity \
        environment_identity $environment_identity \
        project_ownership $project_ownership \
        bd_ownership $bd_ownership \
        synthesis_policy $policy]
}

proc ::stage1e::synthesis_adapter_tests::with_dispatch_timeout {
    context
    seconds
} {
    dict set context synthesis_policy job_policy \
        dispatch_timeout_seconds $seconds
    dict set context launcher_lifetime_policy \
        dispatch_timeout_seconds $seconds
    set dispatch_minutes [expr {($seconds + 59) / 60}]
    dict set context launcher_lifetime_policy \
        dispatch_budget_minutes $dispatch_minutes
    set binding [dict get $context launcher_lifetime_policy]
    set required [expr {
        [dict get $binding pre_synthesis_budget_minutes] +
        $dispatch_minutes + [dict get $binding wait_timeout_minutes] +
        [dict get $binding shutdown_grace_minutes]
    }]
    dict set context launcher_lifetime_policy \
        required_launcher_timeout_minutes $required
    return $context
}

proc ::stage1e::synthesis_adapter_tests::assert_no_forbidden {} {
    variable forbidden_count
    assert_equal 0 $forbidden_count {Forbidden-command tripwire count}
}

proc ::stage1e::synthesis_adapter_tests::command_seen {command} {
    variable invocation_log
    foreach invocation $invocation_log {
        if {[lindex $invocation 0] eq $command} {
            return 1
        }
    }
    return 0
}

proc ::stage1e::synthesis_adapter_tests::command_index {command} {
    variable invocation_log
    set index 0
    foreach invocation $invocation_log {
        if {[lindex $invocation 0] eq $command} {
            return $index
        }
        incr index
    }
    return -1
}

proc ::stage1e::synthesis_adapter_tests::first_invocation {command} {
    variable invocation_log
    foreach invocation $invocation_log {
        if {[lindex $invocation 0] eq $command} {
            return $invocation
        }
    }
    return {}
}

proc ::stage1e::synthesis_adapter_tests::error_codes {result} {
    set codes {}
    foreach error_record [dict get $result errors] {
        lappend codes [dict get $error_record code]
    }
    return $codes
}

proc ::stage1e::synthesis_adapter_tests::ownership_path {context} {
    set identity [dict get $context workspace_identity]
    return [file normalize [file join \
        [dict get $identity workspace_root] \
        [dict get $identity ownership_evidence]]]
}

proc ::stage1e::synthesis_adapter_tests::read_dictionary {path} {
    set channel [open $path r]
    fconfigure $channel -encoding utf-8 -translation auto
    set value [read $channel]
    close $channel
    dict size $value
    return $value
}

proc ::stage1e::synthesis_adapter_tests::reviewed_warning_policy {} {
    set profile_path [file normalize [file join \
        $::stage1e_synthesis_test_dir .. config \
        stage1e_reconstruction_profile_v1.dict]]
    set profile [read_dictionary $profile_path]
    return [dict get $profile build_policy synthesis warning_policy]
}

proc ::stage1e::synthesis_adapter_tests::run_all {} {
    variable invocation_log
    variable dispatch_behavior
    variable wait_behavior
    variable after_count
    variable message_api_available
    variable message_database_missing
    variable message_report_missing
    variable message_write_error
    variable message_report_text
    variable synthesis_report_missing
    variable utilization_report_missing

    run_case SYNTHESIS_CONTEXT_VALID {
        reset_mock
        set context [valid_context context_valid]
        set result [::stage1e::synthesis::run $context]
        assert_status $result PASS {Valid synthesis status}
        assert_true [dict exists $result produced_identities \
            synthesis_result_identity] {Synthesis result identity missing}
        assert_equal CANDIDATE \
            [dict get $result synthesis_result_identity acceptance_state] \
            {Synthesis result must remain a candidate}
        foreach role {synthesis_report utilization_report message_report} {
            assert_true [dict exists $result evidence_references reports $role] \
                "Missing synthesis report evidence: $role"
            assert_true [regexp {^[0-9a-f]{64}$} \
                [dict get $result evidence_references reports $role sha256]] \
                "Invalid synthesis report hash: $role"
        }
        assert_true [command_seen launch_runs] {Synthesis was not launched}
        assert_true [command_seen wait_on_run] {Synthesis was not monitored}
        assert_equal {wait_on_run -timeout 60 run::synth_1} \
            [lindex $invocation_log [command_index wait_on_run]] \
            {Synthesis wait is not bounded by policy}
        assert_true [command_seen open_run] {Synthesis run was not opened}
        assert_true [command_seen write_messages] \
            {Vivado message database was not exported}
        assert_true [expr {[command_index info] >= 0 &&
            [command_index info] < [command_index launch_runs]}] \
            {Message API was not validated before launch}
        assert_true [expr {[command_index write_messages] >
            [command_index wait_on_run]}] \
            {Message evidence was collected before synthesis completion}
        assert_true [expr {![command_seen get_messages] &&
            ![command_seen report_messages]}] \
            {Unsupported Vivado message API was invoked}
        set expected_evidence_dir [file normalize [file join \
            [dict get $context workspace_identity evidence_dir] synthesis]]
        set consumed_policy \
            [dict get $result consumed_identities synthesis_policy]
        assert_equal $expected_evidence_dir \
            [dict get $consumed_policy synthesis_evidence_directory] \
            {Synthesis evidence directory}
        foreach role {synthesis_report utilization_report message_report} {
            assert_equal $expected_evidence_dir [file dirname \
                [dict get $result evidence_references reports $role path]] \
                "Synthesis report evidence directory: $role"
        }
        assert_equal $expected_evidence_dir [file dirname \
            [dict get $result evidence_references synthesis_log path]] \
            {Synthesis log evidence directory}
        assert_equal [dict get $context synthesis_policy run_log_path] \
            [dict get $result evidence_references synthesis_log path] \
            {Synthesis log evidence path}
        assert_equal [file normalize [file join \
            [dict get $context workspace_identity synthesis_output_dir] \
            runme.log]] [dict get $consumed_policy run_log_source_path] \
            {Native synthesis run log source path}
        assert_equal [file normalize [file join \
            [dict get $context workspace_identity synthesis_output_dir] \
            vivado.pb]] [dict get $consumed_policy message_database_path] \
            {Native synthesis message database path}
        assert_equal stage1e-vivado-message-inventory-v1 \
            [dict get $result evidence_references message_inventory \
                schema_version] {Message inventory schema}
        assert_true [expr {[dict get $result evidence_references \
            message_inventory record_count] > 0}] \
            {Message inventory has no records}
        assert_true [regexp {^[0-9a-f]{64}$} [dict get $result \
            evidence_references message_database sha256]] \
            {Message database evidence hash}
        set dispatch [dict get $result evidence_references dispatch]
        assert_equal STARTED [dict get $dispatch state] \
            {Synthesis dispatch state}
        foreach field {
            child_process_observed begin_marker_observed
            begin_marker_validated run_log_observed progress_observed
            dispatch_started
        } {
            assert_equal 1 [dict get $dispatch $field] \
                "Synthesis dispatch evidence: $field"
        }
        assert_equal 100% [dict get $result evidence_references \
            run_readback progress] {Synthesis terminal progress}
        assert_no_forbidden
    }

    run_case SYNTHESIS_DISPATCH_STALLED_REJECT {
        reset_mock
        set dispatch_behavior STALL
        set context [with_dispatch_timeout \
            [valid_context dispatch_stalled] 2]
        set result [::stage1e::synthesis::run $context]
        assert_status $result FAIL {Dispatch stall status}
        assert_equal SYNTHESIS_DISPATCH_STALLED [first_error_code $result] \
            {Dispatch stall error code}
        assert_equal 2 $after_count {Dispatch stall poll count}
        assert_true [expr {![command_seen wait_on_run]}] \
            {Stalled dispatch entered completion wait}
        assert_equal 0 [dict get $result synthesis_performed] \
            {Stalled dispatch reported synthesis execution}
        set dispatch [dict get $result evidence_references dispatch]
        assert_equal STALLED [dict get $dispatch state] \
            {Dispatch stall evidence state}
        foreach field {
            child_process_observed begin_marker_observed
            run_log_observed progress_observed dispatch_started
        } {
            assert_equal 0 [dict get $dispatch $field] \
                "Stalled dispatch evidence: $field"
        }
        assert_no_forbidden
    }

    run_case SYNTHESIS_DISPATCH_BEGIN_MARKER_MISSING_REJECT {
        reset_mock
        set dispatch_behavior NO_BEGIN
        set context [with_dispatch_timeout \
            [valid_context dispatch_no_begin] 2]
        set result [::stage1e::synthesis::run $context]
        assert_status $result FAIL {Missing begin marker status}
        assert_equal SYNTHESIS_DISPATCH_EVIDENCE_INVALID \
            [first_error_code $result] {Missing begin marker error code}
        assert_true [expr {![command_seen wait_on_run]}] \
            {Missing begin marker entered completion wait}
        assert_no_forbidden
    }

    run_case SYNTHESIS_DISPATCH_RUN_LOG_MISSING_REJECT {
        reset_mock
        set dispatch_behavior NO_LOG
        set context [with_dispatch_timeout \
            [valid_context dispatch_no_log] 2]
        set result [::stage1e::synthesis::run $context]
        assert_status $result FAIL {Missing dispatch run log status}
        assert_equal SYNTHESIS_DISPATCH_EVIDENCE_INVALID \
            [first_error_code $result] {Missing dispatch run log error code}
        assert_no_forbidden
    }

    run_case SYNTHESIS_DISPATCH_PROGRESS_MISSING_REJECT {
        reset_mock
        set dispatch_behavior NO_PROGRESS
        set context [with_dispatch_timeout \
            [valid_context dispatch_no_progress] 2]
        set result [::stage1e::synthesis::run $context]
        assert_status $result FAIL {Missing dispatch progress status}
        assert_equal SYNTHESIS_DISPATCH_EVIDENCE_INVALID \
            [first_error_code $result] {Missing dispatch progress error code}
        assert_no_forbidden
    }

    run_case SYNTHESIS_BOUNDED_WAIT_TIMEOUT_REJECT {
        reset_mock
        set wait_behavior TIMEOUT
        set result [::stage1e::synthesis::run \
            [valid_context bounded_wait_timeout]]
        assert_status $result FAIL {Bounded synthesis wait timeout status}
        assert_equal SYNTHESIS_RUN_TIMEOUT [first_error_code $result] \
            {Bounded synthesis wait timeout code}
        assert_true [command_seen wait_on_run] \
            {Bounded synthesis wait was not invoked}
        assert_equal 1 [dict get $result synthesis_performed] \
            {Started synthesis was not reported}
        assert_no_forbidden
    }

    run_case SYNTHESIS_VIVADO_2024_1_MESSAGE_COLLECTION {
        reset_mock
        set context [valid_context vivado_2024_1_messages]
        set result [::stage1e::synthesis::run $context]
        assert_status $result PASS {Vivado 2024.1 message collection status}
        set invocation [first_invocation write_messages]
        set policy [dict get $result consumed_identities synthesis_policy]
        assert_equal [dict get $policy message_database_path] \
            [lindex $invocation [expr {
                [lsearch -exact $invocation {-message_db}] + 1}]] \
            {write_messages database binding}
        assert_equal [dict get $policy report_paths message_report] \
            [lindex $invocation [expr {
                [lsearch -exact $invocation {-file}] + 1}]] \
            {write_messages report binding}
        assert_true [expr {[lsearch -exact $invocation {-verbose}] >= 0}] \
            {write_messages did not suspend message limits}
        assert_true [expr {![command_seen get_messages] &&
            ![command_seen report_messages]}] \
            {Unsupported message API reached backend}
        assert_no_forbidden
    }

    run_case SYNTHESIS_VIVADO_2024_1_REPORT_COLLECTION {
        reset_mock
        set context [valid_context vivado_2024_1_reports]
        set result [::stage1e::synthesis::run $context]
        assert_status $result PASS {Vivado 2024.1 report collection status}
        set invocation [first_invocation report_design_analysis]
        assert_equal 3 [llength $invocation] \
            {report_design_analysis argument count}
        assert_true [expr {[lsearch -exact $invocation {-force}] < 0}] \
            {report_design_analysis used unsupported -force}
        assert_equal [dict get $context synthesis_policy report_paths \
            synthesis_report] [lindex $invocation 2] \
            {report_design_analysis evidence path binding}
        assert_true [expr {[command_index report_design_analysis] >
            [command_index open_run]}] \
            {Synthesis report was generated before native run success readback}
        foreach role {synthesis_report utilization_report message_report} {
            assert_true [dict exists $result evidence_references reports $role] \
                "Missing controlled synthesis evidence: $role"
        }
        assert_no_forbidden
    }

    run_case SYNTHESIS_REPORT_MISSING_REJECT {
        reset_mock
        set synthesis_report_missing 1
        set result [::stage1e::synthesis::run \
            [valid_context synthesis_report_missing]]
        assert_status $result FAIL {Missing synthesis report status}
        assert_equal SYNTHESIS_EVIDENCE_FILE_INVALID \
            [first_error_code $result] {Missing synthesis report code}
        assert_equal 1 [dict get $result synthesis_performed] \
            {Missing report discarded native synthesis success evidence}
        assert_true [dict exists $result evidence_references message_inventory] \
            {Missing report discarded message inventory evidence}
        assert_true [expr {![dict exists $result produced_identities \
            synthesis_result_identity]}] \
            {Missing report produced a synthesis result identity}
        assert_no_forbidden
    }

    run_case SYNTHESIS_UTILIZATION_REPORT_MISSING_REJECT {
        reset_mock
        set utilization_report_missing 1
        set result [::stage1e::synthesis::run \
            [valid_context utilization_report_missing]]
        assert_status $result FAIL {Missing utilization report status}
        assert_equal SYNTHESIS_EVIDENCE_FILE_INVALID \
            [first_error_code $result] {Missing utilization report code}
        assert_equal 1 [dict get $result synthesis_performed] \
            {Missing utilization report discarded native synthesis evidence}
        assert_no_forbidden
    }

    run_case SYNTHESIS_MESSAGE_API_UNAVAILABLE_REJECT {
        reset_mock
        set message_api_available 0
        set result [::stage1e::synthesis::run \
            [valid_context message_api_unavailable]]
        assert_status $result BLOCKED {Unavailable message API status}
        assert_equal SYNTHESIS_MESSAGE_API_UNAVAILABLE \
            [first_error_code $result] {Unavailable message API code}
        assert_true [expr {![command_seen launch_runs]}] \
            {Synthesis launched without message API}
        assert_equal 0 [dict get $result synthesis_performed] \
            {Unavailable message API reported synthesis}
        assert_no_forbidden
    }

    run_case SYNTHESIS_MESSAGE_DATABASE_MISSING_REJECT {
        reset_mock
        set message_database_missing 1
        set result [::stage1e::synthesis::run \
            [valid_context message_database_missing]]
        assert_status $result FAIL {Missing message database status}
        assert_equal SYNTHESIS_MESSAGE_DATABASE_UNAVAILABLE \
            [first_error_code $result] {Missing message database code}
        assert_true [command_seen launch_runs] \
            {Missing message database test did not reach synthesis}
        assert_true [expr {![command_seen write_messages]}] \
            {Message export ran without database evidence}
        assert_no_forbidden
    }

    run_case SYNTHESIS_MESSAGE_EVIDENCE_MISSING_REJECT {
        reset_mock
        set message_report_missing 1
        set result [::stage1e::synthesis::run \
            [valid_context message_evidence_missing]]
        assert_status $result FAIL {Missing message evidence status}
        assert_equal SYNTHESIS_MESSAGE_EVIDENCE_MISSING \
            [first_error_code $result] {Missing message evidence code}
        assert_true [command_seen write_messages] \
            {Missing message report did not invoke supported API}
        assert_no_forbidden
    }

    run_case SYNTHESIS_MESSAGE_EVIDENCE_MALFORMED_REJECT {
        reset_mock
        set message_report_text [join [list \
            {####################################################################################} \
            {# Generated by Vivado 2024.1 built on 'mock' by 'test'} \
            {# Command Used: write_messages -message_db mock/vivado.pb -file mock/messages.rpt} \
            {####################################################################################} \
            {WARNING: malformed message evidence}] "\n"]
        set result [::stage1e::synthesis::run \
            [valid_context message_evidence_malformed]]
        assert_status $result FAIL {Malformed message evidence status}
        assert_equal SYNTHESIS_MESSAGE_EVIDENCE_MALFORMED \
            [first_error_code $result] {Malformed message evidence code}
        assert_no_forbidden
    }

    run_case SYNTHESIS_MESSAGE_API_FAILURE_REJECT {
        reset_mock
        set message_write_error 1
        set result [::stage1e::synthesis::run \
            [valid_context message_api_failure]]
        assert_status $result FAIL {Message API failure status}
        assert_equal SYNTHESIS_MESSAGE_COLLECTION_FAILED \
            [first_error_code $result] {Message API failure code}
        assert_true [command_seen write_messages] \
            {Message API failure path was not exercised}
        assert_no_forbidden
    }

    run_case SYNTHESIS_EVIDENCE_DIRECTORY_MISSING_REJECT {
        reset_mock
        set context [valid_context evidence_directory_missing]
        file delete -force -- [file join \
            [dict get $context workspace_identity evidence_dir] synthesis]
        set result [::stage1e::synthesis::run $context]
        assert_status $result FAIL {Missing evidence directory status}
        assert_equal SYNTHESIS_EVIDENCE_DIRECTORY_INVALID \
            [first_error_code $result] {Missing evidence directory code}
        assert_equal {} $invocation_log \
            {Missing evidence directory reached backend}
    }

    run_case SYNTHESIS_REPORT_SIBLING_REJECT {
        reset_mock
        set context [valid_context report_sibling]
        set sibling [file normalize [file join \
            [dict get $context workspace_identity workspace_root] \
            reports synthesis]]
        file mkdir $sibling
        dict set context synthesis_policy report_paths synthesis_report \
            [file join $sibling synthesis.rpt]
        set result [::stage1e::synthesis::run $context]
        assert_status $result FAIL {Sibling report path status}
        assert_equal SYNTHESIS_REPORT_PATH_INVALID [first_error_code $result] \
            {Sibling report path code}
        assert_equal {} $invocation_log {Sibling report path reached backend}
    }

    run_case SYNTHESIS_REPORT_EXTERNAL_REJECT {
        reset_mock
        set context [valid_context report_external]
        set external [file normalize [file join \
            $::stage1e::synthesis_adapter_tests::test_root external_reports]]
        file mkdir $external
        dict set context synthesis_policy report_paths synthesis_report \
            [file join $external synthesis.rpt]
        set result [::stage1e::synthesis::run $context]
        assert_status $result FAIL {External report path status}
        assert_equal SYNTHESIS_REPORT_PATH_INVALID [first_error_code $result] \
            {External report path code}
        assert_equal {} $invocation_log {External report path reached backend}
    }

    run_case SYNTHESIS_REPORT_TRAVERSAL_REJECT {
        reset_mock
        set context [valid_context report_traversal]
        set evidence [dict get $context workspace_identity evidence_dir]
        set traversal [file join $evidence synthesis .. escaped \
            synthesis.rpt]
        file mkdir [file dirname [file normalize $traversal]]
        dict set context synthesis_policy report_paths synthesis_report \
            $traversal
        set result [::stage1e::synthesis::run $context]
        assert_status $result FAIL {Traversal report path status}
        assert_equal SYNTHESIS_REPORT_PATH_INVALID [first_error_code $result] \
            {Traversal report path code}
        assert_equal {} $invocation_log {Traversal report path reached backend}
    }

    run_case SYNTHESIS_LOG_SIBLING_REJECT {
        reset_mock
        set context [valid_context log_sibling]
        set sibling [file normalize [file join \
            [dict get $context workspace_identity workspace_root] logs]]
        file mkdir $sibling
        dict set context synthesis_policy run_log_path \
            [file join $sibling runme.log]
        set result [::stage1e::synthesis::run $context]
        assert_status $result FAIL {Sibling synthesis log status}
        assert_equal SYNTHESIS_LOG_PATH_INVALID [first_error_code $result] \
            {Sibling synthesis log code}
        assert_equal {} $invocation_log {Sibling log path reached backend}
    }

    run_case SYNTHESIS_LOG_EXTERNAL_REJECT {
        reset_mock
        set context [valid_context log_external]
        set external [file normalize [file join \
            $::stage1e::synthesis_adapter_tests::test_root external_logs]]
        file mkdir $external
        dict set context synthesis_policy run_log_path \
            [file join $external runme.log]
        set result [::stage1e::synthesis::run $context]
        assert_status $result FAIL {External synthesis log status}
        assert_equal SYNTHESIS_LOG_PATH_INVALID [first_error_code $result] \
            {External synthesis log code}
        assert_equal {} $invocation_log {External log path reached backend}
    }

    run_case SYNTHESIS_LOG_TRAVERSAL_REJECT {
        reset_mock
        set context [valid_context log_traversal]
        set evidence [dict get $context workspace_identity evidence_dir]
        dict set context synthesis_policy run_log_path \
            [file join $evidence synthesis .. runme.log]
        set result [::stage1e::synthesis::run $context]
        assert_status $result FAIL {Traversal synthesis log status}
        assert_equal SYNTHESIS_LOG_PATH_INVALID [first_error_code $result] \
            {Traversal synthesis log code}
        assert_equal {} $invocation_log {Traversal log path reached backend}
    }

    run_case SYNTHESIS_WORKSPACE_V2_ACCEPT {
        reset_mock
        set result [::stage1e::synthesis::run \
            [valid_context workspace_v2_accept]]
        assert_status $result PASS {Workspace v2 acceptance status}
        assert_equal stage1e-workspace-identity-v2 \
            [dict get $result consumed_identities workspace_identity \
                schema_version] {Accepted workspace schema}
        assert_equal 15 \
            [dict get $result consumed_identities workspace_identity \
                retry_number] {Accepted workspace retry number}
        assert_no_forbidden
    }

    run_case SYNTHESIS_WORKSPACE_MISSING_IDENTITY_REJECT {
        reset_mock
        set context [valid_context workspace_missing_identity]
        dict set context workspace_identity {}
        set result [::stage1e::synthesis::run $context]
        assert_status $result FAIL {Missing workspace identity status}
        assert_equal WORKSPACE_IDENTITY_MISSING [first_error_code $result] \
            {Missing workspace identity code}
        assert_equal {} $invocation_log \
            {Missing workspace identity reached backend}
    }

    run_case SYNTHESIS_WORKSPACE_MISSING_FIELD_REJECT {
        reset_mock
        set context [valid_context workspace_missing_field]
        dict unset context workspace_identity retry_number
        set result [::stage1e::synthesis::run $context]
        assert_status $result FAIL {Missing workspace field status}
        assert_equal CONTEXT_FIELD_MISSING [first_error_code $result] \
            {Missing workspace field code}
        assert_equal {} $invocation_log \
            {Missing workspace field reached backend}
    }

    run_case SYNTHESIS_WORKSPACE_MALFORMED_REJECT {
        reset_mock
        set context [valid_context workspace_malformed]
        dict set context workspace_identity malformed
        set result [::stage1e::synthesis::run $context]
        assert_status $result FAIL {Malformed workspace identity status}
        assert_equal CONTEXT_FIELD_INVALID [first_error_code $result] \
            {Malformed workspace identity code}
        assert_equal {} $invocation_log \
            {Malformed workspace identity reached backend}
    }

    run_case SYNTHESIS_WORKSPACE_WRONG_OWNERSHIP_REJECT {
        reset_mock
        set context [valid_context workspace_wrong_ownership]
        set path [ownership_path $context]
        set ownership [read_dictionary $path]
        dict set ownership execution_id STAGE1E-OTHER-EXECUTION
        write_file $path $ownership
        set result [::stage1e::synthesis::run $context]
        assert_status $result FAIL {Wrong workspace ownership status}
        assert_equal WORKSPACE_OWNERSHIP_MISMATCH \
            [first_error_code $result] {Wrong workspace ownership code}
        assert_equal {} $invocation_log \
            {Wrong workspace ownership reached backend}
    }

    run_case SYNTHESIS_WORKSPACE_STALE_SCHEMA_REJECT {
        reset_mock
        set context [valid_context workspace_stale_schema]
        dict set context workspace_identity schema_version \
            stage1e-workspace-identity-v1
        set result [::stage1e::synthesis::run $context]
        assert_status $result FAIL {Stale workspace schema status}
        assert_equal WORKSPACE_IDENTITY_SCHEMA_UNSUPPORTED \
            [first_error_code $result] {Stale workspace schema code}
        assert_equal {} $invocation_log \
            {Stale workspace schema reached backend}
    }

    run_case SYNTHESIS_WORKSPACE_HASH_REJECT {
        reset_mock
        set context [valid_context workspace_hash_reject]
        dict set context workspace_identity identity_sha256 \
            [string repeat 0 64]
        set result [::stage1e::synthesis::run $context]
        assert_status $result FAIL {Workspace hash rejection status}
        assert_equal WORKSPACE_IDENTITY_HASH_MISMATCH \
            [first_error_code $result] {Workspace hash rejection code}
        assert_equal {} $invocation_log \
            {Invalid workspace hash reached backend}
    }

    run_case SYNTHESIS_WORKSPACE_PATH_IDENTITY_REJECT {
        reset_mock
        set context [valid_context workspace_path_identity_reject]
        set other [file normalize [file join \
            $::stage1e::synthesis_adapter_tests::test_root other_workspace]]
        dict set context workspace_identity workspace_path $other
        set identity [dict get $context workspace_identity]
        dict unset identity identity_sha256
        dict set context workspace_identity identity_sha256 \
            [::stage1d::source_check::sha256_text $identity]
        set result [::stage1e::synthesis::run $context]
        assert_status $result FAIL {Workspace path identity status}
        assert_equal WORKSPACE_PATH_IDENTITY_MISMATCH \
            [first_error_code $result] {Workspace path identity code}
        assert_equal {} $invocation_log \
            {Mismatched workspace path reached backend}
    }

    run_case SYNTHESIS_AUTH_REJECT {
        reset_mock
        set context [valid_context auth_reject]
        dict set context authorization capability_enabled 0
        set result [::stage1e::synthesis::run $context]
        assert_status $result BLOCKED {Authorization rejection status}
        assert_equal AUTHORIZATION_MISMATCH [first_error_code $result] \
            {Authorization rejection code}
        assert_equal {} $invocation_log {Authorization reached backend}
    }

    run_case SYNTHESIS_BUILD_TARGET_REJECT {
        reset_mock
        set context [valid_context target_reject]
        dict set context build_target_identity acceptance_state CANDIDATE
        set result [::stage1e::synthesis::run $context]
        assert_status $result BLOCKED {Build-target rejection status}
        assert_equal BUILD_TARGET_NOT_ACCEPTED [first_error_code $result] \
            {Build-target rejection code}
        assert_equal {} $invocation_log {Rejected target reached backend}
    }

    run_case SYNTHESIS_OWNERSHIP_REJECT {
        reset_mock
        set context [valid_context ownership_reject]
        dict set context project_ownership owner unexpected_owner
        set result [::stage1e::synthesis::run $context]
        assert_status $result FAIL {Ownership rejection status}
        assert_equal PROJECT_OWNER_INVALID [first_error_code $result] \
            {Ownership rejection code}
        assert_equal {} $invocation_log {Rejected ownership reached backend}
    }

    run_case SYNTHESIS_POLICY_REJECT {
        reset_mock
        set context [valid_context policy_reject]
        dict set context synthesis_policy job_policy jobs 0
        set result [::stage1e::synthesis::run $context]
        assert_status $result FAIL {Policy rejection status}
        assert_equal SYNTHESIS_JOB_POLICY_INVALID [first_error_code $result] \
            {Policy rejection code}
        assert_equal {} $invocation_log {Rejected policy reached backend}
    }

    run_case SYNTHESIS_LAUNCHER_LIFETIME_REJECT {
        reset_mock
        set context [valid_context launcher_lifetime_reject]
        dict set context synthesis_policy job_policy \
            launcher_timeout_minutes 119
        set result [::stage1e::synthesis::run $context]
        assert_status $result FAIL {Launcher lifetime rejection status}
        assert_equal SYNTHESIS_LAUNCHER_LIFETIME_INVALID \
            [first_error_code $result] {Launcher lifetime rejection code}
        assert_equal {} $invocation_log \
            {Rejected launcher lifetime reached backend}
    }

    run_case SYNTHESIS_WORKSPACE_REJECT {
        reset_mock
        set context [valid_context workspace_reject]
        set outside [file normalize [file join $::stage1e::synthesis_adapter_tests::test_root outside]]
        dict set context workspace_identity synthesis_output_dir $outside
        set identity [dict get $context workspace_identity]
        dict unset identity identity_sha256
        dict set context workspace_identity identity_sha256 \
            [::stage1d::source_check::sha256_text $identity]
        set result [::stage1e::synthesis::run $context]
        assert_status $result FAIL {Workspace rejection status}
        assert_equal WORKSPACE_CONTAINMENT_VIOLATION [first_error_code $result] \
            {Workspace rejection code}
        assert_equal {} $invocation_log {Rejected workspace reached backend}
    }

    run_case SYNTHESIS_RESULT_SCHEMA {
        reset_mock
        set result [::stage1e::synthesis::run \
            [valid_context result_schema]]
        assert_status $result PASS {Result-schema status}
        foreach key {
            schema_version operation phase execution_id status
            consumed_identities produced_identities ownership_records
            evidence_references warnings errors cleanup_result
            continuation_recommendation
        } {
            assert_true [dict exists $result $key] \
                "Result schema missing: $key"
        }
        assert_equal stage1e-synthesis-result-v1 \
            [dict get $result schema_version] {Result schema version}
        set identity [dict get $result synthesis_result_identity]
        foreach field {
            source_identity_sha256 configuration_identity_sha256
            environment_identity_sha256 workspace_identity_sha256
            build_target_identity_sha256 synthesis_policy_sha256
            run_identity_sha256 evidence_sha256 warnings_sha256 identity_sha256
        } {
            assert_true [regexp {^[0-9a-f]{64}$} [dict get $identity $field]] \
                "Synthesis identity digest invalid: $field"
        }
    }

    run_case SYNTHESIS_UNKNOWN_WARNING_REJECT {
        reset_mock
        set message_report_text [valid_message_report [list \
            {WARNING: [Vivado 99-1] Unknown synthesis warning}]]
        set result [::stage1e::synthesis::run \
            [valid_context unknown_warning]]
        assert_status $result FAIL {Unknown-warning status}
        assert_equal SYNTHESIS_WARNING_UNRESOLVED [first_error_code $result] \
            {Unknown-warning code}
        assert_equal UNKNOWN \
            [dict get [lindex [dict get $result warnings] 0] classification] \
            {Unknown-warning classification}
        assert_no_forbidden
    }

    run_case SYNTHESIS_ACCEPTED_WARNING_INVENTORY {
        reset_mock
        set context [valid_context accepted_warning]
        dict set context synthesis_policy warning_policy dispositions \
            {Synth 8-7071} [dict create \
                classification ACCEPTED \
                severity WARNING \
                min_count 1 \
                max_count 1 \
                rationale {Reviewed synthesis warning for this identity.}]
        set message_report_text [valid_message_report [list \
            {WARNING: [Synth 8-7071] Reviewed mock synthesis warning}]]
        set result [::stage1e::synthesis::run $context]
        assert_status $result PASS {Accepted-warning status}
        assert_equal 1 [llength [dict get $result warnings]] \
            {Accepted-warning inventory count}
        set warning [lindex [dict get $result warnings] 0]
        assert_equal ACCEPTED [dict get $warning classification] \
            {Accepted-warning classification}
        assert_equal 1 [dict get $warning disposition_match] \
            {Accepted-warning disposition match}
        assert_equal [dict get $result warnings] \
            [dict get $result evidence_references warning_inventory] \
            {Accepted-warning evidence inventory}
        assert_no_forbidden
    }

    run_case SYNTHESIS_RETRY19_WARNING_POLICY_ACCEPT {
        reset_mock
        set context [valid_context retry19_warning_policy]
        dict set context synthesis_policy warning_policy \
            [reviewed_warning_policy]
        set expected_counts [dict create \
            {Synth 8-7071} 8 \
            {Synth 8-7023} 3 \
            {Synth 8-4446} 1 \
            {Synth 8-7129} 48 \
            {Synth 8-7080} 1]
        set message_lines {}
        dict for {identifier count} $expected_counts {
            for {set index 0} {$index < $count} {incr index} {
                lappend message_lines [format \
                    {WARNING: [%s] Reviewed Retry #19 warning occurrence %d} \
                    $identifier [expr {$index + 1}]]
            }
        }
        set message_report_text [valid_message_report $message_lines]
        set result [::stage1e::synthesis::run $context]
        assert_status $result PASS {Reviewed Retry #19 warning-set status}
        assert_true [dict exists $result produced_identities \
            synthesis_result_identity] \
            {Reviewed warning set did not produce a synthesis identity}
        assert_equal 5 [llength [dict get $result warnings]] \
            {Reviewed warning class count}
        foreach warning [dict get $result warnings] {
            set identifier [dict get $warning identifier]
            assert_true [dict exists $expected_counts $identifier] \
                "Unexpected reviewed warning: $identifier"
            assert_equal [dict get $expected_counts $identifier] \
                [dict get $warning count] \
                "Reviewed warning count: $identifier"
            assert_equal ACCEPTED [dict get $warning classification] \
                "Reviewed warning classification: $identifier"
            assert_equal 1 [dict get $warning disposition_match] \
                "Reviewed warning disposition match: $identifier"
        }
        assert_no_forbidden
    }

    run_case SYNTHESIS_REVIEWED_WARNING_COUNT_OVERFLOW_REJECT {
        reset_mock
        set context [valid_context warning_count_overflow]
        dict set context synthesis_policy warning_policy \
            [reviewed_warning_policy]
        set message_lines {}
        for {set index 0} {$index < 9} {incr index} {
            lappend message_lines [format \
                {WARNING: [Synth 8-7071] Overflow warning occurrence %d} \
                [expr {$index + 1}]]
        }
        set message_report_text [valid_message_report $message_lines]
        set result [::stage1e::synthesis::run $context]
        assert_status $result FAIL {Reviewed warning overflow status}
        assert_equal SYNTHESIS_WARNING_UNRESOLVED \
            [first_error_code $result] {Reviewed warning overflow code}
        set warning [lindex [dict get $result warnings] 0]
        assert_equal 9 [dict get $warning count] \
            {Reviewed warning overflow count}
        assert_equal UNKNOWN [dict get $warning classification] \
            {Reviewed warning overflow classification}
        assert_equal 0 [dict get $warning disposition_match] \
            {Reviewed warning overflow disposition match}
        assert_true [expr {![dict exists $result produced_identities \
            synthesis_result_identity]}] \
            {Reviewed warning overflow produced a synthesis identity}
        assert_no_forbidden
    }

    run_case SYNTHESIS_ERROR_MESSAGE_REJECT {
        reset_mock
        set message_report_text [valid_message_report [list \
            {ERROR: [Synth 8-9999] Mock synthesis error}]]
        set result [::stage1e::synthesis::run \
            [valid_context error_message]]
        assert_status $result FAIL {Synthesis-error message status}
        set codes [error_codes $result]
        assert_true [expr {{VIVADO_MESSAGE_ERROR} in $codes}] \
            {Synthesis error was absent from error inventory}
        assert_true [expr {{SYNTHESIS_ERRORS_OBSERVED} in $codes}] \
            {Synthesis error inventory did not block acceptance}
        set first_record [lindex [dict get $result evidence_references \
            message_inventory records] 0]
        assert_equal ERROR [dict get $first_record severity] \
            {Synthesis error message severity}
        assert_no_forbidden
    }

    run_case SYNTHESIS_NO_IMPLEMENTATION {
        reset_mock
        set result [::stage1e::synthesis::run \
            [valid_context no_implementation]]
        assert_status $result PASS {No-implementation status}
        assert_equal 0 [dict get $result implementation_performed] \
            {Implementation was reported}
        assert_equal 0 [dict get $result bitstream_generated] \
            {Bitstream was reported}
        assert_no_forbidden
    }

    run_case SYNTHESIS_NO_ARTIFACT {
        reset_mock
        set result [::stage1e::synthesis::run \
            [valid_context no_artifact]]
        assert_status $result PASS {No-artifact status}
        foreach field {
            xsa_exported artifacts_collected artifacts_generated
            artifact_generation_performed artifact_publication_performed
            board_access_performed
        } {
            assert_equal 0 [dict get $result $field] \
                "Artifact boundary field $field"
        }
        assert_no_forbidden
    }
}

set test_status [catch {
    ::stage1e::synthesis_adapter_tests::prepare_suite
    ::stage1e::synthesis_adapter_tests::run_all
} test_error test_options]
set cleanup_status [catch {
    ::stage1e::synthesis_adapter_tests::safe_cleanup
} cleanup_error cleanup_options]
rename ::stage1e::synthesis::backend::invoke {}
rename ::stage1e::synthesis::backend::_production_invoke \
    ::stage1e::synthesis::backend::invoke

if {$test_status != 0} {
    incr ::stage1e::synthesis_adapter_tests::fail_count
    puts stderr "TEST SUITE: FAIL: $test_error"
    if {[dict exists $test_options -errorinfo]} {
        puts stderr [dict get $test_options -errorinfo]
    }
}
if {$cleanup_status != 0} {
    incr ::stage1e::synthesis_adapter_tests::fail_count
    puts stderr "TEST CLEANUP: FAIL: $cleanup_error"
    if {[dict exists $cleanup_options -errorinfo]} {
        puts stderr [dict get $cleanup_options -errorinfo]
    }
}

puts "SUMMARY PASS=$::stage1e::synthesis_adapter_tests::pass_count FAIL=$::stage1e::synthesis_adapter_tests::fail_count"
