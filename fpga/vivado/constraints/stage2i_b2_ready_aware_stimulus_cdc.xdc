# Stage 2I-B ready-aware synthetic producer CDC authority.
#
# Scoped and top-level implementation XDC readers accept a restricted command
# set. Every crossing is therefore resolved and checked with straight-line Tcl.
# The smaller endpoint period bounds each request/ack, bundled-data, or status
# crossing. Only the two asynchronous-assert/synchronous-release source reset
# registers receive a false path, and only at their CLR pins.

set s2ib2_request_source [get_cells -quiet -hierarchical -regexp \
    {(^|.*/)stage2i_b2_ready_aware_stimulus_0/(inst/)?request_toggle_aclk_reg$}]
set s2ib2_request_destination [get_cells -quiet -hierarchical -regexp \
    {(^|.*/)stage2i_b2_ready_aware_stimulus_0/(inst/)?request_toggle_sync1_src_reg$}]
set s2ib2_request_cell_cardinality_assert [expr {1 / (
    [llength $s2ib2_request_source] == 1 &&
    [llength $s2ib2_request_destination] == 1)}]
set s2ib2_request_source_q [get_pins -quiet -of_objects \
    $s2ib2_request_source -filter {REF_PIN_NAME == Q}]
set s2ib2_request_destination_d [get_pins -quiet -of_objects \
    $s2ib2_request_destination -filter {REF_PIN_NAME == D}]
set s2ib2_request_source_c [get_pins -quiet -of_objects \
    $s2ib2_request_source -filter {REF_PIN_NAME == C}]
set s2ib2_request_destination_c [get_pins -quiet -of_objects \
    $s2ib2_request_destination -filter {REF_PIN_NAME == C}]
set s2ib2_request_pin_cardinality_assert [expr {1 / (
    [llength $s2ib2_request_source_q] == 1 &&
    [llength $s2ib2_request_destination_d] == 1 &&
    [llength $s2ib2_request_source_c] == 1 &&
    [llength $s2ib2_request_destination_c] == 1)}]
set s2ib2_request_source_clock [get_clocks -quiet -of_objects \
    $s2ib2_request_source_c]
set s2ib2_request_destination_clock [get_clocks -quiet -of_objects \
    $s2ib2_request_destination_c]
set s2ib2_request_clock_cardinality_assert [expr {1 / (
    [llength $s2ib2_request_source_clock] == 1 &&
    [llength $s2ib2_request_destination_clock] == 1)}]
set s2ib2_request_source_period [get_property PERIOD \
    $s2ib2_request_source_clock]
set s2ib2_request_destination_period [get_property PERIOD \
    $s2ib2_request_destination_clock]
set s2ib2_request_limit [expr {min(double($s2ib2_request_source_period),
    double($s2ib2_request_destination_period))}]
set s2ib2_request_period_assert [expr {1 / ($s2ib2_request_limit > 0.0)}]
set_max_delay -datapath_only $s2ib2_request_limit \
    -from $s2ib2_request_source -to $s2ib2_request_destination

set s2ib2_command_source_all [get_cells -quiet -hierarchical -regexp \
    {(^|.*/)stage2i_b2_ready_aware_stimulus_0/(inst/)?command_hold_aclk_reg\[[0-9]+\]$}]
set s2ib2_command_source [get_cells -quiet -hierarchical -regexp \
    {(^|.*/)stage2i_b2_ready_aware_stimulus_0/(inst/)?command_hold_aclk_reg\[([0-9]|[1-2][0-9]|30)\]$}]
set s2ib2_command_destination_all [get_cells -quiet -hierarchical -regexp \
    {(^|.*/)stage2i_b2_ready_aware_stimulus_0/(inst/)?command_capture_src_reg\[[0-9]+\]$}]
set s2ib2_command_destination [get_cells -quiet -hierarchical -regexp \
    {(^|.*/)stage2i_b2_ready_aware_stimulus_0/(inst/)?command_capture_src_reg\[([0-9]|[1-2][0-9]|30)\]$}]
set s2ib2_command_cell_cardinality_assert [expr {1 / (
    [llength $s2ib2_command_source_all] == 31 &&
    [llength $s2ib2_command_source] == 31 &&
    [llength $s2ib2_command_destination_all] == 31 &&
    [llength $s2ib2_command_destination] == 31)}]
set s2ib2_command_source_q [get_pins -quiet -of_objects \
    $s2ib2_command_source -filter {REF_PIN_NAME == Q}]
set s2ib2_command_destination_d [get_pins -quiet -of_objects \
    $s2ib2_command_destination -filter {REF_PIN_NAME == D}]
set s2ib2_command_source_c [get_pins -quiet -of_objects \
    $s2ib2_command_source -filter {REF_PIN_NAME == C}]
set s2ib2_command_destination_c [get_pins -quiet -of_objects \
    $s2ib2_command_destination -filter {REF_PIN_NAME == C}]
set s2ib2_command_pin_cardinality_assert [expr {1 / (
    [llength $s2ib2_command_source_q] == 31 &&
    [llength $s2ib2_command_destination_d] == 31 &&
    [llength $s2ib2_command_source_c] == 31 &&
    [llength $s2ib2_command_destination_c] == 31)}]
set s2ib2_command_source_clock [get_clocks -quiet -of_objects \
    $s2ib2_command_source_c]
set s2ib2_command_destination_clock [get_clocks -quiet -of_objects \
    $s2ib2_command_destination_c]
set s2ib2_command_clock_cardinality_assert [expr {1 / (
    [llength $s2ib2_command_source_clock] == 1 &&
    [llength $s2ib2_command_destination_clock] == 1)}]
set s2ib2_command_source_period [get_property PERIOD \
    $s2ib2_command_source_clock]
set s2ib2_command_destination_period [get_property PERIOD \
    $s2ib2_command_destination_clock]
set s2ib2_command_limit [expr {min(double($s2ib2_command_source_period),
    double($s2ib2_command_destination_period))}]
set s2ib2_command_period_assert [expr {1 / ($s2ib2_command_limit > 0.0)}]
set_max_delay -datapath_only $s2ib2_command_limit \
    -from $s2ib2_command_source -to $s2ib2_command_destination
set_bus_skew $s2ib2_command_limit \
    -from $s2ib2_command_source -to $s2ib2_command_destination

set s2ib2_ack_source [get_cells -quiet -hierarchical -regexp \
    {(^|.*/)stage2i_b2_ready_aware_stimulus_0/(inst/)?ack_toggle_src_reg$}]
set s2ib2_ack_destination [get_cells -quiet -hierarchical -regexp \
    {(^|.*/)stage2i_b2_ready_aware_stimulus_0/(inst/)?ack_toggle_sync1_aclk_reg$}]
set s2ib2_ack_cell_cardinality_assert [expr {1 / (
    [llength $s2ib2_ack_source] == 1 &&
    [llength $s2ib2_ack_destination] == 1)}]
set s2ib2_ack_source_q [get_pins -quiet -of_objects \
    $s2ib2_ack_source -filter {REF_PIN_NAME == Q}]
set s2ib2_ack_destination_d [get_pins -quiet -of_objects \
    $s2ib2_ack_destination -filter {REF_PIN_NAME == D}]
set s2ib2_ack_source_c [get_pins -quiet -of_objects \
    $s2ib2_ack_source -filter {REF_PIN_NAME == C}]
set s2ib2_ack_destination_c [get_pins -quiet -of_objects \
    $s2ib2_ack_destination -filter {REF_PIN_NAME == C}]
set s2ib2_ack_pin_cardinality_assert [expr {1 / (
    [llength $s2ib2_ack_source_q] == 1 &&
    [llength $s2ib2_ack_destination_d] == 1 &&
    [llength $s2ib2_ack_source_c] == 1 &&
    [llength $s2ib2_ack_destination_c] == 1)}]
set s2ib2_ack_source_clock [get_clocks -quiet -of_objects \
    $s2ib2_ack_source_c]
set s2ib2_ack_destination_clock [get_clocks -quiet -of_objects \
    $s2ib2_ack_destination_c]
set s2ib2_ack_clock_cardinality_assert [expr {1 / (
    [llength $s2ib2_ack_source_clock] == 1 &&
    [llength $s2ib2_ack_destination_clock] == 1)}]
set s2ib2_ack_source_period [get_property PERIOD $s2ib2_ack_source_clock]
set s2ib2_ack_destination_period [get_property PERIOD \
    $s2ib2_ack_destination_clock]
set s2ib2_ack_limit [expr {min(double($s2ib2_ack_source_period),
    double($s2ib2_ack_destination_period))}]
set s2ib2_ack_period_assert [expr {1 / ($s2ib2_ack_limit > 0.0)}]
set_max_delay -datapath_only $s2ib2_ack_limit \
    -from $s2ib2_ack_source -to $s2ib2_ack_destination

set s2ib2_active_source [get_cells -quiet -hierarchical -regexp \
    {(^|.*/)stage2i_b2_ready_aware_stimulus_0/(inst/)?producer_active_reg_reg$}]
set s2ib2_active_destination [get_cells -quiet -hierarchical -regexp \
    {(^|.*/)stage2i_b2_ready_aware_stimulus_0/(inst/)?producer_active_sync1_aclk_reg$}]
set s2ib2_active_cell_cardinality_assert [expr {1 / (
    [llength $s2ib2_active_source] == 1 &&
    [llength $s2ib2_active_destination] == 1)}]
set s2ib2_active_source_q [get_pins -quiet -of_objects \
    $s2ib2_active_source -filter {REF_PIN_NAME == Q}]
set s2ib2_active_destination_d [get_pins -quiet -of_objects \
    $s2ib2_active_destination -filter {REF_PIN_NAME == D}]
set s2ib2_active_source_c [get_pins -quiet -of_objects \
    $s2ib2_active_source -filter {REF_PIN_NAME == C}]
set s2ib2_active_destination_c [get_pins -quiet -of_objects \
    $s2ib2_active_destination -filter {REF_PIN_NAME == C}]
set s2ib2_active_pin_cardinality_assert [expr {1 / (
    [llength $s2ib2_active_source_q] == 1 &&
    [llength $s2ib2_active_destination_d] == 1 &&
    [llength $s2ib2_active_source_c] == 1 &&
    [llength $s2ib2_active_destination_c] == 1)}]
set s2ib2_active_source_clock [get_clocks -quiet -of_objects \
    $s2ib2_active_source_c]
set s2ib2_active_destination_clock [get_clocks -quiet -of_objects \
    $s2ib2_active_destination_c]
set s2ib2_active_clock_cardinality_assert [expr {1 / (
    [llength $s2ib2_active_source_clock] == 1 &&
    [llength $s2ib2_active_destination_clock] == 1)}]
set s2ib2_active_source_period [get_property PERIOD \
    $s2ib2_active_source_clock]
set s2ib2_active_destination_period [get_property PERIOD \
    $s2ib2_active_destination_clock]
set s2ib2_active_limit [expr {min(double($s2ib2_active_source_period),
    double($s2ib2_active_destination_period))}]
set s2ib2_active_period_assert [expr {1 / ($s2ib2_active_limit > 0.0)}]
set_max_delay -datapath_only $s2ib2_active_limit \
    -from $s2ib2_active_source -to $s2ib2_active_destination

set s2ib2_accepted_source_all [get_cells -quiet -hierarchical -regexp \
    {(^|.*/)stage2i_b2_ready_aware_stimulus_0/(inst/)?accepted_count_gray_src_reg\[[0-9]+\]$}]
set s2ib2_accepted_source [get_cells -quiet -hierarchical -regexp \
    {(^|.*/)stage2i_b2_ready_aware_stimulus_0/(inst/)?accepted_count_gray_src_reg\[[0-7]\]$}]
set s2ib2_accepted_destination_all [get_cells -quiet -hierarchical -regexp \
    {(^|.*/)stage2i_b2_ready_aware_stimulus_0/(inst/)?accepted_count_gray_sync1_aclk_reg\[[0-9]+\]$}]
set s2ib2_accepted_destination [get_cells -quiet -hierarchical -regexp \
    {(^|.*/)stage2i_b2_ready_aware_stimulus_0/(inst/)?accepted_count_gray_sync1_aclk_reg\[[0-7]\]$}]
set s2ib2_accepted_cell_cardinality_assert [expr {1 / (
    [llength $s2ib2_accepted_source_all] == 8 &&
    [llength $s2ib2_accepted_source] == 8 &&
    [llength $s2ib2_accepted_destination_all] == 8 &&
    [llength $s2ib2_accepted_destination] == 8)}]
set s2ib2_accepted_source_q [get_pins -quiet -of_objects \
    $s2ib2_accepted_source -filter {REF_PIN_NAME == Q}]
set s2ib2_accepted_destination_d [get_pins -quiet -of_objects \
    $s2ib2_accepted_destination -filter {REF_PIN_NAME == D}]
set s2ib2_accepted_source_c [get_pins -quiet -of_objects \
    $s2ib2_accepted_source -filter {REF_PIN_NAME == C}]
set s2ib2_accepted_destination_c [get_pins -quiet -of_objects \
    $s2ib2_accepted_destination -filter {REF_PIN_NAME == C}]
set s2ib2_accepted_pin_cardinality_assert [expr {1 / (
    [llength $s2ib2_accepted_source_q] == 8 &&
    [llength $s2ib2_accepted_destination_d] == 8 &&
    [llength $s2ib2_accepted_source_c] == 8 &&
    [llength $s2ib2_accepted_destination_c] == 8)}]
set s2ib2_accepted_source_clock [get_clocks -quiet -of_objects \
    $s2ib2_accepted_source_c]
set s2ib2_accepted_destination_clock [get_clocks -quiet -of_objects \
    $s2ib2_accepted_destination_c]
set s2ib2_accepted_clock_cardinality_assert [expr {1 / (
    [llength $s2ib2_accepted_source_clock] == 1 &&
    [llength $s2ib2_accepted_destination_clock] == 1)}]
set s2ib2_accepted_source_period [get_property PERIOD \
    $s2ib2_accepted_source_clock]
set s2ib2_accepted_destination_period [get_property PERIOD \
    $s2ib2_accepted_destination_clock]
set s2ib2_accepted_limit [expr {min(double($s2ib2_accepted_source_period),
    double($s2ib2_accepted_destination_period))}]
set s2ib2_accepted_period_assert [expr {1 / ($s2ib2_accepted_limit > 0.0)}]
set_max_delay -datapath_only $s2ib2_accepted_limit \
    -from $s2ib2_accepted_source -to $s2ib2_accepted_destination
set_bus_skew $s2ib2_accepted_limit \
    -from $s2ib2_accepted_source -to $s2ib2_accepted_destination

set s2ib2_remaining_source_all [get_cells -quiet -hierarchical -regexp \
    {(^|.*/)stage2i_b2_ready_aware_stimulus_0/(inst/)?remaining_gray_src_reg\[[0-9]+\]$}]
set s2ib2_remaining_source [get_cells -quiet -hierarchical -regexp \
    {(^|.*/)stage2i_b2_ready_aware_stimulus_0/(inst/)?remaining_gray_src_reg\[[0-6]\]$}]
set s2ib2_remaining_destination_all [get_cells -quiet -hierarchical -regexp \
    {(^|.*/)stage2i_b2_ready_aware_stimulus_0/(inst/)?remaining_gray_sync1_aclk_reg\[[0-9]+\]$}]
set s2ib2_remaining_destination [get_cells -quiet -hierarchical -regexp \
    {(^|.*/)stage2i_b2_ready_aware_stimulus_0/(inst/)?remaining_gray_sync1_aclk_reg\[[0-6]\]$}]
set s2ib2_remaining_cell_cardinality_assert [expr {1 / (
    [llength $s2ib2_remaining_source_all] == 7 &&
    [llength $s2ib2_remaining_source] == 7 &&
    [llength $s2ib2_remaining_destination_all] == 7 &&
    [llength $s2ib2_remaining_destination] == 7)}]
set s2ib2_remaining_source_q [get_pins -quiet -of_objects \
    $s2ib2_remaining_source -filter {REF_PIN_NAME == Q}]
set s2ib2_remaining_destination_d [get_pins -quiet -of_objects \
    $s2ib2_remaining_destination -filter {REF_PIN_NAME == D}]
set s2ib2_remaining_source_c [get_pins -quiet -of_objects \
    $s2ib2_remaining_source -filter {REF_PIN_NAME == C}]
set s2ib2_remaining_destination_c [get_pins -quiet -of_objects \
    $s2ib2_remaining_destination -filter {REF_PIN_NAME == C}]
set s2ib2_remaining_pin_cardinality_assert [expr {1 / (
    [llength $s2ib2_remaining_source_q] == 7 &&
    [llength $s2ib2_remaining_destination_d] == 7 &&
    [llength $s2ib2_remaining_source_c] == 7 &&
    [llength $s2ib2_remaining_destination_c] == 7)}]
set s2ib2_remaining_source_clock [get_clocks -quiet -of_objects \
    $s2ib2_remaining_source_c]
set s2ib2_remaining_destination_clock [get_clocks -quiet -of_objects \
    $s2ib2_remaining_destination_c]
set s2ib2_remaining_clock_cardinality_assert [expr {1 / (
    [llength $s2ib2_remaining_source_clock] == 1 &&
    [llength $s2ib2_remaining_destination_clock] == 1)}]
set s2ib2_remaining_source_period [get_property PERIOD \
    $s2ib2_remaining_source_clock]
set s2ib2_remaining_destination_period [get_property PERIOD \
    $s2ib2_remaining_destination_clock]
set s2ib2_remaining_limit [expr {min(double($s2ib2_remaining_source_period),
    double($s2ib2_remaining_destination_period))}]
set s2ib2_remaining_period_assert [expr {1 / ($s2ib2_remaining_limit > 0.0)}]
set_max_delay -datapath_only $s2ib2_remaining_limit \
    -from $s2ib2_remaining_source -to $s2ib2_remaining_destination
set_bus_skew $s2ib2_remaining_limit \
    -from $s2ib2_remaining_source -to $s2ib2_remaining_destination

set s2ib2_reset_release_cells_all [get_cells -quiet -hierarchical -regexp \
    {(^|.*/)u_adc_source_reset_release_sync/release_pipe_reg\[[0-9]+\]$}]
set s2ib2_reset_release_cells [get_cells -quiet -hierarchical -regexp \
    {(^|.*/)u_adc_source_reset_release_sync/release_pipe_reg\[[0-1]\]$}]
set s2ib2_reset_release_cell_cardinality_assert [expr {1 / (
    [llength $s2ib2_reset_release_cells_all] == 2 &&
    [llength $s2ib2_reset_release_cells] == 2)}]
set s2ib2_reset_release_clr_pins [get_pins -quiet -of_objects \
    $s2ib2_reset_release_cells -filter {REF_PIN_NAME == CLR}]
set s2ib2_reset_release_pin_cardinality_assert [expr {1 / (
    [llength $s2ib2_reset_release_clr_pins] == 2)}]
set_false_path -to $s2ib2_reset_release_clr_pins

set ::stage2i_b2_ready_aware_stimulus_cdc_constraint_result {
    {crossing COMMAND_REQUEST width 1}
    {crossing COMMAND_BUNDLED_DATA width 31}
    {crossing COMMAND_ACKNOWLEDGMENT width 1}
    {crossing PRODUCER_ACTIVE_STATUS width 1}
    {crossing ACCEPTED_COUNT_STATUS width 8}
    {crossing REMAINING_COUNT_STATUS width 7}
    {reset ADC_SOURCE_ASYNC_ASSERT_SYNC_RELEASE width 2 exception FALSE_PATH_TO_CLR}
}
