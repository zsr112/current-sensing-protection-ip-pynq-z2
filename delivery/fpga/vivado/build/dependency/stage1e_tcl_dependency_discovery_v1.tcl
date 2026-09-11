# Stage 1E PRT02-E conservative Tcl static dependency discovery v1.
#
# This scanner parses the admitted Tcl command subset without sourcing the
# candidate. Any source expression without one unique repository literal, or
# any ambient package/evaluator/unknown-command construct, is blocking.

namespace eval ::stage1e::tcl_dependency_discovery_v1 {
    variable interface_version stage1e-tcl-dependency-discovery-interface-v1
    variable records {}
    variable blocked {}
    variable procedure_depth 0
    variable node_by_leaf {}
    variable node_by_path {}
    variable repository_root {}
    variable fixed_paths {}
    variable current_source_absolute {}
    variable current_namespace ::
}

proc ::stage1e::tcl_dependency_discovery_v1::interface_version {} {
    variable interface_version
    return $interface_version
}

proc ::stage1e::tcl_dependency_discovery_v1::_raise {code message} {
    return -code error -errorcode [list STAGE1E PRT02E TCL_DISCOVERY $code] \
        $message
}

proc ::stage1e::tcl_dependency_discovery_v1::_read_text {path} {
    set channel [open $path rb]
    try {
        set bytes [read $channel]
    } finally {
        close $channel
    }
    if {[string range $bytes 0 2] eq "\xef\xbb\xbf"} {
        _raise UTF8_BOM "Tcl source contains a UTF-8 BOM: $path"
    }
    if {[catch {encoding convertfrom utf-8 $bytes} text]} {
        _raise UTF8_INVALID "Tcl source is not strict UTF-8: $path"
    }
    return $text
}

proc ::stage1e::tcl_dependency_discovery_v1::_strict_dictionary {
    text label {depth 0} {require_dictionary 1}
} {
    if {$depth > 64} { _raise CONTRACT_INVALID "Dictionary nesting is excessive: $label" }
    if {[catch {llength $text}]} {
        _raise CONTRACT_INVALID "Dictionary value is not a Tcl list: $label"
    }
    set items [lrange $text 0 end]
    set looks_dictionary [expr {[llength $items] > 0 && ([llength $items] % 2) == 0}]
    if {$looks_dictionary} {
        foreach {key value} $items {
            if {![regexp {^[A-Za-z_$][A-Za-z0-9_:$.-]*$} $key]} {
                set looks_dictionary 0
                break
            }
        }
    }
    if {$require_dictionary && !$looks_dictionary} {
        _raise CONTRACT_INVALID "$label is not an alternating Tcl dictionary."
    }
    if {$looks_dictionary} {
        set result {}
        foreach {key value} $items {
            if {[dict exists $result $key]} {
                _raise CONTRACT_INVALID "$label contains duplicate key '$key'."
            }
            dict set result $key $value
            # Recurse only when the nested value itself has dictionary shape;
            # this preserves scalar Tcl values while rejecting duplicate keys
            # in every alternating nested record.
            if {![catch {llength $value}]} {
                set nested [lrange $value 0 end]
                set nested_shape [expr {[llength $nested] > 0 &&
                    ([llength $nested] % 2) == 0}]
                if {$nested_shape} {
                    foreach {nested_key nested_value} $nested {
                        if {![regexp {^[A-Za-z_$][A-Za-z0-9_:$.-]*$} $nested_key]} {
                            set nested_shape 0
                            break
                        }
                    }
                }
                if {$nested_shape} {
                    _strict_dictionary $value "$label.$key" \
                        [expr {$depth + 1}] 1
                }
            }
        }
        return $result
    }
    return $items
}

proc ::stage1e::tcl_dependency_discovery_v1::_read_dictionary {path} {
    set text [string trim [_read_text $path]]
    _strict_dictionary $text $path 0 1
    return $text
}

proc ::stage1e::tcl_dependency_discovery_v1::_line_at {text index} {
    return [expr {1 + [regexp -all {\n} [string range $text 0 $index]]}]
}

proc ::stage1e::tcl_dependency_discovery_v1::_lexical_normalize_path {path} {
    set mapped [string map {\\ /} $path]
    set prefix {}
    if {[regexp {^([A-Za-z]:)(/.*)?$} $mapped -> drive rest]} {
        set prefix $drive
        set mapped $rest
    } elseif {[string index $mapped 0] eq {/}} {
        set prefix /
    } else {
        return $mapped
    }
    set components {}
    foreach component [split [string trimleft $mapped /] /] {
        if {$component eq {} || $component eq {.}} { continue }
        if {$component eq {..}} {
            if {![llength $components]} {
                _raise PATH_ESCAPE "Path traverses above its absolute root: $path"
            }
            set components [lrange $components 0 end-1]
            continue
        }
        lappend components $component
    }
    if {$prefix eq {/}} { return "/[join $components /]" }
    return "${prefix}/[join $components /]"
}

proc ::stage1e::tcl_dependency_discovery_v1::_commands {script {base_line 1}} {
    set commands {}
    set length [string length $script]
    set start 0
    set line $base_line
    set command_line $base_line
    set brace 0
    set bracket 0
    set quote 0
    set escaped 0
    set comment 0
    set command_has_text 0
    for {set index 0} {$index < $length} {incr index} {
        set character [string index $script $index]
        if {$escaped} {
            set escaped 0
            if {$character eq "\n"} { incr line }
            continue
        }
        if {$character eq "\\"} {
            set escaped 1
            continue
        }
        if {$comment} {
            if {$character eq "\n"} {
                set comment 0
                incr line
                set start [expr {$index + 1}]
                set command_line $line
            }
            continue
        }
        if {!$quote && !$brace && !$bracket && !$command_has_text &&
            $character eq {#}} {
            set comment 1
            continue
        }
        if {$character eq {"} && !$brace} {
            set quote [expr {!$quote}]
            set command_has_text 1
            continue
        }
        if {!$quote} {
            if {$character eq "\{"} { incr brace }
            if {$character eq "\}"} {
                incr brace -1
                if {$brace < 0} { _raise PARSE {Unmatched closing brace.} }
            }
            if {!$brace && $character eq {[}} { incr bracket }
            if {!$brace && $character eq {]}} {
                incr bracket -1
                if {$bracket < 0} { _raise PARSE {Unmatched closing bracket.} }
            }
        }
        if {$character eq "\n"} { incr line }
        if {!$quote && !$brace && !$bracket &&
            ($character eq ";" || $character eq "\n")} {
            set command [string trim [string range $script $start \
                [expr {$index - 1}]]]
            if {$command ne {}} { lappend commands [list $command_line $command] }
            set start [expr {$index + 1}]
            set command_line $line
            set command_has_text 0
            continue
        }
        if {![string is space $character]} { set command_has_text 1 }
    }
    if {$quote || $brace || $bracket || $escaped} {
        _raise PARSE {Tcl source contains an unterminated command construct.}
    }
    set command [string trim [string range $script $start end]]
    if {$command ne {}} { lappend commands [list $command_line $command] }
    return $commands
}

proc ::stage1e::tcl_dependency_discovery_v1::_words {command} {
    regsub -all {\\\r?\n[ \t]*} $command { } command
    set words {}
    set length [string length $command]
    set index 0
    while {$index < $length} {
        while {$index < $length && [string is space [string index $command $index]]} {
            incr index
        }
        if {$index >= $length} { break }
        set start $index
        set first [string index $command $index]
        if {$first eq "\{"} {
            set depth 1
            incr index
            set content_start $index
            set escaped 0
            while {$index < $length && $depth} {
                set character [string index $command $index]
                if {$escaped} { set escaped 0; incr index; continue }
                if {$character eq "\\"} { set escaped 1; incr index; continue }
                if {$character eq "\{"} { incr depth }
                if {$character eq "\}"} { incr depth -1 }
                incr index
            }
            if {$depth} { _raise PARSE {Unmatched braced Tcl word.} }
            set value [string range $command $content_start [expr {$index - 2}]]
            lappend words [dict create raw [string range $command $start \
                [expr {$index - 1}]] value $value braced 1]
            continue
        }
        set quote 0
        set bracket 0
        set escaped 0
        while {$index < $length} {
            set character [string index $command $index]
            if {$escaped} { set escaped 0; incr index; continue }
            if {$character eq "\\"} { set escaped 1; incr index; continue }
            if {$character eq {"}} { set quote [expr {!$quote}]; incr index; continue }
            if {$character eq {[}} { incr bracket }
            if {$character eq {]}} { incr bracket -1 }
            if {!$quote && !$bracket && [string is space $character]} { break }
            incr index
        }
        set raw [string range $command $start [expr {$index - 1}]]
        set value [string trim $raw {"}]
        lappend words [dict create raw $raw value $value braced 0]
    }
    return $words
}

# Return every active command substitution contained in a command. Tcl
# substitutes brackets in double-quoted words, while brackets in braced words
# are literal. The walker preserves that distinction without evaluating code.
proc ::stage1e::tcl_dependency_discovery_v1::_bracket_scripts {command} {
    set open_brace [format %c 123]
    set close_brace [format %c 125]
    set open_bracket [format %c 91]
    set close_bracket [format %c 93]
    set backslash [format %c 92]
    set quote_character [format %c 34]
    set scripts {}
    set length [string length $command]
    set index 0
    set outer_brace 0
    set outer_quote 0
    set outer_escaped 0
    while {$index < $length} {
        set character [string index $command $index]
        if {$outer_escaped} { set outer_escaped 0; incr index; continue }
        if {$character eq $backslash} { set outer_escaped 1; incr index; continue }
        if {$outer_brace > 0} {
            if {$character eq $open_brace} { incr outer_brace }
            if {$character eq $close_brace} { incr outer_brace -1 }
            incr index
            continue
        }
        if {$character eq $quote_character} {
            set outer_quote [expr {!$outer_quote}]
            incr index
            continue
        }
        if {!$outer_quote && $character eq $open_brace} {
            set outer_brace 1
            incr index
            continue
        }
        if {$character ne $open_bracket} {
            incr index
            continue
        }
        set start [incr index]
        set depth 1
        set brace 0
        set quote 0
        set escaped 0
        while {$index < $length && $depth > 0} {
            set current [string index $command $index]
            if {$escaped} { set escaped 0; incr index; continue }
            if {$current eq $backslash} { set escaped 1; incr index; continue }
            if {$brace > 0} {
                if {$current eq $open_brace} { incr brace }
                if {$current eq $close_brace} { incr brace -1 }
                incr index
                continue
            }
            if {$current eq $quote_character} {
                set quote [expr {!$quote}]
                incr index
                continue
            }
            if {!$quote && $current eq $open_brace} { set brace 1; incr index; continue }
            if {$current eq $open_bracket} { incr depth; incr index; continue }
            if {$current eq $close_bracket} { incr depth -1; incr index; continue }
            incr index
        }
        if {$depth != 0 || $quote || $brace} {
            return -code error -errorcode {STAGE1E PRT02E PARSE BRACKET} \
                {Unterminated Tcl command substitution.}
        }
        lappend scripts [string range $command $start [expr {$index - 2}]]
    }
    return $scripts
}

proc ::stage1e::tcl_dependency_discovery_v1::_record {fields} {
    variable records
    lappend records $fields
}

proc ::stage1e::tcl_dependency_discovery_v1::_block {path line code detail} {
    variable blocked
    lappend blocked [dict create path $path line $line code $code detail $detail]
}

proc ::stage1e::tcl_dependency_discovery_v1::_variable_key {name} {
    variable current_namespace
    if {[string match {${*}} $name]} {
        set name [string range $name 2 end-1]
    } elseif {[string index $name 0] eq {$}} {
        set name [string range $name 1 end]
    }
    if {![regexp {^(?:::)?[A-Za-z_][A-Za-z0-9_:]*$} $name] ||
        [string first {(} $name] >= 0} {
        return {}
    }
    if {[string first {::} $name] == 0} { return $name }
    if {$current_namespace eq {::}} { return "::$name" }
    return "[string trimright $current_namespace :]::$name"
}

proc ::stage1e::tcl_dependency_discovery_v1::_resolved {value form} {
    return [dict create state RESOLVED value $value form $form]
}

proc ::stage1e::tcl_dependency_discovery_v1::_unresolved {detail} {
    return [dict create state UNRESOLVED detail $detail]
}

proc ::stage1e::tcl_dependency_discovery_v1::_resolve_path_word {
    path line word
} {
    variable fixed_paths
    set raw [string trim [dict get $word raw]]
    if {[dict get $word braced]} {
        set literal [dict get $word value]
        if {[regexp {[$\[\]*?]} $literal]} {
            return [_unresolved "nonliteral braced path component: $raw"]
        }
        return [_resolved $literal LITERAL_COMPONENT]
    }
    if {[regexp {^\$(?:::)?[A-Za-z_][A-Za-z0-9_:]*$} $raw] ||
        [regexp {^\$\{(?:::)?[A-Za-z_][A-Za-z0-9_:]*\}$} $raw]} {
        set key [_variable_key $raw]
        if {$key ne {} && [dict exists $fixed_paths $key]} {
            return [_resolved [dict get $fixed_paths $key] FIXED_SOURCE_VARIABLE]
        }
        return [_unresolved "unproved source variable: $raw"]
    }
    if {[string index $raw 0] eq {[} && [string index $raw end] eq {]}} {
        set substitutions [_bracket_scripts $raw]
        if {[llength $substitutions] != 1} {
            return [_unresolved "compound command-selected path: $raw"]
        }
        set inner [string range $raw 1 end-1]
        if {$inner ne [lindex $substitutions 0]} {
            return [_unresolved "compound command-selected path: $raw"]
        }
        return [_resolve_path_command $path $line [string range $raw 1 end-1]]
    }
    if {[string index $raw 0] eq {"} && [string index $raw end] eq {"}} {
        set raw [string range $raw 1 end-1]
    }
    if {$raw eq {} || [regexp {[$\[\]*?]} $raw] ||
        [string first {::env(} $raw] >= 0} {
        return [_unresolved "dynamic or wildcard path component: $raw"]
    }
    return [_resolved $raw LITERAL_COMPONENT]
}

proc ::stage1e::tcl_dependency_discovery_v1::_resolve_path_command {
    path line script
} {
    variable current_source_absolute
    set words [_words $script]
    if {![llength $words]} { return [_unresolved {empty path command}] }
    set name [dict get [lindex $words 0] value]
    if {$name eq {info} && [llength $words] == 2 &&
        [dict get [lindex $words 1] value] eq {script}} {
        return [_resolved $current_source_absolute INFO_SCRIPT]
    }
    if {$name ne {file} || [llength $words] < 3} {
        return [_unresolved "unadmitted path command: $script"]
    }
    set operation [dict get [lindex $words 1] value]
    if {$operation in {dirname normalize}} {
        if {[llength $words] != 3} {
            return [_unresolved "invalid file $operation arity: $script"]
        }
        set operand [_resolve_path_word $path $line [lindex $words 2]]
        if {[dict get $operand state] ne {RESOLVED}} { return $operand }
        set value [dict get $operand value]
        if {$operation eq {dirname}} { set value [file dirname $value] }
        if {$operation eq {normalize}} { set value [_lexical_normalize_path $value] }
        return [_resolved $value "FILE_[string toupper $operation]"]
    }
    if {$operation ne {join}} {
        return [_unresolved "unadmitted file operation in source path: $script"]
    }
    set components {}
    foreach word [lrange $words 2 end] {
        set component [_resolve_path_word $path $line $word]
        if {[dict get $component state] ne {RESOLVED}} { return $component }
        lappend components [dict get $component value]
    }
    if {![llength $components]} { return [_unresolved {empty file join}] }
    return [_resolved [file join {*}$components] FILE_JOIN]
}

proc ::stage1e::tcl_dependency_discovery_v1::_remember_fixed_path {
    path line variable_word value_word
} {
    variable fixed_paths
    variable procedure_depth
    if {$procedure_depth != 0} { return }
    set key [_variable_key [dict get $variable_word value]]
    if {$key eq {} || [string match {::env(*)} $key] || $key eq {::auto_path}} {
        return
    }
    set resolved [_resolve_path_word $path $line $value_word]
    if {[dict get $resolved state] ne {RESOLVED}} { return }
    set value [dict get $resolved value]
    if {[file pathtype $value] eq {absolute}} {
        dict set fixed_paths $key [_lexical_normalize_path $value]
    }
}

proc ::stage1e::tcl_dependency_discovery_v1::_source_target {
    path line command words
} {
    variable repository_root
    variable node_by_path
    if {[llength $words] != 2} {
        _block $path $line UNRESOLVED_DYNAMIC_DEPENDENCY $command
        return
    }
    set resolved [_resolve_path_word $path $line [lindex $words 1]]
    if {[dict get $resolved state] ne {RESOLVED}} {
        _block $path $line UNRESOLVED_DYNAMIC_DEPENDENCY \
            "[dict get $resolved detail]: $command"
        return
    }
    set value [dict get $resolved value]
    if {[file pathtype $value] ne {absolute}} {
        _block $path $line UNRESOLVED_DYNAMIC_DEPENDENCY \
            "cwd-dependent source path: $command"
        return
    }
    set absolute [_lexical_normalize_path $value]
    set prefix [string trimright [string map {\\ /} $repository_root] /]
    set normalized [string map {\\ /} $absolute]
    if {[string first "${prefix}/" "${normalized}/"] != 0} {
        _block $path $line PATH_ESCAPE $absolute
        return
    }
    set relative [string range $normalized [expr {[string length $prefix] + 1}] end]
    if {![dict exists $node_by_path $relative]} {
        _block $path $line UNDECLARED_SOURCE $relative
        return
    }
    set target [dict get $node_by_path $relative]
    if {[dict get $target language] ne {TCL} ||
        [dict get $target node_class] in {NON_RUNTIME_SOURCE REVIEW_TOOL_SOURCE}} {
        _block $path $line UNDECLARED_SOURCE $relative
        return
    }
    _record [dict create kind EDGE path $path line $line edge_type TCL_SOURCE \
        target [dict get $target node_id] target_path $relative \
        resolution STRUCTURAL_FIXED_PATH_EXPRESSION]
}

proc ::stage1e::tcl_dependency_discovery_v1::_scan_nested_substitution {
    path script line
} {
    set words [_words $script]
    if {![llength $words]} {
        _block $path $line UNRESOLVED_DYNAMIC_DEPENDENCY $script
        return
    }
    set name [dict get [lindex $words 0] value]
    if {[string first {$} $name] == 0 ||
        [string first {::env(} $name] >= 0 ||
        [string first {[} $name] >= 0} {
        _block $path $line UNRESOLVED_DYNAMIC_DEPENDENCY $script
        return
    }
    _scan_script $path $script $line
}

proc ::stage1e::tcl_dependency_discovery_v1::_scan_script {
    path script {base_line 1}
} {
    variable procedure_depth
    variable current_namespace
    variable fixed_paths
    foreach command_record [_commands $script $base_line] {
        lassign $command_record line command
        set words [_words $command]
        if {![llength $words]} { continue }
        set name [dict get [lindex $words 0] value]
        if {[string first {$} $name] == 0 ||
            [string first {[} $name] >= 0 ||
            [string first {::env(} $name] >= 0} {
            _block $path $line UNRESOLVED_DYNAMIC_DEPENDENCY $command
        }
        switch -exact -- $name {
            source {
                _source_target $path $line $command $words
            }
            package - load {
                _block $path $line AMBIENT_MODULE_OR_PACKAGE $command
            }
            exec - socket - cd {
                if {$procedure_depth == 0} {
                    _block $path $line SOURCE_TIME_MUTATION $command
                }
            }
            open {
                if {[llength $words] >= 3} {
                    set mode [string toupper [dict get [lindex $words 2] value]]
                    if {$procedure_depth == 0 && [regexp {(^|[[:space:]])(W\+?|A\+?|WRONLY|RDWR|CREAT|TRUNC|APPEND)([[:space:]]|$)} $mode]} {
                        _block $path $line SOURCE_TIME_MUTATION $command
                    }
                }
            }
            file {
                if {[llength $words] >= 2 &&
                    [dict get [lindex $words 1] value] in {delete rename copy mkdir}} {
                    if {$procedure_depth == 0} {
                        _block $path $line SOURCE_TIME_MUTATION $command
                    }
                } elseif {[llength $words] >= 3 &&
                    [dict get [lindex $words 1] value] eq {attributes}} {
                    if {$procedure_depth == 0} {
                        _block $path $line SOURCE_TIME_MUTATION $command
                    }
                }
            }
            chan {
                if {[llength $words] >= 2 &&
                    [dict get [lindex $words 1] value] eq {configure}} {
                    if {$procedure_depth == 0} {
                        _block $path $line SOURCE_TIME_MUTATION $command
                    }
                }
            }
            set {
                if {[llength $words] >= 2 &&
                    [string match {::env(*)} [dict get [lindex $words 1] value]]} {
                    if {$procedure_depth == 0} {
                        _block $path $line SOURCE_TIME_MUTATION $command
                    }
                }
                if {[llength $words] >= 2 &&
                    [dict get [lindex $words 1] value] eq {::auto_path}} {
                    _block $path $line SOURCE_TIME_MUTATION $command
                }
                if {[llength $words] == 3} {
                    _remember_fixed_path $path $line [lindex $words 1] \
                        [lindex $words 2]
                }
            }
            variable {
                if {$procedure_depth == 0 && [llength $words] >= 3} {
                    for {set index 1} {$index + 1 < [llength $words]} \
                            {incr index 2} {
                        _remember_fixed_path $path $line [lindex $words $index] \
                            [lindex $words [expr {$index + 1}]]
                    }
                }
            }
            unset {
                if {$procedure_depth == 0} {
                    foreach word [lrange $words 1 end] {
                        set key [_variable_key [dict get $word value]]
                        if {$key ne {} && [dict exists $fixed_paths $key]} {
                            dict unset fixed_paths $key
                        }
                    }
                }
            }
            exit {
                if {$procedure_depth == 0} {
                    _block $path $line SOURCE_TIME_TERMINATION $command
                }
            }
            unknown {
                _block $path $line UNKNOWN_COMMAND_PROVIDER $command
            }
            eval {
                _block $path $line UNRESOLVED_DYNAMIC_DEPENDENCY $command
            }
            uplevel {
                if {[string first {$after_temporary_close} $command] < 0 &&
                    [string first {$after_rename} $command] < 0 &&
                    [string first {$provider end} $command] < 0 &&
                    [string first {$verifier end} $command] < 0} {
                    _block $path $line UNRESOLVED_DYNAMIC_DEPENDENCY $command
                } else {
                    _record [dict create kind GUARDED_CALLBACK path $path \
                        line $line edge_type CALLBACK_TARGET target TEST_HOOK]
                }
            }
            proc {
                if {[llength $words] < 4} {
                    _block $path $line PARSE {Malformed proc definition.}
                } else {
                    set provider [dict get [lindex $words 1] value]
                    if {$provider eq {unknown} || [string match {*::unknown} $provider]} {
                        _block $path $line UNKNOWN_COMMAND_PROVIDER $provider
                    }
                    set qualified $provider
                    if {[string first {::} $qualified] != 0} {
                        if {$current_namespace eq {::}} {
                            set qualified "::$qualified"
                        } else {
                            set qualified "[string trimright $current_namespace :]::$qualified"
                        }
                    }
                    _record [dict create kind PROVIDER path $path line $line \
                        provider $qualified fully_qualified 1]
                    set body [lindex $words end]
                    if {[dict get $body braced]} {
                        incr procedure_depth
                        _scan_script $path [dict get $body value] $line
                        incr procedure_depth -1
                    }
                }
            }
            if {
                set expect_body 1
                foreach word [lrange $words 2 end] {
                    set value [dict get $word value]
                    if {$value eq {elseif}} { set expect_body 0; continue }
                    if {$value eq {else}} { set expect_body 1; continue }
                    if {$expect_body && [dict get $word braced]} {
                        _scan_script $path $value $line
                        set expect_body 0
                    } elseif {!$expect_body} {
                        set expect_body 1
                    }
                }
            }
            try - catch - foreach - for - while {
                set body_words [switch -exact -- $name {
                    foreach - for - while { list [lindex $words end] }
                    catch { list [lindex $words end] }
                    default { lrange $words 1 end }
                }]
                foreach word $body_words {
                    if {[dict get $word braced]} {
                        _scan_script $path [dict get $word value] $line
                    }
                }
            }
            namespace {
                if {[llength $words] >= 2} {
                    set operation [dict get [lindex $words 1] value]
                    if {$operation in {import path unknown ensemble}} {
                        _block $path $line AMBIENT_NAMESPACE_RESOLUTION $command
                    }
                    if {$operation eq {eval} && [llength $words] >= 4 &&
                        [dict get [lindex $words end] braced]} {
                        set namespace_name [dict get [lindex $words 2] value]
                        if {![regexp {^::[A-Za-z_][A-Za-z0-9_:]*$} $namespace_name]} {
                            _block $path $line AMBIENT_NAMESPACE_RESOLUTION $command
                        } else {
                            set prior_namespace $current_namespace
                            set current_namespace $namespace_name
                            try {
                                _scan_script $path \
                                    [dict get [lindex $words end] value] $line
                            } finally {
                                set current_namespace $prior_namespace
                            }
                        }
                    }
                }
            }
            interp - rename {
                if {[string first {interp alias} $command] >= 0 || $name eq {rename}} {
                    _block $path $line PROVIDER_REDEFINITION $command
                }
            }
        }
        # Scan substitutions after the outer command.  This catches nested
        # source/eval/uplevel/unknown constructs regardless of their position
        # in a word and makes unresolved dynamic names blocking by default.
        foreach nested [_bracket_scripts $command] {
            _scan_nested_substitution $path $nested $line
        }
    }
}

proc ::stage1e::tcl_dependency_discovery_v1::_scan_references {path text} {
    variable records
    variable node_by_leaf
    foreach suffix {{.dict} {.schema.json}} edge_type {CONFIG_READ SCHEMA_PROVIDER} {
        set escaped_suffix [string map {. {\.}} $suffix]
        set pattern [format {(stage1e_[A-Za-z0-9_]+%s)} $escaped_suffix]
        foreach match [lsort -unique [regexp -all -inline $pattern $text]] {
            if {![string match "*${suffix}" $match]} { continue }
            if {![dict exists $node_by_leaf $match] ||
                [llength [dict get $node_by_leaf $match]] != 1} {
                _block $path 1 UNDECLARED_CONFIG_OR_SCHEMA $match
                continue
            }
            set target [lindex [dict get $node_by_leaf $match] 0]
            _record [dict create kind EDGE path $path line 1 \
                edge_type $edge_type target [dict get $target node_id] \
                target_path [dict get $target repository_path]]
        }
    }
    set capabilities {
        {version VIVADO_2024_1_QUERY_SURFACE}
        {get_property VIVADO_2024_1_QUERY_SURFACE}
        {get_runs VIVADO_2024_1_QUERY_SURFACE}
        {current_run VIVADO_2024_1_QUERY_SURFACE}
        {current_project VIVADO_2024_1_QUERY_SURFACE}
        {current_design VIVADO_2024_1_QUERY_SURFACE}
        {launch_runs VIVADO_2024_1_CONTROL_SURFACE}
        {wait_on_run VIVADO_2024_1_CONTROL_SURFACE}
        {open_run VIVADO_2024_1_CONTROL_SURFACE}
        {report_timing_summary VIVADO_2024_1_REPORT_SURFACE}
        {report_timing VIVADO_2024_1_REPORT_SURFACE}
        {report_clock_interaction VIVADO_2024_1_REPORT_SURFACE}
        {report_clocks VIVADO_2024_1_REPORT_SURFACE}
        {report_exceptions VIVADO_2024_1_REPORT_SURFACE}
        {check_timing VIVADO_2024_1_REPORT_SURFACE}
        {report_utilization VIVADO_2024_1_REPORT_SURFACE}
        {report_drc VIVADO_2024_1_REPORT_SURFACE}
        {report_methodology VIVADO_2024_1_REPORT_SURFACE}
        {report_cdc VIVADO_2024_1_REPORT_SURFACE}
        {report_bus_skew VIVADO_2024_1_REPORT_SURFACE}
        {report_route_status VIVADO_2024_1_REPORT_SURFACE}
    }
    foreach mapping $capabilities {
        lassign $mapping command capability
        set command_pattern [format {(^|[^A-Za-z0-9_])%s([^A-Za-z0-9_]|$)} \
            $command]
        if {[regexp $command_pattern $text]} {
            _record [dict create kind CAPABILITY path $path line 1 \
                capability $capability command $command]
        }
    }
    if {[regexp {(^|[^A-Za-z0-9_])auto_path([^A-Za-z0-9_]|$)} $text]} {
        _block $path 1 AMBIENT_MODULE_OR_PACKAGE auto_path
    }
}

proc ::stage1e::tcl_dependency_discovery_v1::discover {
    selected_root graph_path output_path
} {
    variable records
    variable blocked
    variable node_by_leaf
    variable node_by_path
    variable repository_root
    variable fixed_paths
    variable current_source_absolute
    variable current_namespace
    set records {}
    set blocked {}
    set node_by_leaf {}
    set node_by_path {}
    # Preserve the caller-selected path lexically. Git-for-Windows Tcl can
    # otherwise rewrite the AppData junction differently for a root and its
    # children, producing a false containment result.
    set repository_root [_lexical_normalize_path $selected_root]
    set graph [_read_dictionary $graph_path]
    if {[dict get $graph schema_version] ne \
        {stage1e-runtime-declared-graph-v1}} {
        _raise CONTRACT_VERSION {Declared graph version mismatch.}
    }
    foreach node [dict get $graph nodes] {
        set path [dict get $node repository_path]
        dict lappend node_by_leaf [file tail $path] $node
        dict set node_by_path $path $node
    }
    set sources {}
    foreach node [dict get $graph nodes] {
        if {[dict get $node node_class] in {NON_RUNTIME_SOURCE REVIEW_TOOL_SOURCE}} { continue }
        if {[dict get $node language] ne {TCL}} { continue }
        lappend sources $node
    }
    foreach node [lsort -command \
        ::stage1e::tcl_dependency_discovery_v1::_compare_ordinal $sources] {
        set relative [dict get $node repository_path]
        set absolute [_lexical_normalize_path \
            [file join $repository_root {*}[split $relative /]]]
        set prefix [string trimright [string map {\\ /} $repository_root] /]
        set normalized [string map {\\ /} $absolute]
        if {[string first "${prefix}/" "${normalized}/"] != 0} {
            _block $relative 1 PATH_ESCAPE $absolute
            continue
        }
        if {![file exists $absolute] || ![file isfile $absolute]} {
            _block $relative 1 MISSING_SOURCE $absolute
            continue
        }
        set text [_read_text $absolute]
        set fixed_paths {}
        set current_source_absolute $absolute
        set current_namespace ::
        _record [dict create kind SOURCE path $relative line 1 \
            node_id [dict get $node node_id] parse_state PARSED]
        if {[catch {_scan_script $relative $text 1} message options]} {
            _block $relative 1 PARSE $message
        }
        _scan_references $relative $text
    }
    set output [open $output_path {WRONLY CREAT EXCL}]
    fconfigure $output -encoding utf-8 -translation lf
    try {
        foreach record $records {
            set fields {}
            foreach key [lsort -dictionary [dict keys $record]] {
                set value [string map [list "\t" {\\t} "\n" {\\n} \
                    "\r" {\\r} {|} {\\p}] [dict get $record $key]]
                lappend fields "${key}=${value}"
            }
            puts $output [join $fields |]
        }
        foreach record $blocked {
            dict set record kind BLOCK
            set fields {}
            foreach key [lsort -dictionary [dict keys $record]] {
                set value [string map [list "\t" {\\t} "\n" {\\n} \
                    "\r" {\\r} {|} {\\p}] [dict get $record $key]]
                lappend fields "${key}=${value}"
            }
            puts $output [join $fields |]
        }
    } finally {
        close $output
    }
    if {[llength $blocked]} {
        _raise BLOCKED "Tcl discovery found [llength $blocked] blocking record(s)."
    }
    return [llength $records]
}

proc ::stage1e::tcl_dependency_discovery_v1::_compare_ordinal {left right} {
    return [expr {[dict get $left ordinal] - [dict get $right ordinal]}]
}

proc ::stage1e::tcl_dependency_discovery_v1::_main {arguments} {
    if {[llength $arguments] != 6} {
        puts stderr {usage: scanner --repository-root ROOT --graph PATH --output PATH}
        return 2
    }
    set values {}
    foreach {key value} $arguments { dict set values $key $value }
    foreach key {--repository-root --graph --output} {
        if {![dict exists $values $key]} {
            puts stderr "missing argument: $key"
            return 2
        }
    }
    if {[catch {discover [dict get $values --repository-root] \
        [dict get $values --graph] [dict get $values --output]} message options]} {
        puts stderr $message
        return 1
    }
    return 0
}

if {[file normalize [info script]] eq [file normalize $::argv0]} {
    exit [::stage1e::tcl_dependency_discovery_v1::_main $::argv]
}
