# Source-only tests for the Stage 1E block-design creation extension.
#
# The create operation's backend is replaced with an isolated Tcl mock. The
# suite launches no Vivado executable, creates no real BD or topology, invokes
# no validate/save operation, and generates no FPGA artifact.

namespace eval ::stage1e::bd_creation_adapter_tests {
    variable pass_count 0
    variable fail_count 0
    variable test_root {}
    variable invocation_log {}
    variable current_project_handle {}
    variable current_bd {}
    variable empty_bd_session_behavior RETURN_EMPTY
    variable properties [dict create]
    variable bd_files {}
    variable loaded_bds {}
    variable forced_bd_path {}
    variable topology_objects [dict create]
    variable forbidden_count 0
}

set stage1e_bd_test_dir [file normalize [file dirname [info script]]]
set stage1e_bd_build_root [file normalize [file join $stage1e_bd_test_dir ..]]
set stage1e_bd_flow_library [file join \
    $stage1e_bd_build_root lib bd_flow.tcl]

# Sourcing must be definition-only. Any source-time Vivado command would fail
# before the backend mock is installed.
source $stage1e_bd_flow_library

rename ::stage1d::bd_flow::create_backend::invoke \
    ::stage1d::bd_flow::create_backend::_production_invoke
proc ::stage1d::bd_flow::create_backend::invoke {command arguments} {
    return [::stage1e::bd_creation_adapter_tests::mock_invoke \
        $command $arguments]
}

proc ::stage1e::bd_creation_adapter_tests::fail {message} {
    error "TEST FAILURE: $message"
}

proc ::stage1e::bd_creation_adapter_tests::assert_true {
    condition
    message
} {
    if {!$condition} {
        fail $message
    }
}

proc ::stage1e::bd_creation_adapter_tests::assert_equal {
    expected
    actual
    message
} {
    if {$expected ne $actual} {
        fail "$message: expected=<$expected> actual=<$actual>"
    }
}

proc ::stage1e::bd_creation_adapter_tests::assert_status {
    result
    expected
    message
} {
    if {[catch {dict size $result} dictionary_error]} {
        fail "$message is not a dictionary: $dictionary_error"
    }
    if {[dict get $result status] ne $expected} {
        fail "$message: expected=<$expected> actual=<[dict get $result status]> errors=<[dict get $result errors]>"
    }
}

proc ::stage1e::bd_creation_adapter_tests::first_error_code {result} {
    set errors [dict get $result errors]
    if {[llength $errors] == 0} {
        fail {Expected a structured error record.}
    }
    return [dict get [lindex $errors 0] code]
}

proc ::stage1e::bd_creation_adapter_tests::run_case {name body} {
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

proc ::stage1e::bd_creation_adapter_tests::temporary_base {} {
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
    error {No external temporary directory is available for BD tests.}
}

proc ::stage1e::bd_creation_adapter_tests::write_text {path text} {
    file mkdir [file dirname $path]
    set channel [open $path w]
    fconfigure $channel -encoding utf-8 -translation lf
    set write_status [catch {
        puts -nonewline $channel $text
    } write_error write_options]
    set close_status [catch {close $channel} close_error]
    if {$write_status != 0} {
        return -options $write_options $write_error
    }
    if {$close_status != 0} {
        error "Unable to close test file: $close_error"
    }
}

proc ::stage1e::bd_creation_adapter_tests::prepare_suite {} {
    variable test_root
    set test_root [file normalize [file join [temporary_base] \
        "stage1e_bd_create_tests_[pid]_[clock clicks]"]]
    if {![string match {stage1e_bd_create_tests_*} [file tail $test_root]]} {
        error "Unsafe BD test root: $test_root"
    }
    file mkdir $test_root
}

proc ::stage1e::bd_creation_adapter_tests::safe_cleanup {} {
    variable test_root
    if {$test_root eq {} || ![file exists $test_root]} {
        return
    }
    if {![string match {stage1e_bd_create_tests_*} [file tail $test_root]]} {
        error "Refusing unsafe BD test cleanup: $test_root"
    }
    file delete -force $test_root
}

proc ::stage1e::bd_creation_adapter_tests::reset_mock {} {
    variable invocation_log
    variable current_project_handle
    variable current_bd
    variable empty_bd_session_behavior
    variable properties
    variable bd_files
    variable loaded_bds
    variable forced_bd_path
    variable topology_objects
    variable forbidden_count
    set invocation_log {}
    set current_project_handle {}
    set current_bd {}
    set empty_bd_session_behavior RETURN_EMPTY
    set properties [dict create]
    set bd_files {}
    set loaded_bds {}
    set forced_bd_path {}
    set topology_objects [dict create \
        get_bd_cells {} \
        get_bd_ports {} \
        get_bd_intf_ports {} \
        get_bd_nets {} \
        get_bd_intf_nets {}]
    set forbidden_count 0
}

proc ::stage1e::bd_creation_adapter_tests::mock_invoke {
    command
    arguments
} {
    variable invocation_log
    variable current_project_handle
    variable current_bd
    variable empty_bd_session_behavior
    variable properties
    variable bd_files
    variable loaded_bds
    variable forced_bd_path
    variable topology_objects
    variable forbidden_count
    lappend invocation_log [linsert $arguments 0 $command]

    if {$command in {
        create_bd_cell
        create_bd_port
        create_bd_intf_port
        connect_bd_net
        connect_bd_intf_net
        assign_bd_address
        apply_bd_automation
        validate_bd_design
        save_bd_design
        generate_target
        make_wrapper
        launch_runs
        synth_design
        opt_design
        place_design
        route_design
        write_bitstream
        write_hw_platform
        write_debug_probes
        export_hardware
    }} {
        incr forbidden_count
        error "Forbidden mock command invoked: $command"
    }

    switch -- $command {
        current_project {
            return $current_project_handle
        }
        current_bd_design {
            if {$current_bd ne {}} {
                return $current_bd
            }
            switch -- $empty_bd_session_behavior {
                RETURN_EMPTY {
                    return {}
                }
                RAISE_BD_5_104 {
                    return -code error -errorcode {NONE} -errorinfo \
                        {ERROR: [BD 5-104] A block design must be open to run this command. Please create/open a block design.
ERROR: [Common 17-39] 'current_bd_design' failed due to earlier errors.} \
                        {ERROR: [Common 17-39] 'current_bd_design' failed due to earlier errors.}
                }
                RAISE_UNEXPECTED {
                    error \
                        {ERROR: [Common 17-69] Unexpected BD query failure.}
                }
                default {
                    error "Unsupported empty-BD behavior: $empty_bd_session_behavior"
                }
            }
        }
        get_property {
            lassign $arguments property object
            return [dict get $properties $object [string toupper $property]]
        }
        get_files {
            return $bd_files
        }
        get_bd_designs {
            return $loaded_bds
        }
        create_bd_design {
            set bd_name [lindex $arguments 0]
            set project_name [dict get \
                $properties $current_project_handle NAME]
            set project_directory [dict get \
                $properties $current_project_handle DIRECTORY]
            if {$forced_bd_path eq {}} {
                set bd_path [file normalize [file join \
                    $project_directory "${project_name}.srcs" \
                    sources_1 bd $bd_name "${bd_name}.bd"]]
            } else {
                set bd_path [file normalize $forced_bd_path]
            }
            set bd_object "bdfile::$bd_name"
            set bd_files [list $bd_object]
            set loaded_bds [list "bddesign::$bd_name"]
            set current_bd $bd_name
            dict set properties $bd_object NAME $bd_path
            return $current_bd
        }
        get_bd_cells -
        get_bd_ports -
        get_bd_intf_ports -
        get_bd_nets -
        get_bd_intf_nets {
            return [dict get $topology_objects $command]
        }
        default {
            error "Unexpected mock Vivado command: $command"
        }
    }
}

proc ::stage1e::bd_creation_adapter_tests::valid_context {name} {
    variable test_root
    variable current_project_handle
    variable properties
    set execution_id "STAGE1E-BD-CREATE-$name"
    set workspace_root [file normalize [file join $test_root executions $name]]
    set evidence_dir [file join $workspace_root evidence]
    set project_name stage1e_design
    set project_directory [file join $workspace_root project]
    set project_path [file join $project_directory "${project_name}.xpr"]
    set bd_name protection_system
    set expected_bd_path [file normalize [file join \
        $project_directory "${project_name}.srcs" \
        sources_1 bd $bd_name "${bd_name}.bd"]]
    file mkdir $evidence_dir
    write_text $project_path {mock owned project}

    set current_project_handle "project::$project_name"
    dict set properties $current_project_handle NAME $project_name
    dict set properties $current_project_handle DIRECTORY \
        [file normalize $project_directory]
    dict set properties $current_project_handle PART xc7z020clg400-1
    dict set properties $current_project_handle BOARD_PART \
        tul.com.tw:pynq-z2:part0:1.0

    set project_identity [dict create \
        schema_version stage1e-project-identity-v1 \
        producer_operation vivado_project::create \
        execution_id $execution_id \
        project_name $project_name \
        project_directory [file normalize $project_directory] \
        project_path [file normalize $project_path] \
        part xc7z020clg400-1 \
        board_part tul.com.tw:pynq-z2:part0:1.0 \
        target_language Verilog]
    set project_ownership [dict create \
        owner vivado_project \
        execution_id $execution_id \
        project_handle $current_project_handle \
        project_path [file normalize $project_path] \
        identity_verified 1 \
        project_identity $project_identity]

    return [dict create \
        context_schema_version stage1e-bd-create-context-v1 \
        operation bd_flow::create \
        phase BD_GENERATION \
        execution_id $execution_id \
        authorization [dict create \
            status AUTHORIZED \
            authority controller_core \
            execution_id $execution_id \
            operation bd_flow::create \
            phase BD_GENERATION \
            capability bd_generation_enabled \
            capability_enabled 1] \
        source_identity [dict create \
            schema_version stage1e-source-identity-v1 \
            execution_id $execution_id \
            git_commit [string repeat 1 40]] \
        environment_identity [dict create \
            schema_version stage1e-environment-identity-v1 \
            execution_id $execution_id \
            vivado_version 2024.1 \
            part xc7z020clg400-1 \
            board_part tul.com.tw:pynq-z2:part0:1.0] \
        configuration_identity [dict create \
            schema_version stage1e-configuration-identity-v1 \
            execution_id $execution_id \
            sha256 [string repeat c 64]] \
        workspace_root $workspace_root \
        evidence_dir $evidence_dir \
        project_ownership $project_ownership \
        bd_identity [dict create \
            schema_version stage1e-bd-create-identity-v1 \
            bd_name $bd_name \
            expected_bd_path $expected_bd_path] \
        topology_policy [dict create \
            schema_version stage1e-topology-policy-reference-v1 \
            execution_id $execution_id \
            policy_id pynq_z2_stage1e_base_design_v1 \
            source_reference docs/design/stage1e_wpb_adapter_interface.md \
            sha256 [string repeat d 64]]]
}

proc ::stage1e::bd_creation_adapter_tests::assert_no_commands {
    forbidden_commands
    label
} {
    variable invocation_log
    variable forbidden_count
    assert_equal 0 $forbidden_count "$label tripwire count"
    foreach invocation $invocation_log {
        set command [lindex $invocation 0]
        assert_true [expr {$command ni $forbidden_commands}] \
            "$label command was invoked: $command"
    }
}

proc ::stage1e::bd_creation_adapter_tests::all_files {root} {
    set files {}
    foreach entry [glob -nocomplain -directory $root -- * .*] {
        if {[file tail $entry] in {. ..}} {
            continue
        }
        if {[file isdirectory $entry]} {
            foreach nested [all_files $entry] {
                lappend files $nested
            }
        } elseif {[file isfile $entry]} {
            lappend files $entry
        }
    }
    return $files
}

proc ::stage1e::bd_creation_adapter_tests::run_all {} {
    variable invocation_log
    variable current_bd
    variable empty_bd_session_behavior
    variable bd_files
    variable forced_bd_path

    run_case BD_CREATE_MISSING_PROJECT_OWNERSHIP {
        reset_mock
        set context [valid_context missing_project_ownership]
        dict unset context project_ownership
        set result [::stage1d::bd_flow::create $context]
        assert_status $result FAIL {Missing project ownership status}
        assert_equal CONTEXT_FIELD_MISSING [first_error_code $result] \
            {Missing project ownership code}
        assert_equal 0 [dict get $result vivado_invoked] \
            {Missing project ownership invoked Vivado}
        assert_equal {} $invocation_log \
            {Missing project ownership reached the mock backend}
    }

    run_case BD_CREATE_AUTH_REJECT {
        reset_mock
        set context [valid_context authorization_reject]
        dict set context authorization capability_enabled 0
        set result [::stage1d::bd_flow::create $context]
        assert_status $result BLOCKED {Authorization rejection status}
        assert_equal AUTHORIZATION_MISMATCH [first_error_code $result] \
            {Authorization rejection code}
        assert_equal 0 [dict get $result vivado_invoked] \
            {Authorization rejection invoked Vivado}
        assert_equal {} $invocation_log \
            {Authorization rejection reached the mock backend}
    }

    run_case BD_CREATE_EMPTY_SESSION_BD_5_104 {
        reset_mock
        set empty_bd_session_behavior RAISE_BD_5_104
        set context [valid_context empty_session_bd_5_104]
        set result [::stage1d::bd_flow::create $context]
        assert_status $result PASS {BD 5-104 empty-session status}
        assert_true [dict exists $result produced_identities bd_identity] \
            {BD 5-104 empty-session path produced no BD identity}
        assert_equal 1 [llength [lsearch -all -exact -index 0 \
            $invocation_log create_bd_design]] \
            {BD 5-104 path did not create exactly one BD}
    }

    run_case BD_CREATE_EMPTY_HANDLE_CONTINUES {
        reset_mock
        set empty_bd_session_behavior RETURN_EMPTY
        set context [valid_context empty_handle]
        set result [::stage1d::bd_flow::create $context]
        assert_status $result PASS {Empty-BD-handle status}
        assert_true [dict get $result ownership_records identity_verified] \
            {Empty-BD-handle path did not verify BD ownership}
        assert_equal 1 [llength [lsearch -all -exact -index 0 \
            $invocation_log create_bd_design]] \
            {Empty-BD-handle path did not create exactly one BD}
    }

    run_case BD_CREATE_EXISTING_SESSION_REJECT {
        reset_mock
        set context [valid_context existing_session]
        set current_bd external_design
        set result [::stage1d::bd_flow::create $context]
        assert_status $result FAIL {Existing-BD-session rejection status}
        assert_equal BD_SESSION_OCCUPIED [first_error_code $result] \
            {Existing-BD-session rejection code}
        assert_equal 0 [llength [lsearch -all -exact -index 0 \
            $invocation_log create_bd_design]] \
            {Existing-BD-session rejection created a BD}
        assert_equal 0 [llength [lsearch -all -exact -index 0 \
            $invocation_log close_bd_design]] \
            {Existing-BD-session rejection closed the external BD}
        assert_equal external_design $current_bd \
            {Existing-BD-session rejection adopted or changed the external BD}
    }

    run_case BD_CREATE_UNEXPECTED_QUERY_ERROR {
        reset_mock
        set empty_bd_session_behavior RAISE_UNEXPECTED
        set context [valid_context unexpected_query]
        set result [::stage1d::bd_flow::create $context]
        assert_status $result FAIL {Unexpected-BD-query status}
        assert_equal BD_CURRENT_QUERY_FAILED [first_error_code $result] \
            {Unexpected-BD-query failure code}
        assert_equal 0 [llength [lsearch -all -exact -index 0 \
            $invocation_log create_bd_design]] \
            {Unexpected BD query reached BD creation}
        assert_equal 0 [llength [lsearch -all -exact -index 0 \
            $invocation_log close_bd_design]] \
            {Unexpected BD query closed a BD}
    }

    run_case BD_CREATE_EXISTING_BD_REJECT {
        reset_mock
        set context [valid_context existing_bd]
        set bd_files [list bdfile::historical_protection_system]
        set result [::stage1d::bd_flow::create $context]
        assert_status $result FAIL {Existing BD rejection status}
        assert_equal BD_ALREADY_EXISTS [first_error_code $result] \
            {Existing BD rejection code}
        assert_true [expr {[lsearch -exact $invocation_log \
            [list create_bd_design protection_system]] < 0}] \
            {Existing BD rejection invoked create_bd_design}
    }

    run_case BD_CREATE_PATH_IDENTITY_CHECKS {
        reset_mock
        set context [valid_context invalid_path]
        dict set context bd_identity expected_bd_path [file normalize \
            [file join [dict get $context workspace_root] .. \
                escaped protection_system.bd]]
        set result [::stage1d::bd_flow::create $context]
        assert_status $result FAIL {Invalid expected path status}
        assert_equal BD_PATH_REJECTED [first_error_code $result] \
            {Invalid expected path code}
        assert_equal {} $invocation_log \
            {Invalid expected path reached the mock backend}

        reset_mock
        set context [valid_context readback_mismatch]
        set forced_bd_path [file join \
            [file dirname [dict get $context bd_identity expected_bd_path]] \
            wrong_design.bd]
        set result [::stage1d::bd_flow::create $context]
        assert_status $result FAIL {BD readback mismatch status}
        assert_equal BD_PATH_IDENTITY_MISMATCH [first_error_code $result] \
            {BD readback mismatch code}
        assert_true [dict get $result cleanup_result required] \
            {BD readback mismatch did not require lifecycle cleanup}
    }

    run_case BD_CREATE_RESULT_SCHEMA {
        reset_mock
        set context [valid_context result_schema]
        set result [::stage1d::bd_flow::create $context]
        assert_status $result PASS {Structured result status}
        foreach key {
            schema_version
            operation
            phase
            execution_id
            status
            consumed_identities
            produced_identities
            ownership_records
            bd_ownership
            evidence
            warnings
            errors
            cleanup_result
        } {
            assert_true [dict exists $result $key] \
                "Structured result is missing: $key"
        }
        assert_equal stage1e-bd-create-result-v1 \
            [dict get $result schema_version] {Result schema version}
        assert_equal bd_flow::create [dict get $result operation] \
            {Result operation}
        assert_equal BD_GENERATION [dict get $result phase] {Result phase}
        assert_true [dict exists $result produced_identities bd_identity] \
            {Produced BD identity is missing}
        set ownership [dict get $result ownership_records]
        assert_equal $ownership [dict get $result bd_ownership] \
            {Top-level BD ownership result}
        foreach key {
            owner
            execution_id
            project_path
            bd_name
            bd_path
            opened
            identity_verified
            validated
            saved
        } {
            assert_true [dict exists $ownership $key] \
                "BD ownership is missing: $key"
        }
        assert_equal bd_flow [dict get $ownership owner] {BD owner}
        assert_true [dict get $ownership opened] {BD is not marked open}
        assert_true [dict get $ownership identity_verified] \
            {BD identity is not verified}
        assert_equal 0 [dict get $ownership validated] \
            {New BD is marked validated}
        assert_equal 0 [dict get $ownership saved] {New BD is marked saved}
    }

    run_case BD_CREATE_NO_TOPOLOGY {
        reset_mock
        set context [valid_context no_topology]
        set result [::stage1d::bd_flow::create $context]
        assert_status $result PASS {No-topology create status}
        assert_equal 0 [dict get $result topology_created] \
            {BD create reported topology creation}
        assert_equal 0 [dict get $result topology_mutation_performed] \
            {BD create reported topology mutation}
        assert_no_commands {
            create_bd_cell
            create_bd_port
            create_bd_intf_port
            connect_bd_net
            connect_bd_intf_net
            assign_bd_address
            apply_bd_automation
        } {Topology boundary}
    }

    run_case BD_CREATE_NO_SAVE {
        reset_mock
        set context [valid_context no_save]
        set result [::stage1d::bd_flow::create $context]
        assert_status $result PASS {No-save create status}
        assert_equal 0 [dict get $result bd_validated] \
            {BD create reported validation}
        assert_equal 0 [dict get $result bd_saved] \
            {BD create reported save}
        assert_no_commands {validate_bd_design save_bd_design} \
            {Validate/save boundary}
    }

    run_case BD_CREATE_NO_ARTIFACT {
        reset_mock
        set context [valid_context no_artifact]
        set result [::stage1d::bd_flow::create $context]
        assert_status $result PASS {No-artifact create status}
        foreach field {
            output_products_generated
            synthesis_performed
            implementation_performed
            artifacts_generated
            artifact_generation_performed
            artifact_publication_performed
        } {
            assert_equal 0 [dict get $result $field] \
                "No-artifact result field $field"
        }
        assert_no_commands {
            generate_target
            make_wrapper
            launch_runs
            synth_design
            opt_design
            place_design
            route_design
            write_bitstream
            write_hw_platform
            write_debug_probes
            export_hardware
        } {Artifact boundary}
        foreach path [all_files [dict get $context workspace_root]] {
            assert_true [expr {
                [string tolower [file extension $path]] ni
                    {.bit .hwh .xsa .ltx .dcp}
            }] "Mock BD creation generated an FPGA artifact: $path"
        }
    }
}

set test_status [catch {
    ::stage1e::bd_creation_adapter_tests::prepare_suite
    ::stage1e::bd_creation_adapter_tests::run_all
} test_error test_options]
set cleanup_status [catch {
    ::stage1e::bd_creation_adapter_tests::safe_cleanup
} cleanup_error cleanup_options]
rename ::stage1d::bd_flow::create_backend::invoke {}
rename ::stage1d::bd_flow::create_backend::_production_invoke \
    ::stage1d::bd_flow::create_backend::invoke

if {$test_status != 0} {
    incr ::stage1e::bd_creation_adapter_tests::fail_count
    puts stderr "TEST SUITE: FAIL: $test_error"
    if {[dict exists $test_options -errorinfo]} {
        puts stderr [dict get $test_options -errorinfo]
    }
}
if {$cleanup_status != 0} {
    incr ::stage1e::bd_creation_adapter_tests::fail_count
    puts stderr "TEST CLEANUP: FAIL: $cleanup_error"
    if {[dict exists $cleanup_options -errorinfo]} {
        puts stderr [dict get $cleanup_options -errorinfo]
    }
}

puts "SUMMARY PASS=$::stage1e::bd_creation_adapter_tests::pass_count FAIL=$::stage1e::bd_creation_adapter_tests::fail_count"
if {$::stage1e::bd_creation_adapter_tests::fail_count != 0} {
    exit 1
}
exit 0
