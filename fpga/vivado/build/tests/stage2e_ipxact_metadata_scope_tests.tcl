set script_path [file normalize [info script]]
set repository_root [file normalize \
    [file join [file dirname $script_path] .. .. .. ..]]
set package_path [file join $repository_root fpga vivado \
    package_protection_ip_stage2_axi_lite.tcl]
set generated_path [file join $repository_root fpga vivado generated \
    protection_register_map_ipxact.tcl]

namespace eval ::stage2e::ipxact_scope {
    variable negative_passes 0
    variable registers {}
    variable fields {}
    variable parameters {}
    variable properties {}
}
namespace eval ::ipx {}

proc ::stage2e::ipxact_scope::fail {message} {
    error $message
}

proc ::stage2e::ipxact_scope::assert_true {condition message} {
    if {![uplevel 1 [list expr $condition]]} { fail $message }
}

proc ::stage2e::ipxact_scope::read_text {path} {
    set channel [open $path r]
    fconfigure $channel -encoding utf-8 -translation auto
    set value [read $channel]
    close $channel
    return $value
}

proc ::stage2e::ipxact_scope::require_exact_line {text line label} {
    set normalized [string map {\r\n \n \r \n} $text]
    if {[lsearch -exact [split $normalized \n] $line] < 0} {
        fail "$label lacks exact line: $line"
    }
}

proc ::stage2e::ipxact_scope::option_value {arguments option} {
    set index [lsearch -exact $arguments $option]
    if {$index < 0 || $index + 1 >= [llength $arguments]} {
        fail "mock IP-XACT call lacks $option: $arguments"
    }
    return [lindex $arguments [expr {$index + 1}]]
}

proc ::stage2e::ipxact_scope::object_name {arguments} {
    if {[llength $arguments] == 0 || [string match -* [lindex $arguments 0]]} {
        return {}
    }
    return [lindex $arguments 0]
}

proc ::stage2e::ipxact_scope::reset_mock {} {
    variable registers
    variable fields
    variable parameters
    variable properties
    set registers {}
    set fields {}
    set parameters {}
    set properties {}
    catch {rename ::protection_register_map_apply_ipxact {}}
    catch {rename ::stage2e::ipxact_scope::protection_register_map_apply_ipxact {}}
    unset -nocomplain \
        ::PROTECTION_REGISTER_MAP_REGISTER_COUNT \
        ::PROTECTION_REGISTER_MAP_GENERATOR_VERSION \
        ::PROTECTION_REGISTER_MAP_SCHEMA_VERSION \
        ::PROTECTION_REGISTER_MAP_CANONICAL_SHA256
}

proc ::stage2e::ipxact_scope::load_generated_from_procedure {generated} {
    eval $generated
}

proc ::ipx::get_registers {args} {
    set parent [::stage2e::ipxact_scope::option_value $args -of_objects]
    set name [::stage2e::ipxact_scope::object_name $args]
    set records $::stage2e::ipxact_scope::registers
    if {$name ne {}} {
        set key "$parent/$name"
        return [expr {[dict exists $records $key] ? [list [dict get $records $key]] : {}}]
    }
    set result {}
    dict for {key handle} $records {
        if {[string match "$parent/*" $key]} {
            lappend result $handle
        }
    }
    return $result
}

proc ::ipx::add_register {name parent} {
    set key "$parent/$name"
    if {[dict exists $::stage2e::ipxact_scope::registers $key]} {
        error "duplicate mock register: $key"
    }
    set handle "register:$name"
    dict set ::stage2e::ipxact_scope::registers $key $handle
    return $handle
}

proc ::stage2e::ipxact_scope::get_child {records arguments} {
    set parent [option_value $arguments -of_objects]
    set name [object_name $arguments]
    set key "$parent/$name"
    return [expr {[dict exists $records $key] ? [list [dict get $records $key]] : {}}]
}

proc ::stage2e::ipxact_scope::add_child {variable_name kind name parent} {
    upvar 1 $variable_name records
    set key "$parent/$name"
    if {[dict exists $records $key]} {
        error "duplicate mock $kind: $key"
    }
    set handle "$kind:$parent:$name"
    dict set records $key $handle
    return $handle
}

proc ::ipx::get_fields {args} {
    return [::stage2e::ipxact_scope::get_child \
        $::stage2e::ipxact_scope::fields $args]
}

proc ::ipx::add_field {name parent} {
    return [::stage2e::ipxact_scope::add_child \
        ::stage2e::ipxact_scope::fields field $name $parent]
}

proc ::ipx::get_register_parameters {args} {
    return [::stage2e::ipxact_scope::get_child \
        $::stage2e::ipxact_scope::parameters $args]
}

proc ::ipx::add_register_parameter {name parent} {
    return [::stage2e::ipxact_scope::add_child \
        ::stage2e::ipxact_scope::parameters parameter $name $parent]
}

proc ::set_property {property value object} {
    dict set ::stage2e::ipxact_scope::properties $object $property $value
}

proc ::stage2e::ipxact_scope::validate_static {package generated label} {
    assert_true {[info complete $package]} "$label package is not complete Tcl"
    assert_true {[info complete $generated]} "$label generated metadata is not complete Tcl"
    foreach line {
        {set rtl_decode_aperture 0x100}
        {set ip_address_block_range 0x1000}
        {set ip_xact_address_block_metadata PASS}
        {set ip_xact_register_objects GENERATED_FROM_LIVE_REGISTER_MAP}
        {set external_register_map_authority SPEC_REGISTER_MAP_JSON}
        {source $register_map_ipxact}
        {set generated_register_count [protection_register_map_apply_ipxact $address_block]}
        {puts "IP_XACT_REGISTER_COUNT=$generated_register_count"}
    } {
        require_exact_line $package $line $label
    }
    foreach token {
        {proc protection_register_map_apply_ipxact {address_block}}
        {ipx::add_register}
        {ipx::add_field}
        {set_property enumerated_values [list}
        {set ::PROTECTION_REGISTER_MAP_REGISTER_COUNT 33}
    } {
        assert_true {[string first $token $generated] >= 0} \
            "$label generated metadata lacks token: $token"
    }
    foreach forbidden {
        {ipx::get_enumerated_values}
        {ipx::add_enumerated_value}
    } {
        assert_true {[string first $forbidden $generated] < 0} \
            "$label generated metadata uses unsupported Vivado command: $forbidden"
    }
    foreach forbidden {
        {set ip_xact_register_objects NOT_IMPLEMENTED}
        {set external_register_map_authority RTL_DOC_C_HEADER_PYTHON}
    } {
        assert_true {[string first $forbidden $package] < 0} \
            "$label retains obsolete packaging metadata: $forbidden"
    }
    assert_true {![regexp {(^|[^[:alnum:]])[[:alpha:]]:[\\/]} $package]} \
        "$label contains a machine-specific absolute packaging path"
}

proc ::stage2e::ipxact_scope::validate_procedure_scope {generated label} {
    variable registers
    reset_mock
    load_generated_from_procedure $generated
    assert_true {
        [llength [info commands \
            ::stage2e::ipxact_scope::protection_register_map_apply_ipxact]] == 1
    } "$label procedure-scoped generated apply procedure is missing"
    assert_true {[info exists ::PROTECTION_REGISTER_MAP_REGISTER_COUNT]} \
        "$label procedure-scoped register-count constant is not global"
    set count [::stage2e::ipxact_scope::protection_register_map_apply_ipxact \
        address_block:procedure_scope]
    assert_true {$count == $::PROTECTION_REGISTER_MAP_REGISTER_COUNT} \
        "$label procedure-scoped generated count disagrees with its global constant"
    assert_true {[dict size $registers] == 33} \
        "$label procedure-scoped register object count differs"
}

proc ::stage2e::ipxact_scope::validate_mock {generated label} {
    variable registers
    variable fields
    variable parameters
    variable properties
    reset_mock
    uplevel #0 $generated
    assert_true {[llength [info commands ::protection_register_map_apply_ipxact]] == 1} \
        "$label generated apply procedure is missing"
    assert_true {[info exists ::PROTECTION_REGISTER_MAP_REGISTER_COUNT]} \
        "$label generated register-count constant is missing"
    set first_count [::protection_register_map_apply_ipxact address_block:reg0]
    assert_true {$first_count == 33} "$label generated apply count differs"
    assert_true {$first_count == $::PROTECTION_REGISTER_MAP_REGISTER_COUNT} \
        "$label generated count disagrees with its constant"
    assert_true {[dict size $registers] == 33} "$label register object count differs"
    assert_true {[dict size $fields] == 97} "$label field object count differs"
    assert_true {[dict size $parameters] == 33} "$label reset parameter count differs"
    set fault_code_field field:register:FAULT_CODE:FAULT_CODE_LATCHED
    set enumerated_values [dict get $properties $fault_code_field enumerated_values]
    set expected_enumerated_values [list \
        NONE 0x00 read \
        OVERCURRENT 0x01 read \
        SENSOR_MISMATCH 0x02 read \
        SENSOR_OPEN 0x03 read \
        SENSOR_SATURATION 0x04 read \
        SENSOR_STUCK 0x05 read \
        OC_WITH_ANY_SENSOR 0x06 read]
    assert_true {$enumerated_values eq $expected_enumerated_values} \
        "$label fault-code enumeration metadata differs"
    assert_true {[llength $enumerated_values] / 3 == 7} \
        "$label enum value count differs"
    assert_true {[dict get $properties register:CTRL address_offset] eq {0x00}} \
        "$label CTRL offset differs"
    assert_true {[dict get $properties register:OBS_LAST_DESTINATION_SEQUENCE address_offset] eq {0x60}} \
        "$label final legacy offset differs"
    foreach {name offset} {
        REGISTER_MAP_VERSION 0x80
        CAPABILITIES_0 0x84
        CAPABILITIES_1 0x88
        POLICY_STATUS 0xA0
        FIRST_FAULT_BITMAP 0xA4
        LIVE_FAULT_BITMAP 0xA8
        FAULT_SEEN_BITMAP 0xAC
        POLICY_EVALUATION_SEQUENCE 0xB0
    } {
        assert_true {[dict get $properties register:$name address_offset] eq $offset} \
            "$label ABI 1.1 offset differs: $name"
    }

    set one_to_set 0
    set one_to_clear 0
    dict for {object values} $properties {
        if {[dict exists $values modified_write_value]} {
            set behavior [dict get $values modified_write_value]
            if {$behavior eq {oneToSet}} { incr one_to_set }
            if {$behavior eq {oneToClear}} { incr one_to_clear }
        }
    }
    assert_true {$one_to_set == 1} "$label W1P field metadata differs"
    assert_true {$one_to_clear == 9} "$label W1C field metadata differs"

    set inventory_before [list \
        [dict size $registers] [dict size $fields] [dict size $parameters] \
        [dict size $properties]]
    set second_count [::protection_register_map_apply_ipxact address_block:reg0]
    set inventory_after [list \
        [dict size $registers] [dict size $fields] [dict size $parameters] \
        [dict size $properties]]
        assert_true {$second_count == 33} "$label idempotent apply count differs"
    assert_true {$inventory_before eq $inventory_after} \
        "$label idempotent apply duplicated objects"
}

proc ::stage2e::ipxact_scope::expect_rejected {script label} {
    variable negative_passes
    if {![catch {uplevel 1 $script}]} {
        fail "$label unexpectedly passed"
    }
    incr negative_passes
}

proc ::stage2e::ipxact_scope::run {} {
    variable negative_passes
    variable ::package_path
    variable ::generated_path
    set negative_passes 0
    assert_true {[file isfile $package_path]} {Stage 2E package authority is missing}
    assert_true {[file isfile $generated_path]} {Generated IP-XACT metadata is missing}
    set package [read_text $package_path]
    set generated [read_text $generated_path]
    validate_static $package $generated POSITIVE_GENERATED_IPXACT
    validate_mock $generated POSITIVE_GENERATED_IPXACT
    validate_procedure_scope $generated POSITIVE_GENERATED_IPXACT

    foreach {from to label} {
        {set ip_xact_register_objects GENERATED_FROM_LIVE_REGISTER_MAP} {set ip_xact_register_objects NOT_IMPLEMENTED} STALE_REGISTER_OBJECT_AUTHORITY
        {source $register_map_ipxact} {} MISSING_GENERATED_SOURCE
    } {
        set mutant [string map [list $from $to] $package]
        expect_rejected {
            validate_static $mutant $generated $label
        } $label
    }
    foreach {from to label} {
        {set ::PROTECTION_REGISTER_MAP_REGISTER_COUNT 33} {set ::PROTECTION_REGISTER_MAP_REGISTER_COUNT 32} WRONG_REGISTER_COUNT
        {set_property address_offset 0x00 $register} {set_property address_offset 0x64 $register} WRONG_CTRL_OFFSET
        {set_property modified_write_value oneToClear $field} {set_property modified_write_value read-clear $field} WRONG_W1C_BEHAVIOR
        {{NONE} 0x00 read} {{NONE} 0x07 read} WRONG_FAULT_CODE_ENUMERATION
    } {
        set mutant [string map [list $from $to] $generated]
        expect_rejected {
            validate_static $package $mutant $label
            validate_mock $mutant $label
        } $label
    }

    assert_true {$negative_passes == 6} \
        {IP-XACT generated-metadata negative fixture count differs}
    puts {IP_XACT_ADDRESS_BLOCK_METADATA=PASS}
    puts {IP_XACT_REGISTER_OBJECTS=GENERATED_FROM_LIVE_REGISTER_MAP}
    puts {IP_XACT_REGISTER_COUNT=33}
    puts {IP_XACT_FIELD_COUNT=97}
    puts {IP_XACT_ENUM_VALUE_COUNT=7}
    puts {IP_XACT_IDEMPOTENT_APPLY=PASS}
    puts {EXTERNAL_REGISTER_MAP_AUTHORITY=SPEC_REGISTER_MAP_JSON}
    puts {IP_XACT_GENERATED_METADATA_FIXTURES=PASS_6_OF_6}
    puts {STAGE2E_IPXACT_METADATA_SCOPE_TESTS=PASS}
}

if {[file normalize [info script]] eq [file normalize $::argv0]} {
    if {[catch {::stage2e::ipxact_scope::run} message options]} {
        puts stderr "STAGE2E IP-XACT SCOPE TEST FAILED: $message"
        exit 1
    }
}
