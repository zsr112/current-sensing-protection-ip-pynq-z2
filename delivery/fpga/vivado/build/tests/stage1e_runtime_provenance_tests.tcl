source [file join [file dirname [info script]] \
    stage1e_runtime_test_support.tcl]

set root [::stage1e::runtime_test::repository_root]
set framework_path [file join $root fpga vivado build config \
    stage1e_phase3_implementation_framework_v2.dict]
set framework [::stage1e::runtime_schema::read_dictionary $framework_path]
set source_roles [dict get $framework source_roles]

::stage1e::runtime_test::run_case source_roles_are_unique_and_present {
    set roles [dict keys $source_roles]
    set paths [dict values $source_roles]
    ::stage1e::runtime_test::assert_equal [llength $roles] \
        [llength [lsort -unique $roles]] {Duplicate provenance role}
    ::stage1e::runtime_test::assert_equal [llength $paths] \
        [llength [lsort -unique $paths]] {Duplicate provenance path}
    foreach path $paths {
        set allowed [expr {
            [string match {fpga/vivado/build/runtime/*} $path] ||
            [string match {fpga/vivado/build/config/*v2*} $path] ||
            [string match {fpga/vivado/build/controller/*v2*} $path] ||
            [string match {fpga/vivado/build/adapters/*v2*} $path] ||
            [string match {fpga/vivado/build/lib/*runtime*} $path] ||
            [string match {fpga/vivado/build/tests/*runtime*} $path] ||
            [string match {docs/design/*v2*} $path]
        }]
        ::stage1e::runtime_test::assert_true {$allowed} \
            "Provenance path is outside the execution boundary: $path"
        set absolute [file join $root {*}[split $path /]]
        ::stage1e::runtime_test::assert_true \
            {[file exists $absolute] && [file isfile $absolute]} \
            "Provenance source is missing: $path"
    }
}

::stage1e::runtime_test::run_case source_inventory_hashing_is_deterministic {
    set paths [dict values $source_roles]
    set first [::stage1d::source_check::hash_inventory $root $paths]
    set second [::stage1d::source_check::hash_inventory $root $paths]
    ::stage1e::runtime_test::assert_equal $first $second \
        {Runtime source inventory is not deterministic}
    set first_digest \
        [::stage1d::source_check::aggregate_inventory_hash $first]
    set second_digest \
        [::stage1d::source_check::aggregate_inventory_hash $second]
    ::stage1e::runtime_test::assert_equal $first_digest $second_digest \
        {Runtime aggregate inventory identity is not deterministic}
    ::stage1e::runtime_identity::require_sha256 $first_digest \
        {Synthetic validation inventory digest}
}

::stage1e::runtime_test::run_case framework_provenance_remains_non_authorizing {
    ::stage1e::runtime_test::assert_equal 0 \
        [dict get $framework boundary implementation_execution_authorized] \
        {Provenance framework grants implementation authority}
    ::stage1e::runtime_test::assert_equal 0 \
        [dict get $framework boundary qualification_execution_authorized] \
        {Provenance framework grants qualification authority}
    ::stage1e::runtime_test::assert_equal NONE \
        [dict get $framework boundary artifact_authority] \
        {Provenance framework grants artifact authority}
}

::stage1e::runtime_test::finish
