# Offline fixture tests for the Stage2I Hardware Manager binding contract.

set test_directory [file dirname [file normalize [info script]]]
set repository_root [file dirname $test_directory]
set tool_directory [file join $repository_root tools board_validation]

source [file join $tool_directory stage1_board_ila_common.tcl]

set ::stage2i_fixture_check_count 0

proc assert_true {condition message} {
    incr ::stage2i_fixture_check_count
    if {![uplevel 1 [list expr $condition]]} {
        error "ASSERTION FAILED: $message"
    }
}

proc assert_equal {actual expected message} {
    incr ::stage2i_fixture_check_count
    if {$actual ne $expected} {
        error "ASSERTION FAILED: $message: $actual != $expected"
    }
}

proc expect_error {script pattern message} {
    incr ::stage2i_fixture_check_count
    if {![catch {uplevel 1 $script} observed]} {
        error "ASSERTION FAILED: $message did not fail"
    }
    if {![string match $pattern $observed]} {
        error "ASSERTION FAILED: $message: $observed"
    }
}

proc logical_probe_records {profile role hierarchy} {
    set contract [::stage1::core_contract $profile $role]
    set records {}
    foreach {index width} [dict get $contract probe_widths] {
        lappend records [dict create \
            object "${role}_probe_${index}" \
            name "${hierarchy}/probe${index}_1" \
            width $width]
    }
    return $records
}

set safe_profile SAFE_INERT
set b2_profile READY_AWARE_SYNTHETIC_DIGITAL_STIMULUS
assert_equal [::stage1::profile_core_roles $safe_profile] destination \
    {SAFE_INERT exposes only the destination ILA}
assert_equal [::stage1::profile_core_roles $b2_profile] \
    {destination source} {B2 exposes destination and source ILAs}

set devices [list \
    [dict create object arm_dap_0 name arm_dap_0 part {}] \
    [dict create \
        object xc7z020_1 name xc7z020_1 part xc7z020clg400-1]]
set selected_device [::stage1::select_fpga_device_record $devices]
assert_equal [dict get $selected_device object] xc7z020_1 \
    {the exact xc7z020clg400-1 device is selected}
set jtag_devices [list \
    [dict create object arm_dap_0 name arm_dap_0 part arm_dap] \
    [dict create object xc7z020_1 name xc7z020_1 part xc7z020]]
assert_equal [dict get [::stage1::select_fpga_device_record $jtag_devices] part] \
    xc7z020 {the actual Hardware Manager die identity is retained}
expect_error {
    ::stage1::select_fpga_device_record [list \
        [dict create object wrong name wrong part xc7z010]]
} {Expected exactly one programmable*} {another Zynq die is rejected}
expect_error {
    ::stage1::select_fpga_device_record [concat $jtag_devices [list \
        [dict create object duplicate name duplicate part xc7z020]]]
} {Expected exactly one programmable*} {ambiguous matching dies are rejected}
expect_error {
    ::stage1::select_fpga_device_record [list \
        [dict create object wrong name wrong part xc7z020clg484-1]]
} {Expected exactly one programmable xc7z020clg400-1 FPGA device*} \
    {a different xc7z020 package is rejected}

set destination_hierarchy \
    protection_system_i/system_ila_stage2b_0/inst
set source_hierarchy \
    protection_system_i/system_ila_stage2i_b2_source_0/inst
set destination_probes [logical_probe_records \
    $b2_profile destination $destination_hierarchy]
for {set index 0} {$index < 6} {incr index} {
    lappend destination_probes [dict create \
        object "axi_probe_$index" \
        name "${destination_hierarchy}/slot_0_axi_signal_$index" \
        width 32]
}
set source_probes [logical_probe_records \
    $b2_profile source $source_hierarchy]
set destination_ila [dict create \
    object hw_ila_destination \
    name hw_ila_destination \
    cell_name \
        protection_system_i/system_ila_stage2b_0/inst/ila_lib \
    probes $destination_probes]
set source_ila [dict create \
    object hw_ila_source \
    name hw_ila_source \
    cell_name \
        protection_system_i/system_ila_stage2i_b2_source_0/inst/ila_lib \
    probes $source_probes]

set selected [::stage1::select_ila_records \
    [list $destination_ila $source_ila] $b2_profile]
assert_equal [dict keys $selected] {destination source} \
    {B2 cores are selected by explicit role}
assert_equal [dict size [dict get $selected destination logical_probe_map]] 8 \
    {B2 destination core has exactly eight ACLK-domain logical probes}
assert_equal [dict size [dict get $selected source logical_probe_map]] 8 \
    {source core has exactly 8 logical probes}

set safe_destination_probes [logical_probe_records \
    $safe_profile destination $destination_hierarchy]
set safe_destination_ila [dict replace $destination_ila \
    probes $safe_destination_probes]
set safe_selected [::stage1::select_ila_records \
    [list $safe_destination_ila] $safe_profile]
assert_equal [dict keys $safe_selected] destination \
    {SAFE_INERT destination core is accepted}
expect_error {
    ::stage1::select_ila_records \
        [list $safe_destination_ila $source_ila] $safe_profile
} {*unexpected core*} {a source ILA in SAFE_INERT is rejected}
expect_error {
    ::stage1::select_ila_records [list $destination_ila] $b2_profile
} {Expected exactly one source ILA*} {B2 cannot omit the source ILA}

set missing_source [dict replace $source_ila \
    probes [lreplace $source_probes 5 5]]
expect_error {
    ::stage1::select_ila_records \
        [list $destination_ila $missing_source] $b2_profile
} {*Missing logical probe5 width 7*} {missing source probe is rejected}

set wrong_fsm_state [dict replace [lindex $destination_probes 7] width 2]
set wrong_destination [dict replace $destination_ila \
    probes [lreplace $destination_probes 7 7 $wrong_fsm_state]]
expect_error {
    ::stage1::select_ila_records \
        [list $wrong_destination $source_ila] $b2_profile
} {*Logical probe7 width mismatch*} \
    {B2 destination fsm_state width drift is rejected}

set unexpected_probe [dict create \
    object unexpected_probe \
    name ${source_hierarchy}/probe8_1 \
    width 1]
set unexpected_source [dict replace $source_ila \
    probes [concat $source_probes [list $unexpected_probe]]]
expect_error {
    ::stage1::select_ila_records \
        [list $destination_ila $unexpected_source] $b2_profile
} {*Unexpected logical probe8*} {unexpected logical probes are rejected}

set duplicate_probe [dict create \
    object duplicate_source_probe \
    name alternate/probe1_1 \
    width 1]
set duplicate_source [dict replace $source_ila \
    probes [concat $source_probes [list $duplicate_probe]]]
expect_error {
    ::stage1::select_ila_records \
        [list $destination_ila $duplicate_source] $b2_profile
} {*Duplicate logical probe1 objects*} {duplicate logical probes are rejected}

assert_equal [::stage1::logical_probe_index ${source_hierarchy}/probe7_1] 7 \
    {probe7_1 parses exactly}
assert_equal [::stage1::logical_probe_index ${source_hierarchy}/probe7] 7 \
    {probe7 parses exactly}
assert_equal [::stage1::logical_probe_index ${source_hierarchy}/probe7_10] -1 \
    {probe7 cannot fuzzy-match a different suffix}

set ::stage1_preflight_library_only 1
source [file join $tool_directory stage1_board_ila_binding_preflight.tcl]
unset ::stage1_preflight_library_only
set preflight_graph "[info body execute_binding_preflight]\n\
[info body ::stage1::open_bound_hardware]"
foreach forbidden {
    program_hw_devices
    reset_hw_ila
    run_hw_ila
    wait_on_hw_ila
    upload_hw_ila_data
    write_hw_ila_data
} {
    assert_true {[string first $forbidden $preflight_graph] < 0} \
        "binding preflight excludes $forbidden"
}
assert_true {[string first {PROGRAM.FILE} $preflight_graph] >= 0} \
    {binding preflight binds the explicit BIT metadata}
assert_true {[string first {PROBES.FILE} $preflight_graph] >= 0} \
    {binding preflight binds the explicit LTX metadata}

::stage1::static_compile {execute_binding_preflight}
puts "STAGE2I_ILA_BINDING_FIXTURE_TESTS_PASS checks=$::stage2i_fixture_check_count"
