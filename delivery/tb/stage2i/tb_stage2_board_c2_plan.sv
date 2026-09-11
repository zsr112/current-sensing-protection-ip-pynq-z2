`timescale 1ns/1ps
module tb_stage2_board_c2_plan;
    reg clk = 0, rst_n = 1, sample_valid = 0, clear_fault = 0;
    reg [11:0] ch1 = 0, ch2 = 0;
    reg [31:0] seq = 0;
    wire [5:0] first_bitmap, live_bitmap, seen_bitmap;
    wire [7:0] first_code;
    wire [3:0] state;
    integer fd, parsed, op, a, b, c, d, n, checks = 0;
    reg [8191:0] vector_path;
    always #5 clk = ~clk;
    stage2g_protection_core #(.CNT_WIDTH(16), .HEALTH_CNT_WIDTH(8)) dut (
        .clk(clk), .rst_n(rst_n), .sample_valid(sample_valid), .sample_sequence(seq),
        .sample_source_integrity_clean(1'b1), .sample_destination_integrity_clean(1'b1),
        .pwm_enable(1'b0), .clear_fault(clear_fault), .i_ch1(ch1), .i_ch2(ch2),
        .th_oc_ch1(12'd3000), .th_oc_ch2(12'd3000), .th_diff(12'd200),
        .th_open(12'd0), .th_sat(12'd4095), .th_stuck_delta(12'd0), .th_persist(8'd255),
        .period(16'd1000), .duty(16'd500), .first_fault_bitmap(first_bitmap),
        .live_fault_bitmap(live_bitmap), .fault_seen_bitmap(seen_bitmap),
        .first_fault_code(first_code), .fsm_state(state)
    );
    initial begin
        if (!$value$plusargs("vectors=%s", vector_path)) $fatal(1, "Missing vectors");
        fd = $fopen(vector_path, "r");
        if (!fd) $fatal(1, "Cannot open vectors");
        #1 rst_n = 0;
        repeat (5) @(negedge clk);
        rst_n = 1;
        while (!$feof(fd)) begin
            parsed = $fscanf(fd, "%d %d %d %d %d\n", op, a, b, c, d);
            if (parsed != 5) $fatal(1, "Invalid vector");
            case (op)
                0: begin
                    for (n = 0; n < c; n = n + 1) begin
                        @(negedge clk);
                        sample_valid = 1; ch1 = a; ch2 = b;
                        @(negedge clk);
                        sample_valid = 0; seq = seq + 1;
                        repeat (5) @(negedge clk);
                    end
                end
                1: begin
                    @(negedge clk); clear_fault = 1;
                    @(negedge clk); clear_fault = 0;
                    repeat (5) @(negedge clk);
                end
                2: begin
                    if (first_bitmap !== a[5:0] || live_bitmap !== b[5:0] ||
                        first_code !== c[7:0] || state !== d[3:0])
                        $fatal(1, "check=%0d first=%0d live=%0d code=%0d state=%0d expected=%0d/%0d/%0d/%0d",
                               checks, first_bitmap, live_bitmap, first_code, state, a, b, c, d);
                    checks = checks + 1;
                end
                default: $fatal(1, "Unknown vector opcode");
            endcase
        end
        $fclose(fd);
        $display("C2_PROTECTION_PLAN_RTL=PASS checks=%0d samples=%0d", checks, seq);
        $finish;
    end
endmodule
