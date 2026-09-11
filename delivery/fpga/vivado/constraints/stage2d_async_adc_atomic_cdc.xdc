# Stage 2D asynchronous ADC atomic CDC constraint authority.
#
# The production FIFO fixes ADC_FIFO_ADDR_WIDTH=3, so each Gray pointer bus is
# exactly four bits. Scoped packaged-IP XDC accepts only a restricted command
# set; all validation is therefore expressed through direct collections and
# arithmetic assertions rather than Tcl procedures or control flow.
#
# The registered destination payload boundary is constrained from exactly the
# 8 x 57 production FIFO storage registers. This is a bounded datapath-only
# requirement, not a false path or clock-group exception.
# report_cdc and report_timing remain implemented-design review evidence.

set s2d_wr_source_all [get_cells -quiet -hierarchical -regexp \
    {(^|.*/)u_adc_sample_cdc_bridge/u_fifo/wr_gray_reg\[[0-9]+\]$}]
set s2d_wr_source_cells [get_cells -quiet -hierarchical -regexp \
    {(^|.*/)u_adc_sample_cdc_bridge/u_fifo/wr_gray_reg\[[0-3]\]$}]
set s2d_wr_destination_all [get_cells -quiet -hierarchical -regexp \
    {(^|.*/)u_adc_sample_cdc_bridge/u_fifo/wr_gray_sync1_reg\[[0-9]+\]$}]
set s2d_wr_destination_cells [get_cells -quiet -hierarchical -regexp \
    {(^|.*/)u_adc_sample_cdc_bridge/u_fifo/wr_gray_sync1_reg\[[0-3]\]$}]
set s2d_wr_cell_cardinality_assert [expr {1 / (
    [llength $s2d_wr_source_all] == 4 &&
    [llength $s2d_wr_source_cells] == 4 &&
    [llength $s2d_wr_destination_all] == 4 &&
    [llength $s2d_wr_destination_cells] == 4)}]
set s2d_wr_source_pins [get_pins -quiet -of_objects \
    $s2d_wr_source_cells -filter {REF_PIN_NAME == Q}]
set s2d_wr_destination_pins [get_pins -quiet -of_objects \
    $s2d_wr_destination_cells -filter {REF_PIN_NAME == D}]
set s2d_wr_clock_source_pins [get_pins -quiet -of_objects \
    $s2d_wr_source_cells -filter {REF_PIN_NAME == C}]
set s2d_wr_clock_destination_pins [get_pins -quiet -of_objects \
    $s2d_wr_destination_cells -filter {REF_PIN_NAME == C}]
set s2d_wr_pin_cardinality_assert [expr {1 / (
    [llength $s2d_wr_source_pins] == 4 &&
    [llength $s2d_wr_destination_pins] == 4 &&
    [llength $s2d_wr_clock_source_pins] == 4 &&
    [llength $s2d_wr_clock_destination_pins] == 4)}]
set s2d_wr_source_clocks [get_clocks -quiet -of_objects \
    $s2d_wr_clock_source_pins]
set s2d_wr_destination_clocks [get_clocks -quiet -of_objects \
    $s2d_wr_clock_destination_pins]
set s2d_wr_clock_cardinality_assert [expr {1 / (
    [llength $s2d_wr_source_clocks] == 1 &&
    [llength $s2d_wr_destination_clocks] == 1)}]
set s2d_wr_source_period [get_property PERIOD $s2d_wr_source_clocks]
set s2d_wr_destination_period [get_property PERIOD \
    $s2d_wr_destination_clocks]
set s2d_wr_limit [expr {min(double($s2d_wr_source_period),
    double($s2d_wr_destination_period))}]
set s2d_wr_period_assert [expr {1 / ($s2d_wr_limit > 0.0)}]
set_max_delay -datapath_only $s2d_wr_limit \
    -from $s2d_wr_source_cells -to $s2d_wr_destination_cells
set_bus_skew $s2d_wr_limit \
    -from $s2d_wr_source_cells -to $s2d_wr_destination_cells

set s2d_rd_source_all [get_cells -quiet -hierarchical -regexp \
    {(^|.*/)u_adc_sample_cdc_bridge/u_fifo/rd_gray_reg\[[0-9]+\]$}]
set s2d_rd_source_cells [get_cells -quiet -hierarchical -regexp \
    {(^|.*/)u_adc_sample_cdc_bridge/u_fifo/rd_gray_reg\[[0-3]\]$}]
set s2d_rd_destination_all [get_cells -quiet -hierarchical -regexp \
    {(^|.*/)u_adc_sample_cdc_bridge/u_fifo/rd_gray_sync1_reg\[[0-9]+\]$}]
set s2d_rd_destination_cells [get_cells -quiet -hierarchical -regexp \
    {(^|.*/)u_adc_sample_cdc_bridge/u_fifo/rd_gray_sync1_reg\[[0-3]\]$}]
set s2d_rd_cell_cardinality_assert [expr {1 / (
    [llength $s2d_rd_source_all] == 4 &&
    [llength $s2d_rd_source_cells] == 4 &&
    [llength $s2d_rd_destination_all] == 4 &&
    [llength $s2d_rd_destination_cells] == 4)}]
set s2d_rd_source_pins [get_pins -quiet -of_objects \
    $s2d_rd_source_cells -filter {REF_PIN_NAME == Q}]
set s2d_rd_destination_pins [get_pins -quiet -of_objects \
    $s2d_rd_destination_cells -filter {REF_PIN_NAME == D}]
set s2d_rd_clock_source_pins [get_pins -quiet -of_objects \
    $s2d_rd_source_cells -filter {REF_PIN_NAME == C}]
set s2d_rd_clock_destination_pins [get_pins -quiet -of_objects \
    $s2d_rd_destination_cells -filter {REF_PIN_NAME == C}]
set s2d_rd_pin_cardinality_assert [expr {1 / (
    [llength $s2d_rd_source_pins] == 4 &&
    [llength $s2d_rd_destination_pins] == 4 &&
    [llength $s2d_rd_clock_source_pins] == 4 &&
    [llength $s2d_rd_clock_destination_pins] == 4)}]
set s2d_rd_source_clocks [get_clocks -quiet -of_objects \
    $s2d_rd_clock_source_pins]
set s2d_rd_destination_clocks [get_clocks -quiet -of_objects \
    $s2d_rd_clock_destination_pins]
set s2d_rd_clock_cardinality_assert [expr {1 / (
    [llength $s2d_rd_source_clocks] == 1 &&
    [llength $s2d_rd_destination_clocks] == 1)}]
set s2d_rd_source_period [get_property PERIOD $s2d_rd_source_clocks]
set s2d_rd_destination_period [get_property PERIOD \
    $s2d_rd_destination_clocks]
set s2d_rd_limit [expr {min(double($s2d_rd_source_period),
    double($s2d_rd_destination_period))}]
set s2d_rd_period_assert [expr {1 / ($s2d_rd_limit > 0.0)}]
set_max_delay -datapath_only $s2d_rd_limit \
    -from $s2d_rd_source_cells -to $s2d_rd_destination_cells
set_bus_skew $s2d_rd_limit \
    -from $s2d_rd_source_cells -to $s2d_rd_destination_cells

set s2d_payload_source_all [get_cells -quiet -hierarchical -regexp \
    {(^|.*/)u_adc_sample_cdc_bridge/u_fifo/mem_reg\[[0-9]+\]\[[0-9]+\]$}]
set s2d_payload_source_cells [get_cells -quiet -hierarchical -regexp \
    {(^|.*/)u_adc_sample_cdc_bridge/u_fifo/mem_reg\[[0-7]\]\[([0-9]|[1-4][0-9]|5[0-6])\]$}]
set s2d_payload_destination_all [get_cells -quiet -hierarchical -regexp \
    {(^|.*/)u_adc_sample_cdc_bridge/destination_data_reg\[[0-9]+\]$}]
set s2d_payload_destination_cells [get_cells -quiet -hierarchical -regexp \
    {(^|.*/)u_adc_sample_cdc_bridge/destination_data_reg\[([0-9]|[1-4][0-9]|5[0-6])\]$}]
set s2d_payload_cell_cardinality_assert [expr {1 / (
    [llength $s2d_payload_source_all] == 456 &&
    [llength $s2d_payload_source_cells] == 456 &&
    [llength $s2d_payload_destination_all] == 57 &&
    [llength $s2d_payload_destination_cells] == 57)}]
set s2d_payload_source_pins [get_pins -quiet -of_objects \
    $s2d_payload_source_cells -filter {REF_PIN_NAME == Q}]
set s2d_payload_destination_pins [get_pins -quiet -of_objects \
    $s2d_payload_destination_cells -filter {REF_PIN_NAME == D}]
set s2d_payload_clock_source_pins [get_pins -quiet -of_objects \
    $s2d_payload_source_cells -filter {REF_PIN_NAME == C}]
set s2d_payload_clock_destination_pins [get_pins -quiet -of_objects \
    $s2d_payload_destination_cells -filter {REF_PIN_NAME == C}]
set s2d_payload_pin_cardinality_assert [expr {1 / (
    [llength $s2d_payload_source_pins] == 456 &&
    [llength $s2d_payload_destination_pins] == 57 &&
    [llength $s2d_payload_clock_source_pins] == 456 &&
    [llength $s2d_payload_clock_destination_pins] == 57)}]
set s2d_payload_source_clocks [get_clocks -quiet -of_objects \
    $s2d_payload_clock_source_pins]
set s2d_payload_destination_clocks [get_clocks -quiet -of_objects \
    $s2d_payload_clock_destination_pins]
set s2d_payload_clock_cardinality_assert [expr {1 / (
    [llength $s2d_payload_source_clocks] == 1 &&
    [llength $s2d_payload_destination_clocks] == 1)}]
set s2d_payload_source_period [get_property PERIOD \
    $s2d_payload_source_clocks]
set s2d_payload_destination_period [get_property PERIOD \
    $s2d_payload_destination_clocks]
set s2d_payload_limit [expr {min(double($s2d_payload_source_period),
    double($s2d_payload_destination_period))}]
set s2d_payload_period_assert [expr {1 / ($s2d_payload_limit > 0.0)}]
set_max_delay -datapath_only $s2d_payload_limit \
    -from $s2d_payload_source_cells -to $s2d_payload_destination_cells

set ::stage2d_async_adc_atomic_cdc_constraint_result {
    {crossing WRITE_POINTER_TO_READ_DOMAIN width 4}
    {crossing READ_POINTER_TO_WRITE_DOMAIN width 4}
    {crossing FIFO_PAYLOAD_TO_DESTINATION_REGISTER width 57 depth 8}
}
