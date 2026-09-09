# Stage 2E transaction observability CDC constraint authority.
#
# The seven registered Gray buses are fixed at COUNTER_WIDTH=32 in the current
# production IP. Scoped packaged-IP XDC accepts only a restricted command set;
# all validation is therefore expressed through direct collections and
# arithmetic assertions rather than Tcl procedures or control flow.
#
# Only Q-to-first-stage-D paths are constrained. Binary counters, event pulses,
# FIFO payload RAM, and later synchronizer stages are intentionally excluded.
# report_cdc and report_timing remain implemented-design review evidence.

set s2e_accept_source_all [get_cells -quiet -hierarchical -regexp \
    {(^|.*/)u_adc_sample_cdc_bridge/u_source_observer/source_accept_count_gray_reg\[[0-9]+\]$}]
set s2e_accept_source_cells [get_cells -quiet -hierarchical -regexp \
    {(^|.*/)u_adc_sample_cdc_bridge/u_source_observer/source_accept_count_gray_reg\[(0|[1-9]|[12][0-9]|3[01])\]$}]
set s2e_accept_destination_all [get_cells -quiet -hierarchical -regexp \
    {(^|.*/)u_source_observability_cdc/source_accept_count_gray_sync1_reg\[[0-9]+\]$}]
set s2e_accept_destination_cells [get_cells -quiet -hierarchical -regexp \
    {(^|.*/)u_source_observability_cdc/source_accept_count_gray_sync1_reg\[(0|[1-9]|[12][0-9]|3[01])\]$}]
set s2e_accept_cell_assert [expr {1 / (
    [llength $s2e_accept_source_all] == 32 &&
    [llength $s2e_accept_source_cells] == 32 &&
    [llength $s2e_accept_destination_all] == 32 &&
    [llength $s2e_accept_destination_cells] == 32)}]
set s2e_accept_source_pins [get_pins -quiet -of_objects \
    $s2e_accept_source_cells -filter {REF_PIN_NAME == Q}]
set s2e_accept_destination_pins [get_pins -quiet -of_objects \
    $s2e_accept_destination_cells -filter {REF_PIN_NAME == D}]
set s2e_accept_source_clock_pins [get_pins -quiet -of_objects \
    $s2e_accept_source_cells -filter {REF_PIN_NAME == C}]
set s2e_accept_destination_clock_pins [get_pins -quiet -of_objects \
    $s2e_accept_destination_cells -filter {REF_PIN_NAME == C}]
set s2e_accept_pin_assert [expr {1 / (
    [llength $s2e_accept_source_pins] == 32 &&
    [llength $s2e_accept_destination_pins] == 32 &&
    [llength $s2e_accept_source_clock_pins] == 32 &&
    [llength $s2e_accept_destination_clock_pins] == 32)}]
set s2e_accept_source_clocks [get_clocks -quiet -of_objects \
    $s2e_accept_source_clock_pins]
set s2e_accept_destination_clocks [get_clocks -quiet -of_objects \
    $s2e_accept_destination_clock_pins]
set s2e_accept_clock_assert [expr {1 / (
    [llength $s2e_accept_source_clocks] == 1 &&
    [llength $s2e_accept_destination_clocks] == 1)}]
set s2e_accept_source_period [get_property PERIOD \
    $s2e_accept_source_clocks]
set s2e_accept_destination_period [get_property PERIOD \
    $s2e_accept_destination_clocks]
set s2e_accept_limit [expr {min(double($s2e_accept_source_period),
    double($s2e_accept_destination_period))}]
set s2e_accept_period_assert [expr {1 / ($s2e_accept_limit > 0.0)}]
set_max_delay -datapath_only $s2e_accept_limit \
    -from $s2e_accept_source_cells -to $s2e_accept_destination_cells
set_bus_skew $s2e_accept_limit \
    -from $s2e_accept_source_cells -to $s2e_accept_destination_cells

set s2e_backpressure_source_all [get_cells -quiet -hierarchical -regexp \
    {(^|.*/)u_adc_sample_cdc_bridge/u_source_observer/backpressure_cycle_count_gray_reg\[[0-9]+\]$}]
set s2e_backpressure_source_cells [get_cells -quiet -hierarchical -regexp \
    {(^|.*/)u_adc_sample_cdc_bridge/u_source_observer/backpressure_cycle_count_gray_reg\[(0|[1-9]|[12][0-9]|3[01])\]$}]
set s2e_backpressure_destination_all [get_cells -quiet -hierarchical -regexp \
    {(^|.*/)u_source_observability_cdc/backpressure_cycle_count_gray_sync1_reg\[[0-9]+\]$}]
set s2e_backpressure_destination_cells [get_cells -quiet -hierarchical -regexp \
    {(^|.*/)u_source_observability_cdc/backpressure_cycle_count_gray_sync1_reg\[(0|[1-9]|[12][0-9]|3[01])\]$}]
set s2e_backpressure_cell_assert [expr {1 / (
    [llength $s2e_backpressure_source_all] == 32 &&
    [llength $s2e_backpressure_source_cells] == 32 &&
    [llength $s2e_backpressure_destination_all] == 32 &&
    [llength $s2e_backpressure_destination_cells] == 32)}]
set s2e_backpressure_source_pins [get_pins -quiet -of_objects \
    $s2e_backpressure_source_cells -filter {REF_PIN_NAME == Q}]
set s2e_backpressure_destination_pins [get_pins -quiet -of_objects \
    $s2e_backpressure_destination_cells -filter {REF_PIN_NAME == D}]
set s2e_backpressure_source_clock_pins [get_pins -quiet -of_objects \
    $s2e_backpressure_source_cells -filter {REF_PIN_NAME == C}]
set s2e_backpressure_destination_clock_pins [get_pins -quiet -of_objects \
    $s2e_backpressure_destination_cells -filter {REF_PIN_NAME == C}]
set s2e_backpressure_pin_assert [expr {1 / (
    [llength $s2e_backpressure_source_pins] == 32 &&
    [llength $s2e_backpressure_destination_pins] == 32 &&
    [llength $s2e_backpressure_source_clock_pins] == 32 &&
    [llength $s2e_backpressure_destination_clock_pins] == 32)}]
set s2e_backpressure_source_clocks [get_clocks -quiet -of_objects \
    $s2e_backpressure_source_clock_pins]
set s2e_backpressure_destination_clocks [get_clocks -quiet -of_objects \
    $s2e_backpressure_destination_clock_pins]
set s2e_backpressure_clock_assert [expr {1 / (
    [llength $s2e_backpressure_source_clocks] == 1 &&
    [llength $s2e_backpressure_destination_clocks] == 1)}]
set s2e_backpressure_source_period [get_property PERIOD \
    $s2e_backpressure_source_clocks]
set s2e_backpressure_destination_period [get_property PERIOD \
    $s2e_backpressure_destination_clocks]
set s2e_backpressure_limit [expr {min(double($s2e_backpressure_source_period),
    double($s2e_backpressure_destination_period))}]
set s2e_backpressure_period_assert [expr {1 / (
    $s2e_backpressure_limit > 0.0)}]
set_max_delay -datapath_only $s2e_backpressure_limit \
    -from $s2e_backpressure_source_cells \
    -to $s2e_backpressure_destination_cells
set_bus_skew $s2e_backpressure_limit \
    -from $s2e_backpressure_source_cells \
    -to $s2e_backpressure_destination_cells

set s2e_protocol_source_all [get_cells -quiet -hierarchical -regexp \
    {(^|.*/)u_adc_sample_cdc_bridge/u_source_observer/source_protocol_violation_count_gray_reg\[[0-9]+\]$}]
set s2e_protocol_source_cells [get_cells -quiet -hierarchical -regexp \
    {(^|.*/)u_adc_sample_cdc_bridge/u_source_observer/source_protocol_violation_count_gray_reg\[(0|[1-9]|[12][0-9]|3[01])\]$}]
set s2e_protocol_destination_all [get_cells -quiet -hierarchical -regexp \
    {(^|.*/)u_source_observability_cdc/source_protocol_violation_count_gray_sync1_reg\[[0-9]+\]$}]
set s2e_protocol_destination_cells [get_cells -quiet -hierarchical -regexp \
    {(^|.*/)u_source_observability_cdc/source_protocol_violation_count_gray_sync1_reg\[(0|[1-9]|[12][0-9]|3[01])\]$}]
set s2e_protocol_cell_assert [expr {1 / (
    [llength $s2e_protocol_source_all] == 32 &&
    [llength $s2e_protocol_source_cells] == 32 &&
    [llength $s2e_protocol_destination_all] == 32 &&
    [llength $s2e_protocol_destination_cells] == 32)}]
set s2e_protocol_source_pins [get_pins -quiet -of_objects \
    $s2e_protocol_source_cells -filter {REF_PIN_NAME == Q}]
set s2e_protocol_destination_pins [get_pins -quiet -of_objects \
    $s2e_protocol_destination_cells -filter {REF_PIN_NAME == D}]
set s2e_protocol_source_clock_pins [get_pins -quiet -of_objects \
    $s2e_protocol_source_cells -filter {REF_PIN_NAME == C}]
set s2e_protocol_destination_clock_pins [get_pins -quiet -of_objects \
    $s2e_protocol_destination_cells -filter {REF_PIN_NAME == C}]
set s2e_protocol_pin_assert [expr {1 / (
    [llength $s2e_protocol_source_pins] == 32 &&
    [llength $s2e_protocol_destination_pins] == 32 &&
    [llength $s2e_protocol_source_clock_pins] == 32 &&
    [llength $s2e_protocol_destination_clock_pins] == 32)}]
set s2e_protocol_source_clocks [get_clocks -quiet -of_objects \
    $s2e_protocol_source_clock_pins]
set s2e_protocol_destination_clocks [get_clocks -quiet -of_objects \
    $s2e_protocol_destination_clock_pins]
set s2e_protocol_clock_assert [expr {1 / (
    [llength $s2e_protocol_source_clocks] == 1 &&
    [llength $s2e_protocol_destination_clocks] == 1)}]
set s2e_protocol_source_period [get_property PERIOD \
    $s2e_protocol_source_clocks]
set s2e_protocol_destination_period [get_property PERIOD \
    $s2e_protocol_destination_clocks]
set s2e_protocol_limit [expr {min(double($s2e_protocol_source_period),
    double($s2e_protocol_destination_period))}]
set s2e_protocol_period_assert [expr {1 / ($s2e_protocol_limit > 0.0)}]
set_max_delay -datapath_only $s2e_protocol_limit \
    -from $s2e_protocol_source_cells -to $s2e_protocol_destination_cells
set_bus_skew $s2e_protocol_limit \
    -from $s2e_protocol_source_cells -to $s2e_protocol_destination_cells

set s2e_drop_source_all [get_cells -quiet -hierarchical -regexp \
    {(^|.*/)u_adc_sample_cdc_bridge/u_source_observer/source_drop_count_gray_reg\[[0-9]+\]$}]
set s2e_drop_source_cells [get_cells -quiet -hierarchical -regexp \
    {(^|.*/)u_adc_sample_cdc_bridge/u_source_observer/source_drop_count_gray_reg\[(0|[1-9]|[12][0-9]|3[01])\]$}]
set s2e_drop_destination_all [get_cells -quiet -hierarchical -regexp \
    {(^|.*/)u_source_observability_cdc/source_drop_count_gray_sync1_reg\[[0-9]+\]$}]
set s2e_drop_destination_cells [get_cells -quiet -hierarchical -regexp \
    {(^|.*/)u_source_observability_cdc/source_drop_count_gray_sync1_reg\[(0|[1-9]|[12][0-9]|3[01])\]$}]
set s2e_drop_cell_assert [expr {1 / (
    [llength $s2e_drop_source_all] == 32 &&
    [llength $s2e_drop_source_cells] == 32 &&
    [llength $s2e_drop_destination_all] == 32 &&
    [llength $s2e_drop_destination_cells] == 32)}]
set s2e_drop_source_pins [get_pins -quiet -of_objects \
    $s2e_drop_source_cells -filter {REF_PIN_NAME == Q}]
set s2e_drop_destination_pins [get_pins -quiet -of_objects \
    $s2e_drop_destination_cells -filter {REF_PIN_NAME == D}]
set s2e_drop_source_clock_pins [get_pins -quiet -of_objects \
    $s2e_drop_source_cells -filter {REF_PIN_NAME == C}]
set s2e_drop_destination_clock_pins [get_pins -quiet -of_objects \
    $s2e_drop_destination_cells -filter {REF_PIN_NAME == C}]
set s2e_drop_pin_assert [expr {1 / (
    [llength $s2e_drop_source_pins] == 32 &&
    [llength $s2e_drop_destination_pins] == 32 &&
    [llength $s2e_drop_source_clock_pins] == 32 &&
    [llength $s2e_drop_destination_clock_pins] == 32)}]
set s2e_drop_source_clocks [get_clocks -quiet -of_objects \
    $s2e_drop_source_clock_pins]
set s2e_drop_destination_clocks [get_clocks -quiet -of_objects \
    $s2e_drop_destination_clock_pins]
set s2e_drop_clock_assert [expr {1 / (
    [llength $s2e_drop_source_clocks] == 1 &&
    [llength $s2e_drop_destination_clocks] == 1)}]
set s2e_drop_source_period [get_property PERIOD $s2e_drop_source_clocks]
set s2e_drop_destination_period [get_property PERIOD \
    $s2e_drop_destination_clocks]
set s2e_drop_limit [expr {min(double($s2e_drop_source_period),
    double($s2e_drop_destination_period))}]
set s2e_drop_period_assert [expr {1 / ($s2e_drop_limit > 0.0)}]
set_max_delay -datapath_only $s2e_drop_limit \
    -from $s2e_drop_source_cells -to $s2e_drop_destination_cells
set_bus_skew $s2e_drop_limit \
    -from $s2e_drop_source_cells -to $s2e_drop_destination_cells

set s2e_overflow_source_all [get_cells -quiet -hierarchical -regexp \
    {(^|.*/)u_adc_sample_cdc_bridge/u_source_observer/fifo_overflow_attempt_count_gray_reg\[[0-9]+\]$}]
set s2e_overflow_source_cells [get_cells -quiet -hierarchical -regexp \
    {(^|.*/)u_adc_sample_cdc_bridge/u_source_observer/fifo_overflow_attempt_count_gray_reg\[(0|[1-9]|[12][0-9]|3[01])\]$}]
set s2e_overflow_destination_all [get_cells -quiet -hierarchical -regexp \
    {(^|.*/)u_source_observability_cdc/fifo_overflow_attempt_count_gray_sync1_reg\[[0-9]+\]$}]
set s2e_overflow_destination_cells [get_cells -quiet -hierarchical -regexp \
    {(^|.*/)u_source_observability_cdc/fifo_overflow_attempt_count_gray_sync1_reg\[(0|[1-9]|[12][0-9]|3[01])\]$}]
set s2e_overflow_cell_assert [expr {1 / (
    [llength $s2e_overflow_source_all] == 32 &&
    [llength $s2e_overflow_source_cells] == 32 &&
    [llength $s2e_overflow_destination_all] == 32 &&
    [llength $s2e_overflow_destination_cells] == 32)}]
set s2e_overflow_source_pins [get_pins -quiet -of_objects \
    $s2e_overflow_source_cells -filter {REF_PIN_NAME == Q}]
set s2e_overflow_destination_pins [get_pins -quiet -of_objects \
    $s2e_overflow_destination_cells -filter {REF_PIN_NAME == D}]
set s2e_overflow_source_clock_pins [get_pins -quiet -of_objects \
    $s2e_overflow_source_cells -filter {REF_PIN_NAME == C}]
set s2e_overflow_destination_clock_pins [get_pins -quiet -of_objects \
    $s2e_overflow_destination_cells -filter {REF_PIN_NAME == C}]
set s2e_overflow_pin_assert [expr {1 / (
    [llength $s2e_overflow_source_pins] == 32 &&
    [llength $s2e_overflow_destination_pins] == 32 &&
    [llength $s2e_overflow_source_clock_pins] == 32 &&
    [llength $s2e_overflow_destination_clock_pins] == 32)}]
set s2e_overflow_source_clocks [get_clocks -quiet -of_objects \
    $s2e_overflow_source_clock_pins]
set s2e_overflow_destination_clocks [get_clocks -quiet -of_objects \
    $s2e_overflow_destination_clock_pins]
set s2e_overflow_clock_assert [expr {1 / (
    [llength $s2e_overflow_source_clocks] == 1 &&
    [llength $s2e_overflow_destination_clocks] == 1)}]
set s2e_overflow_source_period [get_property PERIOD \
    $s2e_overflow_source_clocks]
set s2e_overflow_destination_period [get_property PERIOD \
    $s2e_overflow_destination_clocks]
set s2e_overflow_limit [expr {min(double($s2e_overflow_source_period),
    double($s2e_overflow_destination_period))}]
set s2e_overflow_period_assert [expr {1 / ($s2e_overflow_limit > 0.0)}]
set_max_delay -datapath_only $s2e_overflow_limit \
    -from $s2e_overflow_source_cells -to $s2e_overflow_destination_cells
set_bus_skew $s2e_overflow_limit \
    -from $s2e_overflow_source_cells -to $s2e_overflow_destination_cells

set s2e_saturation_source_all [get_cells -quiet -hierarchical -regexp \
    {(^|.*/)u_adc_sample_cdc_bridge/u_source_observer/counter_saturation_event_count_gray_reg\[[0-9]+\]$}]
set s2e_saturation_source_cells [get_cells -quiet -hierarchical -regexp \
    {(^|.*/)u_adc_sample_cdc_bridge/u_source_observer/counter_saturation_event_count_gray_reg\[(0|[1-9]|[12][0-9]|3[01])\]$}]
set s2e_saturation_destination_all [get_cells -quiet -hierarchical -regexp \
    {(^|.*/)u_source_observability_cdc/counter_saturation_event_count_gray_sync1_reg\[[0-9]+\]$}]
set s2e_saturation_destination_cells [get_cells -quiet -hierarchical -regexp \
    {(^|.*/)u_source_observability_cdc/counter_saturation_event_count_gray_sync1_reg\[(0|[1-9]|[12][0-9]|3[01])\]$}]
set s2e_saturation_cell_assert [expr {1 / (
    [llength $s2e_saturation_source_all] == 32 &&
    [llength $s2e_saturation_source_cells] == 32 &&
    [llength $s2e_saturation_destination_all] == 32 &&
    [llength $s2e_saturation_destination_cells] == 32)}]
set s2e_saturation_source_pins [get_pins -quiet -of_objects \
    $s2e_saturation_source_cells -filter {REF_PIN_NAME == Q}]
set s2e_saturation_destination_pins [get_pins -quiet -of_objects \
    $s2e_saturation_destination_cells -filter {REF_PIN_NAME == D}]
set s2e_saturation_source_clock_pins [get_pins -quiet -of_objects \
    $s2e_saturation_source_cells -filter {REF_PIN_NAME == C}]
set s2e_saturation_destination_clock_pins [get_pins -quiet -of_objects \
    $s2e_saturation_destination_cells -filter {REF_PIN_NAME == C}]
set s2e_saturation_pin_assert [expr {1 / (
    [llength $s2e_saturation_source_pins] == 32 &&
    [llength $s2e_saturation_destination_pins] == 32 &&
    [llength $s2e_saturation_source_clock_pins] == 32 &&
    [llength $s2e_saturation_destination_clock_pins] == 32)}]
set s2e_saturation_source_clocks [get_clocks -quiet -of_objects \
    $s2e_saturation_source_clock_pins]
set s2e_saturation_destination_clocks [get_clocks -quiet -of_objects \
    $s2e_saturation_destination_clock_pins]
set s2e_saturation_clock_assert [expr {1 / (
    [llength $s2e_saturation_source_clocks] == 1 &&
    [llength $s2e_saturation_destination_clocks] == 1)}]
set s2e_saturation_source_period [get_property PERIOD \
    $s2e_saturation_source_clocks]
set s2e_saturation_destination_period [get_property PERIOD \
    $s2e_saturation_destination_clocks]
set s2e_saturation_limit [expr {min(double($s2e_saturation_source_period),
    double($s2e_saturation_destination_period))}]
set s2e_saturation_period_assert [expr {1 / (
    $s2e_saturation_limit > 0.0)}]
set_max_delay -datapath_only $s2e_saturation_limit \
    -from $s2e_saturation_source_cells \
    -to $s2e_saturation_destination_cells
set_bus_skew $s2e_saturation_limit \
    -from $s2e_saturation_source_cells \
    -to $s2e_saturation_destination_cells

set s2e_sequence_source_all [get_cells -quiet -hierarchical -regexp \
    {(^|.*/)u_adc_sample_cdc_bridge/u_source_observer/last_source_sequence_gray_reg\[[0-9]+\]$}]
set s2e_sequence_source_cells [get_cells -quiet -hierarchical -regexp \
    {(^|.*/)u_adc_sample_cdc_bridge/u_source_observer/last_source_sequence_gray_reg\[(0|[1-9]|[12][0-9]|3[01])\]$}]
set s2e_sequence_destination_all [get_cells -quiet -hierarchical -regexp \
    {(^|.*/)u_source_observability_cdc/last_source_sequence_gray_sync1_reg\[[0-9]+\]$}]
set s2e_sequence_destination_cells [get_cells -quiet -hierarchical -regexp \
    {(^|.*/)u_source_observability_cdc/last_source_sequence_gray_sync1_reg\[(0|[1-9]|[12][0-9]|3[01])\]$}]
set s2e_sequence_cell_assert [expr {1 / (
    [llength $s2e_sequence_source_all] == 32 &&
    [llength $s2e_sequence_source_cells] == 32 &&
    [llength $s2e_sequence_destination_all] == 32 &&
    [llength $s2e_sequence_destination_cells] == 32)}]
set s2e_sequence_source_pins [get_pins -quiet -of_objects \
    $s2e_sequence_source_cells -filter {REF_PIN_NAME == Q}]
set s2e_sequence_destination_pins [get_pins -quiet -of_objects \
    $s2e_sequence_destination_cells -filter {REF_PIN_NAME == D}]
set s2e_sequence_source_clock_pins [get_pins -quiet -of_objects \
    $s2e_sequence_source_cells -filter {REF_PIN_NAME == C}]
set s2e_sequence_destination_clock_pins [get_pins -quiet -of_objects \
    $s2e_sequence_destination_cells -filter {REF_PIN_NAME == C}]
set s2e_sequence_pin_assert [expr {1 / (
    [llength $s2e_sequence_source_pins] == 32 &&
    [llength $s2e_sequence_destination_pins] == 32 &&
    [llength $s2e_sequence_source_clock_pins] == 32 &&
    [llength $s2e_sequence_destination_clock_pins] == 32)}]
set s2e_sequence_source_clocks [get_clocks -quiet -of_objects \
    $s2e_sequence_source_clock_pins]
set s2e_sequence_destination_clocks [get_clocks -quiet -of_objects \
    $s2e_sequence_destination_clock_pins]
set s2e_sequence_clock_assert [expr {1 / (
    [llength $s2e_sequence_source_clocks] == 1 &&
    [llength $s2e_sequence_destination_clocks] == 1)}]
set s2e_sequence_source_period [get_property PERIOD \
    $s2e_sequence_source_clocks]
set s2e_sequence_destination_period [get_property PERIOD \
    $s2e_sequence_destination_clocks]
set s2e_sequence_limit [expr {min(double($s2e_sequence_source_period),
    double($s2e_sequence_destination_period))}]
set s2e_sequence_period_assert [expr {1 / ($s2e_sequence_limit > 0.0)}]
set_max_delay -datapath_only $s2e_sequence_limit \
    -from $s2e_sequence_source_cells -to $s2e_sequence_destination_cells
set_bus_skew $s2e_sequence_limit \
    -from $s2e_sequence_source_cells -to $s2e_sequence_destination_cells

set ::stage2e_transaction_observability_cdc_constraint_result {
    {crossing SOURCE_ACCEPT_COUNT width 32}
    {crossing BACKPRESSURE_CYCLE_COUNT width 32}
    {crossing SOURCE_PROTOCOL_COUNT width 32}
    {crossing SOURCE_DROP_COUNT width 32}
    {crossing FIFO_OVERFLOW_COUNT width 32}
    {crossing SOURCE_SATURATION_EVENTS width 32}
    {crossing LAST_SOURCE_SEQUENCE width 32}
}
