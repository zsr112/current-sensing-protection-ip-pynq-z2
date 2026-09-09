source [file join [file dirname [info script]] \
    stage1e_runtime_test_support.tcl]

namespace eval ::stage1e::runtime_negative_test {}

proc ::stage1e::runtime_negative_test::reattach {fields record} {
    return [::stage1e::runtime_identity::attach $fields \
        [dict remove $record identity_sha256]]
}

set fixture [::stage1e::runtime_test::identity_fixture]

::stage1e::runtime_test::run_case enabled_phys_opt_is_blocked {
    set configuration [dict get $fixture configuration]
    dict set configuration effective_step_graph phys_opt_design \
        configured_state ENABLED
    set configuration [::stage1e::runtime_negative_test::reattach \
        [::stage1e::runtime_schema::configuration_identity_fields] \
        $configuration]
    ::stage1e::runtime_test::assert_error {
        ::stage1e::runtime_schema::validate_configuration_identity_v2 \
            $configuration
    } {*CONTRACT_MISMATCH*}
}

::stage1e::runtime_test::run_case missing_identity_is_blocked {
    set configuration [dict get $fixture configuration]
    dict set configuration runtime_backend_identity MISSING
    set configuration [::stage1e::runtime_negative_test::reattach \
        [::stage1e::runtime_schema::configuration_identity_fields] \
        $configuration]
    ::stage1e::runtime_test::assert_error {
        ::stage1e::runtime_schema::validate_configuration_identity_v2 \
            $configuration
    } {*IDENTITY_INVALID*}
}

::stage1e::runtime_test::run_case stale_runtime_is_blocked {
    set runtime [dict get $fixture runtime]
    dict set runtime status STALE
    set runtime [::stage1e::runtime_negative_test::reattach \
        [::stage1e::runtime_schema::runtime_backend_identity_fields] $runtime]
    ::stage1e::runtime_test::assert_error {
        ::stage1e::runtime_schema::validate_runtime_backend_identity $runtime
    } {*RUNTIME_STALE*}
}

::stage1e::runtime_test::run_case unauthorized_operation_is_blocked {
    set configuration [dict get $fixture configuration]
    dict lappend configuration operation_order phys_opt_design
    set configuration [::stage1e::runtime_negative_test::reattach \
        [::stage1e::runtime_schema::configuration_identity_fields] \
        $configuration]
    ::stage1e::runtime_test::assert_error {
        ::stage1e::runtime_schema::validate_configuration_identity_v2 \
            $configuration
    } {*UNAUTHORIZED_OPERATION*}
}

::stage1e::runtime_test::finish
