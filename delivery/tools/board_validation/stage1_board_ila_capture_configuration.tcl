# Runtime capability planning for Stage2I System ILA capture configuration.
#
# This file is read-only. It parses report_property output and builds a
# deterministic property plan without programming, arming, or writing files.

namespace eval ::stage1::capture_config {
    variable allowed_actions {
        SET
        KEEP_EXISTING
        SKIP_READ_ONLY_OPTIONAL
        FAIL_MISSING_REQUIRED
        FAIL_READ_ONLY_REQUIRED
        FAIL_INVALID_VALUE
    }
    variable supported_modes {
        destination_trigger_now
        destination_fault_valid
        destination_fault_latched
        source_trigger_now
        source_stall
        source_accept
    }
}

proc ::stage1::capture_config::capture_mode_core_role {mode} {
    variable supported_modes
    if {[lsearch -exact $supported_modes $mode] < 0} {
        error "Unsupported Stage2I capture mode: $mode"
    }
    if {[string match {destination_*} $mode]} {
        return destination
    }
    return source
}

proc ::stage1::capture_config::capture_modes_for_profile {profile} {
    set roles [::stage1::profile_core_roles $profile]
    set modes [list \
        destination_trigger_now \
        destination_fault_valid \
        destination_fault_latched]
    if {[lsearch -exact $roles source] >= 0} {
        lappend modes source_trigger_now source_stall source_accept
    }
    return $modes
}

proc ::stage1::capture_config::mode_is_trigger_now {mode} {
    capture_mode_core_role $mode
    return [string match {*_trigger_now} $mode]
}

proc ::stage1::capture_config::boolean_value {value label} {
    set normalized [string tolower [string trim $value]]
    if {$normalized in {true 1 yes}} {
        return 1
    }
    if {$normalized in {false 0 no}} {
        return 0
    }
    error "Invalid $label boolean in property report: $value"
}

proc ::stage1::capture_config::parse_property_report {report_text} {
    set catalog [dict create]
    foreach raw_line [split $report_text "\n"] {
        set line [string trim $raw_line]
        if {$line eq {}} {
            continue
        }
        if {![regexp \
                {^(\S+)\s+(\S+)\s+(true|false|0|1)\s+(.*)$} \
                $line -> property type read_only remainder]} {
            continue
        }
        if {[string equal -nocase $property Property]} {
            continue
        }
        set value_tokens [regexp -all -inline {\S+} $remainder]
        if {[llength $value_tokens] == 0} {
            set current_value {}
        } elseif {[llength $value_tokens] >= 2 &&
                  [string tolower [lindex $value_tokens 0]] in
                      {true false 0 1}} {
            set current_value [join [lrange $value_tokens 1 end] { }]
        } else {
            set current_value [join $value_tokens { }]
        }
        if {[dict exists $catalog $property]} {
            error "Duplicate property in runtime report: $property"
        }
        dict set catalog $property [dict create \
            present 1 \
            type $type \
            read_only [boolean_value $read_only {read-only}] \
            current_value $current_value]
    }
    return $catalog
}

proc ::stage1::capture_config::runtime_property_catalog {object} {
    set report_text [report_property -all -return_string $object]
    return [parse_property_report $report_text]
}

proc ::stage1::capture_config::capability_for {catalog property} {
    if {![dict exists $catalog $property]} {
        return [dict create \
            present 0 \
            type {} \
            read_only 0 \
            current_value {<ABSENT>}]
    }
    return [dict get $catalog $property]
}

proc ::stage1::capture_config::values_equal {left right} {
    return [string equal -nocase [string trim $left] [string trim $right]]
}

proc ::stage1::capture_config::property_values_equal {type left right} {
    set normalized_type [string tolower [string trim $type]]
    if {$normalized_type in {bool boolean}} {
        if {[catch {
            boolean_value $left {property value}
        } left_boolean]} {
            return 0
        }
        if {[catch {
            boolean_value $right {property value}
        } right_boolean]} {
            return 0
        }
        return [expr {$left_boolean == $right_boolean}]
    }
    return [values_equal $left $right]
}

proc ::stage1::capture_config::current_is_acceptable {
    type current_value desired accepted_values
} {
    if {$desired eq {} && [llength $accepted_values] == 0} {
        return 1
    }
    if {$desired ne {} &&
        [property_values_equal $type $current_value $desired]} {
        return 1
    }
    foreach accepted $accepted_values {
        if {[property_values_equal $type $current_value $accepted]} {
            return 1
        }
    }
    return 0
}

proc ::stage1::capture_config::plan_property {spec capability} {
    variable allowed_actions
    set required [dict get $spec required]
    set desired [dict get $spec desired]
    set accepted_values [dict get $spec accepted_values]
    set present [dict get $capability present]
    set read_only [dict get $capability read_only]
    set current_value [dict get $capability current_value]
    set type [dict get $capability type]

    if {!$present} {
        if {$required} {
            set action FAIL_MISSING_REQUIRED
        } else {
            set action KEEP_EXISTING
        }
    } elseif {[current_is_acceptable \
            $type $current_value $desired $accepted_values]} {
        set action KEEP_EXISTING
    } elseif {$read_only} {
        if {$required} {
            set action FAIL_READ_ONLY_REQUIRED
        } else {
            set action SKIP_READ_ONLY_OPTIONAL
        }
    } elseif {$desired ne {}} {
        set action SET
    } else {
        set action FAIL_INVALID_VALUE
    }

    if {[lsearch -exact $allowed_actions $action] < 0} {
        error "Internal invalid property action: $action"
    }
    return [dict merge $spec $capability [dict create action $action]]
}

proc ::stage1::capture_config::property_spec {
    core_role scope object property required desired accepted_values
} {
    return [dict create \
        core_role $core_role \
        scope $scope \
        object $object \
        property $property \
        required $required \
        desired $desired \
        accepted_values $accepted_values]
}

proc ::stage1::capture_config::wildcard_compare {width} {
    return "eq${width}'b[string repeat x $width]"
}

proc ::stage1::capture_config::compare_for_mode {profile mode index width} {
    if {[mode_is_trigger_now $mode]} {
        return {}
    }
    switch -- $mode {
        destination_fault_valid {
            set trigger_index [expr {
                $profile eq {SAFE_INERT} ? 6 : 3
            }]
            if {$index == $trigger_index} {
                return {eq1'b1}
            }
        }
        destination_fault_latched {
            set trigger_index [expr {
                $profile eq {SAFE_INERT} ? 7 : 4
            }]
            if {$index == $trigger_index} {
                return {eq1'b1}
            }
        }
        source_stall {
            if {$index == 0} {
                return {eq1'b1}
            }
            if {$index == 1} {
                return {eq1'b0}
            }
        }
        source_accept {
            if {$index == 6} {
                return {eq1'b1}
            }
        }
        default {
            error "Unsupported conditional Stage2I capture mode: $mode"
        }
    }
    return [wildcard_compare $width]
}

proc ::stage1::capture_config::build_plan_from_catalogs {
    profile mode target_object target_catalog ila_object ila_catalog
    probe_map probe_catalogs target_frequency_hz
} {
    set core_role [capture_mode_core_role $mode]
    set contract [::stage1::core_contract $profile $core_role]
    set probe_widths [dict get $contract probe_widths]
    set immediate [mode_is_trigger_now $mode]

    set specs {}
    lappend specs [property_spec \
        $core_role target $target_object PARAM.FREQUENCY \
        1 $target_frequency_hz {}]
    lappend specs [property_spec \
        $core_role ila $ila_object CONTROL.DATA_DEPTH 1 4096 {}]
    lappend specs [property_spec \
        $core_role ila $ila_object CONTROL.TRIGGER_POSITION 1 2048 {}]
    lappend specs [property_spec \
        $core_role ila $ila_object CONTROL.WINDOW_COUNT 1 1 {}]
    lappend specs [property_spec \
        $core_role ila $ila_object CONTROL.CAPTURE_MODE \
        0 {} {ALWAYS BASIC}]

    if {$immediate} {
        lappend specs [property_spec \
            $core_role ila $ila_object CONTROL.TRIGGER_MODE 0 {} {}]
        lappend specs [property_spec \
            $core_role ila $ila_object CONTROL.TRIGGER_CONDITION 0 {} {}]
    } else {
        lappend specs [property_spec \
            $core_role ila $ila_object CONTROL.TRIGGER_MODE \
            1 BASIC_ONLY {}]
        lappend specs [property_spec \
            $core_role ila $ila_object CONTROL.TRIGGER_CONDITION 1 AND {}]
    }

    foreach {index width} $probe_widths {
        if {![dict exists $probe_map $index]} {
            error "Configuration plan is missing $core_role probe$index"
        }
        if {![dict exists $probe_catalogs $index]} {
            error "Configuration plan is missing $core_role probe$index report"
        }
        set probe [dict get $probe_map $index]
        set scope "probe$index"
        lappend specs [property_spec \
            $core_role $scope $probe DISPLAY_RADIX 1 BINARY {}]
        lappend specs [property_spec \
            $core_role $scope $probe DISPLAY_AS_ENUM 1 false {}]
        if {$immediate} {
            lappend specs [property_spec \
                $core_role $scope $probe \
                TRIGGER_COMPARE_VALUE 0 {} {}]
        } else {
            lappend specs [property_spec \
                $core_role $scope $probe TRIGGER_COMPARE_VALUE 1 \
                [compare_for_mode $profile $mode $index $width] {}]
        }
    }

    set plan {}
    foreach spec $specs {
        set scope [dict get $spec scope]
        set property [dict get $spec property]
        if {$scope eq {target}} {
            set catalog $target_catalog
        } elseif {$scope eq {ila}} {
            set catalog $ila_catalog
        } elseif {[regexp {^probe([0-9]+)$} $scope -> index]} {
            set catalog [dict get $probe_catalogs $index]
        } else {
            error "Invalid property-plan scope: $scope"
        }
        lappend plan [plan_property \
            $spec [capability_for $catalog $property]]
    }
    return $plan
}

proc ::stage1::capture_config::build_runtime_plan {
    profile mode target ila probe_map target_frequency_hz
} {
    set core_role [capture_mode_core_role $mode]
    set contract [::stage1::core_contract $profile $core_role]
    set target_catalog [runtime_property_catalog $target]
    set ila_catalog [runtime_property_catalog $ila]
    set probe_catalogs [dict create]
    foreach {index width} [dict get $contract probe_widths] {
        set probe [dict get $probe_map $index]
        dict set probe_catalogs $index [runtime_property_catalog $probe]
    }
    return [build_plan_from_catalogs \
        $profile $mode $target $target_catalog $ila $ila_catalog \
        $probe_map $probe_catalogs $target_frequency_hz]
}

proc ::stage1::capture_config::log_plan {mode plan} {
    foreach item $plan {
        puts "STAGE2I_ILA_PROPERTY_CONTEXT=mode=$mode core_role=[dict get $item core_role] scope=[dict get $item scope] object=[dict get $item object]"
        puts "STAGE2I_ILA_PROPERTY_NAME=[dict get $item property]"
        puts "STAGE2I_ILA_PROPERTY_PRESENT=[dict get $item present]"
        puts "STAGE2I_ILA_PROPERTY_READ_ONLY=[dict get $item read_only]"
        puts "STAGE2I_ILA_PROPERTY_CURRENT_VALUE=[dict get $item current_value]"
        puts "STAGE2I_ILA_PROPERTY_REQUIRED=[dict get $item required]"
        puts "STAGE2I_ILA_PROPERTY_ACTION=[dict get $item action]"
    }
}

proc ::stage1::capture_config::validate_plan {plan} {
    foreach item $plan {
        set action [dict get $item action]
        if {[string match {FAIL_*} $action]} {
            error "ILA property plan rejected [dict get $item core_role] [dict get $item scope] [dict get $item property]: action=$action current=[dict get $item current_value] desired=[dict get $item desired]"
        }
    }
    return $plan
}

proc ::stage1::capture_config::plan_signature {plan} {
    set rows {}
    foreach item $plan {
        lappend rows [join [list \
            [dict get $item core_role] \
            [dict get $item scope] \
            [dict get $item property] \
            [dict get $item present] \
            [dict get $item read_only] \
            [dict get $item current_value] \
            [dict get $item required] \
            [dict get $item desired] \
            [dict get $item action]] {|}]
    }
    return [join $rows "\n"]
}
