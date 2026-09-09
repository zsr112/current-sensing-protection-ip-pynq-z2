# Stage 1D controlled-stimulus safe-load mutation module.
#
# Source-time contract:
# - define the mutation namespace, helpers, and apply procedure only;
# - do not invoke Vivado, open lifecycle state, mutate or save a BD, or exit;
# - begin runtime validation and mutation only through an explicit apply call.

namespace eval stage1d_controlled_stimulus {
    variable module_directory [file dirname [file normalize [info script]]]
}

proc stage1d_controlled_stimulus::current_profile_contract {profile} {
    switch -- $profile {
        SAFE_INERT {
            return [dict create \
                implementation_profile SAFE_INERT \
                profile_class PRODUCTION \
                adc_source_clock FCLK_CLK0 \
                destination_clock FCLK_CLK0 \
                gpio_mode SINGLE_CHANNEL_24_BIT \
                ready_consumed 0 \
                source_ila_present 0]
        }
        READY_AWARE_SYNTHETIC_DIGITAL_STIMULUS {
            return [dict create \
                implementation_profile \
                    READY_AWARE_SYNTHETIC_DIGITAL_STIMULUS \
                profile_class BOARD_TEST \
                adc_source_clock FCLK_CLK1_125_MHZ \
                destination_clock FCLK_CLK0_100_MHZ \
                gpio_mode DUAL_CHANNEL_32_BIT \
                command_cdc BUNDLED_DATA_REQUEST_ACK \
                maximum_burst_count 127 \
                ready_consumed 1 \
                source_ila_present 1]
        }
        default {
            error "Unsupported Stage2I controlled-stimulus profile: $profile"
        }
    }
}

proc stage1d_controlled_stimulus::current_runner_path {} {
    variable module_directory
    return [file normalize [file join \
        $module_directory \
        .. runtime runner stage1e_production_vivado_runner_v2.tcl]]
}

proc stage1d_controlled_stimulus::apply_current_profile {context} {
    foreach key {
        authorization_state implementation_profile current_bd project
    } {
        if {![dict exists $context $key]} {
            error "Stage2I profile mutation context is missing required key: $key"
        }
    }
    if {[dict get $context authorization_state] ne \
        {STAGE2I_PROFILE_MUTATION_EXPLICIT}} {
        error "Stage2I profile mutation authorization is not explicit"
    }
    set profile [dict get $context implementation_profile]
    set contract [current_profile_contract $profile]
    if {[dict get $context current_bd] ne {protection_system}} {
        error "Stage2I profile mutation requires protection_system"
    }
    if {[catch {dict size [dict get $context project]} project_error]} {
        error "Stage2I profile mutation project is invalid: $project_error"
    }
    if {[llength [info commands current_bd_design]] != 1 ||
        [current_bd_design] ne {protection_system}} {
        error "Stage2I profile mutation requires the open protection_system BD"
    }

    set runner [current_runner_path]
    if {![file isfile $runner]} {
        error "Stage2I production runner is missing: $runner"
    }
    if {[llength [info procs \
            ::stage1e::production_vivado_runner_v2::add_controlled_stimulus]] \
            == 0} {
        source $runner
    }
    if {[llength [info procs \
            ::stage1e::production_vivado_runner_v2::add_controlled_stimulus]] \
            != 1} {
        error "Stage2I controlled-stimulus runner authority is unavailable"
    }

    set project [::stage1e::production_vivado_runner_v2::add_controlled_stimulus \
        [dict create implementation_profile $profile] \
        [dict get $context project]]
    return [dict create \
        status PASS \
        implementation_profile $profile \
        profile_contract $contract \
        project $project \
        mutation_authority \
            ::stage1e::production_vivado_runner_v2::add_controlled_stimulus]
}

proc stage1d_controlled_stimulus::require_single {objects label} {
    if {[llength $objects] != 1} {
        error "Expected exactly one $label, found [llength $objects]: $objects"
    }
    return [lindex $objects 0]
}

proc stage1d_controlled_stimulus::require_bd_cell {name} {
    return [require_single [get_bd_cells -quiet $name] "BD cell '$name'"]
}

proc stage1d_controlled_stimulus::require_bd_cell_absent {name} {
    set objects [get_bd_cells -quiet $name]
    if {[llength $objects] != 0} {
        error "Stage 1D cell already exists; refusing single-application patch rerun: $name"
    }
}

proc stage1d_controlled_stimulus::require_bd_pin {path} {
    return [require_single [get_bd_pins -quiet $path] "BD pin '$path'"]
}

proc stage1d_controlled_stimulus::require_bd_intf_pin {path} {
    return [require_single [get_bd_intf_pins -quiet $path] "BD interface pin '$path'"]
}

proc stage1d_controlled_stimulus::require_bd_addr_space {path} {
    return [require_single [get_bd_addr_spaces -quiet $path] "BD address space '$path'"]
}

proc stage1d_controlled_stimulus::require_exact_ipdef {expected_vlnv label} {
    set definitions [get_ipdefs -all -quiet $expected_vlnv]
    if {[llength $definitions] != 1} {
        error "Expected exactly one IP definition for $label VLNV '$expected_vlnv', found [llength $definitions]: $definitions"
    }

    set definition [lindex $definitions 0]
    set actual_vlnv [get_property VLNV $definition]
    if {$actual_vlnv ne $expected_vlnv} {
        error "$label IP definition identity mismatch: actual=$actual_vlnv expected=$expected_vlnv"
    }

    puts "require_exact_ipdef_ok label={$label} vlnv=$actual_vlnv"
    return $definition
}

proc stage1d_controlled_stimulus::require_object_properties {object property_names label} {
    set available_properties [list_property $object]
    foreach property_name $property_names {
        if {[lsearch -exact $available_properties $property_name] < 0} {
            error "$label does not expose required Vivado 2024.1 property: $property_name"
        }
    }
    puts "require_object_properties_ok label={$label} properties={$property_names}"
}

proc stage1d_controlled_stimulus::require_scalar_net_of_pin {pin_path} {
    set pin [require_bd_pin $pin_path]
    return [require_single [get_bd_nets -quiet -of_objects $pin] "scalar net at '$pin_path'"]
}

proc stage1d_controlled_stimulus::require_intf_net_of_pin {pin_path} {
    set pin [require_bd_intf_pin $pin_path]
    return [require_single [get_bd_intf_nets -quiet -of_objects $pin] "interface net at '$pin_path'"]
}

proc stage1d_controlled_stimulus::assert_same_scalar_net {first_pin_path second_pin_path label} {
    set first_net [require_scalar_net_of_pin $first_pin_path]
    set second_net [require_scalar_net_of_pin $second_pin_path]
    if {$first_net ne $second_net} {
        error "$label pins are not on the same scalar net: $first_pin_path=$first_net $second_pin_path=$second_net"
    }
    puts "assert_same_scalar_net_ok label={$label} net=$first_net"
    return $first_net
}

proc stage1d_controlled_stimulus::assert_same_intf_net {first_pin_path second_pin_path label} {
    set first_net [require_intf_net_of_pin $first_pin_path]
    set second_net [require_intf_net_of_pin $second_pin_path]
    if {$first_net ne $second_net} {
        error "$label pins are not on the same interface net: $first_pin_path=$first_net $second_pin_path=$second_net"
    }
    puts "assert_same_intf_net_ok label={$label} net=$first_net"
    return $first_net
}

proc stage1d_controlled_stimulus::assert_pin_on_scalar_net {pin_path expected_net label} {
    set actual_net [require_scalar_net_of_pin $pin_path]
    if {$actual_net ne $expected_net} {
        error "$label pin is on an unexpected net: pin=$pin_path actual=$actual_net expected=$expected_net"
    }
    puts "assert_pin_on_scalar_net_ok label={$label} pin=$pin_path net=$actual_net"
}

proc stage1d_controlled_stimulus::assert_single_scalar_driver {net expected_driver_path label} {
    set drivers [get_bd_pins -quiet -of_objects $net -filter {DIR == O}]
    if {[llength $drivers] != 1} {
        error "$label expected one output driver on $net, found [llength $drivers]: $drivers"
    }
    set expected_driver [require_bd_pin $expected_driver_path]
    if {[lindex $drivers 0] ne $expected_driver} {
        error "$label unexpected driver on $net: actual=[lindex $drivers 0] expected=$expected_driver"
    }
    puts "assert_single_scalar_driver_ok label={$label} net=$net driver=$expected_driver"
}

proc stage1d_controlled_stimulus::assert_cell_output_pins_unconnected {cell label} {
    set output_pins [get_bd_pins -quiet -of_objects $cell -filter {DIR == O}]
    if {[llength $output_pins] == 0} {
        error "$label has no output pins to validate before deletion: $cell"
    }

    foreach output_pin $output_pins {
        set remaining_nets [get_bd_nets -quiet -of_objects $output_pin]
        if {[llength $remaining_nets] != 0} {
            error "$label still has a connected output role and cannot be deleted: pin=$output_pin nets=$remaining_nets"
        }
    }

    puts "assert_cell_output_pins_unconnected_ok label={$label} cell=$cell outputs=$output_pins"
}

proc stage1d_controlled_stimulus::to_wide_integer {value label} {
    set normalized [string trim $value]
    if {[regexp -nocase {^([0-9]+)([KMG])$} $normalized -> magnitude suffix]} {
        switch -nocase -- $suffix {
            K { set multiplier 1024 }
            M { set multiplier [expr {1024 * 1024}] }
            G { set multiplier [expr {1024 * 1024 * 1024}] }
            default { error "Unsupported size suffix for $label: '$value'" }
        }
        return [expr {wide($magnitude) * wide($multiplier)}]
    }

    if {[catch {expr {wide($normalized)}} result]} {
        error "Cannot parse numeric value for $label: '$value'"
    }
    return $result
}

proc stage1d_controlled_stimulus::assert_numeric_equal {actual expected label} {
    set actual_number [to_wide_integer $actual "$label actual"]
    set expected_number [to_wide_integer $expected "$label expected"]
    if {$actual_number != $expected_number} {
        error "$label mismatch: actual=$actual expected=$expected"
    }
    puts "assert_numeric_equal_ok label={$label} value=$actual"
}

proc stage1d_controlled_stimulus::assert_property_numeric {object property expected label} {
    set actual [get_property $property $object]
    assert_numeric_equal $actual $expected "$label property=$property"
}

proc stage1d_controlled_stimulus::assert_property_text {object property expected label} {
    set actual [get_property $property $object]
    if {$actual ne $expected} {
        error "$label property mismatch: property=$property actual='$actual' expected='$expected'"
    }
    puts "assert_property_text_ok label={$label} property=$property value={$actual}"
}

proc stage1d_controlled_stimulus::assert_address_range_free {address_space proposed_base proposed_range} {
    set proposed_start [to_wide_integer $proposed_base {proposed address base}]
    set proposed_size [to_wide_integer $proposed_range {proposed address range}]
    set proposed_end [expr {$proposed_start + $proposed_size}]

    foreach segment [get_bd_addr_segs -quiet -of_objects $address_space] {
        set offset [get_property OFFSET $segment]
        set range [get_property RANGE $segment]
        if {$offset eq {} || $range eq {}} {
            continue
        }

        set existing_start [to_wide_integer $offset "address offset for $segment"]
        set existing_size [to_wide_integer $range "address range for $segment"]
        set existing_end [expr {$existing_start + $existing_size}]

        if {$proposed_start < $existing_end && $existing_start < $proposed_end} {
            error "Planned Stage 1D address overlaps existing segment: planned_base=$proposed_base planned_range=$proposed_range segment=$segment offset=$offset range=$range"
        }
    }

    puts "assert_address_range_free_ok base=$proposed_base range=$proposed_range"
}

proc stage1d_controlled_stimulus::require_single_addr_seg_for_interface {intf_pin_path} {
    set pattern [format {%s/*} $intf_pin_path]
    return [require_single [get_bd_addr_segs -quiet $pattern] "address segment below '$intf_pin_path'"]
}

proc stage1d_controlled_stimulus::require_single_mapped_addr_seg {address_space target_cell_name} {
    set pattern [format {*/SEG_%s_*} $target_cell_name]
    set matches {}

    foreach segment [get_bd_addr_segs -quiet -of_objects $address_space] {
        if {[string match $pattern $segment]} {
            lappend matches $segment
        }
    }

    set selected [require_single $matches "mapped address segment for '$target_cell_name' in address space '$address_space'"]
    puts "require_single_mapped_addr_seg_ok segment={$selected} target={$target_cell_name} address_space={$address_space}"
    return $selected
}

# Phase 3-C3 validates the controller-owned authorization assertion before any
# Vivado query or mutation command. The standalone compatibility delegate may
# append the legacy operational values still required by the existing Tcl body;
# those values grant no lifecycle or authorization authority.
proc stage1d_controlled_stimulus::_authorization_error_record {
    error_code
    message
} {
    return [dict create \
        error_code $error_code \
        category AUTHORIZATION \
        phase_name stage1d_mutation \
        message $message \
        underlying_error {} \
        evidence_references {} \
        recoverability PROVIDE_VALID_AUTHORIZATION]
}

proc stage1d_controlled_stimulus::_authorization_blocked_result {
    context
    error_code
    message
} {
    set execution_id {}
    if {![catch {dict size $context}] &&
        [dict exists $context execution_id]} {
        set execution_id [dict get $context execution_id]
    }
    return [dict create \
        status BLOCKED \
        phase MUTATION_EXECUTE \
        execution_id $execution_id \
        vivado_invoked 0 \
        artifacts_generated 0 \
        errors [list [_authorization_error_record $error_code $message]] \
        warnings {} \
        outputs [dict create \
            authorization_valid 0 \
            mutation_started 0] \
        mutation_summary {}]
}

proc stage1d_controlled_stimulus::_validate_authorization_assertion {context} {
    if {[catch {dict size $context} context_error]} {
        return [_authorization_blocked_result $context \
            AUTHORIZATION_CONTEXT_INVALID \
            "Stage 1D mutation context is not a dictionary: $context_error"]
    }

    foreach context_key {
        execution_id
        authorization_assertion
        bd_name
        evidence_dir
        environment_identity
    } {
        if {![dict exists $context $context_key]} {
            return [_authorization_blocked_result $context \
                AUTHORIZATION_CONTEXT_INCOMPLETE \
                "Stage 1D mutation context is missing authorization field: $context_key"]
        }
    }

    set execution_id [dict get $context execution_id]
    set bd_name [dict get $context bd_name]
    if {[string trim $execution_id] eq {} || [string trim $bd_name] eq {}} {
        return [_authorization_blocked_result $context \
            AUTHORIZATION_CONTEXT_INVALID \
            {Stage 1D mutation authorization requires nonempty execution_id and bd_name values.}]
    }

    set authorization_assertion [dict get $context authorization_assertion]
    if {[catch {dict size $authorization_assertion} assertion_error]} {
        return [_authorization_blocked_result $context \
            AUTHORIZATION_ASSERTION_INVALID \
            "Stage 1D authorization_assertion is not a dictionary: $assertion_error"]
    }
    set required_assertion_keys [lsort {
        execution_id
        operation
        phase
        bd_name
        decision
    }]
    if {[lsort [dict keys $authorization_assertion]] ne \
        $required_assertion_keys} {
        return [_authorization_blocked_result $context \
            AUTHORIZATION_ASSERTION_SCOPE_INVALID \
            {Stage 1D authorization_assertion must contain exactly execution_id, operation, phase, bd_name, and decision.}]
    }

    if {[dict get $authorization_assertion execution_id] ne $execution_id} {
        return [_authorization_blocked_result $context \
            AUTHORIZATION_EXECUTION_ID_MISMATCH \
            {Stage 1D authorization_assertion execution_id does not match the current execution.}]
    }
    if {[dict get $authorization_assertion operation] ne \
        {stage1d_controlled_stimulus}} {
        return [_authorization_blocked_result $context \
            AUTHORIZATION_OPERATION_MISMATCH \
            {Stage 1D authorization_assertion does not authorize stage1d_controlled_stimulus.}]
    }
    if {[dict get $authorization_assertion phase] ne {MUTATION_EXECUTE}} {
        return [_authorization_blocked_result $context \
            AUTHORIZATION_PHASE_MISMATCH \
            {Stage 1D authorization_assertion does not authorize MUTATION_EXECUTE.}]
    }
    if {[dict get $authorization_assertion bd_name] ne $bd_name} {
        return [_authorization_blocked_result $context \
            AUTHORIZATION_BD_MISMATCH \
            {Stage 1D authorization_assertion bd_name does not match the authorized active BD.}]
    }
    if {[dict get $authorization_assertion decision] ne {ALLOW}} {
        return [_authorization_blocked_result $context \
            AUTHORIZATION_DECISION_DENIED \
            {Stage 1D authorization_assertion does not explicitly permit mutation.}]
    }

    return [dict create status PASS]
}

proc stage1d_controlled_stimulus::apply {context} {
    set authorization_validation \
        [_validate_authorization_assertion $context]
    if {[dict get $authorization_validation status] ne {PASS}} {
        return $authorization_validation
    }

    set required_context_keys [list \
        axi_gpio_vlnv \
        current_bd \
        expected_bd_name \
        expected_protection_base \
        expected_protection_range \
        gpio_name \
        gpio_width \
        i_ch1_const_name \
        i_ch2_const_name \
        ila_name \
        planned_gpio_base \
        planned_gpio_range \
        project_path \
        protection_name \
        protection_vlnv \
        ps_name \
        reset_name \
        safe_gpio_default \
        sample_valid_const_name \
        stimulus_profile \
        stimulus_profile_class \
        source_acceptance_claimed \
        fault_stimulus_claimed \
        slice_ch1_name \
        slice_ch2_name \
        smartconnect_name \
        stage1d_source_baseline \
        vivado_version \
        xlslice_vlnv \
    ]
    foreach context_key $required_context_keys {
        if {![dict exists $context $context_key]} {
            error "Stage 1D mutation context is missing required key: $context_key"
        }
        set $context_key [dict get $context $context_key]
    }
    if {$stimulus_profile ne {SAFE_INERT_EXPLICIT}} {
        error "Stage 2D controlled stimulus profile must be SAFE_INERT_EXPLICIT."
    }
    if {$stimulus_profile_class ne {SAFE_INERT}} {
        error "Stage 2D controlled stimulus profile class must be SAFE_INERT."
    }
    foreach {claim_name claim_value} [list \
        source_acceptance_claimed $source_acceptance_claimed \
        fault_stimulus_claimed $fault_stimulus_claimed] {
        if {![string is boolean -strict $claim_value] || $claim_value} {
            error "$claim_name must be explicit false for SAFE_INERT_EXPLICIT."
        }
    }

# Required base and Stage 2B cells.
set ps [require_bd_cell $ps_name]
set reset [require_bd_cell $reset_name]
set smartconnect [require_bd_cell $smartconnect_name]
set protection [require_bd_cell $protection_name]
set ila [require_bd_cell $ila_name]
set sample_valid_const [require_bd_cell $sample_valid_const_name]
set i_ch1_const [require_bd_cell $i_ch1_const_name]
set i_ch2_const [require_bd_cell $i_ch2_const_name]

assert_property_text $protection VLNV $protection_vlnv {protection IP identity}

# Stage 1D is a single-application patch.
require_bd_cell_absent $gpio_name
require_bd_cell_absent $slice_ch1_name
require_bd_cell_absent $slice_ch2_name

# Base topology and current-source guards.
assert_property_numeric $smartconnect CONFIG.NUM_SI 1 {SmartConnect input count}
assert_property_numeric $smartconnect CONFIG.NUM_MI 1 {SmartConnect pre-patch output count}
assert_same_intf_net ${ps_name}/M_AXI_GP0 ${smartconnect_name}/S00_AXI {PS to SmartConnect}
assert_same_intf_net ${smartconnect_name}/M00_AXI ${protection_name}/S_AXI {SmartConnect M00 to protection IP}

set ps_data_space [require_bd_addr_space ${ps_name}/Data]
set protection_segment [require_single_mapped_addr_seg $ps_data_space $protection_name]
assert_property_numeric $protection_segment OFFSET $expected_protection_base {protection address offset}
assert_property_numeric $protection_segment RANGE $expected_protection_range {protection address range}

assert_address_range_free $ps_data_space $planned_gpio_base $planned_gpio_range

assert_property_text [require_bd_pin ${ps_name}/FCLK_RESET0_N] CONFIG.POLARITY ACTIVE_LOW {PS FCLK reset polarity}
assert_property_text [require_bd_pin ${reset_name}/peripheral_aresetn] CONFIG.POLARITY ACTIVE_LOW {peripheral reset polarity}
assert_same_scalar_net ${ps_name}/FCLK_CLK0 ${protection_name}/ACLK {protection clock}
assert_same_scalar_net ${reset_name}/peripheral_aresetn ${protection_name}/ARESETN {protection reset}

# The Stage 2D probe order preserves the Stage 2B probes and appends ready.
set sample_valid_net [assert_same_scalar_net ${protection_name}/adc_sample_valid ${ila_name}/probe1 {adc_sample_valid ILA observation}]
set i_ch1_net [assert_same_scalar_net ${protection_name}/adc_sample_ch1 ${ila_name}/probe2 {adc_sample_ch1 ILA observation}]
set i_ch2_net [assert_same_scalar_net ${protection_name}/adc_sample_ch2 ${ila_name}/probe3 {adc_sample_ch2 ILA observation}]
set sample_ready_net [assert_same_scalar_net ${protection_name}/adc_sample_ready ${ila_name}/probe11 {adc_sample_ready ILA evidence path}]

assert_pin_on_scalar_net ${sample_valid_const_name}/dout $sample_valid_net {sample_valid constant source}
assert_pin_on_scalar_net ${i_ch1_const_name}/dout $i_ch1_net {i_ch1 constant source}
assert_pin_on_scalar_net ${i_ch2_const_name}/dout $i_ch2_net {i_ch2 constant source}
assert_single_scalar_driver $i_ch1_net ${i_ch1_const_name}/dout {i_ch1 pre-patch source}
assert_single_scalar_driver $i_ch2_net ${i_ch2_const_name}/dout {i_ch2 pre-patch source}

assert_property_numeric $sample_valid_const CONFIG.CONST_WIDTH 1 {sample_valid constant width}
assert_property_numeric $sample_valid_const CONFIG.CONST_VAL 0 {sample_valid safe-inert base value}
assert_property_numeric $i_ch1_const CONFIG.CONST_WIDTH 12 {i_ch1 constant width}
assert_property_numeric $i_ch2_const CONFIG.CONST_WIDTH 12 {i_ch2 constant width}
assert_property_numeric $i_ch1_const CONFIG.CONST_VAL 1024 {i_ch1 pre-patch value}
assert_property_numeric $i_ch2_const CONFIG.CONST_VAL 1024 {i_ch2 pre-patch value}

# Required catalog IP identities. These exact Vivado 2024.1 definitions are
# verified before mutation. Instance CONFIG.* properties require created BD
# objects and are therefore checked immediately after cell creation below.
require_exact_ipdef $axi_gpio_vlnv {AXI GPIO}
require_exact_ipdef $xlslice_vlnv {XL Slice}

# Lightweight execution identity. Git/source hashes and lifecycle logs remain
# the responsibility of the invoking flow; this patch creates no manifest.
puts "stage1d_execution_identity_begin"
puts "stage1d_source_baseline={$stage1d_source_baseline}"
puts "vivado_version={$vivado_version}"
puts "project_path={$project_path}"
puts "bd_name={$current_bd}"
puts "protection_vlnv={$protection_vlnv}"
puts "axi_gpio_vlnv={$axi_gpio_vlnv}"
puts "xlslice_vlnv={$xlslice_vlnv}"
puts "protection_address={$expected_protection_base} range={$expected_protection_range}"
puts "gpio_planned_address={$planned_gpio_base} range={$planned_gpio_range}"
puts "stage1d_execution_identity_end"

# Mutation failure boundary. Any error stops this block immediately and is
# rethrown with its original Tcl error options. The patch deliberately does not
# close or roll back the project; the invoking flow owns close/exit policy and
# must discard unsaved in-memory changes after failure.
set mutation_status [catch {

# Add Stage 1D cells. This is the first BD mutation.
set gpio [create_bd_cell -type ip -vlnv $axi_gpio_vlnv $gpio_name]
set slice_ch1 [create_bd_cell -type ip -vlnv $xlslice_vlnv $slice_ch1_name]
set slice_ch2 [create_bd_cell -type ip -vlnv $xlslice_vlnv $slice_ch2_name]

assert_property_text $gpio VLNV $axi_gpio_vlnv {AXI GPIO instance identity}
assert_property_text $slice_ch1 VLNV $xlslice_vlnv {CH1 XL Slice instance identity}
assert_property_text $slice_ch2 VLNV $xlslice_vlnv {CH2 XL Slice instance identity}

# Before execution, static review must confirm these property names against the
# Vivado 2024.1 AXI GPIO and XL Slice catalog definitions. Runtime guards below
# stop before property assignment if the installed IP definitions differ.
require_object_properties $gpio [list \
    CONFIG.C_IS_DUAL \
    CONFIG.C_GPIO_WIDTH \
    CONFIG.C_ALL_OUTPUTS \
    CONFIG.C_INTERRUPT_PRESENT \
    CONFIG.C_DOUT_DEFAULT \
] {AXI GPIO configuration}

require_object_properties $slice_ch1 [list \
    CONFIG.DIN_WIDTH \
    CONFIG.DIN_FROM \
    CONFIG.DIN_TO \
    CONFIG.DOUT_WIDTH \
] {CH1 XL Slice configuration}

require_object_properties $slice_ch2 [list \
    CONFIG.DIN_WIDTH \
    CONFIG.DIN_FROM \
    CONFIG.DIN_TO \
    CONFIG.DOUT_WIDTH \
] {CH2 XL Slice configuration}

set_property -dict [list \
    CONFIG.C_IS_DUAL {0} \
    CONFIG.C_GPIO_WIDTH $gpio_width \
    CONFIG.C_ALL_OUTPUTS {1} \
    CONFIG.C_INTERRUPT_PRESENT {0} \
    CONFIG.C_DOUT_DEFAULT $safe_gpio_default \
] $gpio

set_property -dict [list \
    CONFIG.DIN_WIDTH $gpio_width \
    CONFIG.DIN_FROM {11} \
    CONFIG.DIN_TO {0} \
    CONFIG.DOUT_WIDTH {12} \
] $slice_ch1

set_property -dict [list \
    CONFIG.DIN_WIDTH $gpio_width \
    CONFIG.DIN_FROM {23} \
    CONFIG.DIN_TO {12} \
    CONFIG.DOUT_WIDTH {12} \
] $slice_ch2

# Expand SmartConnect while preserving the reviewed protection connection on M00.
set_property -dict [list CONFIG.NUM_SI {1} CONFIG.NUM_MI {2}] $smartconnect
require_bd_intf_pin ${smartconnect_name}/M01_AXI
assert_same_intf_net ${smartconnect_name}/M00_AXI ${protection_name}/S_AXI {post-expand protection remains on M00}

connect_bd_intf_net \
    [get_bd_intf_pins ${smartconnect_name}/M01_AXI] \
    [get_bd_intf_pins ${gpio_name}/S_AXI]

# Use the existing 100 MHz AXI/protection clock and active-low peripheral reset.
connect_bd_net \
    [get_bd_pins ${ps_name}/FCLK_CLK0] \
    [get_bd_pins ${gpio_name}/s_axi_aclk]

connect_bd_net \
    [get_bd_pins ${reset_name}/peripheral_aresetn] \
    [get_bd_pins ${gpio_name}/s_axi_aresetn]

# One 24-bit GPIO output fans out to two slices. Both protection channels are
# therefore updated atomically by one aligned full-width GPIO data write.
connect_bd_net \
    [get_bd_pins ${gpio_name}/gpio_io_o] \
    [get_bd_pins ${slice_ch1_name}/Din] \
    [get_bd_pins ${slice_ch2_name}/Din]

# Preserve the current input nets and their existing protection/ILA sinks.
# Disconnect only the reviewed constant source drivers, then attach slices.
disconnect_bd_net $i_ch1_net [get_bd_pins ${i_ch1_const_name}/dout]
disconnect_bd_net $i_ch2_net [get_bd_pins ${i_ch2_const_name}/dout]

connect_bd_net -net $i_ch1_net [get_bd_pins ${slice_ch1_name}/Dout]
connect_bd_net -net $i_ch2_net [get_bd_pins ${slice_ch2_name}/Dout]

assert_single_scalar_driver $i_ch1_net ${slice_ch1_name}/Dout {i_ch1 Stage 1D source}
assert_single_scalar_driver $i_ch2_net ${slice_ch2_name}/Dout {i_ch2 Stage 1D source}
assert_pin_on_scalar_net ${protection_name}/adc_sample_ch1 $i_ch1_net {adc_sample_ch1 protection sink preserved}
assert_pin_on_scalar_net ${ila_name}/probe2 $i_ch1_net {i_ch1 ILA sink preserved}
assert_pin_on_scalar_net ${protection_name}/adc_sample_ch2 $i_ch2_net {adc_sample_ch2 protection sink preserved}
assert_pin_on_scalar_net ${ila_name}/probe3 $i_ch2_net {i_ch2 ILA sink preserved}

# Delete only the now-disconnected current-code constants. The sample_valid
# constant and its existing net remain, with the constant changed to zero.
assert_cell_output_pins_unconnected $i_ch1_const {i_ch1 constant removal safety}
assert_cell_output_pins_unconnected $i_ch2_const {i_ch2 constant removal safety}
delete_bd_objs $i_ch1_const $i_ch2_const
require_bd_cell_absent $i_ch1_const_name
require_bd_cell_absent $i_ch2_const_name

set_property CONFIG.CONST_VAL {0} $sample_valid_const
assert_property_numeric $sample_valid_const CONFIG.CONST_VAL 0 {sample_valid Stage 1D value}
assert_pin_on_scalar_net ${sample_valid_const_name}/dout $sample_valid_net {sample_valid constant source preserved}
assert_pin_on_scalar_net ${protection_name}/adc_sample_valid $sample_valid_net {adc_sample_valid protection sink preserved}
assert_pin_on_scalar_net ${ila_name}/probe1 $sample_valid_net {sample_valid ILA sink preserved}

# Assign a planning address only. Final execution truth must be confirmed in
# Vivado Address Editor/readback, generated HWH, and Overlay metadata.
set gpio_segment [require_single_addr_seg_for_interface ${gpio_name}/S_AXI]
assign_bd_address \
    -target_address_space $ps_data_space \
    -offset $planned_gpio_base \
    -range $planned_gpio_range \
    $gpio_segment
set gpio_mapped_segment [require_single_mapped_addr_seg $ps_data_space $gpio_name]

# Post-mutation structural assertions.
assert_property_numeric $smartconnect CONFIG.NUM_SI 1 {SmartConnect final input count}
assert_property_numeric $smartconnect CONFIG.NUM_MI 2 {SmartConnect final output count}
assert_same_intf_net ${smartconnect_name}/M00_AXI ${protection_name}/S_AXI {protection final M00 connection}
assert_same_intf_net ${smartconnect_name}/M01_AXI ${gpio_name}/S_AXI {GPIO final M01 connection}

assert_same_scalar_net ${ps_name}/FCLK_CLK0 ${gpio_name}/s_axi_aclk {GPIO clock connection}
assert_same_scalar_net ${reset_name}/peripheral_aresetn ${gpio_name}/s_axi_aresetn {GPIO reset connection}

assert_property_numeric $gpio CONFIG.C_IS_DUAL 0 {GPIO single-channel mode}
assert_property_numeric $gpio CONFIG.C_GPIO_WIDTH $gpio_width {GPIO output width}
assert_property_numeric $gpio CONFIG.C_ALL_OUTPUTS 1 {GPIO output-only mode}
assert_property_numeric $gpio CONFIG.C_INTERRUPT_PRESENT 0 {GPIO interrupt disabled}
assert_property_numeric $gpio CONFIG.C_DOUT_DEFAULT $safe_gpio_default {GPIO safe default word}

assert_property_numeric $slice_ch1 CONFIG.DIN_WIDTH 24 {CH1 slice input width}
assert_property_numeric $slice_ch1 CONFIG.DIN_FROM 11 {CH1 slice high bit}
assert_property_numeric $slice_ch1 CONFIG.DIN_TO 0 {CH1 slice low bit}
assert_property_numeric $slice_ch1 CONFIG.DOUT_WIDTH 12 {CH1 slice output width}

assert_property_numeric $slice_ch2 CONFIG.DIN_WIDTH 24 {CH2 slice input width}
assert_property_numeric $slice_ch2 CONFIG.DIN_FROM 23 {CH2 slice high bit}
assert_property_numeric $slice_ch2 CONFIG.DIN_TO 12 {CH2 slice low bit}
assert_property_numeric $slice_ch2 CONFIG.DOUT_WIDTH 12 {CH2 slice output width}

assert_property_numeric $protection_segment OFFSET $expected_protection_base {protection final address offset}
assert_property_numeric $protection_segment RANGE $expected_protection_range {protection final address range}
assert_property_numeric $gpio_mapped_segment OFFSET $planned_gpio_base {GPIO planning address offset}
assert_property_numeric $gpio_mapped_segment RANGE $planned_gpio_range {GPIO planning address range}

assert_single_scalar_driver $i_ch1_net ${slice_ch1_name}/Dout {i_ch1 final source}
assert_single_scalar_driver $i_ch2_net ${slice_ch2_name}/Dout {i_ch2 final source}
assert_pin_on_scalar_net ${ila_name}/probe2 $i_ch1_net {i_ch1 final ILA sink}
assert_pin_on_scalar_net ${ila_name}/probe3 $i_ch2_net {i_ch2 final ILA sink}
assert_property_numeric $sample_valid_const CONFIG.CONST_VAL 0 {sample_valid final value}
assert_pin_on_scalar_net ${protection_name}/adc_sample_ready $sample_ready_net {adc_sample_ready final evidence source}
assert_pin_on_scalar_net ${ila_name}/probe11 $sample_ready_net {adc_sample_ready final ILA evidence sink}

} mutation_error mutation_options]

if {$mutation_status != 0} {
    puts stderr "Stage 1D BD topology mutation failed: $mutation_error"
    return -options $mutation_options $mutation_error
}

puts "Stage 1D controlled-stimulus topology mutation applied."
puts "BD: $expected_bd_name"
puts "Protection IP: $protection_vlnv on ${smartconnect_name}/M00_AXI"
puts "Stage 1D provider: [get_property VLNV $gpio] on ${smartconnect_name}/M01_AXI"
puts "Stage 1D slices: CH1=[get_property VLNV $slice_ch1] CH2=[get_property VLNV $slice_ch2]"
puts "Packed mapping: GPIO[11:0] -> i_ch1; GPIO[23:12] -> i_ch2"
puts "controlled_stimulus_profile: SAFE_INERT_EXPLICIT"
puts "sample_valid: constant 0; source_acceptance_claimed=0; fault_stimulus_claimed=0"
puts "adc_sample_ready: observed at ${ila_name}/probe11; no transaction acceptance is claimed"
puts "Protection address preserved: base=$expected_protection_base range=$expected_protection_range"
puts "GPIO planning address: base=$planned_gpio_base range=$planned_gpio_range"

# Phase 3-B1 preserves the standalone Tcl error boundary.
#
# Structured PASS/FAIL/BLOCKED mutation result conversion belongs to a later
# migration phase after controller mutation-path integration. This phase
# establishes the procedure boundary while preserving behavior.

}
