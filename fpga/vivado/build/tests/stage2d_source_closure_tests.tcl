namespace eval ::stage2d::source_closure {
    variable repo_root [file normalize [file join [file dirname [info script]] .. .. .. ..]]
    variable failures 0
}

proc ::stage2d::source_closure::read_text {relative_path} {
    variable repo_root
    set path [file join $repo_root {*}[split $relative_path /]]
    if {![file isfile $path]} {
        error "Required file is missing: $relative_path"
    }
    set channel [open $path r]
    try {
        return [read $channel]
    } finally {
        close $channel
    }
}

proc ::stage2d::source_closure::read_dict_file {relative_path} {
    set value [read_text $relative_path]
    if {[catch {dict size $value} message]} {
        error "Not a valid Tcl dictionary: $relative_path: $message"
    }
    return $value
}

proc ::stage2d::source_closure::assert_true {condition message} {
    if {![uplevel 1 [list expr $condition]]} {
        error $message
    }
}

proc ::stage2d::source_closure::assert_path_once {values path label} {
    set count [llength [lsearch -all -exact $values $path]]
    if {$count != 1} {
        error "$label must contain $path exactly once; actual=$count"
    }
}

proc ::stage2d::source_closure::validate_rtl_authority {values label} {
    foreach path {
        rtl/adc_sample_cdc_bridge.v
        rtl/adc_sample_code_normalizer.sv
        rtl/async_fifo_gray.v
        rtl/generated/stage2f_adc_source_profile.svh
        rtl/protection_ip_top_async_adc_axi_lite.v
        rtl/protection_ip_top_axi_lite.v
        rtl/reset_release_sync.v
    } {
        assert_path_once $values $path $label
    }
}

proc ::stage2d::source_closure::validate_cdc_constraint_authority {values label} {
    assert_path_once $values \
        fpga/vivado/constraints/stage2d_async_adc_atomic_cdc.xdc $label
}

proc ::stage2d::source_closure::expect_rejected {script label} {
    if {![catch {uplevel 1 $script} message]} {
        error "Negative source-closure fixture unexpectedly passed: $label"
    }
    puts "$label=PASS"
}

proc ::stage2d::source_closure::remove_exact {values path} {
    set index [lsearch -exact $values $path]
    if {$index < 0} {
        error "Negative fixture cannot remove absent path: $path"
    }
    return [lreplace $values $index $index]
}

proc ::stage2d::source_closure::run {} {
    set phase2 [read_dict_file \
        fpga/vivado/build/config/stage1e_phase2_synthesis_config_v1.dict]
    set stage1d [read_dict_file \
        fpga/vivado/build/config/stage1d_build_config.dict]

    set phase2_authorities {
        {source_verification required_paths}
        {environment custom_protection_ip source_paths}
        {reconstruction_policy packaging source_paths}
        {reconstruction_policy packaging package_inventory source_paths}
    }
    foreach key_path $phase2_authorities {
        validate_rtl_authority [dict get $phase2 {*}$key_path] \
            "Phase 2 $key_path"
    }
    validate_cdc_constraint_authority \
        [dict get $phase2 source_verification required_paths] \
        {Phase 2 required paths}
    validate_cdc_constraint_authority \
        [dict get $phase2 reconstruction_policy packaging package_inventory \
            constraint_paths] \
        {Phase 2 package constraint paths}
    foreach key_path {
        {source_verification required_paths}
        {environment custom_protection_ip source_paths}
    } {
        validate_rtl_authority [dict get $stage1d {*}$key_path] \
            "Stage 1D $key_path"
    }
    validate_cdc_constraint_authority \
        [dict get $stage1d source_verification required_paths] \
        {Stage 1D required paths}
    foreach config [list $phase2 $stage1d] label {Phase2 Stage1D} {
        foreach key {required_paths tcl_paths} {
            assert_path_once [dict get $config source_verification $key] \
                fpga/vivado/build/tests/stage2d_profile_convergence_tests.tcl \
                "$label $key"
        }
    }

    assert_true \
        {[dict get $phase2 reconstruction_policy packaging package_inventory top_module] eq
         "protection_ip_top_async_adc_axi_lite"} \
        {Production package inventory still names the synchronous internal top}
    assert_true \
        {[dict get $phase2 reconstruction_policy packaging package_inventory user_parameters ADC_FIFO_ADDR_WIDTH] == 3} \
        {Production package inventory omits the FIFO depth parameter}
    assert_true \
        {[dict get $phase2 reconstruction_policy packaging vlnv_expectation version] eq {0.3} &&
         [dict get $phase2 environment custom_protection_ip vlnv] eq
            {zsr112.local:protection:protection_ip_axi_lite:0.3}} \
        {Production IP interface is not consistently versioned as 0.3}
    set clock_sinks [dict get $phase2 reconstruction_policy base_design clock_policy sinks]
    assert_path_once $clock_sinks \
        protection_ip_axi_lite_0/adc_src_clk \
        {Production base-design clock sinks}

    set production_wrapper [read_text rtl/protection_ip_top_async_adc_axi_lite.v]
    # Stage 2G selects metadata-aware companion modules in the production
    # path while retaining the exact legacy module definitions/ports for the
    # Stage 2D-2F compatibility surface.
    foreach module {
        reset_release_sync
        stage2g_adc_sample_cdc_bridge
        stage2g_protection_ip_axi_lite
    } {
        assert_true [regexp "\\m${module}\\M" $production_wrapper] \
            "Production wrapper no longer instantiates $module"
    }
    set bridge [read_text rtl/adc_sample_cdc_bridge.v]
    set destination_top [read_text rtl/protection_ip_top_axi_lite.v]
    assert_true [regexp {\mmodule[ \t\r\n]+adc_sample_cdc_bridge\M} $bridge] \
        {Legacy adc_sample_cdc_bridge definition was removed}
    assert_true [regexp {\mmodule[ \t\r\n]+protection_ip_top_axi_lite\M} $destination_top] \
        {Legacy protection_ip_top_axi_lite definition was removed}
    assert_true [regexp {\masync_fifo_gray\M} $bridge] \
        {Parameterized bridge no longer instantiates async_fifo_gray}
    assert_true [regexp {fifo_read_enable[ \t]*=[^;]*dst_ready[^;]*![ \t]*fifo_empty} $bridge] \
        {Destination delivery is no longer gated by ready and nonempty}
    assert_true [regexp {dst_sample_valid[ \t]*=[ \t]*dst_ready[ \t]*&&[ \t]*destination_valid} $bridge] \
        {Destination delivery no longer uses the registered elastic-buffer valid}
    foreach guard {
        STAGE2D_PARAMETER_ERROR_DATA_WIDTH_MUST_BE_AT_LEAST_1
        STAGE2D_PARAMETER_ERROR_FIFO_ADDR_WIDTH_MUST_BE_AT_LEAST_2
    } {
        assert_true [regexp $guard $bridge] \
            "ADC bridge omits elaboration guard $guard"
    }
    set fifo [read_text rtl/async_fifo_gray.v]
    foreach guard {
        STAGE2D_PARAMETER_ERROR_DATA_WIDTH_MUST_BE_AT_LEAST_1
        STAGE2D_PARAMETER_ERROR_FIFO_ADDR_WIDTH_MUST_BE_AT_LEAST_2
    } {
        assert_true [regexp $guard $fifo] \
            "Asynchronous FIFO omits elaboration guard $guard"
    }
    assert_true [regexp {KEEP = "TRUE"[ \t]*\*\)[ \t\r\n]+reg[ \t]+\[PAYLOAD_WIDTH-1:0\][ \t]+destination_data} $bridge] \
        {Destination payload register is not explicitly preserved}
    assert_true [regexp {destination_data[ \t]*<=[^;]*fifo_read_data} $bridge] \
        {Destination payload register no longer captures FIFO data}
    assert_true [regexp {else[ \t]+if[ \t]*\([ \t]*dst_ready[ \t]*\)} $bridge] \
        {Destination payload does not hold while stalled}
    assert_true [regexp \
        {assign[ \t]+local_resetn[ \t]*=[ \t]*local_rst_n} \
        $destination_top] \
        {Destination bridge reset is not the Stage 2C local reset}
    assert_true [regexp \
        {\.dst_rst_n\(adc_dst_local_rst_n\)} \
        $production_wrapper] \
        {FIFO destination side is not driven by the destination local reset}
    assert_true [regexp \
        {\.local_resetn\(adc_dst_local_rst_n\)} \
        $production_wrapper] \
        {Production wrapper does not export the Stage 2C local reset to the FIFO}

    variable repo_root
    source [file join $repo_root fpga vivado build adapters \
        stage1e_ip_packaging.tcl]
    set package_inventory \
        [::stage1e::ip_packaging::_validate_package_inventory \
            [dict get $phase2 reconstruction_policy packaging \
                package_inventory]]
    set dependency_closure \
        [::stage1e::ip_packaging::_validate_top_dependency_closure \
            $repo_root $package_inventory]
    assert_true \
        {[dict get $dependency_closure direct_dependencies] eq
         {adc_sample_code_normalizer reset_release_sync source_observability_cdc stage2g_adc_sample_cdc_bridge stage2g_protection_ip_axi_lite transaction_destination_observer}} \
        {Controlled packaging dependency closure does not match the Stage 2G production top}

    foreach direct_authority {
        fpga/vivado/package_protection_ip_stage2_axi_lite.tcl
        fpga/vivado/create_pynq_z2_project_stage1_boardpart.tcl
        fpga/vivado/create_pynq_z2_project_preboard.tcl
        fpga/vivado/build/runtime/runner/stage1e_production_vivado_runner_v2.tcl
    } {
        set text [read_text $direct_authority]
        assert_true [info complete $text] \
            "$direct_authority is not a complete Tcl script"
        foreach basename {
            adc_sample_cdc_bridge.v
            adc_sample_code_normalizer.sv
            async_fifo_gray.v
            stage2f_adc_source_profile.svh
            protection_ip_top_async_adc_axi_lite.v
        } {
            assert_true [regexp [regsub -all {\.} $basename {\.}] $text] \
                "$direct_authority omits $basename"
        }
        assert_true [regexp {protection_ip_top_async_adc_axi_lite} $text] \
            "$direct_authority omits the production top authority"
        assert_true [regexp {stage2d_async_adc_atomic_cdc\.xdc} $text] \
            "$direct_authority omits the Stage 2D CDC constraint authority"
    }

    set canonical [dict get $phase2 environment custom_protection_ip source_paths]
    set missing_top [remove_exact $canonical \
        rtl/protection_ip_top_async_adc_axi_lite.v]
    expect_rejected {validate_rtl_authority $missing_top NEGATIVE_TOP_OMISSION} \
        NEGATIVE_TOP_INSTANTIATED_SOURCE_OMISSION

    set missing_fifo [remove_exact $canonical rtl/async_fifo_gray.v]
    expect_rejected {validate_rtl_authority $missing_fifo NEGATIVE_FIFO_OMISSION} \
        NEGATIVE_PARAMETERIZED_SUBMODULE_OMISSION

    set config_missing_bridge [remove_exact \
        [dict get $phase2 reconstruction_policy packaging source_paths] \
        rtl/adc_sample_cdc_bridge.v]
    expect_rejected {
        validate_rtl_authority $config_missing_bridge NEGATIVE_CONFIG_OMISSION
    } NEGATIVE_DIRECT_TCL_ONLY_UPDATE

    set missing_constraint [remove_exact \
        [dict get $phase2 reconstruction_policy packaging package_inventory \
            constraint_paths] \
        fpga/vivado/constraints/stage2d_async_adc_atomic_cdc.xdc]
    expect_rejected {
        validate_cdc_constraint_authority $missing_constraint \
            NEGATIVE_CDC_CONSTRAINT_OMISSION
    } NEGATIVE_CDC_CONSTRAINT_OMISSION

    set simulation_only {
        rtl/adc_sample_cdc_bridge.v
        rtl/async_fifo_gray.v
        rtl/protection_ip_top_async_adc_axi_lite.v
    }
    expect_rejected {
        validate_rtl_authority $simulation_only NEGATIVE_SIMULATION_ONLY
    } NEGATIVE_SIMULATION_ONLY_UPDATE

    puts {PRODUCTION_DIRECT_SOURCE_LISTS=PASS}
    puts {PRODUCTION_CONFIG_SOURCE_AUTHORITIES=PASS}
    puts {PARAMETERIZED_RTL_DEPENDENCY_CLOSURE=PASS}
    puts {CONTROLLED_BUILD_SOURCE_CLOSURE=PASS}
    puts {CDC_CONSTRAINT_PRODUCTION_CLOSURE=PASS}
    puts {IP_INTERFACE_VERSIONING=PASS}
    puts {FIFO_PARAMETER_GUARD_SOURCE_CLOSURE=PASS}
    puts {STAGE2D_SOURCE_CLOSURE_TESTS=PASS}
}

if {[file normalize [info script]] eq [file normalize $::argv0]} {
    if {[catch {::stage2d::source_closure::run} message options]} {
        puts stderr "STAGE2D SOURCE CLOSURE FAILED: $message"
        exit 1
    }
}
