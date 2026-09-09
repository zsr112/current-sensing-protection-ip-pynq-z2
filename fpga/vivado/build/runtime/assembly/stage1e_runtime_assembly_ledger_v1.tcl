# Stage 1E PRT02-E Tcl pre-dispatch assembly-ledger validator v1.
#
# This file is a disconnected validator.  Its expected records are projected
# from the frozen declaration and its actual records are reopened from a
# sealed ledger plus publication receipt.  The former Expected/Actual list API
# is intentionally absent.

namespace eval ::stage1e::runtime_assembly_ledger_v1 {
    variable interface_version stage1e-runtime-assembly-ledger-interface-v1
    variable ledger_types {
        HOST_ASSEMBLY_LEDGER VIVADO_ASSEMBLY_LEDGER
        POSTPROCESS_ASSEMBLY_LEDGER
    }
    variable ledger_fields {
        role source_path provider interface_version domain load_ordinal
        attempt_state declared_edge
    }
    variable header_fields {
        schema_version ledger_type publication_state request_identity
        execution_id attempt_id source_identity record_count
    }
    variable record_fields {
        record_kind role source_path provider interface_version domain
        load_ordinal attempt_state declared_edge
    }
    variable receipt_fields {
        schema_version ledger_type ledger_path publication_state
        ledger_byte_count ledger_sha256
    }
    variable attempt_states {LOADED OPTIONAL_NOT_LOADED FAILED BLOCKED}
    variable ledger_schema stage1e-runtime-sealed-assembly-ledger-v1
    variable receipt_schema stage1e-runtime-assembly-ledger-publication-receipt-v1
    variable module_dir [file dirname [file normalize [info script]]]
}

proc ::stage1e::runtime_assembly_ledger_v1::_canonical_path {path} {
    # Git-for-Windows Tcl 8.6 can drop the AppData component when normalizing
    # a Windows path.  nativename retains the OS path identity; separator
    # normalization is applied only after that identity is obtained.
    return [string map {\\ /} [file nativename $path]]
}

proc ::stage1e::runtime_assembly_ledger_v1::interface_version {} {
    variable interface_version
    return $interface_version
}

proc ::stage1e::runtime_assembly_ledger_v1::_raise {code message} {
    return -code error -errorcode [list STAGE1E PRT02E ASSEMBLY_LEDGER $code] \
        $message
}

proc ::stage1e::runtime_assembly_ledger_v1::_read_utf8 {path} {
    set channel [open $path rb]
    fconfigure $channel -translation binary -encoding binary
    try { set bytes [read $channel] } finally { close $channel }
    if {[string range $bytes 0 2] eq "\xef\xbb\xbf"} {
        _raise UTF8_BOM "Ledger input contains a UTF-8 BOM: $path"
    }
    if {[catch {encoding convertfrom utf-8 $bytes} text]} {
        _raise UTF8_INVALID "Ledger input is not strict UTF-8: $path"
    }
    return [list $bytes $text]
}

proc ::stage1e::runtime_assembly_ledger_v1::_decode_value {value} {
    set result {}
    set length [string length $value]
    for {set index 0} {$index < $length} {incr index} {
        set character [string index $value $index]
        if {$character ne {\\}} {
            append result $character
            continue
        }
        if {$index + 1 >= $length} {
            _raise ESCAPE {Sealed ledger value has a trailing escape.}
        }
        incr index
        switch -- [string index $value $index] {
            p { append result | }
            \\ { append result \\ }
            n { append result "\n" }
            r { append result "\r" }
            t { append result "\t" }
            default {
                _raise ESCAPE "Unsupported sealed ledger escape: [string index $value $index]"
            }
        }
    }
    return $result
}

proc ::stage1e::runtime_assembly_ledger_v1::_parse_line {line label} {
    if {$line eq {}} { _raise FORMAT "$label is empty." }
    set result {}
    foreach field [split $line |] {
        set separator [string first = $field]
        if {$separator <= 0} { _raise FORMAT "Malformed $label field: $field" }
        set key [string range $field 0 [expr {$separator - 1}]]
        if {![regexp {^[A-Za-z][A-Za-z0-9_]*$} $key]} {
            _raise FORMAT "Invalid $label field name: $key"
        }
        if {[dict exists $result $key]} {
            _raise DUPLICATE "Duplicate $label field: $key"
        }
        dict set result $key [_decode_value [string range $field [expr {$separator + 1}] end]]
    }
    return $result
}

proc ::stage1e::runtime_assembly_ledger_v1::_assert_exact_fields {
    record expected label
} {
    if {[llength [dict keys $record]] != [llength $expected] ||
        [lrange [dict keys $record] 0 end] ne [lrange $expected 0 end]} {
        _raise FIELD_SET "$label has an incorrect exact field set/order."
    }
}

proc ::stage1e::runtime_assembly_ledger_v1::_validate_record {record label} {
    variable ledger_fields
    variable attempt_states
    _assert_exact_fields $record $ledger_fields $label
    if {![regexp {^[1-9][0-9]*$} [dict get $record load_ordinal]]} {
        _raise ORDINAL "$label has an invalid load ordinal."
    }
    if {[dict get $record attempt_state] ni $attempt_states} {
        _raise ATTEMPT_STATE "$label has an invalid attempt state."
    }
    foreach field $ledger_fields {
        if {$field ne {load_ordinal} && [string trim [dict get $record $field]] eq {}} {
            _raise EMPTY_FIELD "$label has an empty $field."
        }
    }
    return 1
}

proc ::stage1e::runtime_assembly_ledger_v1::_read_ledger {path} {
    variable header_fields
    variable record_fields
    set pair [_read_utf8 $path]
    lassign $pair bytes text
    set lines [split $text "\n"]
    # A final LF is canonical; remove only the final empty split element.
    if {[lindex $lines end] eq {}} { set lines [lrange $lines 0 end-1] }
    if {![llength $lines]} { _raise EMPTY {Sealed assembly ledger is empty.} }
    foreach line $lines {
        if {$line eq {}} { _raise FORMAT {Sealed assembly ledger contains a blank line.} }
    }
    set header [_parse_line [lindex $lines 0] {sealed ledger header}]
    _assert_exact_fields $header $header_fields {Sealed ledger header}
    foreach field $header_fields {
        if {[dict get $header $field] eq {}} { _raise EMPTY "Sealed ledger header has an empty $field." }
    }
    if {![regexp {^(0|[1-9][0-9]*)$} [dict get $header record_count]]} {
        _raise COUNT {Sealed ledger header has an invalid record_count.}
    }
    set records {}
    set ordinal 0
    foreach line [lrange $lines 1 end] {
        incr ordinal
        set raw [_parse_line $line "sealed ledger record $ordinal"]
        _assert_exact_fields $raw $record_fields "Sealed ledger record $ordinal"
        if {[dict get $raw record_kind] ne {RECORD}} {
            _raise FORMAT "Sealed ledger record $ordinal is not a RECORD line."
        }
        set record {}
        variable ledger_fields
        foreach field $ledger_fields { dict set record $field [dict get $raw $field] }
        _validate_record $record "Sealed ledger record $ordinal"
        if {[dict get $record load_ordinal] != $ordinal} {
            _raise ORDER "Sealed ledger record $ordinal has a noncanonical load ordinal."
        }
        lappend records $record
    }
    if {[dict get $header record_count] != [llength $records]} {
        _raise COUNT {Sealed ledger header record_count does not match its records.}
    }
    return [dict create bytes $bytes header $header records $records]
}

proc ::stage1e::runtime_assembly_ledger_v1::_read_receipt {path} {
    variable receipt_fields
    lassign [_read_utf8 $path] bytes text
    set lines [split $text "\n"]
    if {[lindex $lines end] eq {}} { set lines [lrange $lines 0 end-1] }
    if {[llength $lines] != 1 || [lindex $lines 0] eq {}} {
        _raise FORMAT {Assembly publication receipt must contain one line.}
    }
    set receipt [_parse_line [lindex $lines 0] {assembly publication receipt}]
    _assert_exact_fields $receipt $receipt_fields {Assembly publication receipt}
    foreach field $receipt_fields {
        if {[dict get $receipt $field] eq {}} { _raise EMPTY "Receipt has an empty $field." }
    }
    if {![regexp {^(0|[1-9][0-9]*)$} [dict get $receipt ledger_byte_count]] ||
        ![regexp {^[0-9a-f]{64}$} [dict get $receipt ledger_sha256]]} {
        _raise INTEGRITY {Receipt byte-integrity metadata is invalid.}
    }
    return $receipt
}

proc ::stage1e::runtime_assembly_ledger_v1::_strict_dict {text label} {
    if {[catch {llength $text}]} { _raise CONTRACT "$label is not a Tcl list." }
    if {[llength $text] % 2} { _raise CONTRACT "$label has an odd field count." }
    set result {}
    for {set index 0} {$index < [llength $text]} {incr index 2} {
        set key [lindex $text $index]
        if {[dict exists $result $key]} { _raise DUPLICATE "$label has duplicate key '$key'." }
        dict set result $key [lindex $text [expr {$index + 1}]]
    }
    return $result
}

proc ::stage1e::runtime_assembly_ledger_v1::_strict_record_list {text label} {
    set result {}
    if {[catch {llength $text}]} { _raise CONTRACT "$label is not a Tcl list." }
    foreach item $text { lappend result [_strict_dict $item "$label record"] }
    return $result
}

proc ::stage1e::runtime_assembly_ledger_v1::_graph_projection {ledger_type {graph_path {}}} {
    variable ledger_types
    if {$ledger_type ni $ledger_types} { _raise LEDGER_TYPE "Unknown assembly ledger type '$ledger_type'." }
    variable module_dir
    if {$graph_path eq {}} {
        set graph_path [file join $module_dir ../../config stage1e_runtime_declared_graph_v1.dict]
    }
    set graph_path [file nativename $graph_path]
    lassign [_read_utf8 $graph_path] ignored graph_text
    set graph [_strict_dict [string trim $graph_text] {declared graph}]
    if {![dict exists $graph schema_version] ||
        [dict get $graph schema_version] ne {stage1e-runtime-declared-graph-v1}} {
        _raise CONTRACT {Declared graph version mismatch.}
    }
    set provider_path [file join [file dirname $graph_path] stage1e_runtime_provider_contract_v1.dict]
    lassign [_read_utf8 $provider_path] ignored provider_text
    set provider_contract [_strict_dict [string trim $provider_text] {provider contract}]
    set nodes {}
    foreach node [_strict_record_list [dict get $graph nodes] graph_nodes] {
        set id [dict get $node node_id]
        if {[dict exists $nodes $id]} { _raise DUPLICATE "Duplicate graph node: $id" }
        dict set nodes $id $node
    }
    set scenario [switch -exact -- $ledger_type {
        HOST_ASSEMBLY_LEDGER { set value HOST_DISCONNECTED_SAFE_LOAD }
        VIVADO_ASSEMBLY_LEDGER { set value VIVADO_DISCONNECTED_SAFE_LOAD }
        POSTPROCESS_ASSEMBLY_LEDGER { set value POSTPROCESS_DISCONNECTED_SAFE_LOAD }
    }]
    set domain [switch -exact -- $scenario {
        HOST_DISCONNECTED_SAFE_LOAD { set value HOST_POWERSHELL }
        VIVADO_DISCONNECTED_SAFE_LOAD { set value VIVADO_TCL }
        default { set value HOST_POSTPROCESS_TCL }
    }]
    set occurrence {}
    foreach projection [_strict_record_list [dict get $graph trace_expected_occurrences] trace_expected_occurrences] {
        if {[dict get $projection scenario] eq $scenario} { set occurrence $projection; break }
    }
    set provider_order {}
    foreach projection [_strict_record_list [dict get $graph trace_provider_order] trace_provider_order] {
        if {[dict get $projection scenario] eq $scenario} { set provider_order $projection; break }
    }
    if {$occurrence eq {} || $provider_order eq {}} { _raise CONTRACT "No frozen projection for $ledger_type." }
    set providers {}
    foreach provider [_strict_record_list [dict get $provider_contract providers] providers] {
        dict set providers [dict get $provider provider_key] $provider
    }
    set records {}
    set ordinal 0
    foreach key_text [dict get $occurrence keys] {
        set key [lrange $key_text 0 end]
        if {[llength $key] != 3} { _raise CONTRACT "Malformed occurrence in $scenario." }
        set target [lindex $key 1]
        if {![dict exists $nodes $target]} { _raise CONTRACT "Unknown ledger target: $target" }
        set node [dict get $nodes $target]
        incr ordinal
        set state LOADED
        if {[lindex $key 2] eq {DOTNET_SOURCE_PROVIDER} ||
            ([lindex $key 0] eq $target && [lindex $key 2] eq {TCL_SOURCE})} {
            set state OPTIONAL_NOT_LOADED
        }
        lappend records [dict create \
            role [dict get $node role] \
            source_path [dict get $node repository_path] \
            provider NONE \
            interface_version [dict get $node interface_version] \
            domain $domain load_ordinal $ordinal attempt_state $state \
            declared_edge [lindex $key 2]]
    }
    foreach provider_key [dict get $provider_order providers] {
        if {![dict exists $providers $provider_key]} { _raise CONTRACT "Unknown provider projection: $provider_key" }
        set provider [dict get $providers $provider_key]
        set source_path [dict get $provider source_path]
        set node_id {}
        foreach id [dict keys $nodes] {
            if {[dict get $nodes $id repository_path] eq $source_path} { set node_id $id; break }
        }
        if {$node_id eq {}} { _raise CONTRACT "Provider source has no graph node: $provider_key" }
        if {[lsearch -exact [split [dict get $provider process_domains] { }] $domain] < 0} {
            _raise CONTRACT "Provider domain does not cover $scenario: $provider_key"
        }
        set node [dict get $nodes $node_id]
        incr ordinal
        lappend records [dict create \
            role [dict get $node role] source_path $source_path \
            provider $provider_key interface_version [dict get $provider interface_version] \
            domain $domain load_ordinal $ordinal attempt_state LOADED \
            declared_edge PROVIDER_OBSERVATION]
    }
    return $records
}

proc ::stage1e::runtime_assembly_ledger_v1::graph_projection {ledger_type {graph_path {}}} {
    return [_graph_projection $ledger_type $graph_path]
}

proc ::stage1e::runtime_assembly_ledger_v1::validate {
    ledger_type ledger_path receipt_path request_identity execution_id attempt_id source_identity
} {
    variable ledger_types
    variable ledger_schema
    variable receipt_schema
    if {$ledger_type ni $ledger_types} { _raise LEDGER_TYPE "Unknown assembly ledger type '$ledger_type'." }
    foreach value [list $request_identity $execution_id $attempt_id $source_identity] {
        if {[string trim $value] eq {}} { _raise BINDING {Ledger binding fields must be nonempty.} }
    }
    foreach path [list $ledger_path $receipt_path] {
        if {![file exists $path] || [file type $path] ne {file}} { _raise PATH "Ledger/receipt path is not a regular file: $path" }
    }
    set ledger [_read_ledger $ledger_path]
    set receipt [_read_receipt $receipt_path]
    set header [dict get $ledger header]
    if {[dict get $header schema_version] ne $ledger_schema ||
        [dict get $header ledger_type] ne $ledger_type ||
        [dict get $header publication_state] ne {SEALED}} {
        _raise BINDING {Sealed ledger header type/state is invalid.}
    }
    foreach {field expected} [list request_identity $request_identity execution_id $execution_id attempt_id $attempt_id source_identity $source_identity] {
        if {[dict get $header $field] ne $expected} { _raise BINDING "Ledger binding mismatch: $field" }
    }
    set canonical_ledger_path [_canonical_path $ledger_path]
    if {[dict get $receipt schema_version] ne $receipt_schema ||
        [dict get $receipt ledger_type] ne $ledger_type ||
        [string tolower [dict get $receipt ledger_path]] ne [string tolower $canonical_ledger_path] ||
        [dict get $receipt publication_state] ne {PUBLISHED}} {
        _raise BINDING {Assembly publication receipt binding/state is invalid.}
    }
    variable module_dir
    set provider_path [file normalize [file join $module_dir ../../lib/stage1e_runtime_canonical_json_v1.tcl]]
    if {[catch {source $provider_path}]} { _raise HASH {Unable to load Tcl SHA-256 provider.} }
    if {![llength [info commands ::stage1e::canonical_json_v1::hash_provider_interface_version]] ||
        [::stage1e::canonical_json_v1::hash_provider_interface_version] ne
            {stage1e-runtime-sha256-provider-interface-v1}} {
        _raise HASH {Tcl SHA-256 provider interface mismatch.}
    }
    set digest [string tolower [::stage1e::canonical_json_v1::sha256 [dict get $ledger bytes]]]
    if {![regexp {^[0-9a-f]{64}$} $digest]} {
        _raise HASH {Tcl SHA-256 provider returned a noncanonical digest.}
    }
    if {[dict get $receipt ledger_byte_count] != [string length [dict get $ledger bytes]] ||
        [dict get $receipt ledger_sha256] ne $digest} {
        _raise INTEGRITY {Assembly publication receipt byte count or SHA-256 differs.}
    }
    set expected [_graph_projection $ledger_type]
    set actual [dict get $ledger records]
    if {[llength $expected] != [llength $actual]} { _raise COUNT "${ledger_type} sealed record count differs from frozen graph projection." }
    for {set index 0} {$index < [llength $expected]} {incr index} {
        set expected_record [lindex $expected $index]
        set actual_record [lindex $actual $index]
        _validate_record $actual_record "Authoritative sealed ledger record [expr {$index + 1}]"
        foreach field [dict keys $expected_record] {
            if {[dict get $expected_record $field] ne [dict get $actual_record $field]} {
                _raise MISMATCH "${ledger_type} authoritative mismatch at record [expr {$index + 1}], field $field."
            }
        }
    }
    return [dict create ledger_type $ledger_type comparison_state MATCH \
        expected_source FROZEN_DECLARED_GRAPH_DOMAIN_PROJECTION \
        actual_source REOPENED_SEALED_LEDGER_RECORD \
        receipt_state PUBLISHED_AND_BYTE_INTEGRITY_VERIFIED \
        record_count [llength $expected] ledger_sha256 $digest \
        dispatch_state VALIDATED_NOT_CONNECTED \
        integration_state PRE_DISPATCH_INTEGRATION_NOT_CONNECTED]
}
