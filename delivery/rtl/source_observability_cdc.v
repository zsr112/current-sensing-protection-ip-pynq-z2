module source_observability_cdc #(
    parameter SEQUENCE_WIDTH = 32,
    parameter COUNTER_WIDTH = 32
)(
    input  wire dst_clk,
    input  wire dst_rst_n,

    input wire [COUNTER_WIDTH-1:0] source_accept_count_gray,
    input wire [COUNTER_WIDTH-1:0] backpressure_cycle_count_gray,
    input wire [COUNTER_WIDTH-1:0] source_protocol_violation_count_gray,
    input wire [COUNTER_WIDTH-1:0] source_drop_count_gray,
    input wire [COUNTER_WIDTH-1:0] fifo_overflow_attempt_count_gray,
    input wire [COUNTER_WIDTH-1:0] counter_saturation_event_count_gray,
    input wire [SEQUENCE_WIDTH-1:0] last_source_sequence_gray,

    output wire [COUNTER_WIDTH-1:0] source_accept_count,
    output wire [COUNTER_WIDTH-1:0] backpressure_cycle_count,
    output wire [COUNTER_WIDTH-1:0] source_protocol_violation_count,
    output wire [COUNTER_WIDTH-1:0] source_drop_count,
    output wire [COUNTER_WIDTH-1:0] fifo_overflow_attempt_count,
    output wire [COUNTER_WIDTH-1:0] counter_saturation_event_count,
    output wire [SEQUENCE_WIDTH-1:0] last_source_sequence
);
    (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
    reg [COUNTER_WIDTH-1:0] source_accept_count_gray_sync1;
    (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
    reg [COUNTER_WIDTH-1:0] source_accept_count_gray_sync2;
    (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
    reg [COUNTER_WIDTH-1:0] backpressure_cycle_count_gray_sync1;
    (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
    reg [COUNTER_WIDTH-1:0] backpressure_cycle_count_gray_sync2;
    (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
    reg [COUNTER_WIDTH-1:0] source_protocol_violation_count_gray_sync1;
    (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
    reg [COUNTER_WIDTH-1:0] source_protocol_violation_count_gray_sync2;
    (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
    reg [COUNTER_WIDTH-1:0] source_drop_count_gray_sync1;
    (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
    reg [COUNTER_WIDTH-1:0] source_drop_count_gray_sync2;
    (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
    reg [COUNTER_WIDTH-1:0] fifo_overflow_attempt_count_gray_sync1;
    (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
    reg [COUNTER_WIDTH-1:0] fifo_overflow_attempt_count_gray_sync2;
    (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
    reg [COUNTER_WIDTH-1:0] counter_saturation_event_count_gray_sync1;
    (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
    reg [COUNTER_WIDTH-1:0] counter_saturation_event_count_gray_sync2;
    (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
    reg [SEQUENCE_WIDTH-1:0] last_source_sequence_gray_sync1;
    (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
    reg [SEQUENCE_WIDTH-1:0] last_source_sequence_gray_sync2;

    function [COUNTER_WIDTH-1:0] counter_gray_to_binary;
        input [COUNTER_WIDTH-1:0] value;
        integer index;
        begin
            counter_gray_to_binary[COUNTER_WIDTH-1] = value[COUNTER_WIDTH-1];
            for (index = COUNTER_WIDTH-2; index >= 0; index = index - 1)
                counter_gray_to_binary[index] =
                    counter_gray_to_binary[index+1] ^ value[index];
        end
    endfunction

    function [SEQUENCE_WIDTH-1:0] sequence_gray_to_binary;
        input [SEQUENCE_WIDTH-1:0] value;
        integer index;
        begin
            sequence_gray_to_binary[SEQUENCE_WIDTH-1] = value[SEQUENCE_WIDTH-1];
            for (index = SEQUENCE_WIDTH-2; index >= 0; index = index - 1)
                sequence_gray_to_binary[index] =
                    sequence_gray_to_binary[index+1] ^ value[index];
        end
    endfunction

    generate
        if (SEQUENCE_WIDTH < 16) begin : g_invalid_sequence_width
            STAGE2E_PARAMETER_ERROR_SEQUENCE_WIDTH_MUST_BE_AT_LEAST_16
                u_parameter_error();
        end
        if (COUNTER_WIDTH < 2) begin : g_invalid_counter_width
            STAGE2E_PARAMETER_ERROR_COUNTER_WIDTH_MUST_BE_AT_LEAST_2
                u_parameter_error();
        end
    endgenerate

    always @(posedge dst_clk or negedge dst_rst_n) begin
        if (!dst_rst_n) begin
            source_accept_count_gray_sync1 <= {COUNTER_WIDTH{1'b0}};
            source_accept_count_gray_sync2 <= {COUNTER_WIDTH{1'b0}};
            backpressure_cycle_count_gray_sync1 <= {COUNTER_WIDTH{1'b0}};
            backpressure_cycle_count_gray_sync2 <= {COUNTER_WIDTH{1'b0}};
            source_protocol_violation_count_gray_sync1 <= {COUNTER_WIDTH{1'b0}};
            source_protocol_violation_count_gray_sync2 <= {COUNTER_WIDTH{1'b0}};
            source_drop_count_gray_sync1 <= {COUNTER_WIDTH{1'b0}};
            source_drop_count_gray_sync2 <= {COUNTER_WIDTH{1'b0}};
            fifo_overflow_attempt_count_gray_sync1 <= {COUNTER_WIDTH{1'b0}};
            fifo_overflow_attempt_count_gray_sync2 <= {COUNTER_WIDTH{1'b0}};
            counter_saturation_event_count_gray_sync1 <= {COUNTER_WIDTH{1'b0}};
            counter_saturation_event_count_gray_sync2 <= {COUNTER_WIDTH{1'b0}};
            last_source_sequence_gray_sync1 <= {SEQUENCE_WIDTH{1'b0}};
            last_source_sequence_gray_sync2 <= {SEQUENCE_WIDTH{1'b0}};
        end else begin
            source_accept_count_gray_sync1 <= source_accept_count_gray;
            source_accept_count_gray_sync2 <= source_accept_count_gray_sync1;
            backpressure_cycle_count_gray_sync1 <= backpressure_cycle_count_gray;
            backpressure_cycle_count_gray_sync2 <= backpressure_cycle_count_gray_sync1;
            source_protocol_violation_count_gray_sync1 <=
                source_protocol_violation_count_gray;
            source_protocol_violation_count_gray_sync2 <=
                source_protocol_violation_count_gray_sync1;
            source_drop_count_gray_sync1 <= source_drop_count_gray;
            source_drop_count_gray_sync2 <= source_drop_count_gray_sync1;
            fifo_overflow_attempt_count_gray_sync1 <=
                fifo_overflow_attempt_count_gray;
            fifo_overflow_attempt_count_gray_sync2 <=
                fifo_overflow_attempt_count_gray_sync1;
            counter_saturation_event_count_gray_sync1 <=
                counter_saturation_event_count_gray;
            counter_saturation_event_count_gray_sync2 <=
                counter_saturation_event_count_gray_sync1;
            last_source_sequence_gray_sync1 <= last_source_sequence_gray;
            last_source_sequence_gray_sync2 <= last_source_sequence_gray_sync1;
        end
    end

    assign source_accept_count =
        counter_gray_to_binary(source_accept_count_gray_sync2);
    assign backpressure_cycle_count =
        counter_gray_to_binary(backpressure_cycle_count_gray_sync2);
    assign source_protocol_violation_count =
        counter_gray_to_binary(source_protocol_violation_count_gray_sync2);
    assign source_drop_count =
        counter_gray_to_binary(source_drop_count_gray_sync2);
    assign fifo_overflow_attempt_count =
        counter_gray_to_binary(fifo_overflow_attempt_count_gray_sync2);
    assign counter_saturation_event_count =
        counter_gray_to_binary(counter_saturation_event_count_gray_sync2);
    assign last_source_sequence =
        sequence_gray_to_binary(last_source_sequence_gray_sync2);
endmodule
