# Closed Run2 finding-disposition decision contract v1.
#
# This consumer accepts only canonical UTF-8 JSON parsed by the repository
# canonical codec. The codec rejects duplicate keys before object conversion;
# the schema rejects unknown fields recursively; every mismatch resolves to
# BLOCK. A pending decision never grants runtime activation.

set ::stage1e_finding_decision_v1_dir [file dirname [info script]]
set ::stage1e_finding_decision_v1_build [file dirname $::stage1e_finding_decision_v1_dir]
if {![llength [info commands ::stage1e::canonical_json_v1::parse_canonical]]} {
    source [file join $::stage1e_finding_decision_v1_dir stage1e_runtime_canonical_json_v1.tcl]
}

namespace eval ::stage1e::finding_disposition_decision_contract_v1 {
    variable interface_version stage1e-finding-disposition-decision-contract-interface-v1
    variable build_root $::stage1e_finding_decision_v1_build
}
unset ::stage1e_finding_decision_v1_dir
unset ::stage1e_finding_decision_v1_build

proc ::stage1e::finding_disposition_decision_contract_v1::interface_version {} {
    variable interface_version
    return $interface_version
}

proc ::stage1e::finding_disposition_decision_contract_v1::_raise {code message} {
    return -code error -errorcode [list STAGE1E RUN2 FINDING_DECISION_V1 $code] $message
}

proc ::stage1e::finding_disposition_decision_contract_v1::_build_root {} {
    variable build_root
    return $build_root
}

proc ::stage1e::finding_disposition_decision_contract_v1::_schema_bundle {} {
    set schema_path [file join [_build_root] lib stage1e_run2_finding_disposition_decision_v1.schema.json]
    set bytes [::stage1e::canonical_json_v1::read_file_bytes $schema_path]
    set schema [::stage1e::canonical_json_v1::parse_bytes $bytes]
    return [dict create schema $schema registry [dict create stage1e-run2-finding-disposition-decision-v1 $schema]]
}

proc ::stage1e::finding_disposition_decision_contract_v1::_string {node label} {
    if {[::stage1e::canonical_json_v1::node_type $node] ne {string}} { _raise TYPE "$label must be a string." }
    return [::stage1e::canonical_json_v1::node_value $node]
}

proc ::stage1e::finding_disposition_decision_contract_v1::_integer {node label} {
    if {[::stage1e::canonical_json_v1::node_type $node] ne {integer}} { _raise TYPE "$label must be an integer." }
    return [::stage1e::canonical_json_v1::node_value $node]
}

proc ::stage1e::finding_disposition_decision_contract_v1::_object_get_string {object key} {
    return [_string [::stage1e::canonical_json_v1::object_get $object $key] $key]
}

proc ::stage1e::finding_disposition_decision_contract_v1::_array_strings {node label} {
    if {[::stage1e::canonical_json_v1::node_type $node] ne {array}} { _raise TYPE "$label must be an array." }
    set values {}
    foreach value [::stage1e::canonical_json_v1::array_values $node] { lappend values [_string $value $label] }
    if {[llength [lsort -unique $values]] != [llength $values]} { _raise DUPLICATE_GROUP "$label contains duplicate group identifiers." }
    return $values
}

proc ::stage1e::finding_disposition_decision_contract_v1::_same_list {left right} {
    if {[llength $left] != [llength $right]} { return 0 }
    foreach left_value $left right_value $right {
        if {$left_value ne $right_value} { return 0 }
    }
    return 1
}

proc ::stage1e::finding_disposition_decision_contract_v1::_expected_primary_groups {} {
    return {
        W_RECON_4_921_CDC1 W_RECON_4_921_CDC4 W_RECON_4_921_CDC2 W_RECON_4_921_CDC10 W_RECON_4_921_CDC13
        W_RECON_4_935 W_RECON_4_919 W_RECON_SYNTH_8_7129 W_RECON_BD_41_2384 W_RECON_SYNTH_8_7071
        W_RECON_BD_41_702 W_RECON_SYNTH_8_7023 W_RECON_IP_FLOW_19_2187 W_RECON_SYNTH_8_7080 W_RECON_SYNTH_8_4446
        W_RECON_IP_FLOW_19_11770 W_RECON_IP_FLOW_19_11888 W_RECON_VIVADO_12_7122 W_RECON_IP_FLOW_19_4994
        W_NATIVE_4_921_CDC1 W_NATIVE_4_921_CDC4 W_NATIVE_4_921_CDC2 W_NATIVE_4_921_CDC10 W_NATIVE_4_921_CDC13
        W_NATIVE_4_935 W_NATIVE_4_919 W_NATIVE_TIMING_38_436 W_NATIVE_DEVICE_21_9320 W_NATIVE_DEVICE_21_2174
        DRC_PDCN_1569_DEBUG_HUB DRC_RTSTAT_10_NO_ROUTABLE_LOADS METHODOLOGY_LUTAR_1_DEBUG_FIFO_RESET
        METHODOLOGY_XDCB_5_ILA_LINE72 TE_PROC_SYS_RESET TE_SYSTEM_ILA_ACTIVE TE_SMARTCONNECT_XPM_RESET
        TE_DEBUG_HUB_FALSE_PATH TE_DEBUG_HUB_MAX_DELAY
    }
}

proc ::stage1e::finding_disposition_decision_contract_v1::_expected_conditional_groups {} {
    return {W_RECON_SMARTCONNECT_LOW_AREA W_RECON_SMARTCONNECT_LOW_AREA_ACTION W_RECON_BD_41_1306 TE_SYSTEM_ILA_CONDITIONALLY_EMPTY}
}

proc ::stage1e::finding_disposition_decision_contract_v1::_expected_supplemental_groups {} {
    return {W_READ_ONLY_TIMING_38_164}
}

proc ::stage1e::finding_disposition_decision_contract_v1::_require_equal {expected actual label} {
    if {$expected ne $actual} { _raise MISMATCH "$label differs; contract action is BLOCK." }
}

proc ::stage1e::finding_disposition_decision_contract_v1::_validate_rtstat10 {node} {
    _require_equal 40 [_integer [::stage1e::canonical_json_v1::object_get $node member_count] {RTSTAT-10 member_count}] {RTSTAT-10 member count}
    _require_equal 7e8215e2bdc3ba6e14d7f1c823543b3f11ac873facddf3d7bf872c639f8878e1 \
        [_object_get_string $node membership_sha256] {RTSTAT-10 membership identity}
    set ownership [::stage1e::canonical_json_v1::object_get $node ownership_class_counts]
    foreach {key expected} {debug_hub 19 smartconnect_unused_internal 15 system_ila_unused_internal 6 custom_project_logic 0} {
        _require_equal $expected [_integer [::stage1e::canonical_json_v1::object_get $ownership $key] "RTSTAT-10 ownership $key"] "RTSTAT-10 ownership $key"
    }
    set safety [::stage1e::canonical_json_v1::object_get $node functional_safety_counts]
    foreach {key expected} {functional_protection_net_count 0 functional_axi_net_count 0 functional_clock_net_count 0 functional_reset_net_count 0 required_debug_probe_net_count 0 generated_nonfunctional_no_load_net_count 40} {
        _require_equal $expected [_integer [::stage1e::canonical_json_v1::object_get $safety $key] "RTSTAT-10 safety $key"] "RTSTAT-10 safety $key"
    }
    return 1
}

proc ::stage1e::finding_disposition_decision_contract_v1::_validate_semantics {node candidate_path} {
    _require_equal stage1e-run2-finding-disposition-decision-v1 [_object_get_string $node schema_version] {Decision schema}
    _require_equal FINDING_DISPOSITION_DECISION [_object_get_string $node record_type] {Decision record type}
    _require_equal BLOCK [_object_get_string $node mismatch_action] {Mismatch action}
    set candidate [::stage1e::canonical_json_v1::object_get $node reviewed_candidate]
    _require_equal fpga/vivado/build/config/stage1e_run2_finding_disposition_candidate_v1.json [_object_get_string $candidate path] {Reviewed candidate path}
    _require_equal a86ab2717b2217062221cf2a6096b49d687e7915f36ca39b5fb00969a0119af9 [_object_get_string $candidate sha256] {Reviewed candidate SHA-256}
    _require_equal f02aca5f60502042468eb52050d1ae65e1ac5075 [_object_get_string $candidate source_commit] {Historical evidence commit}
    _require_equal e429457d61b36329dd7d2e8670add15f61682be7 [_object_get_string $candidate source_tree] {Historical evidence tree}
    set candidate_bytes [::stage1e::canonical_json_v1::read_file_bytes $candidate_path]
    _require_equal a86ab2717b2217062221cf2a6096b49d687e7915f36ca39b5fb00969a0119af9 [::stage1e::canonical_json_v1::digest_bytes $candidate_bytes] {Candidate file identity}
    set evidence [::stage1e::canonical_json_v1::object_get $node historical_evidence]
    foreach {key expected} {
        run2_hc_report_sha256 2f9029d1b84293b581d0d9111bb4024bc951d31a207054f1938b7c43dcf075bd
        findings_report_sha256 a681d6dc64102bf29dc3a8c1842156879112b54a15dfc58fdc66477d346b8fcf
        rtstat10_report_sha256 04fe16d2c688bcca1d35c3d8a61725727b245e0394547e6cf5616f82ce35b525
        codex_review_report_sha256 7dcd5b24d774212e1eff6ccb5f62afb8f256307c6ce30b544d844c34561b069e
    } { _require_equal $expected [_object_get_string $evidence $key] "Historical evidence $key" }
    set bundles [::stage1e::canonical_json_v1::object_get $node review_bundles]
    foreach {key expected} {
        run2_hc_sha256 026ff11341b406386dd78903348124a5399c834a4b60d0860e8d5fbb62ca5824
        findings_sha256 2e5de4af60931132586d481203cbc9cf86649ffaab9033a83cc7685691d8fe0f
        rtstat10_sha256 12b1f6dd829000ad5e5806e6ecf593f841e4f1dd59165e47c476adcbde6a5d0a
        codex_review_sha256 12f7c2652c6447fe3b750126c8246c4ecff073b07894eef1cf0a1e3f7bc39128
    } { _require_equal $expected [_object_get_string $bundles $key] "Review bundle $key" }
    set groups [::stage1e::canonical_json_v1::object_get $node group_contract]
    if {![_same_list [_expected_primary_groups] [_array_strings [::stage1e::canonical_json_v1::object_get $groups primary_accepted_group_ids] {Primary group IDs}]]} { _raise GROUP_SUBSTITUTION {Primary accepted group contract differs; action is BLOCK.} }
    if {![_same_list [_expected_conditional_groups] [_array_strings [::stage1e::canonical_json_v1::object_get $groups conditional_group_ids] {Conditional group IDs}]]} { _raise GROUP_SUBSTITUTION {Conditional group contract differs; action is BLOCK.} }
    if {![_same_list [_expected_supplemental_groups] [_array_strings [::stage1e::canonical_json_v1::object_get $groups supplemental_accepted_group_ids] {Supplemental group IDs}]]} { _raise GROUP_SUBSTITUTION {Supplemental group contract differs; action is BLOCK.} }
    if {[llength [_array_strings [::stage1e::canonical_json_v1::object_get $groups blocking_group_ids] {Blocking group IDs}]] != 0} { _raise GROUP_SUBSTITUTION {Blocking groups must remain empty in the reviewed candidate baseline.} }
    _validate_rtstat10 [::stage1e::canonical_json_v1::object_get $groups rtstat10]
    set state [_object_get_string $node decision_state]
    set authority [_object_get_string $node acceptance_authority]
    set activation [::stage1e::canonical_json_v1::object_get $node activation_source]
    set activation_commit [_object_get_string $activation activation_commit]
    set activation_tree [_object_get_string $activation activation_tree]
    set effect [_object_get_string $node activation_effect]
    set reviewer [::stage1e::canonical_json_v1::object_get $node reviewer]
    if {$state eq {PROPOSED_PENDING_HUMAN_ACCEPTANCE}} {
        _require_equal NONE $authority {Pending acceptance authority}
        _require_equal NOT_YET_BOUND $activation_commit {Pending activation commit}
        _require_equal NOT_YET_BOUND $activation_tree {Pending activation tree}
        _require_equal NONE $effect {Pending activation effect}
        _require_equal UNASSIGNED [_object_get_string $reviewer name] {Pending reviewer name}
        _require_equal NONE [_object_get_string $reviewer role] {Pending reviewer role}
    } elseif {$state eq {ACCEPTED_HUMAN_DECISION}} {
        _require_equal NAMED_HUMAN_AUTHORITY $authority {Accepted decision authority}
        if {![regexp {^[0-9a-f]{40}$} $activation_commit] ||
            ![regexp {^[0-9a-f]{40}$} $activation_tree] ||
            $effect ne {PERMIT_POLICY_COMPARISON_ONLY}} {
            _raise ACTIVATION_BINDING {Accepted decision lacks exact activation commit and tree bindings.}
        }
    } else {
        _raise DECISION_STATE {Decision state is outside the closed contract.}
    }
    return $state
}

proc ::stage1e::finding_disposition_decision_contract_v1::read {decision_path candidate_path} {
    set bundle [_schema_bundle]
    set bytes [::stage1e::canonical_json_v1::read_file_bytes $decision_path]
    set node [::stage1e::canonical_json_v1::parse_canonical $bytes [dict get $bundle schema] [dict get $bundle registry]]
    set state [_validate_semantics $node $candidate_path]
    return [dict create node $node state $state whole_record_sha256 [::stage1e::canonical_json_v1::digest_bytes $bytes]]
}

proc ::stage1e::finding_disposition_decision_contract_v1::consume {decision_path candidate_path} {
    if {[catch {read $decision_path $candidate_path} result options]} {
        return [dict create action BLOCK reason $result decision_identity NONE errorcode [dict get $options -errorcode]]
    }
    if {[dict get $result state] ne {ACCEPTED_HUMAN_DECISION}} {
        return [dict create action BLOCK reason PROPOSED_PENDING_HUMAN_ACCEPTANCE decision_identity [dict get $result whole_record_sha256]]
    }
    return [dict create action PROCEED reason ACCEPTED_DECISION_BOUND decision_identity [dict get $result whole_record_sha256]]
}
