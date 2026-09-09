# Stage 1E request/result/failure schema consumer v1.

source [file join [file dirname [info script]] \
    stage1e_runtime_canonical_json_v1.tcl]

namespace eval ::stage1e::envelope_contract_v1 {
    variable interface_version stage1e-runtime-envelope-contract-interface-v1
    variable module_root [file dirname [file normalize [info script]]]
    variable supported_keywords {
        {$schema} {$id} title {$ref} {$defs}
        type required additionalProperties x-stage1e-canonical-order properties
        oneOf const enum minimum maximum minLength maxLength
        items minItems maxItems uniqueItems x-stage1e-format
    }
}

proc ::stage1e::envelope_contract_v1::interface_version {} {
    variable interface_version
    return $interface_version
}

proc ::stage1e::envelope_contract_v1::assert_string_array {
    node label {unique 0}
} {
    set values [::stage1e::canonical_json_v1::array_values $node]
    set seen {}
    foreach value_node $values {
        if {[::stage1e::canonical_json_v1::node_type $value_node] ne {string}} {
            error "$label must contain strings."
        }
        set value [::stage1e::canonical_json_v1::node_value $value_node]
        if {$value eq {}} { error "$label must contain nonempty strings." }
        if {$unique && [dict exists $seen $value]} {
            error "$label contains duplicate value '$value'."
        }
        dict set seen $value 1
    }
    return $seen
}

proc ::stage1e::envelope_contract_v1::assert_meta_node {node path} {
    variable supported_keywords
    foreach key [::stage1e::canonical_json_v1::object_keys $node] {
        if {[lsearch -exact $supported_keywords $key] < 0} {
            error "Unsupported schema keyword '$key' at $path."
        }
    }
    if {[::stage1e::canonical_json_v1::object_has $node type]} {
        set type [::stage1e::canonical_json_v1::node_value \
            [::stage1e::canonical_json_v1::object_get $node type]]
        if {$type ni {object array string integer boolean}} {
            error "Unsupported schema type '$type' at $path."
        }
        if {$type eq {object}} {
            foreach keyword {
                properties required additionalProperties x-stage1e-canonical-order
            } {
                if {![::stage1e::canonical_json_v1::object_has $node $keyword]} {
                    error "Exact object schema at $path lacks '$keyword'."
                }
            }
            if {[::stage1e::canonical_json_v1::node_value \
                    [::stage1e::canonical_json_v1::object_get \
                        $node additionalProperties]]} {
                error "Object schema at $path is not exact-field closed."
            }
            set properties [::stage1e::canonical_json_v1::object_get \
                $node properties]
            set required [assert_string_array \
                [::stage1e::canonical_json_v1::object_get $node required] \
                "$path.required" 1]
            set order [assert_string_array \
                [::stage1e::canonical_json_v1::object_get \
                    $node x-stage1e-canonical-order] \
                "$path.x-stage1e-canonical-order" 1]
            set property_names \
                [::stage1e::canonical_json_v1::object_keys $properties]
            if {[dict size $required] != [llength $property_names] ||
                    [dict size $order] != [llength $property_names]} {
                error "Object schema at $path has incomplete field metadata."
            }
            foreach property $property_names {
                if {![dict exists $required $property] ||
                        ![dict exists $order $property]} {
                    error "Object schema at $path does not require/order '$property'."
                }
                assert_meta_node \
                    [::stage1e::canonical_json_v1::object_get $properties $property] \
                    "$path.properties.$property"
            }
        } elseif {$type eq {array} &&
                [::stage1e::canonical_json_v1::object_has $node items]} {
            assert_meta_node \
                [::stage1e::canonical_json_v1::object_get $node items] \
                "$path.items"
        }
    }
    if {[::stage1e::canonical_json_v1::object_has $node oneOf]} {
        set branches [::stage1e::canonical_json_v1::array_values \
            [::stage1e::canonical_json_v1::object_get $node oneOf]]
        if {[llength $branches] < 2} {
            error "oneOf at $path must contain at least two branches."
        }
        set index 0
        foreach branch $branches {
            assert_meta_node $branch "$path.oneOf\[$index\]"
            incr index
        }
    }
    if {[::stage1e::canonical_json_v1::object_has $node {$defs}]} {
        set definitions \
            [::stage1e::canonical_json_v1::object_get $node {$defs}]
        foreach name [::stage1e::canonical_json_v1::object_keys $definitions] {
            assert_meta_node \
                [::stage1e::canonical_json_v1::object_get $definitions $name] \
                "$path.\$defs.$name"
        }
    }
}

proc ::stage1e::envelope_contract_v1::load {{schema_root {}}} {
    variable interface_version
    variable module_root
    if {$schema_root eq {}} { set schema_root $module_root }
    set schema_root [file normalize $schema_root]
    set specifications {
        failure stage1e_runtime_failure_record_v1.schema.json
            stage1e-runtime-failure-record-v1
        request stage1e_runtime_request_envelope_v1.schema.json
            stage1e-production-runtime-request-envelope-v1
        result stage1e_runtime_result_envelope_v1.schema.json
            stage1e-production-runtime-result-envelope-v1
    }
    set registry {}
    set contract [dict create interface_version $interface_version]
    foreach {role filename expected_id} $specifications {
        set path [file join $schema_root $filename]
        if {![file exists $path] || ![file isfile $path]} {
            return -code error -errorcode {STAGE1E SCHEMA MISSING} \
                "Required Stage 1E schema is missing: $path"
        }
        set bytes [::stage1e::canonical_json_v1::read_file_bytes $path]
        set schema [::stage1e::canonical_json_v1::parse_bytes $bytes]
        assert_meta_node $schema {$}
        if {[::stage1e::canonical_json_v1::node_value \
                [::stage1e::canonical_json_v1::object_get $schema {$schema}]] ne \
                {stage1e-schema-subset-v1}} {
            error "Schema subset version mismatch in $path."
        }
        set observed_id [::stage1e::canonical_json_v1::node_value \
            [::stage1e::canonical_json_v1::object_get $schema {$id}]]
        if {$observed_id ne $expected_id} {
            error "Schema identity mismatch in $path."
        }
        if {[dict exists $registry $expected_id]} {
            error "Duplicate schema identity '$expected_id'."
        }
        dict set registry $expected_id $schema
        dict set contract "${role}_schema" $schema
        dict set contract schema_paths $role [file normalize $path]
    }
    dict set contract schema_registry $registry
    return $contract
}

proc ::stage1e::envelope_contract_v1::copy_without_identity {
    record schema identity_field
} {
    set pairs {}
    foreach name_node [::stage1e::canonical_json_v1::array_values \
            [::stage1e::canonical_json_v1::object_get \
                $schema x-stage1e-canonical-order]] {
        set name [::stage1e::canonical_json_v1::node_value $name_node]
        if {$name eq $identity_field} { continue }
        if {![::stage1e::canonical_json_v1::object_has $record $name]} {
            error "Identity payload lacks required property '$name'."
        }
        lappend pairs $name \
            [::stage1e::canonical_json_v1::object_get $record $name]
    }
    set copied_names {}
    foreach {name value} $pairs { dict set copied_names $name 1 }
    foreach name [::stage1e::canonical_json_v1::object_keys $record] {
        if {$name ne $identity_field && ![dict exists $copied_names $name]} {
            error "Identity payload contains unknown property '$name'."
        }
    }
    return [::stage1e::canonical_json_v1::new_object $pairs]
}

proc ::stage1e::envelope_contract_v1::add_identity {
    payload schema registry identity_field {provider {}}
} {
    if {[::stage1e::canonical_json_v1::object_has $payload $identity_field]} {
        error "Identity payload must not contain '$identity_field'."
    }
    set bytes [::stage1e::canonical_json_v1::canonical_bytes \
        $payload $schema $registry $identity_field]
    set identity [::stage1e::canonical_json_v1::digest_bytes $bytes $provider]
    set pairs {}
    foreach name_node [::stage1e::canonical_json_v1::array_values \
            [::stage1e::canonical_json_v1::object_get \
                $schema x-stage1e-canonical-order]] {
        set name [::stage1e::canonical_json_v1::node_value $name_node]
        if {$name eq $identity_field} {
            lappend pairs $name \
                [::stage1e::canonical_json_v1::new_string $identity]
        } else {
            lappend pairs $name \
                [::stage1e::canonical_json_v1::object_get $payload $name]
        }
    }
    return [::stage1e::canonical_json_v1::new_object $pairs]
}

proc ::stage1e::envelope_contract_v1::record_identity {
    record schema registry identity_field {provider {}}
} {
    set payload [copy_without_identity $record $schema $identity_field]
    set bytes [::stage1e::canonical_json_v1::canonical_bytes \
        $payload $schema $registry $identity_field]
    return [::stage1e::canonical_json_v1::digest_bytes $bytes $provider]
}

proc ::stage1e::envelope_contract_v1::scalar {object name} {
    return [::stage1e::canonical_json_v1::node_value \
        [::stage1e::canonical_json_v1::object_get $object $name]]
}

proc ::stage1e::envelope_contract_v1::assert_failure {record contract} {
    ::stage1e::canonical_json_v1::validate $record \
        [dict get $contract failure_schema] \
        [dict get $contract failure_schema] \
        [dict get $contract schema_registry]
    set terminal [scalar $record terminal_status]
    set category [scalar $record failure_category]
    if {$terminal eq {COMPLETED} && $category ne {NONE}} {
        error {A completed failure record must use category NONE.}
    }
    if {$terminal ne {COMPLETED} && $category eq {NONE}} {
        error {A blocked or failed record must name a failure category.}
    }
    return 1
}

proc ::stage1e::envelope_contract_v1::full_path_components {path} {
    if {[catch {file normalize $path} full_path]} {
        error "Path cannot be normalized as an absolute path: $path"
    }
    set components [file split $full_path]
    if {[llength $components] == 0 ||
            [file pathtype $full_path] ne {absolute}} {
        error "Path does not have a structured absolute root: $path"
    }
    return $components
}

proc ::stage1e::envelope_contract_v1::path_equal {left right} {
    if {[catch {full_path_components $left} left_components] ||
            [catch {full_path_components $right} right_components]} {
        return 0
    }
    if {[llength $left_components] != [llength $right_components]} {
        return 0
    }
    foreach left_component $left_components right_component $right_components {
        if {![string equal -nocase $left_component $right_component]} {
            return 0
        }
    }
    return 1
}

proc ::stage1e::envelope_contract_v1::path_within {candidate boundary} {
    if {[catch {full_path_components $candidate} candidate_components] ||
            [catch {full_path_components $boundary} boundary_components]} {
        return 0
    }
    if {[llength $candidate_components] < [llength $boundary_components]} {
        return 0
    }
    for {set index 0} {$index < [llength $boundary_components]} {incr index} {
        if {![string equal -nocase [lindex $candidate_components $index] \
                [lindex $boundary_components $index]]} {
            return 0
        }
    }
    return 1
}

proc ::stage1e::envelope_contract_v1::paths_disjoint {left right} {
    return [expr {![path_within $left $right] &&
        ![path_within $right $left]}]
}

proc ::stage1e::envelope_contract_v1::assert_operation_node {
    node name configured_state authorized sequence directive predecessor
    invocation_policy
} {
    if {[scalar $node configured_state] ne $configured_state ||
            [scalar $node authorized] != $authorized ||
            [scalar $node sequence] != $sequence ||
            [scalar $node directive] ne $directive ||
            [scalar $node predecessor] ne $predecessor ||
            [scalar $node invocation_policy] ne $invocation_policy} {
        error "Effective operation node differs from the frozen graph: $name"
    }
}

proc ::stage1e::envelope_contract_v1::assert_request_semantics {record} {
    set authorization \
        [::stage1e::canonical_json_v1::object_get $record authorization]
    set evidence \
        [::stage1e::canonical_json_v1::object_get $record evidence_contract]
    foreach field {
        execution_id source_identity runtime_backend_identity policy_identity
        configuration_identity qualification_identity environment_identity
        workspace_identity synthesis_result_identity
    } {
        if {[scalar $authorization $field] ne [scalar $record $field]} {
            error "Authorization binding '$field' differs from the request."
        }
    }
    if {[scalar $evidence execution_id] ne [scalar $record execution_id] ||
            [scalar $evidence workspace_identity] ne \
                [scalar $record workspace_identity]} {
        error {Evidence execution/workspace bindings differ from the request.}
    }
    if {[scalar $authorization consumption_record_path] ne
            [scalar $evidence authorization_consumption_record_path]} {
        error {Authorization consumption-record path differs from the evidence contract.}
    }
    set implementation \
        [::stage1e::canonical_json_v1::object_get $record implementation_contract]
    set graph \
        [::stage1e::canonical_json_v1::object_get $implementation effective_step_graph]
    assert_operation_node \
        [::stage1e::canonical_json_v1::object_get $graph opt_design] \
        opt_design ENABLED 1 1 [scalar $implementation opt_design_directive] \
        synthesis REQUIRED
    assert_operation_node \
        [::stage1e::canonical_json_v1::object_get $graph place_design] \
        place_design ENABLED 1 2 \
        [scalar $implementation place_design_directive] opt_design REQUIRED
    assert_operation_node \
        [::stage1e::canonical_json_v1::object_get $graph phys_opt_design] \
        phys_opt_design DISABLED 0 0 NONE place_design PROHIBITED
    assert_operation_node \
        [::stage1e::canonical_json_v1::object_get $graph route_design] \
        route_design ENABLED 1 3 \
        [scalar $implementation route_design_directive] place_design REQUIRED
    assert_operation_node \
        [::stage1e::canonical_json_v1::object_get $graph implementation_reports] \
        implementation_reports ENABLED 1 4 READ_ONLY route_design REQUIRED
    set timeout \
        [::stage1e::canonical_json_v1::object_get $record timeout_contract]
    set total [scalar $timeout total_lifetime_seconds]
    foreach name [::stage1e::canonical_json_v1::object_keys $timeout] {
        if {$name ne {total_lifetime_seconds} && [scalar $timeout $name] > $total} {
            error "Timeout '$name' exceeds the total lifetime budget."
        }
    }
    set launch \
        [::stage1e::canonical_json_v1::object_get $record launch_contract]
    if {![path_equal [scalar $launch cwd] \
                [scalar $launch workspace_root]] ||
            ![path_equal [scalar $launch xil_root] \
                [file join [scalar $launch workspace_root] .Xil]]} {
        error {Launch cwd/workspace/.Xil bindings are inconsistent.}
    }

    foreach {left_name right_name} {
        source_root workspace_root
        source_root evidence_root
        workspace_root evidence_root
    } {
        if {![paths_disjoint [scalar $launch $left_name] \
                [scalar $launch $right_name]]} {
            error "Launch roots '$left_name' and '$right_name' overlap."
        }
    }

    foreach {root_name owner_name} {
        log_root evidence_root
        journal_root evidence_root
        temporary_root workspace_root
        cache_root workspace_root
        request_root evidence_root
    } {
        if {![path_within [scalar $launch $root_name] \
                [scalar $launch $owner_name]]} {
            error "Launch root '$root_name' is outside '$owner_name'."
        }
    }
    if {![path_within [scalar $evidence request_path] \
            [scalar $launch request_root]]} {
        error {Request path is outside its declared request root.}
    }
    set seen {}
    foreach name [::stage1e::canonical_json_v1::object_keys $evidence] {
        set node [::stage1e::canonical_json_v1::object_get $evidence $name]
        if {[::stage1e::canonical_json_v1::node_type $node] ne {string}} {
            continue
        }
        set value [::stage1e::canonical_json_v1::node_value $node]
        if {![::stage1e::canonical_json_v1::is_canonical_path $value]} {
            continue
        }
        foreach seen_path $seen {
            if {[path_equal $value $seen_path]} {
                error "Evidence contract reuses path '$value'."
            }
        }
        lappend seen $value
        if {$name ne {request_path} &&
                ![path_within $value [scalar $launch evidence_root]]} {
            error "Evidence path '$name' is outside the evidence root."
        }
    }
    return 1
}

proc ::stage1e::envelope_contract_v1::assert_request {
    record contract {expected_identity {}} {provider {}}
} {
    set schema [dict get $contract request_schema]
    set registry [dict get $contract schema_registry]
    ::stage1e::canonical_json_v1::validate \
        $record $schema $schema $registry
    assert_request_semantics $record
    set computed [record_identity \
        $record $schema $registry request_identity $provider]
    if {[scalar $record request_identity] ne $computed} {
        error {Embedded request identity does not match the canonical payload.}
    }
    if {$expected_identity ne {} && $expected_identity ne $computed} {
        error {Caller-expected request identity does not match the canonical payload.}
    }
    return $computed
}

proc ::stage1e::envelope_contract_v1::add_request_identity {
    payload contract {provider {}}
} {
    return [add_identity $payload [dict get $contract request_schema] \
        [dict get $contract schema_registry] request_identity $provider]
}

proc ::stage1e::envelope_contract_v1::request_bytes {
    record contract {provider {}}
} {
    assert_request $record $contract {} $provider
    return [::stage1e::canonical_json_v1::canonical_bytes \
        $record [dict get $contract request_schema] \
        [dict get $contract schema_registry]]
}

proc ::stage1e::envelope_contract_v1::parse_request {
    bytes contract expected_identity {provider {}}
} {
    set record [::stage1e::canonical_json_v1::parse_canonical \
        $bytes [dict get $contract request_schema] \
        [dict get $contract schema_registry]]
    assert_request $record $contract $expected_identity $provider
    return $record
}

proc ::stage1e::envelope_contract_v1::assert_component_reference {reference} {
    set status [scalar $reference status]
    if {$status eq {PRESENT}} {
        if {[scalar $reference path] eq {NONE} ||
                [scalar $reference component_identity] eq {NONE} ||
                [scalar $reference missing_reason] ne {NONE}} {
            error {Present component reference has missing-state values.}
        }
    } else {
        if {[scalar $reference path] ne {NONE} ||
                [scalar $reference component_identity] ne {NONE} ||
                [scalar $reference missing_reason] eq {NONE}} {
            error {Missing component reference is not explicit.}
        }
    }
}

proc ::stage1e::envelope_contract_v1::assert_result_semantics {
    record contract
} {
    set terminal [scalar $record terminal_status]
    set first_failure \
        [::stage1e::canonical_json_v1::object_get $record first_failure]
    if {$terminal eq {COMPLETED}} {
        if {[::stage1e::canonical_json_v1::node_type $first_failure] ne {string} ||
                [::stage1e::canonical_json_v1::node_value $first_failure] ne {NONE}} {
            error {Completed result must have first_failure NONE.}
        }
    } else {
        if {[::stage1e::canonical_json_v1::node_type $first_failure] ne {object}} {
            error {Blocked or failed result must contain a failure record.}
        }
        assert_failure $first_failure $contract
        if {[scalar $first_failure terminal_status] ne $terminal} {
            error {First failure terminal status differs from the result.}
        }
    }
    foreach name {host_result vivado_capability_result parser_result} {
        assert_component_reference \
            [::stage1e::canonical_json_v1::object_get $record $name]
    }
    set assembly \
        [::stage1e::canonical_json_v1::object_get $record assembly_result]
    if {[scalar $assembly dependency_closure_state] eq {PARTIAL_FOUNDATION} &&
            $terminal eq {COMPLETED}} {
        error {Partial foundation assembly cannot produce a completed result.}
    }
    set forbidden [::stage1e::canonical_json_v1::object_get \
        $record forbidden_boundary_result]
    if {[scalar $forbidden status] ne {CLEAR} && $terminal eq {COMPLETED}} {
        error {An uncleared forbidden boundary blocks candidate eligibility.}
    }
    foreach secondary [::stage1e::canonical_json_v1::array_values \
            [::stage1e::canonical_json_v1::object_get \
                $assembly secondary_failures]] {
        assert_failure $secondary $contract
    }
    return 1
}

proc ::stage1e::envelope_contract_v1::assert_result {
    record contract {expected_identity {}} {provider {}}
} {
    set schema [dict get $contract result_schema]
    set registry [dict get $contract schema_registry]
    ::stage1e::canonical_json_v1::validate \
        $record $schema $schema $registry
    assert_result_semantics $record $contract
    set computed [record_identity \
        $record $schema $registry result_identity $provider]
    if {[scalar $record result_identity] ne $computed} {
        error {Embedded result identity does not match the canonical payload.}
    }
    if {$expected_identity ne {} && $expected_identity ne $computed} {
        error {Expected result identity does not match the canonical payload.}
    }
    return $computed
}

proc ::stage1e::envelope_contract_v1::add_result_identity {
    payload contract {provider {}}
} {
    return [add_identity $payload [dict get $contract result_schema] \
        [dict get $contract schema_registry] result_identity $provider]
}

proc ::stage1e::envelope_contract_v1::result_bytes {
    record contract {provider {}}
} {
    assert_result $record $contract {} $provider
    return [::stage1e::canonical_json_v1::canonical_bytes \
        $record [dict get $contract result_schema] \
        [dict get $contract schema_registry]]
}

proc ::stage1e::envelope_contract_v1::parse_result {
    bytes contract expected_identity {provider {}}
} {
    set record [::stage1e::canonical_json_v1::parse_canonical \
        $bytes [dict get $contract result_schema] \
        [dict get $contract schema_registry]]
    assert_result $record $contract $expected_identity $provider
    return $record
}
