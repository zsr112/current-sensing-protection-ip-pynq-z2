# Stage 1E controlled-runtime canonical identity helpers v1.
#
# These helpers serialize and hash already validated records. They do not
# create execution authority, consume authorization, decide acceptance, or
# emit an implementation result identity.

namespace eval ::stage1e::runtime_identity {
    variable schema_version stage1e-runtime-canonical-identity-v1
}
proc ::stage1e::runtime_identity::_raise {code message} {
    return -code error -errorcode \
        [list STAGE1E RUNTIME_IDENTITY $code] $message
}

proc ::stage1e::runtime_identity::_require_dictionary {record label} {
    if {[catch {dict size $record} dictionary_error]} {
        _raise SCHEMA_INVALID \
            "$label is not a dictionary: $dictionary_error"
    }
    return 1
}

proc ::stage1e::runtime_identity::_require_exact_fields {
    record
    fields
    label
} {
    _require_dictionary $record $label
    set expected [lsort -dictionary $fields]
    set actual [lsort -dictionary [dict keys $record]]
    if {$expected ne $actual} {
        _raise IDENTITY_INCOMPLETE \
            "$label fields differ: expected=<$expected> actual=<$actual>"
    }
    foreach field $fields {
        if {[dict get $record $field] eq {}} {
            _raise IDENTITY_INCOMPLETE "$label has an empty field: $field"
        }
    }
    return 1
}

proc ::stage1e::runtime_identity::require_sha256 {value label} {
    set value [string tolower $value]
    if {![regexp {^[0-9a-f]{64}$} $value] ||
        $value eq [string repeat 0 64]} {
        _raise IDENTITY_INVALID \
            "$label is not a non-placeholder SHA-256 identity."
    }
    return $value
}

proc ::stage1e::runtime_identity::canonical_payload {fields record} {
    _require_exact_fields $record $fields {Canonical identity record}
    set payload {}
    foreach field $fields {
        append payload [list $field] {=} [list [dict get $record $field]] "\n"
    }
    return $payload
}

proc ::stage1e::runtime_identity::compute {fields record} {
    if {![llength [info commands ::stage1d::source_check::sha256_text]]} {
        _raise DEPENDENCY_MISSING \
            {Stage 1D source-check SHA-256 provider is unavailable.}
    }
    return [::stage1d::source_check::sha256_text \
        [canonical_payload $fields $record]]
}

proc ::stage1e::runtime_identity::attach {fields record} {
    if {[dict exists $record identity_sha256]} {
        _raise SCHEMA_INVALID \
            {Identity record already contains identity_sha256.}
    }
    dict set record identity_sha256 [compute $fields $record]
    return $record
}

proc ::stage1e::runtime_identity::validate {fields record label} {
    _require_exact_fields $record [linsert $fields 1 identity_sha256] $label
    set actual [require_sha256 [dict get $record identity_sha256] \
        "$label identity_sha256"]
    set payload [dict remove $record identity_sha256]
    set expected [compute $fields $payload]
    if {$actual ne $expected} {
        _raise IDENTITY_MISMATCH \
            "$label canonical identity does not match its payload."
    }
    return 1
}
