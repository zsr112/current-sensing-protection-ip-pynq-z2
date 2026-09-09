# Stage 1E PRT02-E Tcl SHA-256 bootstrap projection v1.

proc stage1e_hash_bootstrap_read_binary {path} {
    set channel [open $path rb]
    fconfigure $channel -translation binary -encoding binary
    try { return [read $channel] } finally { close $channel }
}

proc stage1e_hash_bootstrap_main {arguments} {
    if {[llength $arguments] != 6} {
        puts stderr {usage: hash --provider PATH --vector-root ROOT --output PATH}
        return 2
    }
    set values {}
    foreach {key value} $arguments { dict set values $key $value }
    foreach key {--provider --vector-root --output} {
        if {![dict exists $values $key]} { puts stderr "missing $key"; return 2 }
    }
    set provider [file normalize [dict get $values --provider]]
    set vector_root [string map {\\ /} [dict get $values --vector-root]]
    set output [string map {\\ /} [dict get $values --output]]
    if {[catch {source $provider} message options]} {
        puts stderr $message
        return 1
    }
    if {[::stage1e::canonical_json_v1::hash_provider_interface_version] ne \
        {stage1e-runtime-sha256-provider-interface-v1}} {
        puts stderr {Tcl hash-provider interface mismatch.}
        return 1
    }
    set names {
        01_empty.bin 02_abc.bin 03_multiblock_standard.bin 04_utf8.bin
        05_binary.bin 06_lf.bin 07_crlf.bin 08_canonical_json.bin
        09_len55.bin 10_len56.bin 11_len63.bin 12_len64.bin 13_len65.bin
        14_raw_file.bin
    }
    set channel [open $output {WRONLY CREAT EXCL}]
    fconfigure $channel -encoding utf-8 -translation lf
    try {
        foreach name $names {
            set path "${vector_root}/${name}"
            set bytes [stage1e_hash_bootstrap_read_binary $path]
            set digest [::stage1e::canonical_json_v1::sha256 $bytes]
            if {![regexp {^[0-9a-f]{64}$} $digest]} {
                error {Tcl candidate returned a noncanonical SHA-256 value.}
            }
            puts $channel "${name}|$digest"
        }
    } finally {
        close $channel
    }
    return 0
}

exit [stage1e_hash_bootstrap_main $::argv]
