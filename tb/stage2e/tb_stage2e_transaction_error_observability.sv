`timescale 1ns/1ps

module tb_stage2e_transaction_error_observability;
    localparam DATA_WIDTH = 12;
    localparam [7:0] REG_OBS_CAPABILITY = 8'h28;
    localparam [7:0] REG_OBS_STATUS = 8'h2C;
    localparam [7:0] REG_OBS_SOURCE_ACCEPT = 8'h30;
    localparam [7:0] REG_OBS_DESTINATION_DELIVERY = 8'h34;
    localparam [7:0] REG_OBS_BACKPRESSURE = 8'h38;
    localparam [7:0] REG_OBS_SOURCE_PROTOCOL = 8'h3C;
    localparam [7:0] REG_OBS_SOURCE_DROP = 8'h40;
    localparam [7:0] REG_OBS_FIFO_OVERFLOW = 8'h44;
    localparam [7:0] REG_OBS_FIFO_UNDERFLOW = 8'h48;
    localparam [7:0] REG_OBS_DUPLICATE = 8'h4C;
    localparam [7:0] REG_OBS_SEQUENCE_GAP = 8'h50;
    localparam [7:0] REG_OBS_REORDER_STALE = 8'h54;
    localparam [7:0] REG_OBS_AGGREGATE = 8'h58;
    localparam [7:0] REG_OBS_LAST_SOURCE_SEQUENCE = 8'h5C;
    localparam [7:0] REG_OBS_LAST_DESTINATION_SEQUENCE = 8'h60;

    localparam [9:0] STATUS_BACKPRESSURE = 10'h001;
    localparam [9:0] STATUS_SOURCE_PROTOCOL = 10'h002;
    localparam [9:0] STATUS_SOURCE_DROP = 10'h004;
    localparam [9:0] STATUS_FIFO_OVERFLOW = 10'h008;
    localparam [9:0] STATUS_FIFO_UNDERFLOW = 10'h010;
    localparam [9:0] STATUS_DUPLICATE = 10'h020;
    localparam [9:0] STATUS_SEQUENCE_GAP = 10'h040;
    localparam [9:0] STATUS_REORDER_STALE = 10'h080;
    localparam [9:0] STATUS_COUNTER_SATURATED = 10'h100;
    localparam [9:0] STATUS_ANY_ERROR = 10'h200;

    reg ACLK = 1'b0;
    reg adc_src_clk = 1'b0;
    realtime source_half_period = 7.0;
    always #5 ACLK = ~ACLK;
    always begin
        #(source_half_period) adc_src_clk = ~adc_src_clk;
    end

    reg ARESETN = 1'b0;
    reg adc_sample_valid = 1'b0;
    wire adc_sample_ready;
    reg [DATA_WIDTH-1:0] adc_sample_ch1 = 0;
    reg [DATA_WIDTH-1:0] adc_sample_ch2 = 0;

    reg [7:0] S_AXI_AWADDR = 0;
    reg S_AXI_AWVALID = 0;
    wire S_AXI_AWREADY;
    reg [31:0] S_AXI_WDATA = 0;
    reg [3:0] S_AXI_WSTRB = 0;
    reg S_AXI_WVALID = 0;
    wire S_AXI_WREADY;
    wire [1:0] S_AXI_BRESP;
    wire S_AXI_BVALID;
    reg S_AXI_BREADY = 0;
    reg [7:0] S_AXI_ARADDR = 0;
    reg S_AXI_ARVALID = 0;
    wire S_AXI_ARREADY;
    wire [31:0] S_AXI_RDATA;
    wire [1:0] S_AXI_RRESP;
    wire S_AXI_RVALID;
    reg S_AXI_RREADY = 0;
    wire pwm_raw;
    wire pwm_out;
    wire fault_valid;
    wire fault_latched;
    wire [7:0] fault_code;
    wire [7:0] fault_code_latched;
    wire [3:0] fsm_state;

    protection_ip_top_async_adc_axi_lite dut (
        .ACLK(ACLK), .ARESETN(ARESETN),
        .adc_src_clk(adc_src_clk),
        .adc_sample_valid(adc_sample_valid),
        .adc_sample_ready(adc_sample_ready),
        .adc_sample_ch1(adc_sample_ch1),
        .adc_sample_ch2(adc_sample_ch2),
        .S_AXI_AWADDR(S_AXI_AWADDR),
        .S_AXI_AWVALID(S_AXI_AWVALID),
        .S_AXI_AWREADY(S_AXI_AWREADY),
        .S_AXI_WDATA(S_AXI_WDATA),
        .S_AXI_WSTRB(S_AXI_WSTRB),
        .S_AXI_WVALID(S_AXI_WVALID),
        .S_AXI_WREADY(S_AXI_WREADY),
        .S_AXI_BRESP(S_AXI_BRESP),
        .S_AXI_BVALID(S_AXI_BVALID),
        .S_AXI_BREADY(S_AXI_BREADY),
        .S_AXI_ARADDR(S_AXI_ARADDR),
        .S_AXI_ARVALID(S_AXI_ARVALID),
        .S_AXI_ARREADY(S_AXI_ARREADY),
        .S_AXI_RDATA(S_AXI_RDATA),
        .S_AXI_RRESP(S_AXI_RRESP),
        .S_AXI_RVALID(S_AXI_RVALID),
        .S_AXI_RREADY(S_AXI_RREADY),
        .pwm_raw(pwm_raw), .pwm_out(pwm_out),
        .fault_valid(fault_valid), .fault_latched(fault_latched),
        .fault_code(fault_code),
        .fault_code_latched(fault_code_latched),
        .fsm_state(fsm_state)
    );

    // A second bridge proves that destination pause is backpressure, not a
    // duplicate delivery. It is not part of the production DUT scoreboard.
    reg pause_src_valid = 0;
    wire pause_src_ready;
    reg [11:0] pause_ch1 = 0;
    reg [11:0] pause_ch2 = 0;
    reg pause_dst_ready = 0;
    wire pause_dst_valid;
    wire [11:0] pause_dst_ch1;
    wire [11:0] pause_dst_ch2;
    integer pause_delivery_count = 0;

    adc_sample_cdc_bridge pause_bridge (
        .src_clk(adc_src_clk), .src_rst_n(dut.adc_src_local_rst_n),
        .src_sample_valid(pause_src_valid),
        .src_sample_ready(pause_src_ready),
        .src_sample_ch1(pause_ch1), .src_sample_ch2(pause_ch2),
        .dst_clk(ACLK), .dst_rst_n(dut.adc_dst_local_rst_n),
        .dst_ready(pause_dst_ready),
        .dst_sample_valid(pause_dst_valid),
        .dst_sample_ch1(pause_dst_ch1),
        .dst_sample_ch2(pause_dst_ch2)
    );

    always @(posedge ACLK) begin
        if (!dut.adc_dst_local_rst_n)
            pause_delivery_count <= 0;
        else if (pause_dst_valid)
            pause_delivery_count <= pause_delivery_count + 1;
    end

    // Small-width observers exercise saturation and modular wrap in a finite
    // simulation. Production remains fixed at 32-bit software counters.
    reg mini_src_rst_n = 0;
    reg mini_src_valid = 0;
    reg mini_src_ready = 1;
    reg [11:0] mini_src_ch1 = 0;
    reg [11:0] mini_src_ch2 = 0;
    reg mini_src_overflow = 0;
    wire [3:0] mini_backpressure_count;
    wire [3:0] mini_source_saturation_count;

    transaction_source_observer #(
        .DATA_WIDTH(12), .SEQUENCE_WIDTH(16), .COUNTER_WIDTH(4)
    ) mini_source_observer (
        .clk(adc_src_clk), .rst_n(mini_src_rst_n),
        .source_valid(mini_src_valid), .source_ready(mini_src_ready),
        .source_ch1(mini_src_ch1), .source_ch2(mini_src_ch2),
        .fifo_overflow_attempt(mini_src_overflow),
        .backpressure_cycle_count(mini_backpressure_count),
        .counter_saturation_event_count(mini_source_saturation_count)
    );

    reg mini_dst_rst_n = 0;
    reg mini_delivery_valid = 0;
    reg [15:0] mini_delivery_sequence = 0;
    reg mini_underflow = 0;
    reg [9:0] mini_w1c = 0;
    wire [3:0] mini_delivery_count;
    wire [3:0] mini_underflow_count;
    wire [3:0] mini_duplicate_count;
    wire [3:0] mini_gap_count;
    wire [3:0] mini_reorder_count;
    wire [3:0] mini_aggregate_count;
    wire [9:0] mini_status;

    transaction_destination_observer #(
        .SEQUENCE_WIDTH(16), .COUNTER_WIDTH(4)
    ) mini_destination_observer (
        .clk(ACLK), .rst_n(mini_dst_rst_n),
        .delivery_valid(mini_delivery_valid),
        .delivery_sequence(mini_delivery_sequence),
        .fifo_underflow_attempt(mini_underflow),
        .source_accept_count_in(4'd0),
        .backpressure_cycle_count_in(4'd0),
        .source_protocol_violation_count_in(4'd0),
        .source_drop_count_in(4'd0),
        .fifo_overflow_attempt_count_in(4'd0),
        .source_counter_saturation_count_in(4'd0),
        .last_source_sequence_in(16'd0),
        .status_w1c_clear(mini_w1c),
        .destination_delivery_count(mini_delivery_count),
        .fifo_underflow_attempt_count(mini_underflow_count),
        .duplicate_delivery_count(mini_duplicate_count),
        .sequence_gap_count(mini_gap_count),
        .reorder_or_stale_count(mini_reorder_count),
        .aggregate_error_count(mini_aggregate_count),
        .sticky_status(mini_status)
    );

    integer scenario_count = 0;
    integer accepted_total = 0;
    integer destination_delivery_total = 0;
    integer injected_delivery_total = 0;
    integer delivered_total = 0;
    integer reset_discarded_total = 0;
    integer q_head = 0;
    integer q_tail = 0;
    integer pending_total;
    reg [31:0] queued_sequence [0:4095];
    reg [23:0] queued_payload [0:4095];
    reg [31:0] source_sequence_model = 0;
    reg [31:0] destination_expected_model = 0;
    reg [31:0] destination_last_model = 0;
    reg destination_has_last_model = 0;
    reg injection_mode = 0;

    always @(*)
        pending_total = q_tail - q_head;

    reg model_stall_pending = 0;
    reg model_stall_violation_recorded = 0;
    reg [23:0] model_stall_payload = 0;

    reg [31:0] exp_source_accept = 0;
    reg [31:0] exp_destination_delivery = 0;
    reg [31:0] exp_backpressure = 0;
    reg [31:0] exp_source_protocol = 0;
    reg [31:0] exp_source_drop = 0;
    reg [31:0] exp_fifo_overflow = 0;
    reg [31:0] exp_fifo_underflow = 0;
    reg [31:0] exp_duplicate = 0;
    reg [31:0] exp_gap = 0;
    reg [31:0] exp_reorder = 0;
    reg [31:0] exp_aggregate = 0;
    reg [9:0] exp_status = 0;

    task automatic fail(input [8*120-1:0] message);
        begin
            $display("STAGE2E TEST FAILED: %0s", message);
            $fatal(1);
        end
    endtask

    task automatic check_true(
        input [8*120-1:0] label,
        input condition
    );
        begin
            if (!condition)
                fail(label);
        end
    endtask

    task automatic check_equal32(
        input [8*120-1:0] label,
        input [31:0] actual,
        input [31:0] expected
    );
        begin
            if (actual !== expected) begin
                $display("MISMATCH %0s actual=%08x expected=%08x",
                         label, actual, expected);
                fail(label);
            end
        end
    endtask

    task automatic pass_scenario(input [8*80-1:0] name);
        begin
            scenario_count = scenario_count + 1;
            $display("SC%02d=PASS %0s", scenario_count, name);
        end
    endtask

    task automatic reset_models;
        begin
            if (q_tail > q_head)
                reset_discarded_total = reset_discarded_total +
                                        (q_tail - q_head);
            q_head = 0;
            q_tail = 0;
            source_sequence_model = 0;
            destination_expected_model = 0;
            destination_last_model = 0;
            destination_has_last_model = 0;
            model_stall_pending = 0;
            model_stall_violation_recorded = 0;
            model_stall_payload = 0;
            exp_source_accept = 0;
            exp_destination_delivery = 0;
            exp_backpressure = 0;
            exp_source_protocol = 0;
            exp_source_drop = 0;
            exp_fifo_overflow = 0;
            exp_fifo_underflow = 0;
            exp_duplicate = 0;
            exp_gap = 0;
            exp_reorder = 0;
            exp_aggregate = 0;
            exp_status = 0;
        end
    endtask

    always @(negedge ARESETN)
        reset_models();

    always @(posedge adc_src_clk) begin : source_scoreboard
        reg protocol_event;
        reg [23:0] payload;
        protocol_event = 1'b0;
        payload = {adc_sample_ch1, adc_sample_ch2};
        if (dut.adc_src_local_rst_n) begin
            if (model_stall_pending &&
                !model_stall_violation_recorded &&
                (!adc_sample_valid || payload != model_stall_payload))
                protocol_event = 1'b1;

            if (!model_stall_pending) begin
                if (adc_sample_valid && !adc_sample_ready) begin
                    model_stall_pending = 1'b1;
                    model_stall_violation_recorded = 1'b0;
                    model_stall_payload = payload;
                end
            end else begin
                if (protocol_event)
                    model_stall_violation_recorded = 1'b1;
                if (!adc_sample_valid ||
                    (adc_sample_valid && adc_sample_ready)) begin
                    model_stall_pending = 1'b0;
                    model_stall_violation_recorded = 1'b0;
                end
            end

            if (adc_sample_valid && adc_sample_ready) begin
                queued_sequence[q_tail] = source_sequence_model;
                queued_payload[q_tail] = payload;
                q_tail = q_tail + 1;
                source_sequence_model = source_sequence_model + 1;
                exp_source_accept = exp_source_accept + 1;
                accepted_total = accepted_total + 1;
            end
            if (adc_sample_valid && !adc_sample_ready) begin
                exp_backpressure = exp_backpressure + 1;
                exp_status = exp_status | STATUS_BACKPRESSURE;
            end
            if (protocol_event) begin
                exp_source_protocol = exp_source_protocol + 1;
                exp_source_drop = exp_source_drop + 1;
                exp_aggregate = exp_aggregate + 1;
                exp_status = exp_status | STATUS_SOURCE_PROTOCOL |
                             STATUS_SOURCE_DROP | STATUS_ANY_ERROR;
            end
            if (dut.u_adc_sample_cdc_bridge.fifo_overflow_attempt) begin
                exp_fifo_overflow = exp_fifo_overflow + 1;
                exp_aggregate = exp_aggregate + 1;
                exp_status = exp_status | STATUS_FIFO_OVERFLOW |
                             STATUS_ANY_ERROR;
            end
        end
    end

    always @(posedge ACLK) begin : destination_scoreboard
        reg [31:0] actual_sequence;
        if (dut.adc_dst_local_rst_n) begin
            if (dut.dst_sample_valid) begin
                actual_sequence = dut.dst_sample_sequence;
                exp_destination_delivery = exp_destination_delivery + 1;
                delivered_total = delivered_total + 1;
                if (injection_mode) begin
                    injected_delivery_total = injected_delivery_total + 1;
                end else begin
                    destination_delivery_total = destination_delivery_total + 1;
                    if (q_head >= q_tail)
                        fail("phantom destination delivery");
                    if (actual_sequence !== queued_sequence[q_head])
                        fail("destination sequence differs from accepted queue");
                    if ({dut.dst_sample_ch1, dut.dst_sample_ch2} !==
                        queued_payload[q_head])
                        fail("sequence and channel pair are not one atomic word");
                    q_head = q_head + 1;
                end

                if (actual_sequence == destination_expected_model) begin
                    destination_expected_model =
                        destination_expected_model + 1;
                end else if (destination_has_last_model &&
                    actual_sequence == destination_last_model) begin
                    exp_duplicate = exp_duplicate + 1;
                    exp_aggregate = exp_aggregate + 1;
                    exp_status = exp_status | STATUS_DUPLICATE |
                                 STATUS_ANY_ERROR;
                end else if (!destination_has_last_model) begin
                    exp_reorder = exp_reorder + 1;
                    exp_aggregate = exp_aggregate + 1;
                    exp_status = exp_status | STATUS_REORDER_STALE |
                                 STATUS_ANY_ERROR;
                end else if ((actual_sequence -
                    destination_expected_model) < 32'h8000_0000) begin
                    exp_gap = exp_gap + 1;
                    exp_aggregate = exp_aggregate + 1;
                    exp_status = exp_status | STATUS_SEQUENCE_GAP |
                                 STATUS_ANY_ERROR;
                    destination_expected_model = actual_sequence + 1;
                end else begin
                    exp_reorder = exp_reorder + 1;
                    exp_aggregate = exp_aggregate + 1;
                    exp_status = exp_status | STATUS_REORDER_STALE |
                                 STATUS_ANY_ERROR;
                end
                destination_last_model = actual_sequence;
                destination_has_last_model = 1'b1;
            end

            if (dut.fifo_underflow_attempt) begin
                exp_fifo_underflow = exp_fifo_underflow + 1;
                exp_aggregate = exp_aggregate + 1;
                exp_status = exp_status | STATUS_FIFO_UNDERFLOW |
                             STATUS_ANY_ERROR;
            end
        end
    end

    task automatic reset_dut;
        begin
            adc_sample_valid = 1'b0;
            injection_mode = 1'b0;
            S_AXI_AWVALID = 1'b0;
            S_AXI_WVALID = 1'b0;
            S_AXI_ARVALID = 1'b0;
            S_AXI_BREADY = 1'b0;
            S_AXI_RREADY = 1'b0;
            ARESETN = 1'b0;
            #3;
            repeat (3) @(posedge ACLK);
            repeat (3) @(posedge adc_src_clk);
            @(negedge ACLK);
            ARESETN = 1'b1;
            wait (dut.adc_dst_local_rst_n === 1'b1);
            wait (dut.adc_src_local_rst_n === 1'b1);
            repeat (3) @(posedge ACLK);
        end
    endtask

    task automatic axi_write_strb(
        input [7:0] address,
        input [31:0] data,
        input [3:0] strb
    );
        integer guard;
        begin
            @(negedge ACLK);
            S_AXI_AWADDR = address;
            S_AXI_AWVALID = 1'b1;
            S_AXI_WDATA = data;
            S_AXI_WSTRB = strb;
            S_AXI_WVALID = 1'b1;
            guard = 0;
            while (!(S_AXI_AWREADY && S_AXI_WREADY)) begin
                @(posedge ACLK);
                guard = guard + 1;
                if (guard > 30)
                    fail("AXI write handshake timeout");
            end
            @(posedge ACLK);
            #1;
            S_AXI_AWVALID = 1'b0;
            S_AXI_WVALID = 1'b0;
            S_AXI_WSTRB = 4'h0;
            S_AXI_BREADY = 1'b1;
            guard = 0;
            while (!S_AXI_BVALID) begin
                @(posedge ACLK);
                #1;
                guard = guard + 1;
                if (guard > 30)
                    fail("AXI write response timeout");
            end
            if (S_AXI_BRESP !== 2'b00)
                fail("AXI write response is not OKAY");
            @(posedge ACLK);
            #1;
            S_AXI_BREADY = 1'b0;
            S_AXI_AWADDR = 0;
            S_AXI_WDATA = 0;
        end
    endtask

    task automatic axi_read(input [7:0] address, output [31:0] data);
        integer guard;
        begin
            @(negedge ACLK);
            S_AXI_ARADDR = address;
            S_AXI_ARVALID = 1'b1;
            guard = 0;
            while (!S_AXI_ARREADY) begin
                @(posedge ACLK);
                guard = guard + 1;
                if (guard > 30)
                    fail("AXI read address timeout");
            end
            @(posedge ACLK);
            #1;
            S_AXI_ARVALID = 1'b0;
            S_AXI_RREADY = 1'b1;
            guard = 0;
            while (!S_AXI_RVALID) begin
                @(posedge ACLK);
                #1;
                guard = guard + 1;
                if (guard > 30)
                    fail("AXI read response timeout");
            end
            if (S_AXI_RRESP !== 2'b00)
                fail("AXI read response is not OKAY");
            data = S_AXI_RDATA;
            @(posedge ACLK);
            #1;
            S_AXI_RREADY = 1'b0;
            S_AXI_ARADDR = 0;
        end
    endtask

    task automatic send_transaction(
        input [11:0] ch1,
        input [11:0] ch2
    );
        reg accepted;
        begin
            accepted = 1'b0;
            @(negedge adc_src_clk);
            adc_sample_ch1 = ch1;
            adc_sample_ch2 = ch2;
            adc_sample_valid = 1'b1;
            while (!accepted) begin
                @(posedge adc_src_clk);
                accepted = adc_sample_ready;
            end
            @(negedge adc_src_clk);
            adc_sample_valid = 1'b0;
        end
    endtask

    task automatic send_held_high_burst(
        input integer count,
        input [11:0] base,
        input repeat_payload
    );
        integer index;
        reg accepted;
        begin
            @(negedge adc_src_clk);
            adc_sample_valid = 1'b1;
            adc_sample_ch1 = base;
            adc_sample_ch2 = repeat_payload ? base : (base ^ 12'hA5A);
            for (index = 0; index < count; index = index + 1) begin
                accepted = 1'b0;
                while (!accepted) begin
                    @(posedge adc_src_clk);
                    accepted = adc_sample_ready;
                end
                if (index != count - 1) begin
                    @(negedge adc_src_clk);
                    if (!repeat_payload) begin
                        adc_sample_ch1 = base + index + 1;
                        adc_sample_ch2 = (base + index + 1) ^ 12'hA5A;
                    end
                end
            end
            @(negedge adc_src_clk);
            adc_sample_valid = 1'b0;
        end
    endtask

    task automatic wait_for_drain;
        integer guard;
        begin
            guard = 0;
            while (q_head != q_tail) begin
                @(posedge ACLK);
                guard = guard + 1;
                if (guard > 300)
                    fail("accepted queue did not drain");
            end
            repeat (8) @(posedge ACLK);
        end
    endtask

    task automatic wait_for_source_convergence;
        integer guard;
        begin
            guard = 0;
            while ((dut.obs_source_accept_count !== exp_source_accept) ||
                   (dut.obs_backpressure_cycle_count !== exp_backpressure) ||
                   (dut.obs_source_protocol_violation_count !==
                        exp_source_protocol) ||
                   (dut.obs_source_drop_count !== exp_source_drop) ||
                   (dut.obs_fifo_overflow_attempt_count !==
                        exp_fifo_overflow)) begin
                @(posedge ACLK);
                guard = guard + 1;
                if (guard > 300)
                    fail("source Gray telemetry did not converge exactly");
            end
            repeat (3) @(posedge ACLK);
        end
    endtask

    task automatic check_all_registers;
        reg [31:0] value;
        begin
            wait_for_source_convergence();
            axi_read(REG_OBS_SOURCE_ACCEPT, value);
            check_equal32("source accept counter", value, exp_source_accept);
            axi_read(REG_OBS_DESTINATION_DELIVERY, value);
            check_equal32("destination delivery counter", value,
                          exp_destination_delivery);
            axi_read(REG_OBS_BACKPRESSURE, value);
            check_equal32("backpressure counter", value, exp_backpressure);
            axi_read(REG_OBS_SOURCE_PROTOCOL, value);
            check_equal32("source protocol counter", value,
                          exp_source_protocol);
            axi_read(REG_OBS_SOURCE_DROP, value);
            check_equal32("source drop counter", value, exp_source_drop);
            axi_read(REG_OBS_FIFO_OVERFLOW, value);
            check_equal32("FIFO overflow counter", value, exp_fifo_overflow);
            axi_read(REG_OBS_FIFO_UNDERFLOW, value);
            check_equal32("FIFO underflow counter", value, exp_fifo_underflow);
            axi_read(REG_OBS_DUPLICATE, value);
            check_equal32("duplicate counter", value, exp_duplicate);
            axi_read(REG_OBS_SEQUENCE_GAP, value);
            check_equal32("gap counter", value, exp_gap);
            axi_read(REG_OBS_REORDER_STALE, value);
            check_equal32("reorder counter", value, exp_reorder);
            axi_read(REG_OBS_AGGREGATE, value);
            check_equal32("aggregate counter", value, exp_aggregate);
            axi_read(REG_OBS_STATUS, value);
            check_equal32("sticky status", value, {22'd0, exp_status});
        end
    endtask

    task force_delivery(input [31:0] seq_value);
        begin
            injection_mode = 1'b1;
            @(negedge ACLK);
            force dut.dst_sample_sequence = seq_value;
            force dut.dst_sample_valid = 1'b1;
            force dut.dst_sample_ch1 = seq_value[11:0];
            force dut.dst_sample_ch2 = ~seq_value[11:0];
            @(posedge ACLK);
            #1;
            @(negedge ACLK);
            release dut.dst_sample_sequence;
            release dut.dst_sample_valid;
            release dut.dst_sample_ch1;
            release dut.dst_sample_ch2;
            injection_mode = 1'b0;
            repeat (2) @(posedge ACLK);
        end
    endtask

    task automatic force_underflow_event;
        begin
            @(negedge ACLK);
            // Controlled bad implementation: present a read enable while the
            // FIFO is empty. This exercises the FIFO detector itself instead
            // of bypassing it by forcing the derived event output. Suppress
            // the deliberately invalid read-enable from masquerading as the
            // bridge's accepted destination-delivery pulse during this bad fixture.
            force dut.u_adc_sample_cdc_bridge.u_fifo.rd_empty = 1'b1;
            force dut.u_adc_sample_cdc_bridge.u_fifo.rd_en = 1'b1;
            force dut.dst_sample_valid = 1'b0;
            @(posedge ACLK);
            #1;
            @(negedge ACLK);
            release dut.dst_sample_valid;
            release dut.u_adc_sample_cdc_bridge.u_fifo.rd_en;
            release dut.u_adc_sample_cdc_bridge.u_fifo.rd_empty;
            repeat (2) @(posedge ACLK);
        end
    endtask

    task automatic force_overflow_event;
        begin
            @(negedge adc_src_clk);
            // Controlled bad implementation: present a write enable while
            // full. Legal producer valid is deliberately not used here.
            force dut.u_adc_sample_cdc_bridge.u_fifo.wr_full = 1'b1;
            force dut.u_adc_sample_cdc_bridge.u_fifo.wr_en = 1'b1;
            @(posedge adc_src_clk);
            #1;
            @(negedge adc_src_clk);
            release dut.u_adc_sample_cdc_bridge.u_fifo.wr_en;
            release dut.u_adc_sample_cdc_bridge.u_fifo.wr_full;
        end
    endtask

    task automatic pause_bridge_send(input [11:0] value);
        reg accepted;
        begin
            accepted = 0;
            @(negedge adc_src_clk);
            pause_ch1 = value;
            pause_ch2 = value ^ 12'hC3C;
            pause_src_valid = 1;
            while (!accepted) begin
                @(posedge adc_src_clk);
                accepted = pause_src_ready;
            end
            @(negedge adc_src_clk);
            pause_src_valid = 0;
        end
    endtask

    task automatic mini_deliver(input [15:0] seq_value);
        begin
            @(negedge ACLK);
            mini_delivery_sequence = seq_value;
            mini_delivery_valid = 1'b1;
            @(posedge ACLK);
            #1;
            @(negedge ACLK);
            mini_delivery_valid = 1'b0;
        end
    endtask

    reg [31:0] read_value;
    reg [31:0] counter_before_clear;
    integer index;
    integer bp_before;

    initial begin
        begin : waveform_output
            string wave_dir;
            if (!$value$plusargs("CSIP_WAVE_DIR=%s", wave_dir)) wave_dir = ".";
            $dumpfile({wave_dir, "/stage2e_transaction_error_observability.vcd"});
        end
        $dumpvars(0, tb_stage2e_transaction_error_observability);

        reset_dut();
        check_all_registers();
        pass_scenario("safe-inert profile counters and status are zero");

        send_transaction(12'h101, 12'hEFE);
        wait_for_drain();
        check_all_registers();
        check_equal32("single transaction source", exp_source_accept, 1);
        check_equal32("single transaction destination",
                      exp_destination_delivery, 1);
        pass_scenario("single accepted and delivered transaction");

        send_held_high_burst(4, 12'h200, 1'b0);
        wait_for_drain();
        check_all_registers();
        pass_scenario("back-to-back normal transactions");

        send_held_high_burst(2, 12'h333, 1'b1);
        wait_for_drain();
        check_equal32("equal payload must not duplicate", exp_duplicate, 0);
        pass_scenario("repeated payload with distinct sequence is legal");

        mini_dst_rst_n = 0;
        repeat (2) @(posedge ACLK);
        mini_dst_rst_n = 1;
        @(negedge ACLK);
        mini_destination_observer.u_sequence_integrity_tracker
            .expected_sequence = 16'hFFFE;
        mini_destination_observer.u_sequence_integrity_tracker
            .has_last_delivery = 1'b1;
        mini_destination_observer.u_sequence_integrity_tracker
            .last_destination_sequence = 16'hFFFD;
        mini_deliver(16'hFFFE);
        mini_deliver(16'hFFFF);
        mini_deliver(16'h0000);
        mini_deliver(16'h0001);
        check_true("sequence wrap raised an error",
            mini_duplicate_count == 0 && mini_gap_count == 0 &&
            mini_reorder_count == 0);
        pass_scenario("sequence wrap-around is normal");

        source_half_period = 12.0;
        send_held_high_burst(3, 12'h410, 1'b0);
        wait_for_drain();
        pass_scenario("source clock slower than ACLK");

        source_half_period = 3.0;
        send_held_high_burst(12, 12'h500, 1'b0);
        wait_for_drain();
        pass_scenario("source clock faster than ACLK");

        source_half_period = 6.5;
        send_held_high_burst(5, 12'h600, 1'b0);
        wait_for_drain();
        pass_scenario("non-integer clock ratio");

        #3.7;
        send_transaction(12'h6AA, 12'h955);
        wait_for_drain();
        pass_scenario("clock phase offset");

        @(negedge ACLK);
        pause_dst_ready = 0;
        pause_bridge_send(12'h701);
        pause_bridge_send(12'h702);
        repeat (6) @(posedge ACLK);
        check_true("paused destination delivered a transaction",
                   pause_delivery_count == 0);
        @(negedge ACLK);
        pause_dst_ready = 1;
        repeat (20) @(posedge ACLK);
        check_true("paused bridge did not resume exactly twice",
                   pause_delivery_count == 2);
        pass_scenario("destination pause and resume");

        source_half_period = 7.0;
        send_held_high_burst(3, 12'h750, 1'b0);
        wait_for_drain();
        pass_scenario("legal held-high valid");

        reset_dut();
        bp_before = exp_backpressure;
        force dut.u_adc_sample_cdc_bridge.u_fifo.wr_full = 1'b1;
        @(negedge adc_src_clk);
        adc_sample_ch1 = 12'h811;
        adc_sample_ch2 = 12'h8EE;
        adc_sample_valid = 1'b1;
        repeat (4) @(posedge adc_src_clk);
        release dut.u_adc_sample_cdc_bridge.u_fifo.wr_full;
        wait (adc_sample_ready === 1'b1);
        @(posedge adc_src_clk);
        @(negedge adc_src_clk);
        adc_sample_valid = 0;
        wait_for_drain();
        wait_for_source_convergence();
        check_true("legal backpressure count did not increase",
                   exp_backpressure >= bp_before + 4);
        check_equal32("legal backpressure classified as protocol error",
                      exp_source_protocol, 0);
        check_true("backpressure incorrectly set ANY_ERROR",
                   (dut.obs_sticky_status & STATUS_ANY_ERROR) == 0);
        pass_scenario("legal backpressure is not a drop");

        reset_dut();
        send_transaction(12'h901, 12'h9FE);
        wait_for_drain();
        force_underflow_event();
        wait_for_source_convergence();
        check_true("pre-reset counters did not become nonzero",
                   exp_destination_delivery != 0 && exp_fifo_underflow != 0);
        reset_dut();
        check_all_registers();
        pass_scenario("reset clears counters and sticky status");

        send_transaction(12'hA01, 12'hAFE);
        wait_for_drain();
        check_equal32("first post-reset source count", exp_source_accept, 1);
        check_equal32("first post-reset destination count",
                      exp_destination_delivery, 1);
        check_true("legal first post-reset sequence zero was classified",
                   exp_duplicate == 0 && exp_gap == 0 && exp_reorder == 0);
        pass_scenario("first post-reset sequence zero is legal and exactly once");

        force_underflow_event();
        check_all_registers();
        counter_before_clear = exp_fifo_underflow;
        axi_write_strb(REG_OBS_STATUS, 32'h0000_03FF, 4'hF);
        exp_status = 0;
        repeat (4) @(posedge ACLK);
        axi_read(REG_OBS_STATUS, read_value);
        check_equal32("ordinary W1C", read_value, 0);
        pass_scenario("sticky W1C");

        @(negedge ACLK);
        force dut.obs_status_w1c_clear = 10'h3FF;
        force dut.fifo_underflow_attempt = 1'b1;
        @(posedge ACLK);
        #1;
        exp_fifo_underflow = exp_fifo_underflow + 1;
        exp_aggregate = exp_aggregate + 1;
        exp_status = STATUS_FIFO_UNDERFLOW | STATUS_ANY_ERROR;
        @(negedge ACLK);
        release dut.obs_status_w1c_clear;
        release dut.fifo_underflow_attempt;
        repeat (2) @(posedge ACLK);
        axi_read(REG_OBS_STATUS, read_value);
        check_equal32("W1C new-event priority", read_value,
                      {22'd0, exp_status});
        pass_scenario("W1C and new event preserves event");

        mini_src_rst_n = 0;
        repeat (2) @(posedge adc_src_clk);
        mini_src_rst_n = 1;
        mini_src_ready = 0;
        mini_src_valid = 1;
        repeat (20) @(posedge adc_src_clk);
        mini_src_valid = 0;
        check_true("source saturating counter wrapped",
                   mini_backpressure_count == 4'hF);
        check_true("source saturation event missing",
                   mini_source_saturation_count != 0);
        pass_scenario("source counter saturates without wrap");

        axi_read(REG_OBS_CAPABILITY, read_value);
        check_equal32("capability value", read_value, 32'hE278_2001);
        pass_scenario("capability and version fields");

        // Recreate byte-0 and byte-1 sticky bits. Byte 0 clears only bits
        // 7:0; byte 1 clears cause bit 8 while bit 9 is read-only.
        force_underflow_event();
        force dut.u_destination_observer.sticky_status = 10'h310;
        @(posedge ACLK);
        release dut.u_destination_observer.sticky_status;
        exp_status = 10'h310;
        axi_write_strb(REG_OBS_STATUS, 32'h0000_03FF, 4'b0001);
        exp_status = exp_status & 10'h300;
        repeat (4) @(posedge ACLK);
        axi_read(REG_OBS_STATUS, read_value);
        check_equal32("byte-0 W1C", read_value, {22'd0, exp_status});
        axi_write_strb(REG_OBS_STATUS, 32'h0000_03FF, 4'b0010);
        exp_status = 0;
        repeat (4) @(posedge ACLK);
        axi_read(REG_OBS_STATUS, read_value);
        check_equal32("byte-1 W1C", read_value, 0);
        pass_scenario("AXI byte strobe W1C semantics");

        axi_read(8'h64, read_value);
        check_equal32("undefined address read", read_value, 0);
        axi_write_strb(8'h64, 32'hFFFF_FFFF, 4'hF);
        axi_read(8'h64, read_value);
        check_equal32("undefined address after write", read_value, 0);
        pass_scenario("undefined address keeps zero and OKAY contract");

        reset_dut();
        force dut.u_adc_sample_cdc_bridge.u_fifo.wr_full = 1'b1;
        @(negedge adc_src_clk);
        adc_sample_ch1 = 12'hB11;
        adc_sample_ch2 = 12'hBEE;
        adc_sample_valid = 1;
        @(posedge adc_src_clk);
        @(negedge adc_src_clk);
        adc_sample_valid = 0;
        @(posedge adc_src_clk);
        release dut.u_adc_sample_cdc_bridge.u_fifo.wr_full;
        wait_for_source_convergence();
        check_equal32("withdraw violation count", exp_source_protocol, 1);
        check_equal32("withdraw drop count", exp_source_drop, 1);
        pass_scenario("stalled valid withdrawal");

        force dut.u_adc_sample_cdc_bridge.u_fifo.wr_full = 1'b1;
        @(negedge adc_src_clk);
        adc_sample_ch1 = 12'hC11;
        adc_sample_ch2 = 12'hCEE;
        adc_sample_valid = 1;
        @(posedge adc_src_clk);
        @(negedge adc_src_clk);
        adc_sample_ch1 = 12'hC22;
        @(posedge adc_src_clk);
        repeat (2) begin
            @(negedge adc_src_clk);
            adc_sample_ch1 = adc_sample_ch1 + 1;
            @(posedge adc_src_clk);
        end
        check_equal32("payload-change episode recounted",
                      exp_source_protocol, 2);
        release dut.u_adc_sample_cdc_bridge.u_fifo.wr_full;
        wait (adc_sample_ready);
        @(posedge adc_src_clk);
        @(negedge adc_src_clk);
        adc_sample_valid = 0;
        wait_for_drain();
        wait_for_source_convergence();
        pass_scenario("stalled payload change");

        check_equal32("one count per stall episode protocol",
                      exp_source_protocol, 2);
        check_equal32("one count per stall episode drop",
                      exp_source_drop, 2);
        pass_scenario("one violation per stall episode");

        force_overflow_event();
        wait_for_source_convergence();
        check_equal32("overflow injection", exp_fifo_overflow, 1);
        pass_scenario("controlled write-enable-while-full attempt");

        force_underflow_event();
        check_equal32("underflow injection", exp_fifo_underflow, 1);
        pass_scenario("controlled read-enable-while-empty attempt");

        wait_for_drain();
        force_delivery(destination_last_model);
        check_equal32("duplicate sequence injection", exp_duplicate, 1);
        pass_scenario("duplicate sequence delivery");

        force_delivery(destination_expected_model + 3);
        check_equal32("forward gap injection", exp_gap, 1);
        pass_scenario("forward sequence gap");

        force_delivery(destination_expected_model - 2);
        check_equal32("backward sequence injection", exp_reorder, 1);
        pass_scenario("backward reorder sequence");

        reset_dut();
        force_delivery(32'd7);
        check_equal32("first nonzero identity mismatch", exp_reorder, 1);
        pass_scenario("first post-reset nonzero sequence mismatch");

        mini_dst_rst_n = 0;
        repeat (2) @(posedge ACLK);
        mini_dst_rst_n = 1;
        for (index = 0; index < 20; index = index + 1)
            mini_deliver(index[15:0]);
        check_true("destination counter wrapped after saturation",
                   mini_delivery_count == 4'hF);
        check_true("destination saturation sticky missing",
                   (mini_status & STATUS_COUNTER_SATURATED) != 0 &&
                   (mini_status & STATUS_ANY_ERROR) != 0);
        pass_scenario("destination counter saturation observability");

        reset_dut();
        source_half_period = 1.5;
        force dut.u_adc_sample_cdc_bridge.u_fifo.wr_full = 1'b1;
        @(negedge adc_src_clk);
        adc_sample_valid = 1;
        adc_sample_ch1 = 12'hD11;
        adc_sample_ch2 = 12'hDEE;
        repeat (40) @(posedge adc_src_clk);
        @(negedge adc_src_clk);
        adc_sample_valid = 0;
        @(posedge adc_src_clk);
        release dut.u_adc_sample_cdc_bridge.u_fifo.wr_full;
        wait_for_source_convergence();
        check_equal32("fast source backpressure CDC", dut.obs_backpressure_cycle_count,
                      exp_backpressure);
        pass_scenario("source event Gray CDC retains exact count");

        force_overflow_event();
        wait_for_source_convergence();
        check_equal32("one-source-edge event was missed",
                      dut.obs_fifo_overflow_attempt_count,
                      exp_fifo_overflow);
        pass_scenario("short source event cannot be missed");

        force_underflow_event();
        force_delivery(32'd9);
        wait_for_source_convergence();
        check_equal32("aggregate error accounting",
                      dut.obs_aggregate_error_count, exp_aggregate);
        check_true("aggregate ANY_ERROR missing",
                   (dut.obs_sticky_status & STATUS_ANY_ERROR) != 0);
        pass_scenario("aggregate error semantics");

        axi_read(REG_OBS_FIFO_UNDERFLOW, counter_before_clear);
        axi_write_strb(REG_OBS_STATUS, 32'h0000_03FF, 4'hF);
        exp_status = 0;
        repeat (4) @(posedge ACLK);
        axi_read(REG_OBS_FIFO_UNDERFLOW, read_value);
        check_equal32("W1C cleared a counter", read_value,
                      counter_before_clear);
        pass_scenario("sticky clear does not clear counters");

        reset_dut();
        source_half_period = 7.0;
        send_held_high_burst(3, 12'hEEE, 1'b1);
        wait_for_drain();
        check_equal32("payload equality caused duplicate", exp_duplicate, 0);
        check_all_registers();
        pass_scenario("payload equality is never duplicate identity");

        // Writes to RO diagnostics are ignored.
        axi_write_strb(REG_OBS_SOURCE_ACCEPT, 32'hFFFF_FFFF, 4'hF);
        axi_read(REG_OBS_SOURCE_ACCEPT, read_value);
        check_equal32("software wrote a read-only counter", read_value,
                      exp_source_accept);
        axi_write_strb(REG_OBS_CAPABILITY, 32'd0, 4'hF);
        axi_read(REG_OBS_CAPABILITY, read_value);
        check_equal32("software wrote capability", read_value, 32'hE278_2001);

        check_true("scenario total is not 35", scenario_count == 35);
        check_true("accepted queue not drained", q_head == q_tail);
        check_true("destination delivery accounting mismatch",
                   destination_delivery_total ==
                       accepted_total - reset_discarded_total);
        check_true("total delivery accounting mismatch",
                   delivered_total ==
                       destination_delivery_total + injected_delivery_total);
        $display("STAGE2E_POSITIVE_SCENARIOS=PASS_35_OF_35");
        $display("SCOREBOARD_ACCEPTED=%0d", accepted_total);
        $display("SCOREBOARD_DESTINATION_DELIVERIES=%0d",
                 destination_delivery_total);
        $display("SCOREBOARD_INJECTED_DELIVERIES=%0d",
                 injected_delivery_total);
        $display("SCOREBOARD_DELIVERED_TOTAL=%0d", delivered_total);
        $display("SCOREBOARD_RESET_DISCARDED=%0d", reset_discarded_total);
        $display("SCOREBOARD_PENDING=%0d", pending_total);
        $display("DESTINATION_DELIVERY_ACCOUNTING=PASS");
        $display("TOTAL_DELIVERY_ACCOUNTING=PASS");
        $display("HARDWARE_COUNTERS_MATCH_SCOREBOARD=PASS");
        $display("STICKY_BITS_MATCH_SCOREBOARD=PASS");
        $display("FIRST_POST_RESET_SEQUENCE_ZERO_LEGAL=PASS");
        $display("FIRST_POST_RESET_NONZERO_IDENTITY_MISMATCH=PASS");
        $display("EVENTUALLY_CONSISTENT_SOURCE_TELEMETRY=PASS");
        $display("ALL TESTS PASSED: tb_stage2e_transaction_error_observability");
        $finish;
    end

    initial begin
        #2000000;
        fail("global timeout");
    end
endmodule
