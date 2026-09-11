# Stage 1E repository-owned strict JSON codec and canonical encoder v1.

namespace eval ::stage1e::canonical_json_v1 {
    variable interface_version stage1e-runtime-canonical-json-interface-v1
    variable hash_provider_interface_version \
        stage1e-runtime-sha256-provider-interface-v1
    variable maximum_depth 64
    variable parse_text {}
    variable parse_index 0
    variable parse_length 0
}

proc ::stage1e::canonical_json_v1::interface_version {} {
    variable interface_version
    return $interface_version
}

proc ::stage1e::canonical_json_v1::hash_provider_interface_version {} {
    variable hash_provider_interface_version
    return $hash_provider_interface_version
}

proc ::stage1e::canonical_json_v1::new_string {value} {
    return [list string $value]
}

proc ::stage1e::canonical_json_v1::new_integer {value} {
    if {![string is entier -strict $value]} {
        return -code error -errorcode {STAGE1E JSON TYPE} \
            {Integer constructor requires an integer.}
    }
    return [list integer $value]
}

proc ::stage1e::canonical_json_v1::new_boolean {value} {
    if {$value ni {0 1}} {
        return -code error -errorcode {STAGE1E JSON TYPE} \
            {Boolean constructor requires 0 or 1.}
    }
    return [list boolean $value]
}

proc ::stage1e::canonical_json_v1::new_array {values} {
    return [list array $values]
}

proc ::stage1e::canonical_json_v1::new_object {pairs} {
    if {[llength $pairs] % 2 != 0} {
        return -code error -errorcode {STAGE1E JSON TYPE} \
            {Object constructor requires name/value pairs.}
    }
    set seen {}
    foreach {name value} $pairs {
        if {[dict exists $seen $name]} {
            return -code error -errorcode {STAGE1E JSON DUPLICATE} \
                "Duplicate object property: $name"
        }
        dict set seen $name 1
    }
    return [list object $pairs]
}

proc ::stage1e::canonical_json_v1::node_type {node} {
    if {[llength $node] != 2 || [lindex $node 0] ni \
            {object array string integer boolean}} {
        return -code error -errorcode {STAGE1E JSON TYPE} \
            {Value is not a typed Stage 1E JSON node.}
    }
    return [lindex $node 0]
}

proc ::stage1e::canonical_json_v1::node_value {node} {
    node_type $node
    return [lindex $node 1]
}

proc ::stage1e::canonical_json_v1::object_has {node name} {
    if {[node_type $node] ne {object}} {
        return 0
    }
    set pairs [node_value $node]
    foreach {key value} $pairs {
        if {$key eq $name} { return 1 }
    }
    return 0
}

proc ::stage1e::canonical_json_v1::object_get {node name} {
    if {[node_type $node] ne {object}} {
        return -code error -errorcode {STAGE1E JSON TYPE} \
            {Object property requested from a non-object.}
    }
    set pairs [node_value $node]
    foreach {key value} $pairs {
        if {$key eq $name} { return $value }
    }
    return -code error -errorcode {STAGE1E JSON FIELD} \
        "Missing object property: $name"
}

proc ::stage1e::canonical_json_v1::object_keys {node} {
    if {[node_type $node] ne {object}} {
        return -code error -errorcode {STAGE1E JSON TYPE} \
            {Object keys requested from a non-object.}
    }
    set keys {}
    foreach {key value} [node_value $node] { lappend keys $key }
    return $keys
}

proc ::stage1e::canonical_json_v1::array_values {node} {
    if {[node_type $node] ne {array}} {
        return -code error -errorcode {STAGE1E JSON TYPE} \
            {Array values requested from a non-array.}
    }
    return [node_value $node]
}

proc ::stage1e::canonical_json_v1::decode_utf8_strict {bytes} {
    binary scan $bytes c* signed_octets
    set octets {}
    foreach octet $signed_octets {
        if {$octet < 0} { incr octet 256 }
        lappend octets $octet
    }
    if {[llength $octets] >= 3 && [lrange $octets 0 2] eq {239 187 191}} {
        return -code error -errorcode {STAGE1E JSON BOM} \
            {UTF-8 BOM is prohibited.}
    }
    set result {}
    set index 0
    set length [llength $octets]
    while {$index < $length} {
        set first [lindex $octets $index]
        incr index
        if {$first <= 0x7f} {
            set codepoint $first
        } elseif {$first >= 0xc2 && $first <= 0xdf} {
            if {$index >= $length} {
                return -code error -errorcode {STAGE1E JSON UTF8} \
                    {Truncated two-byte UTF-8 sequence.}
            }
            set second [lindex $octets $index]
            incr index
            if {$second < 0x80 || $second > 0xbf} {
                return -code error -errorcode {STAGE1E JSON UTF8} \
                    {Invalid UTF-8 continuation byte.}
            }
            set codepoint [expr {(($first & 0x1f) << 6) | ($second & 0x3f)}]
        } elseif {$first >= 0xe0 && $first <= 0xef} {
            if {$index + 1 >= $length} {
                return -code error -errorcode {STAGE1E JSON UTF8} \
                    {Truncated three-byte UTF-8 sequence.}
            }
            set second [lindex $octets $index]
            set third [lindex $octets [expr {$index + 1}]]
            incr index 2
            if {$second < 0x80 || $second > 0xbf ||
                    $third < 0x80 || $third > 0xbf ||
                    ($first == 0xe0 && $second < 0xa0) ||
                    ($first == 0xed && $second > 0x9f)} {
                return -code error -errorcode {STAGE1E JSON UTF8} \
                    {Invalid three-byte UTF-8 sequence.}
            }
            set codepoint [expr {(($first & 0x0f) << 12) |
                (($second & 0x3f) << 6) | ($third & 0x3f)}]
        } elseif {$first >= 0xf0 && $first <= 0xf4} {
            if {$index + 2 >= $length} {
                return -code error -errorcode {STAGE1E JSON UTF8} \
                    {Truncated four-byte UTF-8 sequence.}
            }
            set second [lindex $octets $index]
            set third [lindex $octets [expr {$index + 1}]]
            set fourth [lindex $octets [expr {$index + 2}]]
            incr index 3
            if {$second < 0x80 || $second > 0xbf ||
                    $third < 0x80 || $third > 0xbf ||
                    $fourth < 0x80 || $fourth > 0xbf ||
                    ($first == 0xf0 && $second < 0x90) ||
                    ($first == 0xf4 && $second > 0x8f)} {
                return -code error -errorcode {STAGE1E JSON UTF8} \
                    {Invalid four-byte UTF-8 sequence.}
            }
            set codepoint [expr {(($first & 0x07) << 18) |
                (($second & 0x3f) << 12) | (($third & 0x3f) << 6) |
                ($fourth & 0x3f)}]
        } else {
            return -code error -errorcode {STAGE1E JSON UTF8} \
                {Invalid UTF-8 leading byte.}
        }
        if {$codepoint >= 0xd800 && $codepoint <= 0xdfff} {
            return -code error -errorcode {STAGE1E JSON UTF8} \
                {UTF-8 must not encode a surrogate code point.}
        }
        if {$codepoint > 0xffff} {
            set adjusted [expr {$codepoint - 0x10000}]
            set high [expr {0xd800 + ($adjusted >> 10)}]
            set low [expr {0xdc00 + ($adjusted & 0x3ff)}]
            append result [format %c $high] [format %c $low]
        } else {
            append result [format %c $codepoint]
        }
    }
    return $result
}

proc ::stage1e::canonical_json_v1::parse_error {message} {
    variable parse_index
    return -code error -errorcode {STAGE1E JSON PARSE} \
        "$message (character offset $parse_index)."
}

proc ::stage1e::canonical_json_v1::skip_whitespace {} {
    variable parse_text
    variable parse_index
    variable parse_length
    while {$parse_index < $parse_length} {
        set code [scan [string index $parse_text $parse_index] %c]
        if {$code != 0x20 && $code != 0x09 &&
                $code != 0x0a && $code != 0x0d} { break }
        incr parse_index
    }
}

proc ::stage1e::canonical_json_v1::hex_value {character} {
    set code [scan $character %c]
    if {$code >= 0x30 && $code <= 0x39} { return [expr {$code - 0x30}] }
    if {$code >= 0x41 && $code <= 0x46} { return [expr {$code - 0x41 + 10}] }
    if {$code >= 0x61 && $code <= 0x66} { return [expr {$code - 0x61 + 10}] }
    parse_error {Invalid Unicode escape}
}

proc ::stage1e::canonical_json_v1::parse_unicode_escape {} {
    variable parse_text
    variable parse_index
    variable parse_length
    if {$parse_index + 4 > $parse_length} {
        parse_error {Truncated Unicode escape}
    }
    set value 0
    for {set count 0} {$count < 4} {incr count} {
        set value [expr {$value * 16 +
            [hex_value [string index $parse_text $parse_index]]}]
        incr parse_index
    }
    return $value
}

proc ::stage1e::canonical_json_v1::parse_string {} {
    variable parse_text
    variable parse_index
    variable parse_length
    if {[string index $parse_text $parse_index] ne {"}} {
        parse_error {Expected JSON string}
    }
    incr parse_index
    set result {}
    while {$parse_index < $parse_length} {
        set character [string index $parse_text $parse_index]
        incr parse_index
        if {$character eq {"}} { return $result }
        if {$character eq "\\"} {
            if {$parse_index >= $parse_length} {
                parse_error {Truncated JSON escape}
            }
            set escape [string index $parse_text $parse_index]
            incr parse_index
            if {$escape eq {"}} {
                append result {"}
            } elseif {$escape eq "\\"} {
                append result "\\"
            } elseif {$escape eq {/}} {
                append result {/}
            } elseif {$escape eq {b}} {
                append result [format %c 8]
            } elseif {$escape eq {f}} {
                append result [format %c 12]
            } elseif {$escape eq {n}} {
                append result [format %c 10]
            } elseif {$escape eq {r}} {
                append result [format %c 13]
            } elseif {$escape eq {t}} {
                append result [format %c 9]
            } elseif {$escape eq {u}} {
                set unit [parse_unicode_escape]
                if {$unit >= 0xd800 && $unit <= 0xdbff} {
                    if {$parse_index + 2 > $parse_length ||
                            [string index $parse_text $parse_index] ne "\\" ||
                            [string index $parse_text [expr {$parse_index + 1}]] ne {u}} {
                        parse_error {High surrogate lacks a low surrogate}
                    }
                    incr parse_index 2
                    set low [parse_unicode_escape]
                    if {$low < 0xdc00 || $low > 0xdfff} {
                        parse_error {Invalid low surrogate}
                    }
                    append result [format %c $unit] [format %c $low]
                } elseif {$unit >= 0xdc00 && $unit <= 0xdfff} {
                    parse_error {Unpaired low surrogate}
                } else {
                    append result [format %c $unit]
                }
            } else {
                parse_error {Unknown JSON escape}
            }
            continue
        }
        set code [scan $character %c]
        if {$code < 0x20} {
            parse_error {Unescaped control character}
        }
        if {$code >= 0xd800 && $code <= 0xdbff} {
            if {$parse_index >= $parse_length} {
                parse_error {Unpaired high surrogate}
            }
            set low_character [string index $parse_text $parse_index]
            set low_code [scan $low_character %c]
            if {$low_code < 0xdc00 || $low_code > 0xdfff} {
                parse_error {Unpaired high surrogate}
            }
            append result $character $low_character
            incr parse_index
            continue
        }
        if {$code >= 0xdc00 && $code <= 0xdfff} {
            parse_error {Unpaired low surrogate}
        }
        append result $character
    }
    parse_error {Unterminated JSON string}
}

proc ::stage1e::canonical_json_v1::parse_integer {} {
    variable parse_text
    variable parse_index
    variable parse_length
    set start $parse_index
    set negative 0
    if {[string index $parse_text $parse_index] eq {-}} {
        set negative 1
        incr parse_index
        if {$parse_index >= $parse_length} { parse_error {Truncated JSON number} }
    }
    set first [string index $parse_text $parse_index]
    set first_code [scan $first %c]
    if {$first eq {0}} {
        incr parse_index
        if {$negative} { parse_error {Negative zero is not supported} }
        if {$parse_index < $parse_length} {
            set next [scan [string index $parse_text $parse_index] %c]
            if {$next >= 0x30 && $next <= 0x39} {
                parse_error {Leading zero in JSON number}
            }
        }
    } elseif {$first_code >= 0x31 && $first_code <= 0x39} {
        while {$parse_index < $parse_length} {
            set code [scan [string index $parse_text $parse_index] %c]
            if {$code < 0x30 || $code > 0x39} { break }
            incr parse_index
        }
    } else {
        parse_error {Invalid JSON number}
    }
    if {$parse_index < $parse_length &&
            [string index $parse_text $parse_index] in {. e E}} {
        parse_error {Only canonical integers are supported}
    }
    set lexeme [string range $parse_text $start [expr {$parse_index - 1}]]
    if {![string is entier -strict $lexeme] ||
            $lexeme < -9223372036854775808 || $lexeme > 9223372036854775807} {
        parse_error {JSON integer is outside the Int64 range}
    }
    return $lexeme
}

proc ::stage1e::canonical_json_v1::parse_literal {literal value} {
    variable parse_text
    variable parse_index
    variable parse_length
    set end [expr {$parse_index + [string length $literal] - 1}]
    if {$end >= $parse_length ||
            [string range $parse_text $parse_index $end] ne $literal} {
        parse_error "Invalid JSON literal; expected $literal"
    }
    set parse_index [expr {$end + 1}]
    return $value
}

proc ::stage1e::canonical_json_v1::parse_array {depth} {
    variable parse_text
    variable parse_index
    variable parse_length
    incr parse_index
    set values {}
    skip_whitespace
    if {$parse_index < $parse_length &&
            [string index $parse_text $parse_index] eq {]}} {
        incr parse_index
        return [new_array $values]
    }
    while {1} {
        lappend values [parse_value $depth]
        skip_whitespace
        if {$parse_index >= $parse_length} { parse_error {Unterminated JSON array} }
        set separator [string index $parse_text $parse_index]
        incr parse_index
        if {$separator eq {]}} { return [new_array $values] }
        if {$separator ne {,}} { parse_error {Expected comma or closing bracket} }
        skip_whitespace
    }
}

proc ::stage1e::canonical_json_v1::parse_object {depth} {
    variable parse_text
    variable parse_index
    variable parse_length
    incr parse_index
    set pairs {}
    set seen {}
    skip_whitespace
    if {$parse_index < $parse_length &&
            [string index $parse_text $parse_index] eq "\}"} {
        incr parse_index
        return [new_object $pairs]
    }
    while {1} {
        if {$parse_index >= $parse_length ||
                [string index $parse_text $parse_index] ne {"}} {
            parse_error {Expected JSON object property}
        }
        set name [parse_string]
        if {[dict exists $seen $name]} { parse_error "Duplicate JSON property '$name'" }
        dict set seen $name 1
        skip_whitespace
        if {$parse_index >= $parse_length ||
                [string index $parse_text $parse_index] ne {:}} {
            parse_error {Expected colon after JSON property}
        }
        incr parse_index
        skip_whitespace
        lappend pairs $name [parse_value $depth]
        skip_whitespace
        if {$parse_index >= $parse_length} { parse_error {Unterminated JSON object} }
        set separator [string index $parse_text $parse_index]
        incr parse_index
        if {$separator eq "\}"} { return [new_object $pairs] }
        if {$separator ne {,}} { parse_error {Expected comma or closing brace} }
        skip_whitespace
    }
}

proc ::stage1e::canonical_json_v1::parse_value {depth} {
    variable maximum_depth
    variable parse_text
    variable parse_index
    variable parse_length
    if {$depth > $maximum_depth} { parse_error {JSON nesting exceeds limit} }
    skip_whitespace
    if {$parse_index >= $parse_length} { parse_error {Unexpected end of JSON input} }
    set character [string index $parse_text $parse_index]
    if {$character eq "\{"} { return [parse_object [expr {$depth + 1}]] }
    if {$character eq {[}} { return [parse_array [expr {$depth + 1}]] }
    if {$character eq {"}} { return [new_string [parse_string]] }
    if {$character eq {t}} { return [new_boolean [parse_literal true 1]] }
    if {$character eq {f}} { return [new_boolean [parse_literal false 0]] }
    if {$character eq {n}} { parse_error {JSON null is not supported} }
    set code [scan $character %c]
    if {$character eq {-} || ($code >= 0x30 && $code <= 0x39)} {
        return [new_integer [parse_integer]]
    }
    parse_error {Unexpected JSON token}
}

proc ::stage1e::canonical_json_v1::parse_bytes {bytes} {
    variable parse_text
    variable parse_index
    variable parse_length
    set parse_text [decode_utf8_strict $bytes]
    set parse_index 0
    set parse_length [string length $parse_text]
    set value [parse_value 0]
    skip_whitespace
    if {$parse_index != $parse_length} { parse_error {Trailing data after JSON value} }
    if {[node_type $value] ne {object}} {
        return -code error -errorcode {STAGE1E JSON ROOT} \
            {The Stage 1E JSON document root must be an object.}
    }
    return $value
}

proc ::stage1e::canonical_json_v1::read_file_bytes {path} {
    set channel [open $path rb]
    fconfigure $channel -translation binary -encoding binary
    try {
        return [read $channel]
    } finally {
        close $channel
    }
}

proc ::stage1e::canonical_json_v1::schema_resolve {schema root registry} {
    if {![object_has $schema {$ref}]} { return [list $schema $root] }
    set reference [node_value [object_get $schema {$ref}]]
    set marker [string first # $reference]
    if {$marker < 0} {
        set document $reference
        set fragment {}
    } else {
        set document [string range $reference 0 [expr {$marker - 1}]]
        set fragment [string range $reference [expr {$marker + 1}] end]
    }
    if {$document eq {}} {
        set target_root $root
    } else {
        if {![dict exists $registry $document]} {
            return -code error -errorcode {STAGE1E SCHEMA REFERENCE} \
                "Schema reference document is not loaded: $document"
        }
        set target_root [dict get $registry $document]
    }
    set target $target_root
    if {$fragment ne {}} {
        if {[string index $fragment 0] ne {/}} {
            return -code error -errorcode {STAGE1E SCHEMA REFERENCE} \
                "Unsupported schema reference fragment: $reference"
        }
        foreach raw [lrange [split $fragment /] 1 end] {
            set part [string map {~1 / ~0 ~} $raw]
            set target [object_get $target $part]
        }
    }
    if {[node_type $target] ne {object}} {
        return -code error -errorcode {STAGE1E SCHEMA REFERENCE} \
            "Schema reference does not select an object: $reference"
    }
    return [list $target $target_root]
}

proc ::stage1e::canonical_json_v1::node_equal {left right} {
    if {[node_type $left] ne [node_type $right]} { return 0 }
    set type [node_type $left]
    if {$type eq {object}} {
        set left_keys [object_keys $left]
        set right_keys [object_keys $right]
        if {[llength $left_keys] != [llength $right_keys]} { return 0 }
        foreach key $left_keys {
            if {![object_has $right $key] ||
                    ![node_equal [object_get $left $key] [object_get $right $key]]} {
                return 0
            }
        }
        return 1
    }
    if {$type eq {array}} {
        set left_values [array_values $left]
        set right_values [array_values $right]
        if {[llength $left_values] != [llength $right_values]} { return 0 }
        foreach lvalue $left_values rvalue $right_values {
            if {![node_equal $lvalue $rvalue]} { return 0 }
        }
        return 1
    }
    return [expr {[node_value $left] eq [node_value $right]}]
}

proc ::stage1e::canonical_json_v1::is_sha256 {value} {
    if {[string length $value] != 64 || $value eq [string repeat 0 64]} { return 0 }
    foreach character [split $value {}] {
        set code [scan $character %c]
        if {!($code >= 0x30 && $code <= 0x39) &&
                !($code >= 0x61 && $code <= 0x66)} { return 0 }
    }
    return 1
}

proc ::stage1e::canonical_json_v1::is_canonical_path {value} {
    foreach forbidden [list "\\" {*} {?} {[} {]}] {
        if {[string first $forbidden $value] >= 0} { return 0 }
    }
    foreach character [split $value {}] {
        if {[scan $character %c] < 0x20} { return 0 }
    }
    if {[string first {//} $value] == 0} {
        set segments [split [string range $value 2 end] /]
        if {[llength $segments] < 2} { return 0 }
    } elseif {[string index $value 0] eq {/}} {
        set segments [split [string range $value 1 end] /]
    } else {
        if {[string length $value] < 3 || [string index $value 1] ne {:} ||
                [string index $value 2] ne {/}} { return 0 }
        set drive [scan [string index $value 0] %c]
        if {$drive < 0x41 || $drive > 0x5a} { return 0 }
        set segments [split [string range $value 3 end] /]
    }
    foreach segment $segments {
        if {$segment eq {} || $segment in {. ..} ||
                [string first : $segment] >= 0} { return 0 }
    }
    return 1
}

proc ::stage1e::canonical_json_v1::validate_format {value format path} {
    if {$format eq {sha256}} {
        if {![is_sha256 $value]} { error "$path is not a canonical SHA-256 value." }
    } elseif {$format eq {canonical-absolute-path}} {
        if {![is_canonical_path $value]} { error "$path is not a canonical absolute path." }
    } elseif {$format in {token message canonical-reference}} {
        if {[string first [format %c 0] $value] >= 0} {
            error "$path contains a prohibited NUL character."
        }
        if {$format eq {canonical-reference} && [string first "\\" $value] >= 0} {
            error "$path contains a non-canonical backslash."
        }
    } else {
        error "Unsupported Stage 1E string format '$format' at $path."
    }
}

proc ::stage1e::canonical_json_v1::select_one_of {value schema root registry path} {
    set matches {}
    foreach candidate [array_values [object_get $schema oneOf]] {
        if {![catch {validate $value $candidate $root $registry $path {}}]} {
            lappend matches $candidate
        }
    }
    if {[llength $matches] != 1} {
        error "$path matches [llength $matches] oneOf branches; exactly one is required."
    }
    return [lindex $matches 0]
}

proc ::stage1e::canonical_json_v1::validate {
    value schema root registry {path {$}} {omit {}}
} {
    lassign [schema_resolve $schema $root $registry] schema root
    if {[object_has $schema oneOf]} {
        set selected [select_one_of $value $schema $root $registry $path]
        return [validate $value $selected $root $registry $path $omit]
    }
    if {[object_has $schema type]} {
        set type [node_value [object_get $schema type]]
        if {[node_type $value] ne $type} { error "$path must be a $type." }
        if {$type eq {object}} {
            foreach keyword {properties required additionalProperties
                    x-stage1e-canonical-order} {
                if {![object_has $schema $keyword]} {
                    error "$path uses an incomplete exact-object schema."
                }
            }
            if {[node_value [object_get $schema additionalProperties]]} {
                error "$path permits additional properties."
            }
            set properties [object_get $schema properties]
            set required_nodes [array_values [object_get $schema required]]
            set order_nodes [array_values [object_get $schema x-stage1e-canonical-order]]
            set expected {}
            foreach node $order_nodes {
                set name [node_value $node]
                if {[dict exists $expected $name] || ![object_has $properties $name]} {
                    error "$path has invalid canonical-order metadata."
                }
                dict set expected $name 1
            }
            if {[dict size $expected] != [llength [object_keys $properties]]} {
                error "$path canonical order is incomplete."
            }
            foreach node $required_nodes {
                set name [node_value $node]
                set omitted [expr {$path eq {$} && $omit ne {} && $name eq $omit}]
                if {!$omitted && ![object_has $value $name]} {
                    error "$path is missing required property '$name'."
                }
            }
            foreach name [object_keys $value] {
                if {![dict exists $expected $name]} {
                    error "$path contains unknown property '$name'."
                }
                if {$path eq {$} && $name eq $omit} {
                    error "$path identity payload must omit '$name'."
                }
            }
            foreach node $order_nodes {
                set name [node_value $node]
                if {[object_has $value $name]} {
                    validate [object_get $value $name] [object_get $properties $name] \
                        $root $registry "${path}.${name}" {}
                }
            }
        } elseif {$type eq {array}} {
            set values [array_values $value]
            if {[object_has $schema minItems] &&
                    [llength $values] < [node_value [object_get $schema minItems]]} {
                error "$path has too few items."
            }
            if {[object_has $schema maxItems] &&
                    [llength $values] > [node_value [object_get $schema maxItems]]} {
                error "$path has too many items."
            }
            if {[object_has $schema items]} {
                set index 0
                foreach item $values {
                    validate $item [object_get $schema items] $root $registry \
                        "${path}\[$index\]" {}
                    incr index
                }
            }
            if {[object_has $schema uniqueItems] &&
                    [node_value [object_get $schema uniqueItems]]} {
                for {set left 0} {$left < [llength $values]} {incr left} {
                    for {set right [expr {$left + 1}]} {$right < [llength $values]} {incr right} {
                        if {[node_equal [lindex $values $left] [lindex $values $right]]} {
                            error "$path contains duplicate array items."
                        }
                    }
                }
            }
        } elseif {$type eq {string}} {
            set scalar [node_value $value]
            if {[object_has $schema minLength] &&
                    [string length $scalar] < [node_value [object_get $schema minLength]]} {
                error "$path is too short."
            }
            if {[object_has $schema maxLength] &&
                    [string length $scalar] > [node_value [object_get $schema maxLength]]} {
                error "$path is too long."
            }
            if {[object_has $schema x-stage1e-format]} {
                validate_format $scalar [node_value [object_get $schema x-stage1e-format]] $path
            }
        } elseif {$type eq {integer}} {
            set scalar [node_value $value]
            if {[object_has $schema minimum] &&
                    $scalar < [node_value [object_get $schema minimum]]} {
                error "$path is below its minimum."
            }
            if {[object_has $schema maximum] &&
                    $scalar > [node_value [object_get $schema maximum]]} {
                error "$path exceeds its maximum."
            }
        }
    }
    if {[object_has $schema const] && ![node_equal $value [object_get $schema const]]} {
        error "$path does not match its constant."
    }
    if {[object_has $schema enum]} {
        set found 0
        foreach candidate [array_values [object_get $schema enum]] {
            if {[node_equal $value $candidate]} { set found 1; break }
        }
        if {!$found} { error "$path is not an allowed enum value." }
    }
    return 1
}

proc ::stage1e::canonical_json_v1::encode_string {value} {
    set result {"}
    set length [string length $value]
    for {set index 0} {$index < $length} {incr index} {
        set character [string index $value $index]
        set code [scan $character %c]
        if {$code == 0x22} {
            append result {\"}
        } elseif {$code == 0x5c} {
            append result {\\}
        } elseif {$code == 0x08} {
            append result {\b}
        } elseif {$code == 0x0c} {
            append result {\f}
        } elseif {$code == 0x0a} {
            append result {\n}
        } elseif {$code == 0x0d} {
            append result {\r}
        } elseif {$code == 0x09} {
            append result {\t}
        } elseif {$code < 0x20 || $code == 0x7f ||
                $code == 0x2028 || $code == 0x2029} {
            append result [format {\u%04x} $code]
        } elseif {$code >= 0xd800 && $code <= 0xdbff} {
            if {$index + 1 >= $length} {
                error {Cannot encode an unpaired high surrogate.}
            }
            set low_character [string index $value [expr {$index + 1}]]
            set low_code [scan $low_character %c]
            if {$low_code < 0xdc00 || $low_code > 0xdfff} {
                error {Cannot encode an unpaired high surrogate.}
            }
            append result $character $low_character
            incr index
        } elseif {$code >= 0xdc00 && $code <= 0xdfff} {
            error {Cannot encode an unpaired low surrogate.}
        } else {
            append result $character
        }
    }
    append result {"}
    return $result
}

proc ::stage1e::canonical_json_v1::encode_value {
    value schema root registry path omit
} {
    lassign [schema_resolve $schema $root $registry] schema root
    if {[object_has $schema oneOf]} {
        set schema [select_one_of $value $schema $root $registry $path]
        lassign [schema_resolve $schema $root $registry] schema root
    }
    set type [node_value [object_get $schema type]]
    if {$type eq {object}} {
        set result "\{"
        set first 1
        set properties [object_get $schema properties]
        foreach name_node [array_values [object_get $schema x-stage1e-canonical-order]] {
            set name [node_value $name_node]
            if {$path eq {$} && $name eq $omit} { continue }
            if {!$first} { append result , }
            set first 0
            append result [encode_string $name] :
            append result [encode_value [object_get $value $name] \
                [object_get $properties $name] $root $registry "${path}.${name}" {}]
        }
        append result "\}"
        return $result
    }
    if {$type eq {array}} {
        set result {[}
        set first 1
        set item_schema [object_get $schema items]
        set index 0
        foreach item [array_values $value] {
            if {!$first} { append result , }
            set first 0
            append result [encode_value $item $item_schema $root $registry \
                "${path}\[$index\]" {}]
            incr index
        }
        append result {]}
        return $result
    }
    if {$type eq {string}} { return [encode_string [node_value $value]] }
    if {$type eq {integer}} { return [node_value $value] }
    if {$type eq {boolean}} {
        if {[node_value $value]} { return true }
        return false
    }
    error "Unsupported canonical type '$type' at $path."
}

proc ::stage1e::canonical_json_v1::canonical_bytes {
    value schema registry {omit {}}
} {
    validate $value $schema $schema $registry {$} $omit
    set text [encode_value $value $schema $schema $registry {$} $omit]
    append text "\n"
    return [encoding convertto utf-8 $text]
}

proc ::stage1e::canonical_json_v1::bytes_equal {left right} {
    return [expr {[string length $left] == [string length $right] && $left eq $right}]
}

proc ::stage1e::canonical_json_v1::parse_canonical {bytes schema registry} {
    set value [parse_bytes $bytes]
    set canonical [canonical_bytes $value $schema $registry]
    if {![bytes_equal $bytes $canonical]} {
        return -code error -errorcode {STAGE1E JSON NONCANONICAL} \
            {JSON bytes are valid but are not the Stage 1E canonical representation.}
    }
    return $value
}

proc ::stage1e::canonical_json_v1::u32 {value} {
    return [expr {$value & 0xffffffff}]
}

proc ::stage1e::canonical_json_v1::ror {value count} {
    set value [u32 $value]
    return [u32 [expr {($value >> $count) |
        (($value << (32 - $count)) & 0xffffffff)}]]
}

proc ::stage1e::canonical_json_v1::sha256 {bytes} {
    variable sha256_constants {
        0x428a2f98 0x71374491 0xb5c0fbcf 0xe9b5dba5 0x3956c25b 0x59f111f1 0x923f82a4 0xab1c5ed5
        0xd807aa98 0x12835b01 0x243185be 0x550c7dc3 0x72be5d74 0x80deb1fe 0x9bdc06a7 0xc19bf174
        0xe49b69c1 0xefbe4786 0x0fc19dc6 0x240ca1cc 0x2de92c6f 0x4a7484aa 0x5cb0a9dc 0x76f988da
        0x983e5152 0xa831c66d 0xb00327c8 0xbf597fc7 0xc6e00bf3 0xd5a79147 0x06ca6351 0x14292967
        0x27b70a85 0x2e1b2138 0x4d2c6dfc 0x53380d13 0x650a7354 0x766a0abb 0x81c2c92e 0x92722c85
        0xa2bfe8a1 0xa81a664b 0xc24b8b70 0xc76c51a3 0xd192e819 0xd6990624 0xf40e3585 0x106aa070
        0x19a4c116 0x1e376c08 0x2748774c 0x34b0bcb5 0x391c0cb3 0x4ed8aa4a 0x5b9cca4f 0x682e6ff3
        0x748f82ee 0x78a5636f 0x84c87814 0x8cc70208 0x90befffa 0xa4506ceb 0xbef9a3f7 0xc67178f2
    }
    binary scan $bytes c* signed_octets
    set octets {}
    foreach octet $signed_octets {
        if {$octet < 0} { incr octet 256 }
        lappend octets $octet
    }
    set bit_length [expr {[llength $octets] * 8}]
    lappend octets 128
    while {[llength $octets] % 64 != 56} { lappend octets 0 }
    for {set shift 56} {$shift >= 0} {incr shift -8} {
        lappend octets [expr {($bit_length >> $shift) & 0xff}]
    }
    set hashes {
        0x6a09e667 0xbb67ae85 0x3c6ef372 0xa54ff53a
        0x510e527f 0x9b05688c 0x1f83d9ab 0x5be0cd19
    }
    for {set offset 0} {$offset < [llength $octets]} {incr offset 64} {
        set words {}
        for {set index 0} {$index < 16} {incr index} {
            set base [expr {$offset + $index * 4}]
            lappend words [expr {([lindex $octets $base] << 24) |
                ([lindex $octets [expr {$base + 1}]] << 16) |
                ([lindex $octets [expr {$base + 2}]] << 8) |
                [lindex $octets [expr {$base + 3}]]}]
        }
        for {set index 16} {$index < 64} {incr index} {
            set x [lindex $words [expr {$index - 15}]]
            set y [lindex $words [expr {$index - 2}]]
            set s0 [expr {[ror $x 7] ^ [ror $x 18] ^ ([u32 $x] >> 3)}]
            set s1 [expr {[ror $y 17] ^ [ror $y 19] ^ ([u32 $y] >> 10)}]
            lappend words [u32 [expr {[lindex $words [expr {$index - 16}]] +
                $s0 + [lindex $words [expr {$index - 7}]] + $s1}]]
        }
        lassign $hashes a b c d e f g h
        for {set index 0} {$index < 64} {incr index} {
            set sum1 [expr {[ror $e 6] ^ [ror $e 11] ^ [ror $e 25]}]
            set choice [expr {([u32 $e] & [u32 $f]) ^
                (([u32 $e] ^ 0xffffffff) & [u32 $g])}]
            set temp1 [u32 [expr {$h + $sum1 + $choice +
                [lindex $sha256_constants $index] + [lindex $words $index]}]]
            set sum0 [expr {[ror $a 2] ^ [ror $a 13] ^ [ror $a 22]}]
            set majority [expr {([u32 $a] & [u32 $b]) ^
                ([u32 $a] & [u32 $c]) ^ ([u32 $b] & [u32 $c])}]
            set temp2 [u32 [expr {$sum0 + $majority}]]
            set h $g
            set g $f
            set f $e
            set e [u32 [expr {$d + $temp1}]]
            set d $c
            set c $b
            set b $a
            set a [u32 [expr {$temp1 + $temp2}]]
        }
        set updated {}
        foreach old $hashes current [list $a $b $c $d $e $f $g $h] {
            lappend updated [u32 [expr {$old + $current}]]
        }
        set hashes $updated
    }
    set result {}
    foreach value $hashes { append result [format %08x [u32 $value]] }
    return $result
}

proc ::stage1e::canonical_json_v1::digest_file {path} {
    if {$path eq {}} {
        return -code error -errorcode {STAGE1E JSON FILE_DIGEST} \
            {File digest input path must not be empty.}
    }
    if {[catch {file normalize $path} normalized_path] ||
        ![file exists $normalized_path] || ![file isfile $normalized_path]} {
        return -code error -errorcode {STAGE1E JSON FILE_DIGEST} \
            {File digest input must be one existing regular file.}
    }
    if {![info exists ::env(SystemRoot)] || $::env(SystemRoot) eq {}} {
        return -code error -errorcode {STAGE1E JSON FILE_DIGEST} \
            {Required SystemRoot for the file digest provider is unavailable.}
    }
    if {[catch {
        file normalize [file join $::env(SystemRoot) System32 certutil.exe]
    } provider] || ![file exists $provider] || ![file isfile $provider] ||
        ![file executable $provider]} {
        return -code error -errorcode {STAGE1E JSON FILE_DIGEST} \
            {Required fixed file digest provider certutil.exe is unavailable.}
    }
    set command [list $provider -hashfile $normalized_path SHA256]
    if {[catch {exec {*}$command 2>@1} output]} {
        return -code error -errorcode {STAGE1E JSON FILE_DIGEST} \
            {certutil.exe did not complete file hashing successfully.}
    }
    set candidates {}
    foreach line [split $output "\n"] {
        set line [string trim $line]
        if {[string length $line] == 64 &&
                [string is xdigit -strict $line]} {
            lappend candidates $line
        }
    }
    if {[llength $candidates] != 1} {
        return -code error -errorcode {STAGE1E JSON FILE_DIGEST} \
            {certutil.exe output did not contain exactly one SHA-256 result line.}
    }
    set digest [string tolower [lindex $candidates 0]]
    if {![is_sha256 $digest]} {
        return -code error -errorcode {STAGE1E JSON FILE_DIGEST} \
            {certutil.exe returned a malformed SHA-256 result.}
    }
    return $digest
}

proc ::stage1e::canonical_json_v1::digest_bytes {bytes {provider {}}} {
    if {$provider eq {}} {
        set digest [sha256 $bytes]
    } else {
        set digest [uplevel #0 [linsert $provider end $bytes]]
    }
    if {![is_sha256 $digest]} {
        return -code error -errorcode {STAGE1E JSON DIGEST} \
            {Digest provider did not return a canonical SHA-256 value.}
    }
    return $digest
}
