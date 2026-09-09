# Stage 1E PRT03 structural connection for the accepted PRT02-E Tcl ledger
# validator. It exposes graph projections and fixture-only validation without
# claiming that a live Vivado or post-process ledger exists.

namespace eval ::stage1e::connected_tcl_assembly_projection_v1 {
    variable interface_version \
        stage1e-connected-tcl-assembly-projection-interface-v1
    variable module_dir [file dirname [file normalize [info script]]]
    variable build_root [file normalize [file join $module_dir ../..]]
    variable accepted_ledger_interface \
        stage1e-runtime-assembly-ledger-interface-v1
}

source [file join $::stage1e::connected_tcl_assembly_projection_v1::module_dir \
    stage1e_runtime_assembly_ledger_v1.tcl]
if {[::stage1e::runtime_assembly_ledger_v1::interface_version] ne \
        $::stage1e::connected_tcl_assembly_projection_v1::accepted_ledger_interface} {
    error {Accepted PRT02-E Tcl ledger interface differs.}
}

proc ::stage1e::connected_tcl_assembly_projection_v1::interface_version {} {
    variable interface_version
    return $interface_version
}

proc ::stage1e::connected_tcl_assembly_projection_v1::_read_utf8 {path} {
    set channel [open $path rb]
    fconfigure $channel -translation binary -encoding binary
    try { set bytes [read $channel] } finally { close $channel }
    if {[string range $bytes 0 2] eq "\xef\xbb\xbf"} {
        return -code error -errorcode {STAGE1E PRT03 ACTIVATION BOM} \
            {Activation contract contains a UTF-8 BOM.}
    }
    if {[catch {encoding convertfrom utf-8 $bytes} text]} {
        return -code error -errorcode {STAGE1E PRT03 ACTIVATION UTF8} \
            {Activation contract is not strict UTF-8.}
    }
    return $text
}

proc ::stage1e::connected_tcl_assembly_projection_v1::activation_contract_state {} {
    variable build_root
    set path [file join $build_root config \
        stage1e_runtime_activation_contract_v1.dict]
    set text [_read_utf8 $path]
    set contract [::stage1e::runtime_assembly_ledger_v1::_strict_dict \
        [string trim $text] {activation contract}]
    if {[dict get $contract schema_version] ne \
            {stage1e-runtime-activation-contract-v1} ||
        [dict get $contract interface_version] ne \
            {stage1e-runtime-activation-contract-interface-v1} ||
        [dict get $contract contract_state] ne \
            {PRT03_ACTIVATION_TARGET_DECLARED}} {
        return -code error -errorcode {STAGE1E PRT03 ACTIVATION CONTRACT} \
            {Activation contract identity or state differs.}
    }
    set graph_path [file join $build_root config \
        stage1e_runtime_activation_graph_v1.dict]
    set graph [::stage1e::runtime_assembly_ledger_v1::_strict_dict \
        [string trim [_read_utf8 $graph_path]] {PRT03 activation graph}]
    if {[dict get $graph schema_version] ne \
            {stage1e-prt03-activation-graph-v1} ||
        [dict get $graph interface_version] ne \
            {stage1e-prt03-activation-graph-interface-v1} ||
        [dict get $graph graph_state] ne {PRT03_ACTIVATION_GRAPH_DECLARED}} {
        return -code error -errorcode {STAGE1E PRT03 ACTIVATION GRAPH} \
            {PRT03 activation graph identity or state differs.}
    }
    return [dict create \
        contract_state PRT03_ACTIVATION_TARGET_DECLARED \
        graph_state PRT03_ACTIVATION_GRAPH_DECLARED \
        target_capability_state PRODUCTION_IMPLEMENTED \
        capability_candidate NOT_DERIVED_IN_TCL_PROJECTION \
        review_state REVIEW_REQUIRED \
        final_closure_state FINAL_TOOL_BOUND_PRE_DISPATCH_CLOSURE_NOT_PROVEN]
}

proc ::stage1e::connected_tcl_assembly_projection_v1::expected_projection {
    ledger_type
} {
    if {$ledger_type ni {VIVADO_ASSEMBLY_LEDGER \
            POSTPROCESS_ASSEMBLY_LEDGER}} {
        return -code error -errorcode {STAGE1E PRT03 PROJECTION TYPE} \
            {Only Vivado and post-process projections are structurally connected.}
    }
    return [::stage1e::runtime_assembly_ledger_v1::graph_projection \
        $ledger_type]
}

proc ::stage1e::connected_tcl_assembly_projection_v1::live_projection_state {} {
    set vivado [expected_projection VIVADO_ASSEMBLY_LEDGER]
    set postprocess [expected_projection POSTPROCESS_ASSEMBLY_LEDGER]
    return [dict create \
        vivado_structural_state VIVADO_VALIDATOR_STRUCTURALLY_CONNECTED \
        vivado_expected_record_count [llength $vivado] \
        vivado_live_ledger_state VIVADO_PRE_DISPATCH_LEDGER_NOT_AVAILABLE \
        postprocess_structural_state \
            POSTPROCESS_VALIDATOR_STRUCTURALLY_CONNECTED \
        postprocess_expected_record_count [llength $postprocess] \
        postprocess_live_ledger_state \
            POSTPROCESS_PRE_DISPATCH_LEDGER_NOT_AVAILABLE \
        final_closure_state FINAL_TOOL_BOUND_PRE_DISPATCH_CLOSURE_NOT_PROVEN]
}

proc ::stage1e::connected_tcl_assembly_projection_v1::validate_fixture_ledger {
    ledger_type ledger_path receipt_path request_identity execution_id \
    attempt_id source_identity
} {
    set result [::stage1e::runtime_assembly_ledger_v1::validate \
        $ledger_type $ledger_path $receipt_path $request_identity \
        $execution_id $attempt_id $source_identity]
    dict set result evidence_class FIXTURE_ONLY
    dict set result production_observation_effect NONE
    dict set result live_ledger_availability NOT_CREATED_BY_FIXTURE
    return $result
}
