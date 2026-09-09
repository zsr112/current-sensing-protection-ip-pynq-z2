# Expand every DRC object from a routed checkpoint without changing the design.
if {[llength $argv] != 2} { error "Expected checkpoint and fresh output directory" }
lassign $argv checkpoint output
if {[file exists $output]} { error "Refusing to overwrite routed review evidence" }
file mkdir $output
set outcome [catch {
    open_checkpoint $checkpoint
    report_drc -name csip_drc -file [file join $output drc.rpt]
    set stream [open [file join $output objects.tsv] {WRONLY CREAT EXCL}]
    puts $stream "violation\tseverity\tobject_type\tobject"
    set violations [get_drc_violations -quiet -name csip_drc]
    if {[llength $violations] != 4} { error "Expected four routed DRC findings" }
    set object_count 0
    foreach violation $violations {
        set name [get_property NAME $violation]
        set severity [get_property SEVERITY $violation]
        report_property -all $violation -file [file join $output ${name}.txt]
        foreach kind {cells nets pins ports} {
            foreach object [get_$kind -quiet -of_objects $violation] {
                incr object_count
                puts $stream "$name\t$severity\t$kind\t[get_property NAME $object]"
            }
        }
    }
    close $stream
    if {$object_count == 0} { error "DRC object extraction was empty" }
    puts "DRC_OBJECT_EXTRACTION=PASS"
} message options]
catch {close_design}
if {$outcome} {
    puts stderr "DRC_OBJECT_EXTRACTION=FAIL: $message"
    puts stderr [dict get $options -errorinfo]
    exit 1
}
exit 0
