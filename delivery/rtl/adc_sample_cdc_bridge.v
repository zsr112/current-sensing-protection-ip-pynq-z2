module adc_sample_cdc_bridge #(
    // Contract: DATA_WIDTH >= 1 and FIFO_ADDR_WIDTH >= 2.
    parameter DATA_WIDTH = 12,
    parameter FIFO_ADDR_WIDTH = 3,
    parameter SEQUENCE_WIDTH = 32,
    parameter COUNTER_WIDTH = 32
)(
    input  wire                  src_clk,
    input  wire                  src_rst_n,
    input  wire                  src_sample_valid,
    output wire                  src_sample_ready,
    input  wire [DATA_WIDTH-1:0] src_sample_ch1,
    input  wire [DATA_WIDTH-1:0] src_sample_ch2,

    input  wire                  dst_clk,
    input  wire                  dst_rst_n,
    input  wire                  dst_ready,
    output wire                  dst_sample_valid,
    output wire [DATA_WIDTH-1:0] dst_sample_ch1,
    output wire [DATA_WIDTH-1:0] dst_sample_ch2,
    output wire [SEQUENCE_WIDTH-1:0] dst_sample_sequence,
    output wire                  fifo_underflow_attempt,

    output wire [COUNTER_WIDTH-1:0] source_accept_count_gray,
    output wire [COUNTER_WIDTH-1:0] backpressure_cycle_count_gray,
    output wire [COUNTER_WIDTH-1:0] source_protocol_violation_count_gray,
    output wire [COUNTER_WIDTH-1:0] source_drop_count_gray,
    output wire [COUNTER_WIDTH-1:0] fifo_overflow_attempt_count_gray,
    output wire [COUNTER_WIDTH-1:0] counter_saturation_event_count_gray,
    output wire [SEQUENCE_WIDTH-1:0] last_source_sequence_gray
);
    localparam PAYLOAD_WIDTH = SEQUENCE_WIDTH + (2 * DATA_WIDTH);

    wire [PAYLOAD_WIDTH-1:0] fifo_write_data;
    wire [PAYLOAD_WIDTH-1:0] fifo_read_data;
    wire fifo_empty;
    wire fifo_write_enable;
    wire fifo_read_enable;
    wire fifo_overflow_attempt;
    wire [SEQUENCE_WIDTH-1:0] source_sequence;
    // This is the only destination-domain payload capture boundary. KEEP
    // makes the bounded FIFO-memory-to-register implementation constraint
    // fail closed if synthesis attempts to remove or rename the boundary.
    (* KEEP = "TRUE" *) reg [PAYLOAD_WIDTH-1:0] destination_data;
    reg destination_valid;

    // These generate branches deliberately reference undefined modules. A
    // bad configuration therefore cannot elaborate into ambiguous hardware.
    generate
        if (DATA_WIDTH < 1) begin : g_invalid_data_width
            STAGE2D_PARAMETER_ERROR_DATA_WIDTH_MUST_BE_AT_LEAST_1
                u_parameter_error();
        end
        if (FIFO_ADDR_WIDTH < 2) begin : g_invalid_fifo_addr_width
            STAGE2D_PARAMETER_ERROR_FIFO_ADDR_WIDTH_MUST_BE_AT_LEAST_2
                u_parameter_error();
        end
        if (SEQUENCE_WIDTH < 16) begin : g_invalid_sequence_width
            STAGE2E_PARAMETER_ERROR_SEQUENCE_WIDTH_MUST_BE_AT_LEAST_16
                u_parameter_error();
        end
        if (COUNTER_WIDTH < 2) begin : g_invalid_counter_width
            STAGE2E_PARAMETER_ERROR_COUNTER_WIDTH_MUST_BE_AT_LEAST_2
                u_parameter_error();
        end
    endgenerate

    assign fifo_write_enable = src_rst_n &&
                               src_sample_valid && src_sample_ready;
    assign fifo_write_data = {
        source_sequence, src_sample_ch1, src_sample_ch2
    };

    // The output register is an elastic one-word destination buffer. A ready
    // edge may deliver its current word and refill it from the FIFO at the
    // same time, preserving one delivery per cycle after initial fill. When
    // ready is low neither the read pointer nor the registered payload moves.
    // fifo_read_enable/u_fifo.rd_fire is an internal prefetch into the elastic
    // register. The later accepted dst_sample_valid edge is the external
    // destination-delivery event and the Stage2B/Stage2G transaction authority.
    assign fifo_read_enable = dst_rst_n && dst_ready && !fifo_empty;
    assign dst_sample_valid = dst_ready && destination_valid;

    // Downstream logic sees only the destination-domain register, never the
    // inferred FIFO-memory read mux. Data holds outside a refill, including
    // throughout an arbitrarily long destination stall.
    assign dst_sample_sequence =
        destination_data[PAYLOAD_WIDTH-1 -: SEQUENCE_WIDTH];
    assign dst_sample_ch1 =
        destination_data[(2*DATA_WIDTH)-1:DATA_WIDTH];
    assign dst_sample_ch2 = destination_data[DATA_WIDTH-1:0];

    (* KEEP_HIERARCHY = "TRUE" *) transaction_source_observer #(
        .DATA_WIDTH(DATA_WIDTH),
        .SEQUENCE_WIDTH(SEQUENCE_WIDTH),
        .COUNTER_WIDTH(COUNTER_WIDTH)
    ) u_source_observer (
        .clk(src_clk),
        .rst_n(src_rst_n),
        .source_valid(src_sample_valid),
        .source_ready(src_sample_ready),
        .source_ch1(src_sample_ch1),
        .source_ch2(src_sample_ch2),
        .fifo_overflow_attempt(fifo_overflow_attempt),
        .transaction_sequence(source_sequence),
        .transaction_integrity_clean(),
        .last_source_sequence(),
        .last_source_sequence_gray(last_source_sequence_gray),
        .source_accept_count(),
        .backpressure_cycle_count(),
        .source_protocol_violation_count(),
        .source_drop_count(),
        .fifo_overflow_attempt_count(),
        .counter_saturation_event_count(),
        .source_accept_count_gray(source_accept_count_gray),
        .backpressure_cycle_count_gray(backpressure_cycle_count_gray),
        .source_protocol_violation_count_gray(
            source_protocol_violation_count_gray),
        .source_drop_count_gray(source_drop_count_gray),
        .fifo_overflow_attempt_count_gray(
            fifo_overflow_attempt_count_gray),
        .counter_saturation_event_count_gray(
            counter_saturation_event_count_gray)
    );

    always @(posedge dst_clk or negedge dst_rst_n) begin
        if (!dst_rst_n) begin
            destination_data <= {PAYLOAD_WIDTH{1'b0}};
            destination_valid <= 1'b0;
        end else if (dst_ready) begin
            if (!fifo_empty) begin
                destination_data <= fifo_read_data;
                destination_valid <= 1'b1;
            end else begin
                destination_valid <= 1'b0;
            end
        end
    end

    (* KEEP_HIERARCHY = "TRUE" *) async_fifo_gray #(
        .DATA_WIDTH(PAYLOAD_WIDTH),
        .ADDR_WIDTH(FIFO_ADDR_WIDTH)
    ) u_fifo (
        .wr_clk(src_clk),
        .wr_rst_n(src_rst_n),
        .wr_en(fifo_write_enable),
        .wr_ready(src_sample_ready),
        .wr_data(fifo_write_data),
        .wr_overflow_attempt(fifo_overflow_attempt),
        .rd_clk(dst_clk),
        .rd_rst_n(dst_rst_n),
        .rd_en(fifo_read_enable),
        .rd_empty(fifo_empty),
        .rd_data(fifo_read_data),
        .rd_underflow_attempt(fifo_underflow_attempt)
    );
endmodule

// Stage 2G metadata-aware bridge.  The legacy bridge above retains its exact
// port list and payload contract for Stage 2D/2E fixtures.  This variant adds
// one atomic FIFO sideband bit carrying source offer integrity.
module stage2g_adc_sample_cdc_bridge #(
    parameter DATA_WIDTH = 12,
    parameter FIFO_ADDR_WIDTH = 3,
    parameter SEQUENCE_WIDTH = 32,
    parameter COUNTER_WIDTH = 32
)(
    input  wire                  src_clk,
    input  wire                  src_rst_n,
    input  wire                  src_sample_valid,
    output wire                  src_sample_ready,
    input  wire [DATA_WIDTH-1:0] src_sample_ch1,
    input  wire [DATA_WIDTH-1:0] src_sample_ch2,

    input  wire                  dst_clk,
    input  wire                  dst_rst_n,
    input  wire                  dst_ready,
    output wire                  dst_sample_valid,
    output wire [DATA_WIDTH-1:0] dst_sample_ch1,
    output wire [DATA_WIDTH-1:0] dst_sample_ch2,
    output wire [SEQUENCE_WIDTH-1:0] dst_sample_sequence,
    output wire                  dst_sample_integrity_clean,
    output wire                  fifo_underflow_attempt,

    output wire [COUNTER_WIDTH-1:0] source_accept_count_gray,
    output wire [COUNTER_WIDTH-1:0] backpressure_cycle_count_gray,
    output wire [COUNTER_WIDTH-1:0]
        source_protocol_violation_count_gray,
    output wire [COUNTER_WIDTH-1:0] source_drop_count_gray,
    output wire [COUNTER_WIDTH-1:0]
        fifo_overflow_attempt_count_gray,
    output wire [COUNTER_WIDTH-1:0]
        counter_saturation_event_count_gray,
    output wire [SEQUENCE_WIDTH-1:0] last_source_sequence_gray
);
    localparam PAYLOAD_WIDTH = 1 + SEQUENCE_WIDTH + (2 * DATA_WIDTH);

    wire [PAYLOAD_WIDTH-1:0] fifo_write_data;
    wire [PAYLOAD_WIDTH-1:0] fifo_read_data;
    wire fifo_empty;
    wire fifo_write_enable;
    wire fifo_read_enable;
    wire fifo_overflow_attempt;
    wire [SEQUENCE_WIDTH-1:0] source_sequence;
    wire source_integrity_clean;
    (* KEEP = "TRUE" *) reg [PAYLOAD_WIDTH-1:0] destination_data;
    reg destination_valid;

    generate
        if (DATA_WIDTH < 1) begin : g_invalid_data_width
            STAGE2D_PARAMETER_ERROR_DATA_WIDTH_MUST_BE_AT_LEAST_1
                u_parameter_error();
        end
        if (FIFO_ADDR_WIDTH < 2) begin : g_invalid_fifo_addr_width
            STAGE2D_PARAMETER_ERROR_FIFO_ADDR_WIDTH_MUST_BE_AT_LEAST_2
                u_parameter_error();
        end
        if (SEQUENCE_WIDTH < 16) begin : g_invalid_sequence_width
            STAGE2E_PARAMETER_ERROR_SEQUENCE_WIDTH_MUST_BE_AT_LEAST_16
                u_parameter_error();
        end
        if (COUNTER_WIDTH < 2) begin : g_invalid_counter_width
            STAGE2E_PARAMETER_ERROR_COUNTER_WIDTH_MUST_BE_AT_LEAST_2
                u_parameter_error();
        end
    endgenerate

    assign fifo_write_enable = src_rst_n &&
                               src_sample_valid && src_sample_ready;
    assign fifo_write_data = {
        source_integrity_clean, source_sequence, src_sample_ch1,
        src_sample_ch2
    };
    // Keep the internal FIFO prefetch distinct from the later accepted
    // destination delivery. Only dst_sample_valid is Stage2B/Stage2G authority.
    assign fifo_read_enable = dst_rst_n && dst_ready && !fifo_empty;
    assign dst_sample_valid = dst_ready && destination_valid;
    assign dst_sample_integrity_clean = destination_data[PAYLOAD_WIDTH-1];
    assign dst_sample_sequence =
        destination_data[PAYLOAD_WIDTH-2 -: SEQUENCE_WIDTH];
    assign dst_sample_ch1 =
        destination_data[(2*DATA_WIDTH)-1:DATA_WIDTH];
    assign dst_sample_ch2 = destination_data[DATA_WIDTH-1:0];

    // Keep the established observer hierarchy so the Stage 2E Gray-counter
    // constraints and status semantics remain unchanged.
    (* KEEP_HIERARCHY = "TRUE" *) transaction_source_observer #(
        .DATA_WIDTH(DATA_WIDTH),
        .SEQUENCE_WIDTH(SEQUENCE_WIDTH),
        .COUNTER_WIDTH(COUNTER_WIDTH)
    ) u_source_observer (
        .clk(src_clk), .rst_n(src_rst_n),
        .source_valid(src_sample_valid),
        .source_ready(src_sample_ready),
        .source_ch1(src_sample_ch1), .source_ch2(src_sample_ch2),
        .fifo_overflow_attempt(fifo_overflow_attempt),
        .transaction_sequence(source_sequence),
        .transaction_integrity_clean(source_integrity_clean),
        .last_source_sequence(),
        .last_source_sequence_gray(last_source_sequence_gray),
        .source_accept_count(), .backpressure_cycle_count(),
        .source_protocol_violation_count(), .source_drop_count(),
        .fifo_overflow_attempt_count(),
        .counter_saturation_event_count(),
        .source_accept_count_gray(source_accept_count_gray),
        .backpressure_cycle_count_gray(backpressure_cycle_count_gray),
        .source_protocol_violation_count_gray(
            source_protocol_violation_count_gray),
        .source_drop_count_gray(source_drop_count_gray),
        .fifo_overflow_attempt_count_gray(
            fifo_overflow_attempt_count_gray),
        .counter_saturation_event_count_gray(
            counter_saturation_event_count_gray)
    );

    always @(posedge dst_clk or negedge dst_rst_n) begin
        if (!dst_rst_n) begin
            destination_data <= {PAYLOAD_WIDTH{1'b0}};
            destination_valid <= 1'b0;
        end else if (dst_ready) begin
            if (!fifo_empty) begin
                destination_data <= fifo_read_data;
                destination_valid <= 1'b1;
            end else begin
                destination_valid <= 1'b0;
            end
        end
    end

    (* KEEP_HIERARCHY = "TRUE" *) async_fifo_gray #(
        .DATA_WIDTH(PAYLOAD_WIDTH),
        .ADDR_WIDTH(FIFO_ADDR_WIDTH)
    ) u_fifo (
        .wr_clk(src_clk), .wr_rst_n(src_rst_n),
        .wr_en(fifo_write_enable), .wr_ready(src_sample_ready),
        .wr_data(fifo_write_data),
        .wr_overflow_attempt(fifo_overflow_attempt),
        .rd_clk(dst_clk), .rd_rst_n(dst_rst_n),
        .rd_en(fifo_read_enable), .rd_empty(fifo_empty),
        .rd_data(fifo_read_data),
        .rd_underflow_attempt(fifo_underflow_attempt)
    );
endmodule
