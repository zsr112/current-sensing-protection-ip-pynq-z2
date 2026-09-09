# Stage 1E Run2 production report collector v2.
#
# The collector reserves the complete closed report set before issuing any
# report command, retains every attempt, and publishes only content facts. It
# writes the artifact manifest after collection but never decides acceptance.

set ::stage1e_vivado_collector_v2_dir [file dirname [info script]]
set ::stage1e_vivado_collector_v2_build [file dirname [file dirname $::stage1e_vivado_collector_v2_dir]]
if {![llength [info commands ::stage1e::canonical_json_v1::digest_bytes]]} {
    source [file join $::stage1e_vivado_collector_v2_build lib stage1e_runtime_canonical_json_v1.tcl]
}
unset ::stage1e_vivado_collector_v2_dir
unset ::stage1e_vivado_collector_v2_build

namespace eval ::stage1e::production_vivado_collector_v2 {
    variable interface_version stage1e-production-vivado-collector-interface-v2
}

proc ::stage1e::production_vivado_collector_v2::interface_version {} {
    variable interface_version
    return $interface_version
}

proc ::stage1e::production_vivado_collector_v2::_raise {code message} {
    return -code error -errorcode [list STAGE1E RUN2 COLLECTOR_V2 $code] $message
}

proc ::stage1e::production_vivado_collector_v2::report_roles {} {
    return {
        TIMING_SUMMARY TIMING_PATH_GROUPS CLOCK_INTERACTION CLOCKS_GENERATED_CLOCKS
        CONSTRAINT_COVERAGE CHECK_TIMING TIMING_EXCEPTION_SOURCE CONDITIONAL_BUS_SKEW
        UTILIZATION DRC METHODOLOGY CDC MESSAGE_SOURCE
    }
}

proc ::stage1e::production_vivado_collector_v2::_canonical_path {path} {
    return [string map {\\ /} [file normalize $path]]
}

proc ::stage1e::production_vivado_collector_v2::_path_within {candidate root} {
    set candidate [_canonical_path $candidate]
    set root [_canonical_path $root]
    set prefix "[string trimright $root /\\]/"
    return [expr {$candidate eq $root || [string first $prefix $candidate] == 0}]
}

proc ::stage1e::production_vivado_collector_v2::_reservation_path {request role} {
    return [file join [dict get $request report_root] .stage1e-reservations \
        "[string tolower $role].reservation"]
}

proc ::stage1e::production_vivado_collector_v2::_attempt_ledger_path {request} {
    return [file join [dict get $request report_root] .stage1e-report-attempts.tsv]
}

proc ::stage1e::production_vivado_collector_v2::_reserve_new {path text} {
    set channel [open $path {WRONLY CREAT EXCL}]
    fconfigure $channel -encoding utf-8 -translation lf
    puts -nonewline $channel $text
    close $channel
}

proc ::stage1e::production_vivado_collector_v2::_validate_binding {binding} {
    set expected {
        implementation_profile execution_id source_commit source_tree
        project_identity design_identity
    }
    if {[catch {dict size $binding}] ||
        [lsort -dictionary [dict keys $binding]] ne [lsort -dictionary $expected]} {
        _raise ARTIFACT_BINDING {Artifact binding fields are not exact.}
    }
    if {![regexp {^[0-9a-f]{40}$} [dict get $binding source_commit]] ||
        ![regexp {^[0-9a-f]{40}$} [dict get $binding source_tree]]} {
        _raise ARTIFACT_BINDING {Artifact source commit or tree is invalid.}
    }
    if {[dict get $binding implementation_profile] ni {
        SAFE_INERT READY_AWARE_SYNTHETIC_DIGITAL_STIMULUS
    }} {
        _raise ARTIFACT_BINDING {Artifact implementation profile is invalid.}
    }
    foreach field {execution_id project_identity design_identity} {
        if {[dict get $binding $field] eq {}} {
            _raise ARTIFACT_BINDING "Artifact binding field is empty: $field"
        }
    }
    return $binding
}

proc ::stage1e::production_vivado_collector_v2::_artifact_record {binding role path} {
    _validate_binding $binding
    if {![file exists $path] || ![file isfile $path]} {
        _raise ARTIFACT_MISSING "Artifact is missing: $role"
    }
    return [dict create role $role path [_canonical_path $path] \
        bytes [file size $path] \
        sha256 [::stage1e::canonical_json_v1::digest_file $path] \
        implementation_profile [dict get $binding implementation_profile] \
        execution_id [dict get $binding execution_id] \
        source_commit [dict get $binding source_commit] \
        source_tree [dict get $binding source_tree] \
        project_identity [dict get $binding project_identity] \
        design_identity [dict get $binding design_identity]]
}

proc ::stage1e::production_vivado_collector_v2::_validate_request {request} {
    set expected {
        report_root implementation_profile execution_id source_commit
        source_tree project_identity design_identity run_identity
        process_identity role_output_paths
    }
    if {[catch {dict size $request}] ||
        [lsort -dictionary [dict keys $request]] ne [lsort -dictionary $expected]} {
        _raise REQUEST_FIELD_MISSING {Collector request fields are not exact and closed.}
    }
    _validate_binding [dict create \
        implementation_profile [dict get $request implementation_profile] \
        execution_id [dict get $request execution_id] \
        source_commit [dict get $request source_commit] \
        source_tree [dict get $request source_tree] \
        project_identity [dict get $request project_identity] \
        design_identity [dict get $request design_identity]]
    set root [_canonical_path [dict get $request report_root]]
    if {![file exists $root] || ![file isdirectory $root]} { _raise REPORT_ROOT_INVALID {Report root must already exist.} }
    set paths [dict get $request role_output_paths]
    set expected [lsort -dictionary [report_roles]]
    if {[lsort -dictionary [dict keys $paths]] ne $expected} { _raise REPORT_ROLE_SET {Report roles are not exact and closed.} }
    set seen {}
    foreach role [report_roles] {
        set path [_canonical_path [dict get $paths $role]]
        if {![_path_within $path $root]} { _raise OUTPUT_PATH_ESCAPE "Report output escapes root: $role" }
        if {[file exists $path]} { _raise OUTPUT_PATH_EXISTS "Report output already exists: $role" }
        set key [string tolower $path]
        if {[dict exists $seen $key]} { _raise OUTPUT_PATH_DUPLICATE "Report path is reused: $role" }
        dict set seen $key 1
        if {![file exists [file dirname $path]]} { _raise OUTPUT_PARENT_MISSING "Report parent does not exist: $role" }
    }
    return 1
}

proc ::stage1e::production_vivado_collector_v2::_reserve_all {request} {
    set reservation_root [file join [dict get $request report_root] .stage1e-reservations]
    if {[file exists $reservation_root]} { _raise RESERVATION_ROOT_EXISTS {Reservation root must be new.} }
    file mkdir $reservation_root
    set ledger_path [_attempt_ledger_path $request]
    _reserve_new $ledger_path "ordinal\treport_role\tstate\tpath\tbytes\tsha256\treason\n"
    set reservations {}
    foreach role [report_roles] {
        set output [_canonical_path [dict get $request role_output_paths $role]]
        set reservation [_reservation_path $request $role]
        set binding "execution_id=[dict get $request execution_id]\nrun_identity=[dict get $request run_identity]\nprocess_identity=[dict get $request process_identity]\nreport_role=$role\nrequested_path=$output\nreservation_state=EXCLUSIVE_NO_OVERWRITE\n"
        _reserve_new $reservation $binding
        lappend reservations [dict create role $role reservation_path $reservation output_path $output]
    }
    return $reservations
}

proc ::stage1e::production_vivado_collector_v2::_append_attempt {request ordinal role state path reason} {
    set bytes -1
    set digest NONE
    if {[file exists $path] && [file isfile $path]} {
        set bytes [file size $path]
        set digest [::stage1e::canonical_json_v1::digest_file $path]
    }
    set channel [open [_attempt_ledger_path $request] a]
    fconfigure $channel -encoding utf-8 -translation lf
    puts $channel "$ordinal\t$role\t$state\t$path\t$bytes\t$digest\t$reason"
    close $channel
    return [dict create ordinal $ordinal role $role state $state path $path bytes $bytes sha256 $digest reason $reason]
}

proc ::stage1e::production_vivado_collector_v2::_invoke_fixed_report {role output_path} {
    switch -- $role {
        TIMING_SUMMARY { report_timing_summary -file $output_path }
        TIMING_PATH_GROUPS { report_timing -max_paths 100 -sort_by group -file $output_path }
        CLOCK_INTERACTION { report_clock_interaction -file $output_path }
        CLOCKS_GENERATED_CLOCKS { report_clocks -file $output_path }
        CONSTRAINT_COVERAGE { report_exceptions -coverage -file $output_path }
        CHECK_TIMING { check_timing -verbose -file $output_path }
        TIMING_EXCEPTION_SOURCE { report_exceptions -file $output_path }
        CONDITIONAL_BUS_SKEW { report_bus_skew -file $output_path }
        UTILIZATION { report_utilization -file $output_path }
        DRC { report_drc -file $output_path }
        METHODOLOGY { report_methodology -file $output_path }
        CDC { report_cdc -details -file $output_path }
        MESSAGE_SOURCE { report_route_status -file $output_path }
        default { _raise REPORT_ROLE_UNKNOWN "Unknown closed report role: $role" }
    }
}

proc ::stage1e::production_vivado_collector_v2::collect_live {request} {
    _validate_request $request
    set reservations [_reserve_all $request]
    set attempts {}
    set ordinal 0
    foreach reservation $reservations {
        incr ordinal
        set role [dict get $reservation role]
        set path [dict get $reservation output_path]
        set code [catch {_invoke_fixed_report $role $path} reason]
        set state [expr {$code ? {FAILED} : {COLLECTED}}]
        set attempt [_append_attempt $request $ordinal $role $state $path [expr {$code ? $reason : {NONE}}]]
        lappend attempts $attempt
        if {$code || [dict get $attempt bytes] <= 0} {
            set failure [expr {$code ? $reason : {Report output missing or zero-byte.}}]
            return [dict create action BLOCK reason $failure reservations $reservations attempts $attempts \
                acceptance_decision NOT_EVALUATED]
        }
    }
    return [dict create action PROCEED reason NONE reservations $reservations attempts $attempts \
        acceptance_decision NOT_EVALUATED]
}

proc ::stage1e::production_vivado_collector_v2::collect_fixture {request fixture_reports} {
    _validate_request $request
    set reservations [_reserve_all $request]
    set attempts {}
    set ordinal 0
    foreach reservation $reservations {
        incr ordinal
        set role [dict get $reservation role]
        if {![dict exists $fixture_reports $role]} {
            return [dict create action BLOCK reason "Fixture report missing: $role" reservations $reservations attempts $attempts acceptance_decision NOT_EVALUATED]
        }
        set path [dict get $reservation output_path]
        _reserve_new $path [dict get $fixture_reports $role]
        lappend attempts [_append_attempt $request $ordinal $role COLLECTED $path NONE]
    }
    return [dict create action PROCEED reason NONE reservations $reservations attempts $attempts acceptance_decision NOT_EVALUATED]
}

proc ::stage1e::production_vivado_collector_v2::write_artifact_manifest {
    artifact_root artifacts report_attempts binding
} {
    _validate_binding $binding
    set root [_canonical_path $artifact_root]
    if {![file exists $root] || ![file isdirectory $root]} {
        _raise ARTIFACT_ROOT_INVALID {Artifact root must already exist.}
    }
    set manifest [file join $root artifact-manifest.tsv]
    if {[file exists $manifest]} { _raise ARTIFACT_MANIFEST_EXISTS {Artifact manifest already exists.} }
    set roles {}
    foreach artifact $artifacts {
        set role [dict get $artifact role]
        if {[lsearch -exact $roles $role] >= 0} {
            _raise ARTIFACT_ROLE_DUPLICATE "Artifact role is duplicated: $role"
        }
        lappend roles $role
        foreach field {
            implementation_profile execution_id source_commit source_tree
            project_identity design_identity
        } {
            if {[dict get $artifact $field] ne [dict get $binding $field]} {
                _raise ARTIFACT_BINDING "Artifact $role differs from the execution binding: $field"
            }
        }
    }
    set channel [open $manifest {WRONLY CREAT EXCL}]
    fconfigure $channel -encoding utf-8 -translation lf
    puts $channel "kind\trole\tcanonical_path\tbytes\tsha256\timplementation_profile\texecution_id\tsource_commit\tsource_tree\tproject_identity\tdesign_identity"
    foreach artifact $artifacts {
        puts $channel "artifact\t[dict get $artifact role]\t[dict get $artifact path]\t[dict get $artifact bytes]\t[dict get $artifact sha256]\t[dict get $binding implementation_profile]\t[dict get $binding execution_id]\t[dict get $binding source_commit]\t[dict get $binding source_tree]\t[dict get $binding project_identity]\t[dict get $binding design_identity]"
    }
    foreach attempt $report_attempts {
        puts $channel "report\t[dict get $attempt role]\t[_canonical_path [dict get $attempt path]]\t[dict get $attempt bytes]\t[dict get $attempt sha256]\t[dict get $binding implementation_profile]\t[dict get $binding execution_id]\t[dict get $binding source_commit]\t[dict get $binding source_tree]\t[dict get $binding project_identity]\t[dict get $binding design_identity]"
    }
    close $channel
    lappend artifacts [_artifact_record $binding ARTIFACT_MANIFEST $manifest]
    return $artifacts
}
