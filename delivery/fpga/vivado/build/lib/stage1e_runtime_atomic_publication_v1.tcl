# Stage 1E no-overwrite atomic publication helper v1.

source [file join [file dirname [info script]] \
    stage1e_runtime_canonical_json_v1.tcl]

namespace eval ::stage1e::atomic_publication_v1 {
    variable interface_version stage1e-runtime-atomic-publication-interface-v1
}

proc ::stage1e::atomic_publication_v1::interface_version {} {
    variable interface_version
    return $interface_version
}

proc ::stage1e::atomic_publication_v1::path_within {candidate boundary} {
    set candidate [string tolower [string map {\\ /} \
        [file normalize $candidate]]]
    set boundary [string tolower [string map {\\ /} \
        [file normalize $boundary]]]
    set candidate [string trimright $candidate /]
    set boundary [string trimright $boundary /]
    return [expr {$candidate eq $boundary ||
        [string first "${boundary}/" "${candidate}/"] == 0}]
}

proc ::stage1e::atomic_publication_v1::read_binary {path} {
    set channel [open $path rb]
    fconfigure $channel -translation binary -encoding binary
    try {
        return [read $channel]
    } finally {
        close $channel
    }
}

proc ::stage1e::atomic_publication_v1::invoke_verifier {verifier bytes} {
    if {$verifier eq {}} { return }
    set accepted [uplevel #0 [linsert $verifier end $bytes]]
    if {$accepted in {0 false FALSE}} {
        return -code error -errorcode {STAGE1E PUBLICATION VERIFY} \
            {Publication verifier rejected canonical bytes.}
    }
}

proc ::stage1e::atomic_publication_v1::publish {
    final_path bytes boundary_path {verifier {}} {temporary_leaf {}}
    {after_temporary_close {}} {after_rename {}}
} {
    variable interface_version
    if {[file pathtype $final_path] ne {absolute} ||
            [file pathtype $boundary_path] ne {absolute}} {
        return -code error -errorcode {STAGE1E PUBLICATION PATH} \
            {Atomic publication paths must be absolute.}
    }
    foreach wildcard [list {*} {?} {[} {]}] {
        if {[string first $wildcard $final_path] >= 0 ||
                [string first $wildcard $boundary_path] >= 0} {
            return -code error -errorcode {STAGE1E PUBLICATION PATH} \
                {Atomic publication paths must be literal.}
        }
    }
    set parent [file dirname $final_path]
    if {![file exists $parent] || ![file isdirectory $parent]} {
        return -code error -errorcode {STAGE1E PUBLICATION PARENT} \
            "Final parent directory does not exist: $parent"
    }
    if {![file exists $boundary_path] || ![file isdirectory $boundary_path]} {
        return -code error -errorcode {STAGE1E PUBLICATION BOUNDARY} \
            "Publication boundary does not exist: $boundary_path"
    }
    if {![path_within $final_path $boundary_path]} {
        return -code error -errorcode {STAGE1E PUBLICATION CONTAINMENT} \
            {Final publication path is outside the qualified boundary.}
    }
    if {[file exists $final_path]} {
        return -code error -errorcode {STAGE1E PUBLICATION COLLISION} \
            "Final publication path already exists: $final_path"
    }
    if {$temporary_leaf eq {}} {
        set temporary_leaf ".[file tail $final_path].stage1e-tmp-[pid]-[clock clicks]"
    }
    if {$temporary_leaf eq {} || [file tail $temporary_leaf] ne $temporary_leaf ||
            [string first / $temporary_leaf] >= 0 ||
            [string first "\\" $temporary_leaf] >= 0} {
        return -code error -errorcode {STAGE1E PUBLICATION TEMP} \
            {Temporary publication name must be one literal sibling leaf.}
    }
    set temporary [file join $parent $temporary_leaf]
    if {[string equal -nocase [string map {\\ /} $temporary] \
            [string map {\\ /} $final_path]]} {
        return -code error -errorcode {STAGE1E PUBLICATION TEMP} \
            {Temporary and final publication paths must differ.}
    }

    set created_temporary 0
    set renamed_final 0
    try {
        set channel [open $temporary {WRONLY CREAT EXCL}]
        set created_temporary 1
        fconfigure $channel -translation binary -encoding binary
        try {
            puts -nonewline $channel $bytes
            flush $channel
        } finally {
            close $channel
        }
        if {$after_temporary_close ne {}} {
            uplevel #0 [linsert $after_temporary_close end $temporary]
        }
        set temporary_bytes [read_binary $temporary]
        if {![::stage1e::canonical_json_v1::bytes_equal \
                $bytes $temporary_bytes]} {
            return -code error -errorcode {STAGE1E PUBLICATION TEMP_MISMATCH} \
                {Temporary publication bytes differ after close and reopen.}
        }
        invoke_verifier $verifier $temporary_bytes
        if {[file exists $final_path]} {
            return -code error -errorcode {STAGE1E PUBLICATION COLLISION} \
                "Final publication path collided before rename: $final_path"
        }
        file rename $temporary $final_path
        set created_temporary 0
        set renamed_final 1
        if {$after_rename ne {}} {
            uplevel #0 [linsert $after_rename end $final_path]
        }
        set final_bytes [read_binary $final_path]
        if {![::stage1e::canonical_json_v1::bytes_equal $bytes $final_bytes]} {
            return -code error -errorcode {STAGE1E PUBLICATION FINAL_MISMATCH} \
                {Final publication bytes differ after atomic rename.}
        }
        invoke_verifier $verifier $final_bytes
        return [dict create \
            interface_version $interface_version \
            publication_state SEALED \
            final_path $final_path \
            byte_count [string length $final_bytes] \
            byte_sha256 [::stage1e::canonical_json_v1::sha256 $final_bytes] \
            overwrite_performed 0]
    } on error {message options} {
        if {$created_temporary && [file exists $temporary]} {
            file delete $temporary
        }
        if {$renamed_final && [file exists $final_path]} {
            file delete $final_path
        }
        return -options $options $message
    }
}
