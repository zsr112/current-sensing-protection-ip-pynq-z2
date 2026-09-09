`timescale 1ns/1ps

module stage2e_mutation_source_wrapper #(
    parameter integer MUTATION_ID = 0
)(
    input wire clk,
    input wire rst_n,
    input wire source_valid,
    input wire source_ready,
    input wire [11:0] source_ch1,
    input wire [11:0] source_ch2,
    output wire [31:0] raw_backpressure_count,
    output wire [31:0] observed_protocol_count,
    output wire [31:0] observed_drop_count,
    output wire [31:0] observed_transaction_sequence
);
    wire [31:0] raw_transaction_sequence;
    wire [31:0] raw_last_source_sequence;
    wire [31:0] raw_protocol_count;
    wire [31:0] raw_drop_count;

    transaction_source_observer u_observer (
        .clk(clk),
        .rst_n(rst_n),
        .source_valid(source_valid),
        .source_ready(source_ready),
        .source_ch1(source_ch1),
        .source_ch2(source_ch2),
        .fifo_overflow_attempt(1'b0),
        .transaction_sequence(raw_transaction_sequence),
        .last_source_sequence(raw_last_source_sequence),
        .backpressure_cycle_count(raw_backpressure_count),
        .source_protocol_violation_count(raw_protocol_count),
        .source_drop_count(raw_drop_count)
    );

    assign observed_protocol_count =
        ((MUTATION_ID == 2) || (MUTATION_ID == 3)) ? 32'd0 :
        ((MUTATION_ID == 4) && (raw_protocol_count != 0)) ?
            raw_protocol_count + 1 : raw_protocol_count;
    assign observed_drop_count = raw_drop_count +
        ((MUTATION_ID == 1) ? raw_backpressure_count : 32'd0);
    assign observed_transaction_sequence = (MUTATION_ID == 7) ?
        raw_last_source_sequence : raw_transaction_sequence;
endmodule

module stage2e_mutation_destination_wrapper #(
    parameter integer MUTATION_ID = 0
)(
    input wire clk,
    input wire rst_n,
    input wire delivery_valid,
    input wire [31:0] delivery_sequence,
    input wire [23:0] delivery_payload,
    input wire fifo_underflow_attempt,
    input wire [31:0] backpressure_count,
    input wire [9:0] status_w1c_clear,
    output wire [31:0] observed_delivery_count,
    output wire [31:0] observed_duplicate_count,
    output wire [31:0] observed_gap_count,
    output wire [31:0] observed_reorder_count,
    output wire [9:0] observed_status,
    output wire payload_equal_to_last,
    output wire sequence_equal_to_last,
    output wire wrap_transition
);
    wire observer_delivery_valid;
    wire observer_underflow_attempt;
    wire [31:0] raw_delivery_count;
    wire [31:0] raw_duplicate_count;
    wire [31:0] raw_gap_count;
    wire [31:0] raw_reorder_count;
    wire [9:0] raw_status;
    reg [23:0] last_payload;
    reg [31:0] last_sequence;
    reg has_last;

    assign observer_delivery_valid = delivery_valid && (MUTATION_ID != 8);
    assign observer_underflow_attempt = fifo_underflow_attempt &&
        !((MUTATION_ID == 14) && (|status_w1c_clear));

    assign payload_equal_to_last = delivery_valid && has_last &&
        (delivery_payload == last_payload);
    assign sequence_equal_to_last = delivery_valid && has_last &&
        (delivery_sequence == last_sequence);
    assign wrap_transition = delivery_valid && has_last &&
        (last_sequence == 32'hFFFF_FFFF) && (delivery_sequence == 0);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            last_payload <= 0;
            last_sequence <= 0;
            has_last <= 0;
        end else if (delivery_valid) begin
            last_payload <= delivery_payload;
            last_sequence <= delivery_sequence;
            has_last <= 1;
        end
    end

    transaction_destination_observer u_observer (
        .clk(clk),
        .rst_n(rst_n),
        .delivery_valid(observer_delivery_valid),
        .delivery_sequence(delivery_sequence),
        .fifo_underflow_attempt(observer_underflow_attempt),
        .source_accept_count_in(32'd0),
        .backpressure_cycle_count_in(backpressure_count),
        .source_protocol_violation_count_in(32'd0),
        .source_drop_count_in(32'd0),
        .fifo_overflow_attempt_count_in(32'd0),
        .source_counter_saturation_count_in(32'd0),
        .last_source_sequence_in(32'd0),
        .status_w1c_clear(status_w1c_clear),
        .destination_delivery_count(raw_delivery_count),
        .duplicate_delivery_count(raw_duplicate_count),
        .sequence_gap_count(raw_gap_count),
        .reorder_or_stale_count(raw_reorder_count),
        .sticky_status(raw_status)
    );

    assign observed_delivery_count = (MUTATION_ID == 17) ?
        (raw_delivery_count | 32'd1) : raw_delivery_count;
    assign observed_duplicate_count = raw_duplicate_count +
        (((MUTATION_ID == 5) && payload_equal_to_last &&
          !sequence_equal_to_last) ? 32'd1 : 32'd0);
    assign observed_gap_count = (MUTATION_ID == 9) ? 32'd0 : raw_gap_count;
    assign observed_reorder_count =
        ((MUTATION_ID == 10) ? 32'd0 : raw_reorder_count) +
        (((MUTATION_ID == 18) && wrap_transition) ? 32'd1 : 32'd0);
    assign observed_status = raw_status |
        (((MUTATION_ID == 15) && raw_status[0]) ? 10'h200 : 10'd0);
endmodule

module stage2e_mutation_atomic_word #(
    parameter integer MUTATION_ID = 0
)(
    input wire clk,
    input wire rst_n,
    input wire accept,
    input wire [31:0] accept_sequence,
    input wire [23:0] accept_payload,
    input wire destination_delivery,
    output reg delivery_valid,
    output reg [31:0] delivery_sequence,
    output reg [23:0] delivery_payload
);
    reg [31:0] stored_sequence;
    reg [23:0] stored_payload;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            stored_sequence <= 0;
            stored_payload <= 0;
            delivery_valid <= 0;
            delivery_sequence <= 0;
            delivery_payload <= 0;
        end else begin
            delivery_valid <= 0;
            if (accept) begin
                stored_sequence <= accept_sequence;
                stored_payload <= accept_payload;
            end
            if (destination_delivery) begin
                delivery_valid <= 1;
                delivery_sequence <= (MUTATION_ID == 6) ?
                    stored_sequence + 1 : stored_sequence;
                delivery_payload <= stored_payload;
            end
        end
    end
endmodule

module stage2e_mutation_counter_cdc #(
    parameter integer MUTATION_ID = 0
)(
    input wire clk,
    input wire rst_n,
    input wire [3:0] source_count,
    output wire [3:0] observed_count,
    output wire registered_gray_source,
    output wire two_stage_gray_destination,
    output wire binary_bus_synchronized_per_bit
);
    reg [3:0] source_gray_registered;
    reg [3:0] gray_sync1;
    reg [3:0] gray_sync2;
    reg [3:0] previous_source_count;
    reg [3:0] binary_sync1;
    reg [3:0] binary_sync2;

    function [3:0] gray_to_binary(input [3:0] value);
        integer index;
        begin
            gray_to_binary[3] = value[3];
            for (index = 2; index >= 0; index = index - 1)
                gray_to_binary[index] = gray_to_binary[index+1] ^ value[index];
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            source_gray_registered <= 0;
            gray_sync1 <= 0;
            gray_sync2 <= 0;
            previous_source_count <= 0;
            binary_sync1 <= 0;
            binary_sync2 <= 0;
        end else begin
            source_gray_registered <= (source_count >> 1) ^ source_count;
            gray_sync1 <= source_gray_registered;
            gray_sync2 <= gray_sync1;
            previous_source_count <= source_count;
            binary_sync1 <= {source_count[3], previous_source_count[2:0]};
            binary_sync2 <= binary_sync1;
        end
    end

    assign observed_count = (MUTATION_ID == 11) ?
        binary_sync2 : gray_to_binary(gray_sync2);
    assign registered_gray_source = (MUTATION_ID != 11);
    assign two_stage_gray_destination = 1'b1;
    assign binary_bus_synchronized_per_bit = (MUTATION_ID == 11);
endmodule

module stage2e_mutation_event_cdc #(
    parameter integer MUTATION_ID = 0
)(
    input wire src_clk,
    input wire dst_clk,
    input wire rst_n,
    input wire source_event,
    output reg destination_event_seen,
    output wire event_is_monotonic_count_or_toggle,
    output wire short_pulse_directly_synchronized
);
    reg source_toggle;
    reg toggle_sync1;
    reg toggle_sync2;
    reg toggle_previous;
    reg pulse_sync1;
    reg pulse_sync2;

    always @(posedge src_clk or negedge rst_n) begin
        if (!rst_n)
            source_toggle <= 0;
        else if (source_event)
            source_toggle <= ~source_toggle;
    end

    always @(posedge dst_clk or negedge rst_n) begin
        if (!rst_n) begin
            toggle_sync1 <= 0;
            toggle_sync2 <= 0;
            toggle_previous <= 0;
            pulse_sync1 <= 0;
            pulse_sync2 <= 0;
            destination_event_seen <= 0;
        end else begin
            toggle_sync1 <= source_toggle;
            toggle_sync2 <= toggle_sync1;
            toggle_previous <= toggle_sync2;
            pulse_sync1 <= source_event;
            pulse_sync2 <= pulse_sync1;
            if (MUTATION_ID == 12) begin
                if (pulse_sync2)
                    destination_event_seen <= 1;
            end else if (toggle_sync2 != toggle_previous) begin
                destination_event_seen <= 1;
            end
        end
    end

    assign event_is_monotonic_count_or_toggle = (MUTATION_ID != 12);
    assign short_pulse_directly_synchronized = (MUTATION_ID == 12);
endmodule

module stage2e_mutation_saturating_counter #(
    parameter integer MUTATION_ID = 0
)(
    input wire clk,
    input wire rst_n,
    input wire load,
    input wire increment,
    input wire [31:0] load_value,
    output reg [31:0] count,
    output reg saturation_sticky
);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            count <= 0;
            saturation_sticky <= 0;
        end else if (load) begin
            count <= load_value;
            saturation_sticky <= 0;
        end else if (increment) begin
            if (MUTATION_ID == 13) begin
                count <= count + 1;
            end else if (count != 32'hFFFF_FFFF) begin
                count <= count + 1;
                if (count == 32'hFFFF_FFFE)
                    saturation_sticky <= 1;
            end else begin
                count <= count;
                saturation_sticky <= 1;
            end
        end
    end
endmodule

module stage2e_mutation_register_wrapper #(
    parameter integer MUTATION_ID = 0
)(
    input wire clk,
    input wire rst_n,
    input wire wr_en,
    input wire [7:0] addr,
    input wire [31:0] wr_data,
    output wire [31:0] observed_read_data
);
    wire [31:0] raw_read_data;
    reg shadow_valid;
    reg [31:0] shadow_value;

    protection_reg_bank u_reg_bank (
        .clk(clk),
        .rst_n(rst_n),
        .wr_en(wr_en),
        .rd_en(1'b1),
        .addr(addr),
        .wr_data(wr_data),
        .wr_strb(4'hF),
        .rd_data(raw_read_data),
        .fault_valid(1'b0),
        .fault_latched(1'b0),
        .fault_code_latched(8'd0),
        .i_ch1_mon(12'd0),
        .i_ch2_mon(12'd0),
        .obs_sticky_status(10'd0),
        .obs_source_accept_count(32'd9),
        .obs_destination_delivery_count(32'd0),
        .obs_backpressure_cycle_count(32'd0),
        .obs_source_protocol_violation_count(32'd0),
        .obs_source_drop_count(32'd0),
        .obs_fifo_overflow_attempt_count(32'd0),
        .obs_fifo_underflow_attempt_count(32'd0),
        .obs_duplicate_delivery_count(32'd0),
        .obs_sequence_gap_count(32'd0),
        .obs_reorder_or_stale_count(32'd0),
        .obs_aggregate_error_count(32'd0),
        .obs_last_source_sequence(32'd0),
        .obs_last_destination_sequence(32'd0)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            shadow_valid <= 0;
            shadow_value <= 0;
        end else if ((MUTATION_ID == 16) && wr_en && (addr == 8'h30)) begin
            shadow_valid <= 1;
            shadow_value <= wr_data;
        end
    end

    assign observed_read_data = ((MUTATION_ID == 16) && shadow_valid &&
        (addr == 8'h30)) ? shadow_value : raw_read_data;
endmodule

module stage2e_mutation_connected_fixture #(
    parameter integer MUTATION_ID = 0
);
    reg clk = 0;
    reg src_clk = 0;
    always #5 clk = ~clk;
    always #3 src_clk = ~src_clk;

    stage2e_transaction_observability_checker u_checker();

    reg source_rst_n = 0;
    reg source_valid = 0;
    reg source_ready = 0;
    reg [11:0] source_ch1 = 0;
    reg [11:0] source_ch2 = 0;
    wire [31:0] raw_backpressure_count;
    wire [31:0] observed_protocol_count;
    wire [31:0] observed_drop_count;
    wire [31:0] observed_transaction_sequence;

    stage2e_mutation_source_wrapper #(.MUTATION_ID(MUTATION_ID))
        u_source (
            .clk(clk), .rst_n(source_rst_n),
            .source_valid(source_valid), .source_ready(source_ready),
            .source_ch1(source_ch1), .source_ch2(source_ch2),
            .raw_backpressure_count(raw_backpressure_count),
            .observed_protocol_count(observed_protocol_count),
            .observed_drop_count(observed_drop_count),
            .observed_transaction_sequence(observed_transaction_sequence)
        );

    reg destination_rst_n = 0;
    reg delivery_valid = 0;
    reg [31:0] delivery_sequence = 0;
    reg [23:0] delivery_payload = 0;
    reg fifo_underflow_attempt = 0;
    reg [31:0] destination_backpressure_count = 0;
    reg [9:0] status_w1c_clear = 0;
    wire [31:0] observed_delivery_count;
    wire [31:0] observed_duplicate_count;
    wire [31:0] observed_gap_count;
    wire [31:0] observed_reorder_count;
    wire [9:0] observed_status;
    wire payload_equal_to_last;
    wire sequence_equal_to_last;
    wire wrap_transition;

    stage2e_mutation_destination_wrapper #(.MUTATION_ID(MUTATION_ID))
        u_destination (
            .clk(clk), .rst_n(destination_rst_n),
            .delivery_valid(delivery_valid),
            .delivery_sequence(delivery_sequence),
            .delivery_payload(delivery_payload),
            .fifo_underflow_attempt(fifo_underflow_attempt),
            .backpressure_count(destination_backpressure_count),
            .status_w1c_clear(status_w1c_clear),
            .observed_delivery_count(observed_delivery_count),
            .observed_duplicate_count(observed_duplicate_count),
            .observed_gap_count(observed_gap_count),
            .observed_reorder_count(observed_reorder_count),
            .observed_status(observed_status),
            .payload_equal_to_last(payload_equal_to_last),
            .sequence_equal_to_last(sequence_equal_to_last),
            .wrap_transition(wrap_transition)
        );

    reg atomic_rst_n = 0;
    reg atomic_accept = 0;
    reg [31:0] atomic_accept_sequence = 0;
    reg [23:0] atomic_accept_payload = 0;
    reg atomic_destination_delivery = 0;
    wire atomic_delivery_valid;
    wire [31:0] atomic_delivery_sequence;
    wire [23:0] atomic_delivery_payload;

    stage2e_mutation_atomic_word #(.MUTATION_ID(MUTATION_ID)) u_atomic (
        .clk(clk), .rst_n(atomic_rst_n), .accept(atomic_accept),
        .accept_sequence(atomic_accept_sequence),
        .accept_payload(atomic_accept_payload),
        .destination_delivery(atomic_destination_delivery),
        .delivery_valid(atomic_delivery_valid),
        .delivery_sequence(atomic_delivery_sequence),
        .delivery_payload(atomic_delivery_payload)
    );

    reg cdc_rst_n = 0;
    reg [3:0] cdc_source_count = 0;
    wire [3:0] cdc_observed_count;
    wire cdc_registered_gray_source;
    wire cdc_two_stage_gray_destination;
    wire cdc_binary_bus_synchronized_per_bit;

    stage2e_mutation_counter_cdc #(.MUTATION_ID(MUTATION_ID)) u_counter_cdc (
        .clk(clk), .rst_n(cdc_rst_n), .source_count(cdc_source_count),
        .observed_count(cdc_observed_count),
        .registered_gray_source(cdc_registered_gray_source),
        .two_stage_gray_destination(cdc_two_stage_gray_destination),
        .binary_bus_synchronized_per_bit(
            cdc_binary_bus_synchronized_per_bit)
    );

    reg event_rst_n = 0;
    reg source_event = 0;
    wire destination_event_seen;
    wire event_is_monotonic_count_or_toggle;
    wire short_pulse_directly_synchronized;

    stage2e_mutation_event_cdc #(.MUTATION_ID(MUTATION_ID)) u_event_cdc (
        .src_clk(src_clk), .dst_clk(clk), .rst_n(event_rst_n),
        .source_event(source_event),
        .destination_event_seen(destination_event_seen),
        .event_is_monotonic_count_or_toggle(
            event_is_monotonic_count_or_toggle),
        .short_pulse_directly_synchronized(
            short_pulse_directly_synchronized)
    );

    reg saturation_rst_n = 0;
    reg saturation_load = 0;
    reg saturation_increment = 0;
    reg [31:0] saturation_load_value = 0;
    wire [31:0] saturation_count;
    wire saturation_sticky;

    stage2e_mutation_saturating_counter #(.MUTATION_ID(MUTATION_ID))
        u_saturation (
            .clk(clk), .rst_n(saturation_rst_n), .load(saturation_load),
            .increment(saturation_increment),
            .load_value(saturation_load_value), .count(saturation_count),
            .saturation_sticky(saturation_sticky)
        );

    reg register_rst_n = 0;
    reg register_wr_en = 0;
    reg [7:0] register_addr = 8'h30;
    reg [31:0] register_wr_data = 0;
    wire [31:0] register_read_data;

    stage2e_mutation_register_wrapper #(.MUTATION_ID(MUTATION_ID))
        u_register (
            .clk(clk), .rst_n(register_rst_n), .wr_en(register_wr_en),
            .addr(register_addr), .wr_data(register_wr_data),
            .observed_read_data(register_read_data)
        );

    task automatic clock_step;
        begin
            @(posedge clk);
            #1;
        end
    endtask

    task automatic reset_source;
        begin
            source_rst_n = 0;
            source_valid = 0;
            source_ready = 0;
            source_ch1 = 0;
            source_ch2 = 0;
            repeat (2) clock_step();
            @(negedge clk);
            source_rst_n = 1;
            clock_step();
        end
    endtask

    task automatic reset_destination;
        begin
            destination_rst_n = 0;
            delivery_valid = 0;
            delivery_sequence = 0;
            delivery_payload = 0;
            fifo_underflow_attempt = 0;
            destination_backpressure_count = 0;
            status_w1c_clear = 0;
            repeat (2) clock_step();
            @(negedge clk);
            destination_rst_n = 1;
            clock_step();
        end
    endtask

    task automatic deliver(input [31:0] identity, input [23:0] payload);
        begin
            @(negedge clk);
            delivery_sequence = identity;
            delivery_payload = payload;
            delivery_valid = 1;
            clock_step();
            @(negedge clk);
            delivery_valid = 0;
        end
    endtask

    task automatic test_backpressure_drop;
        begin
            reset_source();
            @(negedge clk);
            source_valid = 1;
            source_ready = 0;
            source_ch1 = 12'h111;
            source_ch2 = 12'hEEE;
            clock_step();
            u_checker.observe_backpressure(
                source_valid, source_ready, observed_drop_count != 0);
        end
    endtask

    task automatic test_withdrawal;
        begin
            reset_source();
            @(negedge clk);
            source_valid = 1;
            source_ready = 0;
            source_ch1 = 12'h211;
            source_ch2 = 12'hDEE;
            clock_step();
            @(negedge clk);
            source_valid = 0;
            clock_step();
            u_checker.observe_withdrawal(
                raw_backpressure_count != 0, !source_valid,
                observed_protocol_count != 0);
        end
    endtask

    task automatic test_payload_change;
        begin
            reset_source();
            @(negedge clk);
            source_valid = 1;
            source_ready = 0;
            source_ch1 = 12'h311;
            source_ch2 = 12'hCEE;
            clock_step();
            @(negedge clk);
            source_ch1 = 12'h322;
            clock_step();
            u_checker.observe_payload_change(
                raw_backpressure_count != 0, source_ch1 == 12'h322,
                observed_protocol_count != 0);
        end
    endtask

    task automatic test_episode_recount;
        begin
            reset_source();
            @(negedge clk);
            source_valid = 1;
            source_ready = 0;
            source_ch1 = 12'h411;
            source_ch2 = 12'hBEE;
            clock_step();
            @(negedge clk);
            source_ch1 = 12'h422;
            clock_step();
            @(negedge clk);
            source_ch1 = 12'h433;
            clock_step();
            u_checker.observe_episode_count(observed_protocol_count);
        end
    endtask

    task automatic test_payload_identity;
        reg [31:0] duplicate_before;
        begin
            reset_destination();
            deliver(0, 24'h55_AA_55);
            duplicate_before = observed_duplicate_count;
            @(negedge clk);
            delivery_sequence = 1;
            delivery_payload = 24'h55_AA_55;
            delivery_valid = 1;
            #1;
            u_checker.observe_duplicate_identity(
                payload_equal_to_last, sequence_equal_to_last,
                observed_duplicate_count != duplicate_before);
            clock_step();
        end
    endtask

    task automatic test_atomic_word;
        begin
            atomic_rst_n = 0;
            atomic_accept = 0;
            atomic_destination_delivery = 0;
            repeat (2) clock_step();
            @(negedge clk);
            atomic_rst_n = 1;
            atomic_accept_sequence = 32'h1234_5678;
            atomic_accept_payload = 24'hABC_DEF;
            atomic_accept = 1;
            clock_step();
            @(negedge clk);
            atomic_accept = 0;
            atomic_destination_delivery = 1;
            clock_step();
            u_checker.observe_atomic_fifo_word(
                atomic_delivery_valid &&
                (atomic_delivery_sequence == atomic_accept_sequence) &&
                (atomic_delivery_payload == atomic_accept_payload));
        end
    endtask

    task automatic test_accept_sequence;
        reg [31:0] previous_sequence;
        reg [31:0] next_sequence;
        begin
            reset_source();
            previous_sequence = observed_transaction_sequence;
            @(negedge clk);
            source_valid = 1;
            source_ready = 1;
            source_ch1 = 12'h711;
            source_ch2 = 12'h8EE;
            clock_step();
            next_sequence = observed_transaction_sequence;
            u_checker.observe_accept_sequence(
                source_valid && source_ready,
                previous_sequence, next_sequence);
        end
    endtask

    task automatic test_delivery_accounting;
        begin
            reset_destination();
            deliver(0, 24'h800_001);
            u_checker.observe_delivery_accounting(
                1, observed_delivery_count);
        end
    endtask

    task automatic test_gap;
        begin
            reset_destination();
            deliver(0, 24'h900_000);
            deliver(3, 24'h900_003);
            u_checker.observe_gap(1, observed_gap_count != 0);
        end
    endtask

    task automatic test_sequence_relative_stale;
        begin
            reset_destination();
            deliver(7, 24'hA00_007);
            u_checker.observe_sequence_relative_stale_or_reorder(
                1, observed_reorder_count != 0);
        end
    endtask

    task automatic test_binary_cdc;
        begin
            cdc_rst_n = 0;
            cdc_source_count = 4'd7;
            repeat (2) clock_step();
            @(negedge clk);
            cdc_rst_n = 1;
            repeat (5) clock_step();
            @(negedge clk);
            cdc_source_count = 4'd8;
            repeat (2) clock_step();
            u_checker.observe_counter_cdc(
                cdc_registered_gray_source,
                cdc_two_stage_gray_destination,
                cdc_binary_bus_synchronized_per_bit,
                (cdc_observed_count == 4'd7) ||
                    (cdc_observed_count == 4'd8));
        end
    endtask

    task automatic test_pulse_cdc;
        begin
            event_rst_n = 0;
            source_event = 0;
            repeat (3) clock_step();
            event_rst_n = 1;
            @(negedge src_clk);
            source_event = 1;
            @(posedge src_clk);
            #1;
            source_event = 0;
            repeat (6) clock_step();
            u_checker.observe_event_cdc(
                event_is_monotonic_count_or_toggle,
                short_pulse_directly_synchronized,
                1'b1, destination_event_seen);
        end
    endtask

    task automatic test_counter_wrap;
        reg [31:0] saturated_value;
        begin
            saturation_rst_n = 0;
            saturation_load = 0;
            saturation_increment = 0;
            repeat (2) clock_step();
            @(negedge clk);
            saturation_rst_n = 1;
            saturation_load_value = 32'hFFFF_FFFE;
            saturation_load = 1;
            clock_step();
            @(negedge clk);
            saturation_load = 0;
            saturation_increment = 1;
            clock_step();
            saturated_value = saturation_count;
            clock_step();
            u_checker.observe_saturation(
                saturated_value, saturation_count, saturation_sticky);
        end
    endtask

    task automatic test_w1c_race;
        begin
            reset_destination();
            @(negedge clk);
            status_w1c_clear = 10'h010;
            fifo_underflow_attempt = 1;
            clock_step();
            u_checker.observe_w1c_race(
                |status_w1c_clear, fifo_underflow_attempt,
                observed_status[4]);
        end
    endtask

    task automatic test_any_error_backpressure;
        begin
            reset_destination();
            @(negedge clk);
            destination_backpressure_count = 1;
            clock_step();
            u_checker.observe_any_error_backpressure(
                observed_status[0], observed_status[9]);
        end
    endtask

    task automatic test_read_only_counter;
        reg [31:0] value_before;
        begin
            register_rst_n = 0;
            register_wr_en = 0;
            register_addr = 8'h30;
            repeat (2) clock_step();
            @(negedge clk);
            register_rst_n = 1;
            clock_step();
            value_before = register_read_data;
            @(negedge clk);
            register_wr_data = 32'd99;
            register_wr_en = 1;
            clock_step();
            register_wr_en = 0;
            u_checker.observe_read_only_write(
                value_before, register_read_data);
        end
    endtask

    task automatic test_reset_state;
        begin
            reset_destination();
            u_checker.observe_reset_state(
                observed_delivery_count, observed_status,
                u_destination.u_observer.u_sequence_integrity_tracker.
                    has_last_delivery);
        end
    endtask

    task automatic test_sequence_wrap;
        begin
            reset_destination();
            @(negedge clk);
            u_destination.u_observer.u_sequence_integrity_tracker.
                expected_sequence = 32'hFFFF_FFFF;
            u_destination.u_observer.u_sequence_integrity_tracker.
                has_last_delivery = 1;
            u_destination.u_observer.u_sequence_integrity_tracker.
                last_destination_sequence = 32'hFFFF_FFFE;
            deliver(32'hFFFF_FFFF, 24'hFFF_FFF);
            @(negedge clk);
            delivery_sequence = 0;
            delivery_payload = 24'h000_000;
            delivery_valid = 1;
            #1;
            u_checker.observe_sequence_wrap(
                wrap_transition, observed_reorder_count != 0);
            clock_step();
        end
    endtask

    task automatic print_mutation_contract;
        begin
            case (MUTATION_ID)
                0: begin
                    $display("MUTATION_ID=CONTROL");
                    $display("MUTATION_CHANGED_BEHAVIOR=NONE");
                    $display("MUTATION_EXPECTED_REJECTION=NONE");
                end
                1: begin
                    $display("MUTATION_ID=01_BACKPRESSURE_COUNTED_AS_DROP");
                    $display("MUTATION_CHANGED_BEHAVIOR=DROP_OUTPUT_ADDS_BACKPRESSURE_COUNT");
                    $display("MUTATION_EXPECTED_REJECTION=BACKPRESSURE_MISCLASSIFIED_AS_DROP");
                end
                2: begin
                    $display("MUTATION_ID=02_VALID_WITHDRAWAL_NOT_RECORDED");
                    $display("MUTATION_CHANGED_BEHAVIOR=PROTOCOL_COUNT_OUTPUT_MASKED_ON_WITHDRAWAL");
                    $display("MUTATION_EXPECTED_REJECTION=VALID_WITHDRAWAL_NOT_RECORDED");
                end
                3: begin
                    $display("MUTATION_ID=03_PAYLOAD_CHANGE_NOT_RECORDED");
                    $display("MUTATION_CHANGED_BEHAVIOR=PROTOCOL_COUNT_OUTPUT_MASKED_ON_PAYLOAD_CHANGE");
                    $display("MUTATION_EXPECTED_REJECTION=STALLED_PAYLOAD_CHANGE_NOT_RECORDED");
                end
                4: begin
                    $display("MUTATION_ID=04_STALL_EPISODE_RECOUNTED");
                    $display("MUTATION_CHANGED_BEHAVIOR=PROTOCOL_MONITOR_ADDS_SECOND_COUNT_PER_EPISODE");
                    $display("MUTATION_EXPECTED_REJECTION=STALL_EPISODE_RECOUNTED");
                end
                5: begin
                    $display("MUTATION_ID=05_PAYLOAD_EQUALITY_USED_AS_DUPLICATE_IDENTITY");
                    $display("MUTATION_CHANGED_BEHAVIOR=DUPLICATE_MONITOR_ADDS_EQUAL_PAYLOAD_EVENT");
                    $display("MUTATION_EXPECTED_REJECTION=PAYLOAD_EQUALITY_USED_AS_IDENTITY");
                end
                6: begin
                    $display("MUTATION_ID=06_SEQUENCE_NOT_ATOMIC_WITH_PAYLOAD");
                    $display("MUTATION_CHANGED_BEHAVIOR=DESTINATION_DELIVERY_SEQUENCE_COMES_FROM_DIFFERENT_IDENTITY");
                    $display("MUTATION_EXPECTED_REJECTION=SEQUENCE_NOT_ATOMIC_WITH_PAYLOAD");
                end
                7: begin
                    $display("MUTATION_ID=07_SEQUENCE_NOT_INCREMENTED_ON_ACCEPTANCE");
                    $display("MUTATION_CHANGED_BEHAVIOR=SEQUENCE_OUTPUT_MISWIRED_TO_LAST_ACCEPTED_IDENTITY");
                    $display("MUTATION_EXPECTED_REJECTION=SEQUENCE_NOT_INCREMENTED_ON_ACCEPTANCE");
                end
                8: begin
                    $display("MUTATION_ID=08_DELIVERY_ACCOUNTING_MISMATCH");
                    $display("MUTATION_CHANGED_BEHAVIOR=DESTINATION_DELIVERY_PULSE_DISCONNECTED_FROM_DELIVERY_OBSERVER");
                    $display("MUTATION_EXPECTED_REJECTION=DESTINATION_DELIVERY_COUNT_MISMATCH");
                end
                9: begin
                    $display("MUTATION_ID=09_FORWARD_GAP_NOT_RECORDED");
                    $display("MUTATION_CHANGED_BEHAVIOR=GAP_COUNT_OBSERVATION_CONNECTION_TIED_ZERO");
                    $display("MUTATION_EXPECTED_REJECTION=FORWARD_GAP_NOT_RECORDED");
                end
                10: begin
                    $display("MUTATION_ID=10_SEQUENCE_RELATIVE_STALE_REORDER_NOT_RECORDED");
                    $display("MUTATION_CHANGED_BEHAVIOR=REORDER_COUNT_OBSERVATION_CONNECTION_TIED_ZERO");
                    $display("MUTATION_EXPECTED_REJECTION=SEQUENCE_RELATIVE_STALE_OR_REORDER_NOT_RECORDED");
                end
                11: begin
                    $display("MUTATION_ID=11_BINARY_COUNTER_BUS_SYNCHRONIZED_PER_BIT");
                    $display("MUTATION_CHANGED_BEHAVIOR=GRAY_CDC_REPLACED_BY_SKEWED_BINARY_BIT_SYNCHRONIZER");
                    $display("MUTATION_EXPECTED_REJECTION=BINARY_COUNTER_CDC_OR_UNREGISTERED_GRAY");
                end
                12: begin
                    $display("MUTATION_ID=12_SOURCE_SHORT_PULSE_DIRECTLY_SYNCHRONIZED");
                    $display("MUTATION_CHANGED_BEHAVIOR=MONOTONIC_EVENT_TOGGLE_REPLACED_BY_DIRECT_PULSE_SYNC");
                    $display("MUTATION_EXPECTED_REJECTION=SHORT_SOURCE_PULSE_DIRECTLY_SYNCHRONIZED");
                end
                13: begin
                    $display("MUTATION_ID=13_COUNTER_WRAPS");
                    $display("MUTATION_CHANGED_BEHAVIOR=SATURATING_INCREMENT_REPLACED_BY_MODULAR_INCREMENT");
                    $display("MUTATION_EXPECTED_REJECTION=DIAGNOSTIC_COUNTER_WRAPPED_OR_SATURATION_HIDDEN");
                end
                14: begin
                    $display("MUTATION_ID=14_W1C_LOSES_SAME_CYCLE_EVENT");
                    $display("MUTATION_CHANGED_BEHAVIOR=EVENT_CONNECTION_MASKED_WHEN_CLEAR_ASSERTED");
                    $display("MUTATION_EXPECTED_REJECTION=W1C_LOST_SAME_CYCLE_EVENT");
                end
                15: begin
                    $display("MUTATION_ID=15_ANY_ERROR_INCLUDES_LEGAL_BACKPRESSURE");
                    $display("MUTATION_CHANGED_BEHAVIOR=ANY_ERROR_OUTPUT_ORS_BACKPRESSURE_STICKY");
                    $display("MUTATION_EXPECTED_REJECTION=ANY_ERROR_INCLUDES_LEGAL_BACKPRESSURE");
                end
                16: begin
                    $display("MUTATION_ID=16_READ_ONLY_COUNTER_WRITABLE");
                    $display("MUTATION_CHANGED_BEHAVIOR=RO_COUNTER_READ_PATH_SELECTS_WRITE_SHADOW");
                    $display("MUTATION_EXPECTED_REJECTION=READ_ONLY_COUNTER_IS_WRITABLE");
                end
                17: begin
                    $display("MUTATION_ID=17_RESET_STATE_NONZERO");
                    $display("MUTATION_CHANGED_BEHAVIOR=DELIVERY_COUNT_RESET_OBSERVATION_FORCED_NONZERO");
                    $display("MUTATION_EXPECTED_REJECTION=OBSERVABILITY_RESET_STATE_NONZERO");
                end
                18: begin
                    $display("MUTATION_ID=18_LEGAL_SEQUENCE_WRAP_MISCLASSIFIED");
                    $display("MUTATION_CHANGED_BEHAVIOR=WRAP_TRANSITION_ADDED_TO_REORDER_COUNT");
                    $display("MUTATION_EXPECTED_REJECTION=LEGAL_SEQUENCE_WRAP_MISCLASSIFIED");
                end
                default: $fatal(1, "unknown mutation ID");
            endcase
        end
    endtask

    initial begin
        print_mutation_contract();
        case (MUTATION_ID)
            0: begin
                test_backpressure_drop();
                test_withdrawal();
                test_payload_change();
                test_episode_recount();
                test_payload_identity();
                test_atomic_word();
                test_accept_sequence();
                test_delivery_accounting();
                test_gap();
                test_sequence_relative_stale();
                test_binary_cdc();
                test_pulse_cdc();
                test_counter_wrap();
                test_w1c_race();
                test_any_error_backpressure();
                test_read_only_counter();
                test_reset_state();
                test_sequence_wrap();
                $display("MUTATION_CONNECTED_CONTROL=PASS_18_BEHAVIORS");
                $finish;
            end
            1: test_backpressure_drop();
            2: test_withdrawal();
            3: test_payload_change();
            4: test_episode_recount();
            5: test_payload_identity();
            6: test_atomic_word();
            7: test_accept_sequence();
            8: test_delivery_accounting();
            9: test_gap();
            10: test_sequence_relative_stale();
            11: test_binary_cdc();
            12: test_pulse_cdc();
            13: test_counter_wrap();
            14: test_w1c_race();
            15: test_any_error_backpressure();
            16: test_read_only_counter();
            17: test_reset_state();
            18: test_sequence_wrap();
            default: $fatal(1, "unknown mutation ID");
        endcase
        $display("MUTATION_OBSERVED_REJECTION=UNEXPECTED_PASS");
        $finish;
    end

    initial begin
        #500000;
        $fatal(1, "mutation fixture timeout");
    end
endmodule

module tb_stage2e_mutation_control;
    stage2e_mutation_connected_fixture #(.MUTATION_ID(0)) fixture();
endmodule
module tb_stage2e_mutation_backpressure_drop;
    stage2e_mutation_connected_fixture #(.MUTATION_ID(1)) fixture();
endmodule
module tb_stage2e_mutation_withdrawal;
    stage2e_mutation_connected_fixture #(.MUTATION_ID(2)) fixture();
endmodule
module tb_stage2e_mutation_payload_change;
    stage2e_mutation_connected_fixture #(.MUTATION_ID(3)) fixture();
endmodule
module tb_stage2e_mutation_episode_recount;
    stage2e_mutation_connected_fixture #(.MUTATION_ID(4)) fixture();
endmodule
module tb_stage2e_mutation_payload_identity;
    stage2e_mutation_connected_fixture #(.MUTATION_ID(5)) fixture();
endmodule
module tb_stage2e_mutation_nonatomic_sequence;
    stage2e_mutation_connected_fixture #(.MUTATION_ID(6)) fixture();
endmodule
module tb_stage2e_mutation_accept_sequence;
    stage2e_mutation_connected_fixture #(.MUTATION_ID(7)) fixture();
endmodule
module tb_stage2e_mutation_delivery_accounting;
    stage2e_mutation_connected_fixture #(.MUTATION_ID(8)) fixture();
endmodule
module tb_stage2e_mutation_gap;
    stage2e_mutation_connected_fixture #(.MUTATION_ID(9)) fixture();
endmodule
module tb_stage2e_mutation_stale_reorder;
    stage2e_mutation_connected_fixture #(.MUTATION_ID(10)) fixture();
endmodule
module tb_stage2e_mutation_binary_cdc;
    stage2e_mutation_connected_fixture #(.MUTATION_ID(11)) fixture();
endmodule
module tb_stage2e_mutation_pulse_cdc;
    stage2e_mutation_connected_fixture #(.MUTATION_ID(12)) fixture();
endmodule
module tb_stage2e_mutation_counter_wrap;
    stage2e_mutation_connected_fixture #(.MUTATION_ID(13)) fixture();
endmodule
module tb_stage2e_mutation_w1c_race;
    stage2e_mutation_connected_fixture #(.MUTATION_ID(14)) fixture();
endmodule
module tb_stage2e_mutation_any_error_backpressure;
    stage2e_mutation_connected_fixture #(.MUTATION_ID(15)) fixture();
endmodule
module tb_stage2e_mutation_writable_counter;
    stage2e_mutation_connected_fixture #(.MUTATION_ID(16)) fixture();
endmodule
module tb_stage2e_mutation_reset_nonzero;
    stage2e_mutation_connected_fixture #(.MUTATION_ID(17)) fixture();
endmodule
module tb_stage2e_mutation_wrap_misclassified;
    stage2e_mutation_connected_fixture #(.MUTATION_ID(18)) fixture();
endmodule
