module stage2i_b2_ready_aware_stimulus (
    input  wire        aclk,
    input  wire        aclk_aresetn,
    input  wire        adc_src_clk,
    input  wire        adc_src_aresetn,
    input  wire [31:0] control_word_aclk,
    output wire [31:0] status_word_aclk,

    output wire        sample_valid,
    input  wire        sample_ready,
    output wire [11:0] sample_ch1,
    output wire [11:0] sample_ch2,

    output wire        producer_active,
    output wire [6:0]  producer_remaining,
    output wire        producer_accept,
    output wire        command_pending_src
);
    // control_word_aclk[11:0]  = channel 1 raw sample
    // control_word_aclk[23:12] = channel 2 raw sample
    // control_word_aclk[30:24] = bounded burst count (0..127)
    // control_word_aclk[31]    = command epoch, toggled once per command

    (* KEEP = "TRUE" *) reg [30:0] command_hold_aclk;
    (* KEEP = "TRUE" *) reg        request_toggle_aclk;
    reg command_overwrite_error_aclk;

    (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
    reg request_toggle_sync1_src;
    (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
    reg request_toggle_sync2_src;

    (* KEEP = "TRUE" *) reg [30:0] command_capture_src;
    reg command_capture_pending_src;
    reg request_toggle_seen_src;
    (* KEEP = "TRUE" *) reg ack_toggle_src;

    reg        sample_valid_reg;
    reg [11:0] sample_ch1_reg;
    reg [11:0] sample_ch2_reg;
    (* KEEP = "TRUE" *) reg producer_active_reg;
    reg [6:0]  producer_remaining_reg;
    reg [7:0]  accepted_count_src;
    (* KEEP = "TRUE" *) reg [7:0] accepted_count_gray_src;
    (* KEEP = "TRUE" *) reg [6:0] remaining_gray_src;

    (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
    reg ack_toggle_sync1_aclk;
    (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
    reg ack_toggle_sync2_aclk;
    (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
    reg producer_active_sync1_aclk;
    (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
    reg producer_active_sync2_aclk;
    (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
    reg [7:0] accepted_count_gray_sync1_aclk;
    (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
    reg [7:0] accepted_count_gray_sync2_aclk;
    (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
    reg [6:0] remaining_gray_sync1_aclk;
    (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
    reg [6:0] remaining_gray_sync2_aclk;

    wire command_pending_aclk =
        request_toggle_aclk != ack_toggle_sync2_aclk;

    function automatic [7:0] binary_to_gray8(input [7:0] value);
        binary_to_gray8 = (value >> 1) ^ value;
    endfunction

    function automatic [6:0] binary_to_gray7(input [6:0] value);
        binary_to_gray7 = (value >> 1) ^ value;
    endfunction

    function automatic [7:0] gray_to_binary8(input [7:0] value);
        integer index;
        begin
            gray_to_binary8[7] = value[7];
            for (index = 6; index >= 0; index = index - 1)
                gray_to_binary8[index] =
                    gray_to_binary8[index + 1] ^ value[index];
        end
    endfunction

    function automatic [6:0] gray_to_binary7(input [6:0] value);
        integer index;
        begin
            gray_to_binary7[6] = value[6];
            for (index = 5; index >= 0; index = index - 1)
                gray_to_binary7[index] =
                    gray_to_binary7[index + 1] ^ value[index];
        end
    endfunction

    // The ACLK side captures a complete command only when the prior request
    // has been acknowledged. The holding bus is then immutable until the
    // source-domain capture and acknowledgment complete.
    always @(posedge aclk or negedge aclk_aresetn) begin
        if (!aclk_aresetn) begin
            command_hold_aclk <= 31'd0;
            request_toggle_aclk <= 1'b0;
            command_overwrite_error_aclk <= 1'b0;
        end else begin
            if (command_pending_aclk &&
                control_word_aclk[31] != request_toggle_aclk)
                command_overwrite_error_aclk <= 1'b1;

            if (!command_pending_aclk &&
                control_word_aclk[31] != request_toggle_aclk) begin
                command_hold_aclk <= control_word_aclk[30:0];
                request_toggle_aclk <= control_word_aclk[31];
            end
        end
    end

    always @(posedge adc_src_clk or negedge adc_src_aresetn) begin
        if (!adc_src_aresetn) begin
            request_toggle_sync1_src <= 1'b0;
            request_toggle_sync2_src <= 1'b0;
        end else begin
            request_toggle_sync1_src <= request_toggle_aclk;
            request_toggle_sync2_src <= request_toggle_sync1_src;
        end
    end

    // A request is detected only after the toggle synchronizer. The bundled
    // command bus has therefore been stable for multiple source cycles before
    // this dedicated capture register samples it. A second source cycle loads
    // the producer and returns the acknowledgment.
    always @(posedge adc_src_clk or negedge adc_src_aresetn) begin
        if (!adc_src_aresetn) begin
            command_capture_src <= 31'd0;
            command_capture_pending_src <= 1'b0;
            request_toggle_seen_src <= 1'b0;
            ack_toggle_src <= 1'b0;
            sample_valid_reg <= 1'b0;
            sample_ch1_reg <= 12'd0;
            sample_ch2_reg <= 12'd0;
            producer_active_reg <= 1'b0;
            producer_remaining_reg <= 7'd0;
            accepted_count_src <= 8'd0;
            accepted_count_gray_src <= 8'd0;
            remaining_gray_src <= 7'd0;
        end else begin
            if (!producer_active_reg && !command_capture_pending_src &&
                request_toggle_sync2_src != request_toggle_seen_src) begin
                command_capture_src <= command_hold_aclk;
                command_capture_pending_src <= 1'b1;
            end else if (command_capture_pending_src) begin
                sample_ch1_reg <= command_capture_src[11:0];
                sample_ch2_reg <= command_capture_src[23:12];
                producer_remaining_reg <= command_capture_src[30:24];
                remaining_gray_src <=
                    binary_to_gray7(command_capture_src[30:24]);
                sample_valid_reg <= |command_capture_src[30:24];
                producer_active_reg <= |command_capture_src[30:24];
                request_toggle_seen_src <= request_toggle_sync2_src;
                ack_toggle_src <= request_toggle_sync2_src;
                command_capture_pending_src <= 1'b0;
            end else if (sample_valid_reg && sample_ready) begin
                accepted_count_src <= accepted_count_src + 1'b1;
                accepted_count_gray_src <=
                    binary_to_gray8(accepted_count_src + 1'b1);
                if (producer_remaining_reg == 7'd1) begin
                    producer_remaining_reg <= 7'd0;
                    remaining_gray_src <= 7'd0;
                    sample_valid_reg <= 1'b0;
                    producer_active_reg <= 1'b0;
                end else begin
                    producer_remaining_reg <=
                        producer_remaining_reg - 1'b1;
                    remaining_gray_src <= binary_to_gray7(
                        producer_remaining_reg - 1'b1);
                end
            end
        end
    end

    always @(posedge aclk or negedge aclk_aresetn) begin
        if (!aclk_aresetn) begin
            ack_toggle_sync1_aclk <= 1'b0;
            ack_toggle_sync2_aclk <= 1'b0;
            producer_active_sync1_aclk <= 1'b0;
            producer_active_sync2_aclk <= 1'b0;
            accepted_count_gray_sync1_aclk <= 8'd0;
            accepted_count_gray_sync2_aclk <= 8'd0;
            remaining_gray_sync1_aclk <= 7'd0;
            remaining_gray_sync2_aclk <= 7'd0;
        end else begin
            ack_toggle_sync1_aclk <= ack_toggle_src;
            ack_toggle_sync2_aclk <= ack_toggle_sync1_aclk;
            producer_active_sync1_aclk <= producer_active_reg;
            producer_active_sync2_aclk <= producer_active_sync1_aclk;
            accepted_count_gray_sync1_aclk <= accepted_count_gray_src;
            accepted_count_gray_sync2_aclk <=
                accepted_count_gray_sync1_aclk;
            remaining_gray_sync1_aclk <= remaining_gray_src;
            remaining_gray_sync2_aclk <= remaining_gray_sync1_aclk;
        end
    end

    // status_word_aclk is read through AXI GPIO channel 2.
    // [31:24] profile marker, [18:11] accepted count, [10:4] remaining,
    // [3] overwrite error, [2] request pending, [1] active, [0] ack epoch.
    assign status_word_aclk = {
        8'hB2,
        5'd0,
        gray_to_binary8(accepted_count_gray_sync2_aclk),
        gray_to_binary7(remaining_gray_sync2_aclk),
        command_overwrite_error_aclk,
        command_pending_aclk,
        producer_active_sync2_aclk,
        ack_toggle_sync2_aclk
    };

    assign sample_valid = sample_valid_reg;
    assign sample_ch1 = sample_ch1_reg;
    assign sample_ch2 = sample_ch2_reg;
    assign producer_active = producer_active_reg;
    assign producer_remaining = producer_remaining_reg;
    assign producer_accept = sample_valid_reg && sample_ready;
    assign command_pending_src =
        command_capture_pending_src ||
        (request_toggle_sync2_src != request_toggle_seen_src);
endmodule
