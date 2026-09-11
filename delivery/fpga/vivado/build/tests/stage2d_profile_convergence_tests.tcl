namespace eval ::stage2d::profile_convergence {
    variable repo_root [file normalize [file join [file dirname [info script]] .. .. .. ..]]
    variable negative_passes 0
}

proc ::stage2d::profile_convergence::read_text {relative_path} {
    variable repo_root
    set path [file join $repo_root {*}[split $relative_path /]]
    if {![file isfile $path]} {
        error "Required profile authority is missing: $relative_path"
    }
    set channel [open $path r]
    try {
        fconfigure $channel -encoding utf-8 -translation lf
        return [read $channel]
    } finally {
        close $channel
    }
}

proc ::stage2d::profile_convergence::read_dict_file {relative_path} {
    set value [read_text $relative_path]
    if {[catch {dict size $value} reason]} {
        error "Profile authority is not a Tcl dictionary: $relative_path: $reason"
    }
    return $value
}

proc ::stage2d::profile_convergence::assert_true {condition message} {
    if {![uplevel 1 [list expr $condition]]} { error $message }
}

proc ::stage2d::profile_convergence::require_keys {value keys label} {
    foreach key $keys {
        if {![dict exists $value $key]} {
            error "$label omits required field $key"
        }
    }
}

proc ::stage2d::profile_convergence::require_boolean {value label} {
    if {$value ni {0 1}} { error "$label must be a canonical boolean" }
}

proc ::stage2d::profile_convergence::validate_profile_entry {entry label} {
    set required {
        profile profile_class production_authority demo_test_only valid_value
        functional_adc_stimulus valid_source_exists ready_consumed
        no_overwrite_when_ready_low transaction_pulse_bounded
    }
    require_keys $entry $required $label
    foreach key {
        production_authority demo_test_only functional_adc_stimulus
        valid_source_exists ready_consumed no_overwrite_when_ready_low
        transaction_pulse_bounded
    } {
        require_boolean [dict get $entry $key] "$label.$key"
    }
    set valid_value [dict get $entry valid_value]
    if {$valid_value ni {0 1}} { error "$label.valid_value must be zero or one" }
    if {[dict get $entry production_authority] && [dict get $entry demo_test_only]} {
        error "$label cannot be both production and demo/test-only"
    }
    if {![dict get $entry production_authority]} {
        error "$label is an active production entry but is not classified as production"
    }

    set profile [dict get $entry profile]
    set profile_class [dict get $entry profile_class]
    if {$profile_class ni {SAFE_INERT FUNCTIONAL_READY_AWARE}} {
        error "$label uses forbidden or unclassified production profile class $profile_class"
    }
    switch -- $profile_class {
        SAFE_INERT {
            if {$profile ni {SAFE_INERT SAFE_INERT_EXPLICIT}} {
                error "$label SAFE_INERT class has an incompatible implementation profile"
            }
            if {$valid_value != 0 || [dict get $entry functional_adc_stimulus]} {
                error "$label SAFE_INERT profile must hold valid low and cannot claim functional ADC stimulus"
            }
        }
        FUNCTIONAL_READY_AWARE {
            if {$profile ne {FUNCTIONAL_READY_AWARE} ||
                $valid_value != 1 ||
                ![dict get $entry functional_adc_stimulus] ||
                ![dict get $entry valid_source_exists] ||
                ![dict get $entry ready_consumed] ||
                ![dict get $entry no_overwrite_when_ready_low] ||
                ![dict get $entry transaction_pulse_bounded]} {
                error "$label functional profile lacks a source, ready consumption, overwrite protection, or bounded transaction pulse"
            }
        }
    }
    return 1
}

proc ::stage2d::profile_convergence::validate_debug_boundary {entry label} {
    require_keys $entry {
        ready_observation_clock_domain adc_src_clock_domain
        destination_clock_domain clocks_identical_in_current_profile
        acceptance_evidence_scope distinct_clock_debug_policy
        direct_async_ready_observation_as_cdc_proof
    } $label
    if {[dict get $entry ready_observation_clock_domain] ne {ACLK} ||
        [dict get $entry adc_src_clock_domain] ne {FCLK_CLK0} ||
        [dict get $entry destination_clock_domain] ne {FCLK_CLK0} ||
        ![dict get $entry clocks_identical_in_current_profile] ||
        [dict get $entry acceptance_evidence_scope] ne {CURRENT_IDENTICAL_CLOCKS_ONLY} ||
        [dict get $entry distinct_clock_debug_policy] ne
            {SOURCE_DOMAIN_ILA_OR_SYNCHRONIZED_OBSERVATION} ||
        [dict get $entry direct_async_ready_observation_as_cdc_proof]} {
        error "$label does not enforce the current same-clock boundary and future distinct-clock observation policy"
    }
    return 1
}

proc ::stage2d::profile_convergence::extract_assignment {text name label} {
    set pattern [format {^[ \t]*set[ \t]+%s[ \t]+([^#\r\n]+)} $name]
    set matches [regexp -all -inline -line $pattern $text]
    if {[llength $matches] != 2} {
        error "$label must assign $name exactly once"
    }
    return [string trim [lindex $matches 1] " \\t{}"]
}

proc ::stage2d::profile_convergence::json_node_to_native {node} {
    set type [::stage1e::canonical_json_v1::node_type $node]
    set value [::stage1e::canonical_json_v1::node_value $node]
    switch -- $type {
        object {
            set result {}
            foreach {key child} $value {
                dict set result $key [json_node_to_native $child]
            }
            return $result
        }
        array {
            set result {}
            foreach child $value { lappend result [json_node_to_native $child] }
            return $result
        }
        default { return $value }
    }
}

proc ::stage2d::profile_convergence::expect_rejected {script label} {
    variable negative_passes
    if {![catch {uplevel 1 $script}]} {
        error "Negative profile fixture unexpectedly passed: $label"
    }
    incr negative_passes
    puts "$label=PASS"
}

proc ::stage2d::profile_convergence::run {} {
    variable repo_root
    variable negative_passes
    set negative_passes 0

    source [file join $repo_root fpga vivado build lib \
        stage1e_runtime_canonical_json_v1.tcl]
    source [file join $repo_root fpga vivado build runtime runner \
        stage1e_production_vivado_runner_v2.tcl]
    source [file join $repo_root fpga vivado build adapters \
        stage1e_base_design.tcl]

    set bd_text [read_text fpga/vivado/create_pynq_z2_stage2_bd.tcl]
    set bd_entry [dict create \
        profile [extract_assignment $bd_text stage2d_profile {Stage 2 BD}] \
        profile_class [extract_assignment $bd_text stage2d_profile_class {Stage 2 BD}] \
        production_authority [extract_assignment $bd_text stage2d_production_authority {Stage 2 BD}] \
        demo_test_only 0 \
        valid_value [extract_assignment $bd_text sample_valid_const {Stage 2 BD}] \
        functional_adc_stimulus [extract_assignment $bd_text stage2d_functional_adc_stimulus {Stage 2 BD}] \
        valid_source_exists 1 \
        ready_consumed [extract_assignment $bd_text stage2d_ready_aware_producer {Stage 2 BD}] \
        no_overwrite_when_ready_low 0 \
        transaction_pulse_bounded 0]

    set phase2 [read_dict_file \
        fpga/vivado/build/config/stage1e_phase2_synthesis_config_v1.dict]
    set phase_entry [dict get $phase2 reconstruction_policy base_design profile_policy]
    set configured_valid [dict get $phase2 reconstruction_policy base_design \
        cell_policy instances sample_valid_const properties CONFIG.CONST_VAL]
    assert_true {$configured_valid == [dict get $phase_entry valid_value]} \
        {Phase 2 sample-valid cell and declared profile disagree}
    ::stage1e::base_design::_validate_profile_policy $phase_entry

    set runtime_topology [::stage1e::production_vivado_runner_v2::topology_contract]
    set runtime_entry [dict get $runtime_topology controlled_stimulus]
    set runtime_debug [dict get $runtime_topology debug_ready_observation]

    set contract_bytes [::stage1e::canonical_json_v1::read_file_bytes \
        [file join $repo_root fpga vivado build config \
            stage1e_execution_contract_v1.json]]
    set contract [json_node_to_native \
        [::stage1e::canonical_json_v1::parse_bytes $contract_bytes]]
    set contract_entry [dict get $contract topology controlled_stimulus]
    set contract_debug [dict get $contract topology debug_ready_observation]

    set entries [list \
        [list STAGE2_BD $bd_entry] \
        [list PHASE2_BASE_DESIGN $phase_entry] \
        [list PRODUCTION_RUNTIME $runtime_entry] \
        [list EXECUTION_CONTRACT $contract_entry]]
    set unclassified_valid_count 0
    set production_demo_count 0
    foreach record $entries {
        lassign $record label entry
        validate_profile_entry $entry $label
        if {[dict get $entry valid_value] == 1 &&
            [dict get $entry profile_class] ni {SAFE_INERT FUNCTIONAL_READY_AWARE}} {
            incr unclassified_valid_count
        }
        if {[dict get $entry production_authority] &&
            [dict get $entry demo_test_only]} {
            incr production_demo_count
        }
    }
    assert_true {$unclassified_valid_count == 0} \
        {An active production sample-valid source is unclassified}
    assert_true {$production_demo_count == 0} \
        {A demo/test-only profile is referenced by production}
    assert_true {[dict get $bd_entry profile] eq [dict get $phase_entry profile]} \
        {Stage 2 BD and Phase 2 base profile do not converge}
    assert_true {[dict get $runtime_entry profile_class] eq
        [dict get $contract_entry profile_class]} \
        {Runtime and machine-contract profile classes do not converge}
    validate_debug_boundary $runtime_debug {Production runtime debug boundary}
    validate_debug_boundary $contract_debug {Execution-contract debug boundary}
    assert_true {$runtime_debug eq $contract_debug} \
        {Runtime and machine-contract debug observation boundaries differ}

    foreach config_path {
        fpga/vivado/build/config/stage1d_build_config.dict
        fpga/vivado/build/config/stage1e_phase2_synthesis_config_v1.dict
    } {
        set config_text [read_text $config_path]
        assert_true {[regexp -all -line \
            {^[ \t]*fpga/vivado/create_pynq_z2_stage2_bd\.tcl[ \t]*$} \
            $config_text] >= 1} \
            "$config_path does not explicitly reference the classified Stage 2 BD authority"
    }

    foreach documentation_path {
        docs/bringup/stage2_block_design_tcl_note.md
        docs/verification/stage2d_async_adc_atomic_cdc_result.md
        docs/verification/stage2d_review_findings_hardening_result.md
        docs/verification/stage2d_premerge_profile_observability_convergence_result.md
    } {
        set documentation [read_text $documentation_path]
        foreach token {
            SAFE_INERT
            FUNCTIONAL_ADC_STIMULUS=NO
            CURRENT_ADC_SRC_CLK_EQUALS_ACLK=YES
            ACLK_ILA_READY_OBSERVATION_VALID_ONLY_WHILE_CLOCKS_IDENTICAL=YES
            DISTINCT_ADC_CLOCK_REQUIRES_SOURCE_CLOCK_ILA_OR_SYNCHRONIZED_OBSERVATION=YES
            SOURCE_DOMAIN_ILA_OR_SYNCHRONIZED_OBSERVATION
            DIRECT_ASYNC_READY_OBSERVATION_AS_CDC_PROOF=FORBIDDEN
        } {
            assert_true {[string first $token $documentation] >= 0} \
                "$documentation_path omits machine-bound profile/observation token $token"
        }
    }

    set functional_without_ready [dict create \
        profile FUNCTIONAL_READY_AWARE profile_class FUNCTIONAL_READY_AWARE \
        production_authority 1 demo_test_only 0 valid_value 1 \
        functional_adc_stimulus 1 valid_source_exists 1 ready_consumed 0 \
        no_overwrite_when_ready_low 0 transaction_pulse_bounded 0]
    expect_rejected {validate_profile_entry $functional_without_ready \
        NEGATIVE_PRODUCTION_VALID_ONE_WITHOUT_READY} \
        NEGATIVE_PRODUCTION_VALID_ONE_WITHOUT_READY

    set missing_profile [dict remove $phase_entry profile]
    expect_rejected {validate_profile_entry $missing_profile \
        NEGATIVE_MISSING_PROFILE_FIELD} NEGATIVE_MISSING_PROFILE_FIELD

    set unsafe_safe $phase_entry
    dict set unsafe_safe valid_value 1
    expect_rejected {validate_profile_entry $unsafe_safe \
        NEGATIVE_SAFE_PROFILE_VALID_ONE} NEGATIVE_SAFE_PROFILE_VALID_ONE

    set production_demo $phase_entry
    dict set production_demo demo_test_only 1
    expect_rejected {validate_profile_entry $production_demo \
        NEGATIVE_DEMO_REFERENCED_BY_PRODUCTION} \
        NEGATIVE_DEMO_REFERENCED_BY_PRODUCTION

    assert_true {$negative_passes == 4} \
        {Profile convergence negative-fixture count is not four}
    puts {STAGE2_BD_PROFILE=SAFE_INERT}
    puts {SAMPLE_VALID_DEFAULT=0}
    puts {FUNCTIONAL_ADC_STIMULUS=NO}
    puts "UNCLASSIFIED_SAMPLE_VALID_PROFILE_COUNT=$unclassified_valid_count"
    puts "PRODUCTION_DEMO_PROFILE_REFERENCES=$production_demo_count"
    puts {PROFILE_NEGATIVE_FIXTURES=PASS}
    puts {CURRENT_ADC_SRC_CLK_EQUALS_ACLK=YES}
    puts {ACLK_ILA_READY_OBSERVATION_BOUNDARY=DOCUMENTED}
    puts {DISTINCT_CLOCK_DEBUG_POLICY=SOURCE_DOMAIN_ILA_OR_SYNCHRONIZED_OBSERVATION}
    puts {DIRECT_ASYNC_READY_OBSERVATION_AS_CDC_PROOF=FORBIDDEN}
    puts {PROFILE_CONVERGENCE_TESTS=PASS}
}

if {[file normalize [info script]] eq [file normalize $::argv0]} {
    if {[catch {::stage2d::profile_convergence::run} reason options]} {
        puts stderr "STAGE2D PROFILE CONVERGENCE FAILED: $reason"
        exit 1
    }
}
