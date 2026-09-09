namespace eval ::stage1d::source_check {
    variable sha256_initial_hashes {
        0x6a09e667 0xbb67ae85 0x3c6ef372 0xa54ff53a
        0x510e527f 0x9b05688c 0x1f83d9ab 0x5be0cd19
    }
    variable sha256_round_constants {
        0x428a2f98 0x71374491 0xb5c0fbcf 0xe9b5dba5
        0x3956c25b 0x59f111f1 0x923f82a4 0xab1c5ed5
        0xd807aa98 0x12835b01 0x243185be 0x550c7dc3
        0x72be5d74 0x80deb1fe 0x9bdc06a7 0xc19bf174
        0xe49b69c1 0xefbe4786 0x0fc19dc6 0x240ca1cc
        0x2de92c6f 0x4a7484aa 0x5cb0a9dc 0x76f988da
        0x983e5152 0xa831c66d 0xb00327c8 0xbf597fc7
        0xc6e00bf3 0xd5a79147 0x06ca6351 0x14292967
        0x27b70a85 0x2e1b2138 0x4d2c6dfc 0x53380d13
        0x650a7354 0x766a0abb 0x81c2c92e 0x92722c85
        0xa2bfe8a1 0xa81a664b 0xc24b8b70 0xc76c51a3
        0xd192e819 0xd6990624 0xf40e3585 0x106aa070
        0x19a4c116 0x1e376c08 0x2748774c 0x34b0bcb5
        0x391c0cb3 0x4ed8aa4a 0x5b9cca4f 0x682e6ff3
        0x748f82ee 0x78a5636f 0x84c87814 0x8cc70208
        0x90befffa 0xa4506ceb 0xbef9a3f7 0xc67178f2
    }
}

proc ::stage1d::source_check::_u32 {value} {
    return [expr {$value & 0xffffffff}]
}

proc ::stage1d::source_check::_rotate_right {value amount} {
    return [_u32 [expr {
        (($value >> $amount) | ($value << (32 - $amount)))
    }]]
}

proc ::stage1d::source_check::_sha256_data {data} {
    variable sha256_initial_hashes
    variable sha256_round_constants

    binary scan $data c* bytes
    set bit_length [expr {[llength $bytes] * 8}]
    lappend bytes 0x80
    while {[expr {[llength $bytes] % 64}] != 56} {
        lappend bytes 0
    }
    for {set shift 56} {$shift >= 0} {incr shift -8} {
        lappend bytes [expr {($bit_length >> $shift) & 0xff}]
    }

    lassign $sha256_initial_hashes h0 h1 h2 h3 h4 h5 h6 h7
    set byte_count [llength $bytes]
    for {set offset 0} {$offset < $byte_count} {incr offset 64} {
        set words {}
        for {set word_index 0} {$word_index < 16} {incr word_index} {
            set word 0
            for {set byte_index 0} {$byte_index < 4} {incr byte_index} {
                set source_index [expr {$offset + ($word_index * 4) + $byte_index}]
                set byte_value [expr {[lindex $bytes $source_index] & 0xff}]
                set word [_u32 [expr {($word << 8) | $byte_value}]]
            }
            lappend words $word
        }

        for {set word_index 16} {$word_index < 64} {incr word_index} {
            set prior_15 [lindex $words [expr {$word_index - 15}]]
            set prior_2 [lindex $words [expr {$word_index - 2}]]
            set sigma0 [_u32 [expr {
                [_rotate_right $prior_15 7] ^
                [_rotate_right $prior_15 18] ^
                ($prior_15 >> 3)
            }]]
            set sigma1 [_u32 [expr {
                [_rotate_right $prior_2 17] ^
                [_rotate_right $prior_2 19] ^
                ($prior_2 >> 10)
            }]]
            lappend words [_u32 [expr {
                [lindex $words [expr {$word_index - 16}]] +
                $sigma0 +
                [lindex $words [expr {$word_index - 7}]] +
                $sigma1
            }]]
        }

        set a $h0
        set b $h1
        set c $h2
        set d $h3
        set e $h4
        set f $h5
        set g $h6
        set h $h7

        for {set round 0} {$round < 64} {incr round} {
            set sum1 [_u32 [expr {
                [_rotate_right $e 6] ^
                [_rotate_right $e 11] ^
                [_rotate_right $e 25]
            }]]
            set choose [_u32 [expr {($e & $f) ^ ((~$e) & $g)}]]
            set temporary1 [_u32 [expr {
                $h + $sum1 + $choose +
                [lindex $sha256_round_constants $round] +
                [lindex $words $round]
            }]]
            set sum0 [_u32 [expr {
                [_rotate_right $a 2] ^
                [_rotate_right $a 13] ^
                [_rotate_right $a 22]
            }]]
            set majority [_u32 [expr {
                ($a & $b) ^ ($a & $c) ^ ($b & $c)
            }]]
            set temporary2 [_u32 [expr {$sum0 + $majority}]]

            set h $g
            set g $f
            set f $e
            set e [_u32 [expr {$d + $temporary1}]]
            set d $c
            set c $b
            set b $a
            set a [_u32 [expr {$temporary1 + $temporary2}]]
        }

        set h0 [_u32 [expr {$h0 + $a}]]
        set h1 [_u32 [expr {$h1 + $b}]]
        set h2 [_u32 [expr {$h2 + $c}]]
        set h3 [_u32 [expr {$h3 + $d}]]
        set h4 [_u32 [expr {$h4 + $e}]]
        set h5 [_u32 [expr {$h5 + $f}]]
        set h6 [_u32 [expr {$h6 + $g}]]
        set h7 [_u32 [expr {$h7 + $h}]]
    }

    return [string tolower [format {%08x%08x%08x%08x%08x%08x%08x%08x} \
        $h0 $h1 $h2 $h3 $h4 $h5 $h6 $h7]]
}

proc ::stage1d::source_check::sha256_text {text} {
    return [_sha256_data [encoding convertto utf-8 $text]]
}

proc ::stage1d::source_check::sha256_file {path} {
    set channel [open $path r]
    fconfigure $channel -encoding binary -translation binary
    set read_status [catch {read $channel} content read_options]
    set close_status [catch {close $channel} close_error]
    if {$read_status != 0} {
        return -options $read_options $content
    }
    if {$close_status != 0} {
        error "Unable to close file while hashing: $close_error"
    }
    return [_sha256_data $content]
}

proc ::stage1d::source_check::_canonical_components {path} {
    set components [file split [file normalize $path]]
    if {$::tcl_platform(platform) ne {windows}} {
        return $components
    }
    set canonical {}
    foreach component $components {
        lappend canonical [string tolower $component]
    }
    return $canonical
}

proc ::stage1d::source_check::_is_equal_or_descendant {candidate parent} {
    set candidate_components [_canonical_components $candidate]
    set parent_components [_canonical_components $parent]
    if {[llength $candidate_components] < [llength $parent_components]} {
        return 0
    }
    for {set index 0} {$index < [llength $parent_components]} {incr index} {
        if {[lindex $candidate_components $index] ne [lindex $parent_components $index]} {
            return 0
        }
    }
    return 1
}

proc ::stage1d::source_check::_resolve_repository_path {repository_root relative_path} {
    set canonical_relative [string map {\\ /} $relative_path]
    if {$canonical_relative eq {} || [file pathtype $canonical_relative] ne {relative}} {
        error "Source inventory path must be repository-relative: $relative_path"
    }
    foreach component [file split $canonical_relative] {
        if {$component in {. ..}} {
            error "Source inventory path contains a disallowed component: $relative_path"
        }
    }

    set absolute_path [file normalize [file join $repository_root $canonical_relative]]
    if {![_is_equal_or_descendant $absolute_path $repository_root]} {
        error "Source inventory path escapes the repository: $relative_path"
    }
    return [list $canonical_relative $absolute_path]
}

proc ::stage1d::source_check::hash_inventory {repository_root relative_paths} {
    set inventory {}
    set seen [dict create]
    foreach relative_path $relative_paths {
        lassign [_resolve_repository_path $repository_root $relative_path] canonical_relative absolute_path
        if {[dict exists $seen $canonical_relative]} {
            error "Duplicate source inventory path: $canonical_relative"
        }
        dict set seen $canonical_relative 1
        if {![file exists $absolute_path] || ![file isfile $absolute_path]} {
            error "Required source file is missing: $canonical_relative"
        }
        lappend inventory [dict create \
            path $canonical_relative \
            size [file size $absolute_path] \
            sha256 [sha256_file $absolute_path]]
    }
    return $inventory
}

proc ::stage1d::source_check::aggregate_inventory_hash {inventory} {
    set canonical_inventory {}
    foreach entry $inventory {
        append canonical_inventory \
            [dict get $entry path] "\t" \
            [dict get $entry sha256] "\n"
    }
    return [sha256_text $canonical_inventory]
}

proc ::stage1d::source_check::_error_record {
    error_code
    category
    message
    recoverability
} {
    return [dict create \
        error_code $error_code \
        category $category \
        phase_name source_verification \
        message $message \
        underlying_error {} \
        evidence_references {} \
        recoverability $recoverability]
}

proc ::stage1d::source_check::_result {status outputs errors {evidence_locations {}}} {
    return [dict create \
        status $status \
        evidence_locations $evidence_locations \
        logs {} \
        reports {} \
        errors $errors \
        outputs $outputs \
        artifact_references {}]
}

proc ::stage1d::source_check::_stop {
    status
    error_code
    category
    message
    recoverability
    outputs
} {
    return [_result $status $outputs [list [_error_record \
        $error_code $category $message $recoverability]]]
}

proc ::stage1d::source_check::_git {repository_root arguments} {
    set command [list git -C $repository_root]
    foreach argument $arguments {
        lappend command $argument
    }
    return [string trim [exec {*}$command]]
}

proc ::stage1d::source_check::_run {context} {
    set parsed [dict get $context parsed_arguments]
    set configuration [dict get $context configuration]
    set execution_identity [dict get $context execution_identity]
    set input_outputs [dict get $context input_validation_outputs]
    set repository_root [file normalize [dict get $parsed repository_root]]
    set outputs [dict create repository_root $repository_root]

    if {![file isdirectory $repository_root]} {
        return [_stop FAIL REPOSITORY_NOT_FOUND SOURCE \
            {Repository root is not an existing directory.} NONE $outputs]
    }
    if {[auto_execok git] eq {}} {
        return [_stop BLOCKED GIT_UNAVAILABLE TOOL \
            {Git executable is unavailable for source verification.} INSTALL_GIT $outputs]
    }

    if {[catch {_git $repository_root {rev-parse --show-toplevel}} git_root]} {
        return [_stop FAIL REPOSITORY_NOT_GIT SOURCE \
            "Repository verification failed: $git_root" NONE $outputs]
    }
    set git_root [file normalize $git_root]
    if {[_canonical_components $git_root] ne [_canonical_components $repository_root]} {
        return [_stop FAIL REPOSITORY_ROOT_MISMATCH SOURCE \
            {Supplied repository root does not match the Git top-level directory.} NONE $outputs]
    }
    dict set outputs repository_verified 1

    if {[catch {_git $repository_root {rev-parse HEAD}} actual_commit]} {
        return [_stop FAIL GIT_HEAD_UNAVAILABLE SOURCE \
            "Unable to resolve Git HEAD: $actual_commit" NONE $outputs]
    }
    set candidate_commit [dict get $execution_identity candidate_git_commit]
    set commit_expression "${candidate_commit}^{commit}"
    if {[catch {
        _git $repository_root [list rev-parse --verify $commit_expression]
    } resolved_candidate]} {
        return [_stop FAIL GIT_COMMIT_UNRESOLVED SOURCE \
            "Candidate Git commit cannot be resolved: $candidate_commit" NONE $outputs]
    }
    set actual_commit [string tolower $actual_commit]
    set resolved_candidate [string tolower $resolved_candidate]
    dict set outputs git_commit $actual_commit
    dict set outputs candidate_git_commit $candidate_commit
    if {$actual_commit ne $resolved_candidate} {
        return [_stop FAIL GIT_COMMIT_MISMATCH SOURCE \
            "Git HEAD does not match the candidate commit: actual=$actual_commit expected=$resolved_candidate" NONE $outputs]
    }
    dict set outputs git_commit_verified 1

    if {[catch {
        _git $repository_root {status --porcelain=v1 --untracked-files=all}
    } worktree_status]} {
        return [_stop FAIL GIT_STATUS_FAILED SOURCE \
            "Unable to inspect Git worktree state: $worktree_status" NONE $outputs]
    }
    if {$worktree_status ne {}} {
        dict set outputs worktree_clean 0
        dict set outputs dirty_entries [split $worktree_status "\n"]
        return [_stop FAIL WORKTREE_NOT_CLEAN SOURCE \
            {Git worktree contains tracked or untracked changes.} CLEAN_WORKTREE $outputs]
    }
    dict set outputs worktree_clean 1

    set source_configuration [dict get $configuration source_verification]
    set required_paths [dict get $source_configuration required_paths]
    if {[catch {
        hash_inventory $repository_root $required_paths
    } source_inventory]} {
        return [_stop FAIL SOURCE_INVENTORY_FAILED SOURCE \
            "Source inventory failed: $source_inventory" NONE $outputs]
    }

    if {[catch {_git $repository_root {ls-files}} tracked_output]} {
        return [_stop FAIL TRACKED_SOURCE_QUERY_FAILED SOURCE \
            "Unable to inventory tracked Git files: $tracked_output" NONE $outputs]
    }
    set tracked_paths [dict create]
    foreach tracked_path [split $tracked_output "\n"] {
        if {$tracked_path ne {}} {
            dict set tracked_paths [string map {\\ /} $tracked_path] 1
        }
    }
    foreach source_entry $source_inventory {
        set source_path [dict get $source_entry path]
        if {![dict exists $tracked_paths $source_path]} {
            dict set outputs source_inventory $source_inventory
            return [_stop FAIL SOURCE_NOT_GIT_TRACKED SOURCE \
                "Required source is not tracked by Git: $source_path" NONE $outputs]
        }
    }
    dict set outputs source_inventory $source_inventory
    dict set outputs source_inventory_count [llength $source_inventory]

    if {[catch {
        hash_inventory $repository_root [dict get $source_configuration tcl_paths]
    } tcl_inventory]} {
        return [_stop FAIL TCL_HASH_INVENTORY_FAILED PROVENANCE \
            "Tcl SHA256 inventory failed: $tcl_inventory" NONE $outputs]
    }
    dict set outputs tcl_sha256_inventory $tcl_inventory

    if {[catch {
        hash_inventory $repository_root [dict get $source_configuration controller_source_paths]
    } controller_inventory]} {
        return [_stop FAIL CONTROLLER_HASH_FAILED PROVENANCE \
            "Controller source inventory failed: $controller_inventory" NONE $outputs]
    }
    set controller_source_hash [aggregate_inventory_hash $controller_inventory]
    set expected_controller_hash [string tolower \
        [dict get $source_configuration expected_controller_source_sha256]]
    dict set outputs controller_source_inventory $controller_inventory
    dict set outputs controller_source_hash $controller_source_hash
    if {$controller_source_hash ne $expected_controller_hash} {
        return [_stop FAIL CONTROLLER_SOURCE_HASH_MISMATCH PROVENANCE \
            "Controller source hash mismatch: actual=$controller_source_hash expected=$expected_controller_hash" NONE $outputs]
    }

    set configuration_path [dict get $configuration configuration_path]
    if {[catch {sha256_file $configuration_path} configuration_hash]} {
        return [_stop FAIL CONFIGURATION_HASH_FAILED PROVENANCE \
            "Configuration hashing failed: $configuration_hash" NONE $outputs]
    }
    dict set outputs configuration_hash $configuration_hash
    dict set outputs controller_version [::stage1d::controller_core::version]
    dict set outputs controller_api_version [::stage1d::controller_core::api_version]

    if {![dict exists $input_outputs collision_check_result] ||
        [dict get $input_outputs collision_check_result] ne {PASS}} {
        return [_stop FAIL EXECUTION_ID_COLLISION_CHECK_MISSING PROVENANCE \
            {Execution identifier collision verification is missing or did not pass.} NONE $outputs]
    }
    set execution_identity_evidence [dict create \
        execution_identifier [dict get $execution_identity execution_identifier] \
        execution_id_schema_version [dict get $execution_identity execution_id_schema_version] \
        generation_timestamp [dict get $execution_identity generated_at] \
        collision_check_result [dict get $input_outputs collision_check_result]]
    dict set outputs execution_identity_evidence $execution_identity_evidence
    dict set outputs source_state_frozen 1

    set evidence_locations {}
    foreach source_entry $source_inventory {
        lappend evidence_locations [dict get $source_entry path]
    }
    return [_result PASS $outputs {} $evidence_locations]
}

proc ::stage1d::source_check::run {context} {
    set run_status [catch {_run $context} result run_options]
    if {$run_status == 0} {
        return $result
    }

    set underlying_error {}
    if {[dict exists $run_options -errorinfo]} {
        set underlying_error [dict get $run_options -errorinfo]
    }
    set error_record [_error_record \
        SOURCE_CHECK_INTERNAL_ERROR \
        CORE \
        "Unexpected source verification error: $result" \
        NONE]
    dict set error_record underlying_error $underlying_error
    return [_result FAIL {} [list $error_record]]
}
