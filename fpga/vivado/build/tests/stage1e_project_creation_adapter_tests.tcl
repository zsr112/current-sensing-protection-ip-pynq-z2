# Source-only tests for the Stage 1E project-creation extension.
#
# The suite replaces the create operation's single backend boundary with an
# isolated Tcl mock. It invokes no Vivado executable, creates no block design,
# runs no build phase, and generates no FPGA artifact.

namespace eval ::stage1e::project_creation_adapter_tests {
    variable pass_count 0
    variable fail_count 0
    variable test_root {}
    variable repository_root {}
    variable invocation_log {}
    variable current_handle {}
    variable empty_session_behavior RETURN_EMPTY
    variable properties [dict create]
    variable property_failure {}
    variable expected_vlnv {}
    variable forbidden_count 0
}

set stage1e_project_test_dir [file normalize [file dirname [info script]]]
set stage1e_project_build_root [file normalize \
    [file join $stage1e_project_test_dir ..]]
set stage1e_vivado_project_library [file join \
    $stage1e_project_build_root lib vivado_project.tcl]

# Sourcing must remain definition-only. A source-time Vivado command would
# fail here before the mock boundary is installed.
source $stage1e_vivado_project_library

rename ::stage1d::vivado_project::create_backend::invoke \
    ::stage1d::vivado_project::create_backend::_production_invoke
proc ::stage1d::vivado_project::create_backend::invoke {
    command
    arguments
} {
    return [::stage1e::project_creation_adapter_tests::mock_invoke \
        $command $arguments]
}

rename ::stage1d::vivado_project::create_backend::set_current_project_property \
    ::stage1d::vivado_project::create_backend::_production_set_current_project_property
proc ::stage1d::vivado_project::create_backend::set_current_project_property {
    property
    value
} {
    return [::stage1e::project_creation_adapter_tests::mock_invoke \
        set_current_project_property [list $property $value]]
}

rename ::stage1d::vivado_project::create_backend::get_current_project_property \
    ::stage1d::vivado_project::create_backend::_production_get_current_project_property
proc ::stage1d::vivado_project::create_backend::get_current_project_property {
    property
} {
    return [::stage1e::project_creation_adapter_tests::mock_invoke \
        get_current_project_property [list $property]]
}

proc ::stage1e::project_creation_adapter_tests::fail {message} {
    error "TEST FAILURE: $message"
}

proc ::stage1e::project_creation_adapter_tests::assert_true {
    condition
    message
} {
    if {!$condition} {
        fail $message
    }
}

proc ::stage1e::project_creation_adapter_tests::assert_equal {
    expected
    actual
    message
} {
    if {$expected ne $actual} {
        fail "$message: expected=<$expected> actual=<$actual>"
    }
}

proc ::stage1e::project_creation_adapter_tests::assert_status {
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

proc ::stage1e::project_creation_adapter_tests::first_error_code {result} {
    set errors [dict get $result errors]
    if {[llength $errors] == 0} {
        fail {Expected a structured error record.}
    }
    return [dict get [lindex $errors 0] code]
}

proc ::stage1e::project_creation_adapter_tests::run_case {name body} {
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

proc ::stage1e::project_creation_adapter_tests::temporary_base {} {
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
    error {No external temporary directory is available for project tests.}
}

proc ::stage1e::project_creation_adapter_tests::write_text {path text} {
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

proc ::stage1e::project_creation_adapter_tests::prepare_suite {} {
    variable test_root
    variable repository_root
    set test_root [file normalize [file join [temporary_base] \
        "stage1e_project_create_tests_[pid]_[clock clicks]"]]
    if {![string match {stage1e_project_create_tests_*} \
        [file tail $test_root]]} {
        error "Unsafe project test root: $test_root"
    }
    file mkdir $test_root
    set repository_root [file join $test_root source_repository]
    file mkdir [file join $repository_root rtl]
    write_text [file join $repository_root rtl project_support.v] \
        "module project_support; endmodule\n"
}

proc ::stage1e::project_creation_adapter_tests::safe_cleanup {} {
    variable test_root
    if {$test_root eq {} || ![file exists $test_root]} {
        return
    }
    if {![string match {stage1e_project_create_tests_*} \
        [file tail $test_root]]} {
        error "Refusing unsafe project test cleanup: $test_root"
    }
    file delete -force $test_root
}

proc ::stage1e::project_creation_adapter_tests::reset_mock {} {
    variable invocation_log
    variable current_handle
    variable empty_session_behavior
    variable properties
    variable property_failure
    variable expected_vlnv
    variable forbidden_count
    set invocation_log {}
    set current_handle {}
    set empty_session_behavior RETURN_EMPTY
    set properties [dict create]
    set property_failure {}
    set expected_vlnv zsr112.local:protection:protection_ip_axi_lite:0.3
    set forbidden_count 0
}

proc ::stage1e::project_creation_adapter_tests::mock_invoke {
    command
    arguments
} {
    variable invocation_log
    variable current_handle
    variable empty_session_behavior
    variable properties
    variable property_failure
    variable expected_vlnv
    variable forbidden_count
    lappend invocation_log [linsert $arguments 0 $command]

    if {$command in {
        create_bd_design
        open_bd_design
        validate_bd_design
        save_bd_design
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
            if {$current_handle ne {}} {
                return $current_handle
            }
            switch -- $empty_session_behavior {
                RETURN_EMPTY {
                    return {}
                }
                RAISE_CORETCL_NO_PROJECT {
                    error \
                        {ERROR: [Coretcl 2-88] No projects are currently open.}
                }
                RAISE_UNEXPECTED {
                    error \
                        {ERROR: [Common 17-69] Unexpected project query failure.}
                }
                default {
                    error "Unsupported empty-session behavior: $empty_session_behavior"
                }
            }
        }
        create_project {
            lassign $arguments project_name project_directory option part
            if {$option ne {-part}} {
                error {Mock create_project did not receive -part.}
            }
            file mkdir $project_directory
            write_text [file join $project_directory "${project_name}.xpr"] \
                "mock Vivado project\n"
            # Vivado 2024.1 renders a stored current_project value as the plain
            # project name. Project property operations must use the dedicated
            # backend that evaluates [current_project] in the same command.
            set current_handle $project_name
            dict set properties $current_handle NAME $project_name
            dict set properties $current_handle DIRECTORY \
                [file normalize $project_directory]
            dict set properties $current_handle PART $part
            dict set properties $current_handle BOARD_PART {}
            dict set properties $current_handle TARGET_LANGUAGE {}
            dict set properties $current_handle IP_REPO_PATHS {}
            return $current_handle
        }
        set_property {
            lassign $arguments property value object
            if {$object eq $current_handle} {
                error "ERROR: \[Common 17-161\] Invalid option value '$object' specified for 'objects'."
            }
            dict set properties $object [string toupper $property] $value
            return {}
        }
        set_current_project_property {
            lassign $arguments property value
            if {$current_handle eq {}} {
                error {Mock has no current project object for property write.}
            }
            if {$property_failure ne {} &&
                [string equal -nocase $property_failure $property]} {
                error \
                    {ERROR: [Common 17-69] Unexpected project property failure.}
            }
            dict set properties $current_handle \
                [string toupper $property] $value
            return {}
        }
        get_property {
            lassign $arguments property object
            set property [string toupper $property]
            if {[string match {ipdef::*} $object] && $property eq {VLNV}} {
                return [string range $object [string length {ipdef::}] end]
            }
            return [dict get $properties $object $property]
        }
        get_current_project_property {
            lassign $arguments property
            if {$current_handle eq {}} {
                error {Mock has no current project object for property readback.}
            }
            return [dict get $properties $current_handle \
                [string toupper $property]]
        }
        update_ip_catalog {
            return {}
        }
        get_ipdefs {
            lassign $arguments option vlnv
            if {$option ne {-all}} {
                error {Mock get_ipdefs requires -all.}
            }
            if {$vlnv eq $expected_vlnv} {
                return [list "ipdef::$vlnv"]
            }
            return {}
        }
        add_files {
            return {}
        }
        close_project {
            set current_handle {}
            return {}
        }
        default {
            error "Unexpected mock Vivado command: $command"
        }
    }
}

proc ::stage1e::project_creation_adapter_tests::valid_context {name} {
    variable test_root
    variable repository_root
    variable expected_vlnv
    set execution_id "STAGE1E-PROJECT-CREATE-$name"
    set workspace_root [file normalize \
        [file join $test_root executions $name]]
    set evidence_dir [file join $workspace_root evidence]
    set ip_repo_path [file join $workspace_root ip_repo]
    set packaged_ip_path [file join $ip_repo_path protection_ip_axi_lite]
    file mkdir $evidence_dir
    file mkdir $packaged_ip_path
    set project_name stage1e_design
    set support_path rtl/project_support.v
    set support_file [file join $repository_root rtl project_support.v]
    set accepted_sources [list [dict create \
        path $support_path \
        size [file size $support_file] \
        sha256 [::stage1d::source_check::sha256_file $support_file]]]
    return [dict create \
        context_schema_version stage1e-vivado-project-create-context-v1 \
        operation vivado_project::create \
        phase PROJECT_RECONSTRUCTION \
        execution_id $execution_id \
        authorization [dict create \
            status AUTHORIZED \
            authority controller_core \
            execution_id $execution_id \
            operation vivado_project::create \
            phase PROJECT_RECONSTRUCTION \
            capability project_reconstruction_enabled \
            capability_enabled 1] \
        source_identity [dict create \
            schema_version stage1e-source-identity-v1 \
            repository_root $repository_root \
            git_commit [string repeat 1 40] \
            source_inventory $accepted_sources] \
        environment_identity [dict create \
            schema_version stage1e-environment-identity-v1 \
            vivado_version 2024.1 \
            part xc7z020clg400-1 \
            board_part tul.com.tw:pynq-z2:part0:1.0] \
        configuration_identity [dict create \
            schema_version stage1e-configuration-identity-v1 \
            build_profile stage1e_controller_skeleton \
            sha256 [string repeat c 64]] \
        workspace_root $workspace_root \
        evidence_dir $evidence_dir \
        project_path [file join $workspace_root project "${project_name}.xpr"] \
        project_name $project_name \
        part xc7z020clg400-1 \
        board_part tul.com.tw:pynq-z2:part0:1.0 \
        target_language Verilog \
        source_inventory [list $support_path] \
        constraint_policy [dict create \
            schema_version stage1e-constraint-policy-v1 \
            mode NO_USER_XDC \
            files {}] \
        ip_repo_identity [dict create \
            schema_version stage1e-ip-repo-identity-v1 \
            execution_id $execution_id \
            path $ip_repo_path \
            packaged_ip_path $packaged_ip_path \
            vlnv $expected_vlnv \
            package_sha256 [string repeat a 64] \
            ip_repo_sha256 [string repeat b 64]]]
}

proc ::stage1e::project_creation_adapter_tests::all_files {root} {
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

proc ::stage1e::project_creation_adapter_tests::assert_no_commands {
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

proc ::stage1e::project_creation_adapter_tests::run_all {} {
    variable repository_root
    variable invocation_log
    variable current_handle
    variable empty_session_behavior
    variable property_failure

    run_case PROJECT_CREATE_CONTEXT_VALID {
        reset_mock
        set context [valid_context context_valid]
        set result [::stage1d::vivado_project::create $context]
        assert_status $result PASS {Valid create context status}
        set ownership [dict get $result ownership_records]
        assert_equal vivado_project [dict get $ownership owner] \
            {Project owner}
        assert_equal [dict get $context execution_id] \
            [dict get $ownership execution_id] {Project execution binding}
        assert_true [dict get $ownership identity_verified] \
            {Project identity was not verified}
        assert_true [expr {[lsearch -exact $invocation_log \
            [list update_ip_catalog]] >= 0}] \
            {IP catalog was not updated}
    }

    run_case PROJECT_CREATE_AUTH_REJECT {
        reset_mock
        set context [valid_context auth_reject]
        dict set context authorization capability_enabled 0
        set result [::stage1d::vivado_project::create $context]
        assert_status $result BLOCKED {Authorization rejection status}
        assert_equal AUTHORIZATION_MISMATCH [first_error_code $result] \
            {Authorization rejection code}
        assert_equal 0 [dict get $result vivado_invoked] \
            {Authorization rejection invoked Vivado}
        assert_equal {} $invocation_log \
            {Authorization rejection reached the mock backend}
    }

    run_case PROJECT_CREATE_PATH_REJECT {
        reset_mock
        set context [valid_context path_reject]
        dict set context project_path [file join \
            $repository_root generated stage1e_design.xpr]
        set result [::stage1d::vivado_project::create $context]
        assert_status $result FAIL {Project path rejection status}
        assert_equal PROJECT_PATH_REJECTED [first_error_code $result] \
            {Project path rejection code}
        assert_equal {} $invocation_log \
            {Project path rejection reached the mock backend}
    }

    run_case PROJECT_CREATE_EXISTING_PROJECT_REJECT {
        reset_mock
        set context [valid_context existing_project]
        write_text [dict get $context project_path] {historical project}
        set result [::stage1d::vivado_project::create $context]
        assert_status $result FAIL {Existing project rejection status}
        assert_equal PROJECT_ALREADY_EXISTS [first_error_code $result] \
            {Existing project rejection code}
        assert_equal {} $invocation_log \
            {Existing project rejection reached the mock backend}
    }

    run_case PROJECT_CREATE_EMPTY_SESSION_CORETCL_2_88 {
        reset_mock
        set empty_session_behavior RAISE_CORETCL_NO_PROJECT
        set context [valid_context empty_session_coretcl]
        set result [::stage1d::vivado_project::create $context]
        assert_status $result PASS {Coretcl empty-session create status}
        assert_true [dict exists $result produced_identities project_identity] \
            {Coretcl empty-session create produced no project identity}
        assert_equal 1 [llength [lsearch -all -exact -index 0 \
            $invocation_log create_project]] \
            {Coretcl empty-session path did not create exactly one project}
    }

    run_case PROJECT_CREATE_EMPTY_HANDLE_CONTINUES {
        reset_mock
        set empty_session_behavior RETURN_EMPTY
        set context [valid_context empty_handle]
        set result [::stage1d::vivado_project::create $context]
        assert_status $result PASS {Empty-handle create status}
        assert_true [dict get $result ownership_records identity_verified] \
            {Empty-handle create did not verify owned project identity}
        assert_equal 1 [llength [lsearch -all -exact -index 0 \
            $invocation_log create_project]] \
            {Empty-handle path did not create exactly one project}
    }

    run_case PROJECT_CREATE_BOARD_PART_OBJECT_TARGET {
        reset_mock
        set context [valid_context board_part_target]
        set result [::stage1d::vivado_project::create $context]
        assert_status $result PASS {Board-part target status}
        set expected_board_part [dict get $context board_part]
        assert_true [expr {[lsearch -exact $invocation_log \
            [list set_current_project_property board_part \
                $expected_board_part]] >= 0}] \
            {Board part did not target the explicit current project object}
        assert_true [expr {[lsearch -exact $invocation_log \
            [list get_current_project_property BOARD_PART]] >= 0}] \
            {Board part was not read back from the current project object}
        assert_equal $expected_board_part \
            [dict get $result produced_identities project_identity board_part] \
            {Board-part identity readback}
        assert_equal 0 [llength [lsearch -all -exact -index 0 \
            $invocation_log set_property]] \
            {Project creation used generic set_property}
    }

    run_case PROJECT_CREATE_PROPERTY_OBJECT_TARGET {
        reset_mock
        set context [valid_context property_target]
        set result [::stage1d::vivado_project::create $context]
        assert_status $result PASS {Project-property target status}
        foreach {property value} [list \
            board_part [dict get $context board_part] \
            target_language [dict get $context target_language] \
            IP_REPO_PATHS [list [dict get $context ip_repo_identity path]]] {
            assert_true [expr {[lsearch -exact $invocation_log \
                [list set_current_project_property $property $value]] >= 0}] \
                "Project property did not target current_project: $property"
        }
        foreach property {
            NAME DIRECTORY PART BOARD_PART TARGET_LANGUAGE IP_REPO_PATHS
        } {
            assert_true [expr {[lsearch -exact $invocation_log \
                [list get_current_project_property $property]] >= 0}] \
                "Project property was not read from current_project: $property"
        }
        foreach invocation $invocation_log {
            if {[lindex $invocation 0] eq {get_property}} {
                assert_true [expr {[lindex $invocation 2] ne $current_handle}] \
                    {Generic get_property received the plain project name}
            }
        }
        set setter_body [info body \
            ::stage1d::vivado_project::create_backend::_production_set_current_project_property]
        assert_true [expr {[string first \
            {set_property $property $value [current_project]} \
            $setter_body] >= 0}] \
            {Production property setter does not use [current_project]}
        set getter_body [info body \
            ::stage1d::vivado_project::create_backend::_production_get_current_project_property]
        assert_true [expr {[string first \
            {get_property $property [current_project]} \
            $getter_body] >= 0}] \
            {Production property reader does not use [current_project]}
        assert_equal 0 [llength [lsearch -all -exact -index 0 \
            $invocation_log set_property]] \
            {Project creation used a plain-name property target}
    }

    run_case PROJECT_CREATE_UNEXPECTED_PROPERTY_FAILURE {
        reset_mock
        set property_failure BOARD_PART
        set context [valid_context unexpected_property]
        set project_directory [file dirname [dict get $context project_path]]
        set result [::stage1d::vivado_project::create $context]
        assert_status $result FAIL {Unexpected-property failure status}
        assert_equal VIVADO_PROJECT_CREATE_FAILED \
            [first_error_code $result] {Unexpected-property failure code}
        assert_true [dict get $result cleanup_result required] \
            {Unexpected-property failure did not require cleanup}
        assert_true [dict get $result cleanup_result attempted] \
            {Unexpected-property failure did not attempt cleanup}
        assert_true [dict get $result cleanup_result completed] \
            {Unexpected-property cleanup did not complete}
        assert_true [dict get $result cleanup_result project_closed] \
            {Unexpected-property cleanup did not close the owned project}
        assert_equal {} $current_handle \
            {Unexpected-property cleanup retained the project handle}
        assert_true [expr {![file exists $project_directory]}] \
            {Unexpected-property cleanup retained the project directory}
        assert_true [expr {![dict exists $result produced_identities \
            project_identity]}] \
            {Unexpected-property failure produced a project identity}
    }

    run_case PROJECT_CREATE_EXISTING_SESSION_REJECT {
        reset_mock
        set current_handle project::external
        set context [valid_context existing_session]
        set result [::stage1d::vivado_project::create $context]
        assert_status $result BLOCKED {Existing-session rejection status}
        assert_equal VIVADO_PROJECT_SESSION_OCCUPIED \
            [first_error_code $result] {Existing-session rejection code}
        assert_equal 0 [llength [lsearch -all -exact -index 0 \
            $invocation_log create_project]] \
            {Existing-session rejection created a project}
        assert_equal 0 [llength [lsearch -all -exact -index 0 \
            $invocation_log close_project]] \
            {Existing-session rejection closed the external project}
        assert_equal project::external $current_handle \
            {Existing-session rejection adopted or changed the external project}
    }

    run_case PROJECT_CREATE_UNEXPECTED_QUERY_ERROR {
        reset_mock
        set empty_session_behavior RAISE_UNEXPECTED
        set context [valid_context unexpected_query]
        set result [::stage1d::vivado_project::create $context]
        assert_status $result FAIL {Unexpected-query failure status}
        assert_equal VIVADO_PROJECT_QUERY_FAILED \
            [first_error_code $result] {Unexpected-query failure code}
        assert_equal 0 [llength [lsearch -all -exact -index 0 \
            $invocation_log create_project]] \
            {Unexpected query error reached project creation}
        assert_equal 0 [llength [lsearch -all -exact -index 0 \
            $invocation_log close_project]] \
            {Unexpected query error closed a project}
    }

    run_case PROJECT_CREATE_RESULT_SCHEMA {
        reset_mock
        set context [valid_context result_schema]
        set result [::stage1d::vivado_project::create $context]
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
            evidence
            warnings
            errors
            cleanup_result
        } {
            assert_true [dict exists $result $key] \
                "Structured result is missing: $key"
        }
        assert_equal stage1e-vivado-project-create-result-v1 \
            [dict get $result schema_version] {Result schema version}
        assert_equal vivado_project::create [dict get $result operation] \
            {Result operation}
        assert_equal PROJECT_RECONSTRUCTION [dict get $result phase] \
            {Result phase}
        foreach key {source_identity environment_identity \
            configuration_identity workspace_identity ip_repo_identity} {
            assert_true [dict exists $result consumed_identities $key] \
                "Consumed identity is missing: $key"
        }
        assert_true [dict exists $result produced_identities \
            project_identity] {Produced project identity is missing}
        foreach key {owner project_handle project_path identity_verified} {
            assert_true [dict exists $result ownership_records $key] \
                "Project ownership field is missing: $key"
        }
    }

    run_case PROJECT_CREATE_NO_BD {
        reset_mock
        set context [valid_context no_bd]
        set result [::stage1d::vivado_project::create $context]
        assert_status $result PASS {No-BD create status}
        assert_equal 0 [dict get $result bd_created] \
            {Project create reported a BD}
        assert_no_commands {
            create_bd_design open_bd_design validate_bd_design save_bd_design
        } {BD boundary}
    }

    run_case PROJECT_CREATE_NO_SYNTHESIS {
        reset_mock
        set context [valid_context no_synthesis]
        set result [::stage1d::vivado_project::create $context]
        assert_status $result PASS {No-synthesis create status}
        assert_equal 0 [dict get $result synthesis_performed] \
            {Project create reported synthesis}
        assert_equal 0 [dict get $result implementation_performed] \
            {Project create reported implementation}
        assert_no_commands {
            launch_runs synth_design opt_design place_design route_design
        } {Build boundary}
    }

    run_case PROJECT_CREATE_NO_ARTIFACT {
        reset_mock
        set context [valid_context no_artifact]
        set result [::stage1d::vivado_project::create $context]
        assert_status $result PASS {No-artifact create status}
        foreach field {
            artifacts_generated
            artifact_generation_performed
            artifact_publication_performed
        } {
            assert_equal 0 [dict get $result $field] \
                "No-artifact result field $field"
        }
        assert_no_commands {
            write_bitstream write_hw_platform write_debug_probes export_hardware
        } {Artifact boundary}
        foreach path [all_files [dict get $context workspace_root]] {
            assert_true [expr {
                [string tolower [file extension $path]] ni
                    {.bit .hwh .xsa .ltx .dcp}
            }] "Mock project creation generated an FPGA artifact: $path"
        }
    }
}

set test_status [catch {
    ::stage1e::project_creation_adapter_tests::prepare_suite
    ::stage1e::project_creation_adapter_tests::run_all
} test_error test_options]
set cleanup_status [catch {
    ::stage1e::project_creation_adapter_tests::safe_cleanup
} cleanup_error cleanup_options]
rename ::stage1d::vivado_project::create_backend::invoke {}
rename ::stage1d::vivado_project::create_backend::_production_invoke \
    ::stage1d::vivado_project::create_backend::invoke
rename ::stage1d::vivado_project::create_backend::set_current_project_property {}
rename ::stage1d::vivado_project::create_backend::_production_set_current_project_property \
    ::stage1d::vivado_project::create_backend::set_current_project_property
rename ::stage1d::vivado_project::create_backend::get_current_project_property {}
rename ::stage1d::vivado_project::create_backend::_production_get_current_project_property \
    ::stage1d::vivado_project::create_backend::get_current_project_property

if {$test_status != 0} {
    incr ::stage1e::project_creation_adapter_tests::fail_count
    puts stderr "TEST SUITE: FAIL: $test_error"
    if {[dict exists $test_options -errorinfo]} {
        puts stderr [dict get $test_options -errorinfo]
    }
}
if {$cleanup_status != 0} {
    incr ::stage1e::project_creation_adapter_tests::fail_count
    puts stderr "TEST CLEANUP: FAIL: $cleanup_error"
    if {[dict exists $cleanup_options -errorinfo]} {
        puts stderr [dict get $cleanup_options -errorinfo]
    }
}

puts "SUMMARY PASS=$::stage1e::project_creation_adapter_tests::pass_count FAIL=$::stage1e::project_creation_adapter_tests::fail_count"
if {$::stage1e::project_creation_adapter_tests::fail_count != 0} {
    exit 1
}
exit 0
