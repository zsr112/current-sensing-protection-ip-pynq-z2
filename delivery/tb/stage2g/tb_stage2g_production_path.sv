`timescale 1ns/1ps
`include "protection_register_map.svh"

module tb_stage2g_production_path #(
    parameter OBS_SEQUENCE_WIDTH = 32
);
    localparam DATA_WIDTH = 12;
    localparam AXI_ADDR_WIDTH = 8;

    reg ACLK = 1'b0;
    reg adc_src_clk = 1'b0;
    always #5 ACLK = ~ACLK;
    always #3.5 adc_src_clk = ~adc_src_clk;

    reg ARESETN = 1'b0;
    reg adc_sample_valid = 1'b0;
    wire adc_sample_ready;
    reg [DATA_WIDTH-1:0] adc_sample_ch1 = 12'd0;
    reg [DATA_WIDTH-1:0] adc_sample_ch2 = 12'd0;

    reg [AXI_ADDR_WIDTH-1:0] awaddr = 8'd0;
    reg awvalid = 1'b0;
    wire awready;
    reg [31:0] wdata = 32'd0;
    reg [3:0] wstrb = 4'd0;
    reg wvalid = 1'b0;
    wire wready;
    wire [1:0] bresp;
    wire bvalid;
    reg bready = 1'b0;
    reg [AXI_ADDR_WIDTH-1:0] araddr = 8'd0;
    reg arvalid = 1'b0;
    wire arready;
    wire [31:0] rdata;
    wire [1:0] rresp;
    wire rvalid;
    reg rready = 1'b0;

    wire pwm_raw;
    wire pwm_out;
    wire fault_valid;
    wire fault_latched;
    wire [7:0] fault_code;
    wire [7:0] fault_code_latched;
    wire [3:0] fsm_state;

    integer failures = 0;
    integer guard;
    integer snapshot_file;
    reg [8*1024-1:0] snapshot_path;
    reg [31:0] snapshot_ctrl;
    reg [31:0] snapshot_status;
    reg [31:0] snapshot_fault_code;
    reg [31:0] snapshot_i_ch1;
    reg [31:0] snapshot_i_ch2;
    integer production_unsafe_pulse_count = 0;
    integer pwm_before_high_count = 0;
    integer pwm_before_low_count = 0;
    integer pwm_reset_wait_raw_high_count = 0;
    integer pwm_reset_wait_raw_low_count = 0;
    integer pwm_after_high_count = 0;
    integer pwm_after_low_count = 0;
    reg monitor_pwm_before_fault = 1'b0;
    reg monitor_reset_wait_reenabled = 1'b0;
    reg monitor_pwm_after_armed = 1'b0;
    reg [31:0] abi_read_value;
    reg [31:0] identity_after_healthy;
    reg [31:0] identity_after_fault;
    reg [31:0] identity_after_clean_update;
    reg [31:0] identity_after_nonclean;
    reg [31:0] forced_identity_expected;
    reg [OBS_SEQUENCE_WIDTH-1:0] forced_identity_source;
    reg [7:0] abi_registers [0:7];
    reg [31:0] abi_reset_values [0:7];
    integer abi_register_index;
    integer abi_strobe;


    protection_ip_top_async_adc_axi_lite #(
        .OBS_SEQUENCE_WIDTH(OBS_SEQUENCE_WIDTH)
    ) dut (
        .ACLK(ACLK), .ARESETN(ARESETN), .adc_src_clk(adc_src_clk),
        .adc_sample_valid(adc_sample_valid),
        .adc_sample_ready(adc_sample_ready),
        .adc_sample_ch1(adc_sample_ch1),
        .adc_sample_ch2(adc_sample_ch2),
        .S_AXI_AWADDR(awaddr), .S_AXI_AWVALID(awvalid),
        .S_AXI_AWREADY(awready), .S_AXI_WDATA(wdata),
        .S_AXI_WSTRB(wstrb), .S_AXI_WVALID(wvalid),
        .S_AXI_WREADY(wready), .S_AXI_BRESP(bresp),
        .S_AXI_BVALID(bvalid), .S_AXI_BREADY(bready),
        .S_AXI_ARADDR(araddr), .S_AXI_ARVALID(arvalid),
        .S_AXI_ARREADY(arready), .S_AXI_RDATA(rdata),
        .S_AXI_RRESP(rresp), .S_AXI_RVALID(rvalid),
        .S_AXI_RREADY(rready), .pwm_raw(pwm_raw), .pwm_out(pwm_out),
        .fault_valid(fault_valid), .fault_latched(fault_latched),
        .fault_code(fault_code), .fault_code_latched(fault_code_latched),
        .fsm_state(fsm_state)
    );

    // Sample every production-policy ACLK edge after registered state settles.
    // Any high output outside ARMED is an unsafe pulse, including the fault,
    // clear-resolution, and RESET_WAIT transition edges themselves.
    always @(posedge ACLK) begin
        #1;
        if (ARESETN && (fsm_state != 4'd0) && (pwm_out !== 1'b0))
            production_unsafe_pulse_count =
                production_unsafe_pulse_count + 1;
        if (monitor_pwm_before_fault) begin
            if (pwm_out === 1'b1)
                pwm_before_high_count = pwm_before_high_count + 1;
            if (pwm_out === 1'b0)
                pwm_before_low_count = pwm_before_low_count + 1;
        end
        if (monitor_reset_wait_reenabled) begin
            if (pwm_raw === 1'b1)
                pwm_reset_wait_raw_high_count =
                    pwm_reset_wait_raw_high_count + 1;
            if (pwm_raw === 1'b0)
                pwm_reset_wait_raw_low_count =
                    pwm_reset_wait_raw_low_count + 1;
            if (pwm_out !== 1'b0)
                production_unsafe_pulse_count =
                    production_unsafe_pulse_count + 1;
        end
        if (monitor_pwm_after_armed) begin
            if (pwm_out === 1'b1)
                pwm_after_high_count = pwm_after_high_count + 1;
            if (pwm_out === 1'b0)
                pwm_after_low_count = pwm_after_low_count + 1;
        end
    end

    task automatic fail;
        input [8*100-1:0] message;
        begin
            $display("STAGE2G PRODUCTION FAILED: %0s", message);
            failures = failures + 1;
        end
    endtask

    task automatic wait_aclks;
        input integer count;
        integer index;
        begin
            for (index = 0; index < count; index = index + 1)
                @(posedge ACLK);
            #1;
        end
    endtask

    task automatic axi_write;
        input [7:0] address;
        input [31:0] value;
        input [3:0] byte_enable;
        begin
            @(negedge ACLK);
            awaddr = address;
            awvalid = 1'b1;
            wdata = value;
            wstrb = byte_enable;
            wvalid = 1'b1;
            guard = 0;
            while (!(awready && wready)) begin
                @(posedge ACLK);
                guard = guard + 1;
                if (guard > 40) begin
                    fail("AXI write address/data timeout");
                    disable axi_write;
                end
            end
            @(posedge ACLK);
            #1;
            awvalid = 1'b0;
            wvalid = 1'b0;
            wstrb = 4'd0;
            bready = 1'b1;
            guard = 0;
            while (!bvalid) begin
                @(posedge ACLK);
                #1;
                guard = guard + 1;
                if (guard > 40) begin
                    fail("AXI write response timeout");
                    disable axi_write;
                end
            end
            if (bresp !== 2'b00)
                fail("AXI write response not OKAY");
            @(posedge ACLK);
            #1;
            bready = 1'b0;
        end
    endtask

    task automatic send_sample;
        input [DATA_WIDTH-1:0] ch1;
        input [DATA_WIDTH-1:0] ch2;
        begin
            @(negedge adc_src_clk);
            adc_sample_ch1 = ch1;
            adc_sample_ch2 = ch2;
            adc_sample_valid = 1'b1;
            guard = 0;
            while (!adc_sample_ready) begin
                @(posedge adc_src_clk);
                guard = guard + 1;
                if (guard > 80) begin
                    fail("ADC source acceptance timeout");
                    disable send_sample;
                end
            end
            @(posedge adc_src_clk);
            #1;
            adc_sample_valid = 1'b0;
        end
    endtask

    task automatic send_dirty_sample;
        input [DATA_WIDTH-1:0] initial_ch1;
        input [DATA_WIDTH-1:0] initial_ch2;
        input [DATA_WIDTH-1:0] accepted_ch1;
        input [DATA_WIDTH-1:0] accepted_ch2;
        begin
            force dut.u_adc_sample_cdc_bridge.src_sample_ready = 1'b0;
            @(negedge adc_src_clk);
            adc_sample_ch1 = initial_ch1;
            adc_sample_ch2 = initial_ch2;
            adc_sample_valid = 1'b1;
            wait_aclks(2);
            @(posedge adc_src_clk);
            adc_sample_ch1 = accepted_ch1;
            adc_sample_ch2 = accepted_ch2;
            @(negedge adc_src_clk);
            release dut.u_adc_sample_cdc_bridge.src_sample_ready;
            guard = 0;
            while (!adc_sample_ready) begin
                @(posedge adc_src_clk);
                guard = guard + 1;
                if (guard > 80) begin
                    fail("dirty source acceptance timeout");
                    adc_sample_valid = 1'b0;
                    disable send_dirty_sample;
                end
            end
            @(posedge adc_src_clk);
            #1;
            adc_sample_valid = 1'b0;
        end
    endtask

    task automatic axi_read;
        input [7:0] address;
        output [31:0] value;
        begin
            @(negedge ACLK);
            araddr = address;
            arvalid = 1'b1;
            rready = 1'b1;
            guard = 0;
            while (!arready) begin
                @(posedge ACLK);
                #1;
                guard = guard + 1;
                if (guard > 40) begin
                    fail("AXI read address timeout");
                    disable axi_read;
                end
            end
            @(posedge ACLK);
            #1;
            arvalid = 1'b0;
            guard = 0;
            while (!rvalid) begin
                @(posedge ACLK);
                #1;
                guard = guard + 1;
                if (guard > 40) begin
                    fail("AXI read response timeout");
                    disable axi_read;
                end
            end
            if (rresp !== 2'b00)
                fail("AXI read response not OKAY");
            value = rdata;
            @(posedge ACLK);
            #1;
            rready = 1'b0;
        end
    endtask

    task automatic expect_axi_read;
        input [8*96-1:0] label;
        input [7:0] address;
        input [31:0] expected;
        begin
            axi_read(address, abi_read_value);
            if (abi_read_value !== expected) begin
                $display(
                    "ABI READ MISMATCH %0s address=0x%02h actual=0x%08h expected=0x%08h",
                    label, address, abi_read_value, expected);
                fail(label);
            end
        end
    endtask

    task automatic capture_snapshot;
        input [8*64-1:0] label;
        begin
            axi_read(8'h00, snapshot_ctrl);
            axi_read(8'h04, snapshot_status);
            axi_read(8'h08, snapshot_fault_code);
            axi_read(8'h0c, snapshot_i_ch1);
            axi_read(8'h10, snapshot_i_ch2);
            $fdisplay(snapshot_file, "%0s\t%08x\t%08x\t%08x\t%08x\t%08x\t%0d\t%0d",
                      label, snapshot_ctrl, snapshot_status,
                      snapshot_fault_code, snapshot_i_ch1, snapshot_i_ch2,
                      fsm_state, pwm_out);
        end
    endtask

    task automatic expect_state;
        input [3:0] expected;
        input [8*80-1:0] label;
        begin
            if (fsm_state !== expected) begin
                $display("STATE MISMATCH %0s actual=%0d expected=%0d",
                         label, fsm_state, expected);
                fail(label);
            end
        end
    endtask

    initial begin
        if (!$value$plusargs("RECOVERY_SNAPSHOTS=%s", snapshot_path))
            snapshot_path = "recovery_snapshots.tsv";
        snapshot_file = $fopen(snapshot_path, "w");
        if (snapshot_file == 0) begin
            $display("STAGE2G PRODUCTION FAILED: snapshot file open");
            $fatal(2);
        end
        $fdisplay(snapshot_file,
                  "LABEL\tCTRL\tSTATUS\tFAULT_CODE\tI_CH1\tI_CH2\tFSM_STATE\tPWM_OUT");

        // Wait through both local reset-release synchronizers.
        wait_aclks(4);
        ARESETN = 1'b1;
        wait_aclks(8);

        expect_state(4'd2, "reset release without sample remains RESET_WAIT");
        expect_axi_read(
            "explicit ABI version", `REG_REGISTER_MAP_VERSION,
            `REGISTER_MAP_VERSION_VALUE);
        expect_axi_read(
            "explicit capabilities 0", `REG_CAPABILITIES_0,
            `CAPABILITIES_0_ABI_1_1_VALUE);
        expect_axi_read(
            "parameterized capabilities 1", `REG_CAPABILITIES_1,
            `CAPABILITIES_1_VALUE(OBS_SEQUENCE_WIDTH));
        expect_axi_read(
            "startup RESET_WAIT policy", `REG_POLICY_STATUS,
            `POLICY_STATUS_RESET_WAIT_STATE);
        expect_axi_read(
            "identity reset", `REG_POLICY_EVALUATION_SEQUENCE, 32'd0);

        abi_registers[0] = `REG_REGISTER_MAP_VERSION;
        abi_registers[1] = `REG_CAPABILITIES_0;
        abi_registers[2] = `REG_CAPABILITIES_1;
        abi_registers[3] = `REG_POLICY_STATUS;
        abi_registers[4] = `REG_FIRST_FAULT_BITMAP;
        abi_registers[5] = `REG_LIVE_FAULT_BITMAP;
        abi_registers[6] = `REG_FAULT_SEEN_BITMAP;
        abi_registers[7] = `REG_POLICY_EVALUATION_SEQUENCE;
        abi_reset_values[0] = `REGISTER_MAP_VERSION_VALUE;
        abi_reset_values[1] = `CAPABILITIES_0_ABI_1_1_VALUE;
        abi_reset_values[2] = `CAPABILITIES_1_VALUE(OBS_SEQUENCE_WIDTH);
        abi_reset_values[3] = `POLICY_STATUS_RESET_WAIT_STATE;
        abi_reset_values[4] = 32'd0;
        abi_reset_values[5] = 32'd0;
        abi_reset_values[6] = 32'd0;
        abi_reset_values[7] = 32'd0;
        for (abi_register_index = 0; abi_register_index < 8;
             abi_register_index = abi_register_index + 1) begin
            for (abi_strobe = 0; abi_strobe < 16;
                 abi_strobe = abi_strobe + 1) begin
                axi_write(
                    abi_registers[abi_register_index],
                    32'hFFFF_FFFF,
                    abi_strobe[3:0]);
                expect_axi_read(
                    "ABI RO write has no effect",
                    abi_registers[abi_register_index],
                    abi_reset_values[abi_register_index]);
            end
        end
        expect_axi_read("undefined 0x64 read", 8'h64, 32'd0);
        expect_axi_read("undefined 0x8C read", 8'h8C, 32'd0);
        axi_write(8'h64, 32'hFFFF_FFFF, 4'hF);
        axi_write(8'h8C, 32'hFFFF_FFFF, 4'hF);
        expect_axi_read("undefined 0x64 write ignored", 8'h64, 32'd0);
        expect_axi_read("undefined 0x8C write ignored", 8'h8C, 32'd0);

        // Configure the raw protection domain and enable the normal PWM path
        // through the real AXI-Lite write channel.
        axi_write(8'h14, 32'd1000, 4'b1111);
        axi_write(8'h18, 32'd1000, 4'b1111);
        axi_write(8'h1C, 32'd50, 4'b1111);
        axi_write(8'h20, 32'd8, 4'b1111);
        axi_write(8'h24, 32'd4, 4'b1111);
        axi_write(8'h00, 32'h0000_0001, 4'b1111);

        send_sample(12'd200, 12'd200);
        wait_aclks(30);
        expect_state(4'd0, "production first healthy ARMED");
        expect_axi_read(
            "first healthy ARMED_READY", `REG_POLICY_STATUS,
            `POLICY_STATUS_ARMED_READY);
        axi_read(
            `REG_POLICY_EVALUATION_SEQUENCE, identity_after_healthy);
        wait_aclks(10);
        expect_axi_read(
            "identity holds after healthy idle",
            `REG_POLICY_EVALUATION_SEQUENCE, identity_after_healthy);
        monitor_pwm_before_fault = 1'b1;
        wait_aclks(24);
        monitor_pwm_before_fault = 1'b0;
        if ((pwm_before_high_count == 0) ||
            (pwm_before_low_count == 0))
            fail("production PWM was not visibly active before fault");

        send_sample(12'd3500, 12'd3500);
        wait_aclks(35);
        expect_state(4'd1, "production overcurrent FAULT_LATCHED");
        if (fault_latched !== 1'b1 || fault_code_latched !== 8'h01)
            fail("production first fault status/code");
        if (pwm_out !== 1'b0)
            fail("production safe output was not asserted");
        expect_axi_read(
            "fault policy state", `REG_POLICY_STATUS,
            `POLICY_STATUS_FAULT_LATCHED_STATE);
        expect_axi_read(
            "simultaneous first bitmap", `REG_FIRST_FAULT_BITMAP,
            `FAULT_CAUSE_CH1_OVERCURRENT | `FAULT_CAUSE_CH2_OVERCURRENT);
        expect_axi_read(
            "simultaneous live bitmap", `REG_LIVE_FAULT_BITMAP,
            `FAULT_CAUSE_CH1_OVERCURRENT | `FAULT_CAUSE_CH2_OVERCURRENT);
        expect_axi_read(
            "simultaneous seen bitmap", `REG_FAULT_SEEN_BITMAP,
            `FAULT_CAUSE_CH1_OVERCURRENT | `FAULT_CAUSE_CH2_OVERCURRENT);
        axi_read(`REG_POLICY_EVALUATION_SEQUENCE, identity_after_fault);
        if (identity_after_fault === identity_after_healthy)
            fail("fault retirement identity was not captured");
        capture_snapshot("FAULT_LATCHED");
        if (!snapshot_status[1] || snapshot_fault_code[7:0] != 8'h01)
            fail("AXI first fault status/code");

        // A later clean cause set replaces LIVE, accumulates into SEEN, and
        // leaves FIRST immutable for the active episode.
        send_sample(12'd600, 12'd200);
        wait_aclks(35);
        expect_state(4'd1, "clean mismatch update remains FAULT_LATCHED");
        expect_axi_read(
            "first bitmap immutable", `REG_FIRST_FAULT_BITMAP,
            `FAULT_CAUSE_CH1_OVERCURRENT | `FAULT_CAUSE_CH2_OVERCURRENT);
        expect_axi_read(
            "live bitmap replaces", `REG_LIVE_FAULT_BITMAP,
            `FAULT_CAUSE_SENSOR_MISMATCH_OR_DIFFERENTIAL);
        expect_axi_read(
            "seen bitmap accumulates", `REG_FAULT_SEEN_BITMAP,
            `FAULT_CAUSE_CH1_OVERCURRENT | `FAULT_CAUSE_CH2_OVERCURRENT |
            `FAULT_CAUSE_SENSOR_MISMATCH_OR_DIFFERENTIAL);
        axi_read(
            `REG_POLICY_EVALUATION_SEQUENCE, identity_after_clean_update);
        if (identity_after_clean_update === identity_after_fault)
            fail("clean in-episode retirement identity was not captured");
        wait_aclks(10);
        expect_axi_read(
            "clean update identity holds during idle",
            `REG_POLICY_EVALUATION_SEQUENCE, identity_after_clean_update);

        send_dirty_sample(12'd600, 12'd200, 12'd200, 12'd200);
        wait_aclks(40);
        expect_state(4'd1, "nonclean in-episode retirement is ignored by policy");
        axi_read(`REG_POLICY_EVALUATION_SEQUENCE, identity_after_nonclean);
        if (identity_after_nonclean === identity_after_clean_update)
            fail("nonclean valid retirement identity was not captured");
        expect_axi_read(
            "nonclean leaves first bitmap", `REG_FIRST_FAULT_BITMAP,
            `FAULT_CAUSE_CH1_OVERCURRENT | `FAULT_CAUSE_CH2_OVERCURRENT);
        expect_axi_read(
            "nonclean leaves live bitmap", `REG_LIVE_FAULT_BITMAP,
            `FAULT_CAUSE_SENSOR_MISMATCH_OR_DIFFERENTIAL);
        expect_axi_read(
            "nonclean leaves seen bitmap", `REG_FAULT_SEEN_BITMAP,
            `FAULT_CAUSE_CH1_OVERCURRENT | `FAULT_CAUSE_CH2_OVERCURRENT |
            `FAULT_CAUSE_SENSOR_MISMATCH_OR_DIFFERENTIAL);
        wait_aclks(10);
        expect_axi_read(
            "nonclean identity holds during idle",
            `REG_POLICY_EVALUATION_SEQUENCE, identity_after_nonclean);

        // A real AXI W1P control write requests clear. With no subsequent
        // delivery the request remains fenced and the fault stays safe.
        axi_write(8'h00, 32'h0000_0002, 4'b1111);
        wait_aclks(12);
        expect_state(4'd1, "clear pending with no sample remains latched");
        expect_axi_read(
            "clear pending policy level", `REG_POLICY_STATUS,
            `POLICY_STATUS_FAULT_LATCHED_STATE |
            `POLICY_STATUS_CLEAR_PENDING);
        if (pwm_out !== 1'b0)
            fail("clear pending released production safe output");

        send_sample(12'd200, 12'd200);
        wait_aclks(35);
        expect_state(4'd2, "healthy clear enters RESET_WAIT");
        if (pwm_out !== 1'b0)
            fail("clear resolution released production safe output");
        if (fault_latched !== 1'b1 || fault_code_latched !== 8'h01)
            fail("clear acceptance dropped compatibility status");
        expect_axi_read(
            "post-clear recovery policy", `REG_POLICY_STATUS,
            `POLICY_STATUS_RESET_WAIT_STATE |
            `POLICY_STATUS_POST_CLEAR_RECOVERY_PENDING);
        expect_axi_read(
            "post-clear first bitmap cleared", `REG_FIRST_FAULT_BITMAP,
            32'd0);
        expect_axi_read(
            "post-clear live bitmap cleared", `REG_LIVE_FAULT_BITMAP,
            32'd0);
        expect_axi_read(
            "post-clear seen bitmap cleared", `REG_FAULT_SEEN_BITMAP,
            32'd0);
        capture_snapshot("POST_CLEAR_RESET_WAIT");
        if (!snapshot_status[1] || snapshot_fault_code[7:0] != 8'h01)
            fail("AXI post-clear status/code not retained");

        wait_aclks(24);
        expect_state(4'd2, "no-sample post-clear remains RESET_WAIT");
        axi_read(`REG_POLICY_EVALUATION_SEQUENCE, identity_after_healthy);
        wait_aclks(10);
        expect_axi_read(
            "post-clear identity holds with no sample",
            `REG_POLICY_EVALUATION_SEQUENCE, identity_after_healthy);
        capture_snapshot("NO_SAMPLE_POST_CLEAR");
        if (!snapshot_status[1] || snapshot_fault_code[7:0] != 8'h01)
            fail("no-sample post-clear dropped compatibility status");

        // The accepted payload is healthy but its stalled offer changed.
        // Transaction integrity therefore blocks public recovery completion.
        send_dirty_sample(12'd3500, 12'd3500, 12'd200, 12'd200);
        wait_aclks(40);
        expect_state(4'd2, "nonclean post-clear remains RESET_WAIT");
        expect_axi_read(
            "nonclean post-clear policy", `REG_POLICY_STATUS,
            `POLICY_STATUS_RESET_WAIT_STATE |
            `POLICY_STATUS_POST_CLEAR_RECOVERY_PENDING);
        axi_read(`REG_POLICY_EVALUATION_SEQUENCE, identity_after_nonclean);
        if (identity_after_nonclean === identity_after_healthy)
            fail("nonclean post-clear identity was not captured");
        expect_axi_read(
            "nonclean post-clear first remains zero",
            `REG_FIRST_FAULT_BITMAP, 32'd0);
        expect_axi_read(
            "nonclean post-clear live remains zero",
            `REG_LIVE_FAULT_BITMAP, 32'd0);
        expect_axi_read(
            "nonclean post-clear seen remains zero",
            `REG_FAULT_SEEN_BITMAP, 32'd0);
        capture_snapshot("NONCLEAN_POST_CLEAR");
        if (!snapshot_status[1] || snapshot_fault_code[7:0] != 8'h01)
            fail("nonclean post-clear dropped compatibility status");

        // The W1P clear write also writes CTRL[0]=0. Re-enable PWM while the
        // controller is still RESET_WAIT: pwm_raw must toggle, but the real
        // gated output must remain safe until a later healthy evaluation.
        axi_write(8'h00, 32'h0000_0001, 4'b1111);
        expect_state(4'd2, "PWM re-enable remains RESET_WAIT");
        monitor_reset_wait_reenabled = 1'b1;
        wait_aclks(24);
        monitor_reset_wait_reenabled = 1'b0;
        if ((pwm_reset_wait_raw_high_count == 0) ||
            (pwm_reset_wait_raw_low_count == 0))
            fail("re-enabled PWM raw carrier was not active in RESET_WAIT");
        if (pwm_out !== 1'b0)
            fail("PWM re-enable bypassed RESET_WAIT safe hold");

        // Keep PWM disabled while taking the software recovery snapshot.
        axi_write(8'h00, 32'h0000_0000, 4'b1111);
        send_sample(12'd200, 12'd200);
        wait_aclks(35);
        expect_state(4'd0, "later healthy evaluation arms production");
        expect_axi_read(
            "later healthy ARMED_READY", `REG_POLICY_STATUS,
            `POLICY_STATUS_ARMED_READY);
        capture_snapshot("ARMED_AFTER_LATER_HEALTHY");
        if (snapshot_status[1:0] != 2'b00 ||
            snapshot_fault_code[7:0] != 8'h00)
            fail("later healthy did not clear AXI compatibility status");

        axi_write(8'h00, 32'h0000_0001, 4'b1111);
        monitor_pwm_after_armed = 1'b1;
        wait_aclks(24);
        monitor_pwm_after_armed = 1'b0;
        if ((pwm_after_high_count == 0) || (pwm_after_low_count == 0))
            fail("production PWM activity did not resume after ARMED");

        // A clean fault before healthy re-arm begins a new episode and must
        // replace the retained public code with the new first cause.
        send_sample(12'd3500, 12'd3500);
        wait_aclks(35);
        expect_state(4'd1, "second episode overcurrent fault");
        expect_axi_read(
            "second episode first bitmap", `REG_FIRST_FAULT_BITMAP,
            `FAULT_CAUSE_CH1_OVERCURRENT | `FAULT_CAUSE_CH2_OVERCURRENT);
        if (fault_code_latched !== 8'h01)
            fail("second episode first cause was not overcurrent");
        axi_write(8'h00, 32'h0000_0002, 4'b1111);
        send_sample(12'd200, 12'd200);
        wait_aclks(35);
        expect_state(4'd2, "second clear enters RESET_WAIT");
        expect_axi_read(
            "second post-clear is not ready", `REG_POLICY_STATUS,
            `POLICY_STATUS_RESET_WAIT_STATE |
            `POLICY_STATUS_POST_CLEAR_RECOVERY_PENDING);
        if (fault_latched !== 1'b1 || fault_code_latched !== 8'h01)
            fail("second clear did not retain first cause");

        send_sample(12'd600, 12'd200);
        wait_aclks(35);
        expect_state(4'd1, "new mismatch fault before healthy re-arm");
        expect_axi_read(
            "replacement fault remains not ready", `REG_POLICY_STATUS,
            `POLICY_STATUS_FAULT_LATCHED_STATE);
        expect_axi_read(
            "replacement fault first bitmap", `REG_FIRST_FAULT_BITMAP,
            `FAULT_CAUSE_SENSOR_MISMATCH_OR_DIFFERENTIAL);
        expect_axi_read(
            "replacement fault live bitmap", `REG_LIVE_FAULT_BITMAP,
            `FAULT_CAUSE_SENSOR_MISMATCH_OR_DIFFERENTIAL);
        expect_axi_read(
            "replacement fault seen bitmap", `REG_FAULT_SEEN_BITMAP,
            `FAULT_CAUSE_SENSOR_MISMATCH_OR_DIFFERENTIAL);
        capture_snapshot("POST_CLEAR_NEW_FAULT");
        if (!snapshot_status[1] || snapshot_fault_code[7:0] != 8'h02)
            fail("new pre-arm fault did not replace public code");

        // Return to post-clear RESET_WAIT, then prove reset clears the public
        // compatibility state and recovery-pending boundary.
        axi_write(8'h00, 32'h0000_0002, 4'b1111);
        send_sample(12'd200, 12'd200);
        wait_aclks(35);
        expect_state(4'd2, "new-fault clear enters RESET_WAIT");
        capture_snapshot("PRE_RESET_POST_CLEAR");
        if (!snapshot_status[1] || snapshot_fault_code[7:0] != 8'h02)
            fail("pre-reset compatibility state was not retained");

        ARESETN = 1'b0;
        wait_aclks(5);
        if (fsm_state !== 4'd2)
            fail("reset asserted must not advertise ARMED_READY");
        ARESETN = 1'b1;
        wait_aclks(8);
        expect_state(4'd2, "reset returns to RESET_WAIT");
        expect_axi_read(
            "reset clears diagnostic identity",
            `REG_POLICY_EVALUATION_SEQUENCE, 32'd0);
        expect_axi_read(
            "reset clears first bitmap", `REG_FIRST_FAULT_BITMAP, 32'd0);
        expect_axi_read(
            "reset clears live bitmap", `REG_LIVE_FAULT_BITMAP, 32'd0);
        expect_axi_read(
            "reset clears seen bitmap", `REG_FAULT_SEEN_BITMAP, 32'd0);
        capture_snapshot("RESET_DURING_POST_CLEAR");
        if (snapshot_status[1:0] != 2'b00 ||
            snapshot_fault_code[7:0] != 8'h00)
            fail("reset did not clear compatibility status");

        // Force one valid retirement at the existing Stage 2G-to-register-bank
        // connection to prove zero extension at 16/24 bits and exact capture
        // at 32 bits without requiring billions of source transactions.
        forced_identity_source = 32'hA5C3_FE91;
        forced_identity_expected = 32'hA5C3_FE91;
        if (OBS_SEQUENCE_WIDTH == 16)
            forced_identity_expected = 32'h0000_FE91;
        else if (OBS_SEQUENCE_WIDTH == 24)
            forced_identity_expected = 32'h00C3_FE91;
        force dut.u_destination_axi_lite.u_reg_controlled_top.fault_eval_valid =
            1'b1;
        force dut.u_destination_axi_lite.u_reg_controlled_top.fault_eval_sequence =
            forced_identity_source;
        wait_aclks(1);
        release dut.u_destination_axi_lite.u_reg_controlled_top.fault_eval_valid;
        release dut.u_destination_axi_lite.u_reg_controlled_top.fault_eval_sequence;
        expect_axi_read(
            "parameterized identity capture",
            `REG_POLICY_EVALUATION_SEQUENCE, forced_identity_expected);
        wait_aclks(10);
        expect_axi_read(
            "parameterized identity idle hold",
            `REG_POLICY_EVALUATION_SEQUENCE, forced_identity_expected);

        // A clean fault before any healthy startup evaluation must remain not
        // ready and begin a normal internal episode.
        send_sample(12'd600, 12'd200);
        wait_aclks(35);
        expect_state(4'd1, "startup fault remains not ready");
        expect_axi_read(
            "startup fault policy", `REG_POLICY_STATUS,
            `POLICY_STATUS_FAULT_LATCHED_STATE);

        if (production_unsafe_pulse_count != 0)
            fail("production unsafe pulse observed outside ARMED");

        $fclose(snapshot_file);
        if (failures != 0) begin
            $display("STAGE2G_PRODUCTION_PATH=FAIL_%0d", failures);
            $fatal(1);
        end
        $display("STAGE2G_PRODUCTION_PATH=PASS");
        $display("PRODUCTION_W1P_CLEAR=PASS");
        $display("FIFO_CARRIED_SOURCE_INTEGRITY=PASS");
        $display("SAFE_OUTPUT_PRODUCTION=PASS");
        $display("PRODUCTION_SAFE_HOLD=PASS");
        $display("PRODUCTION_SAFE_RELEASE_AFTER_LATER_HEALTHY=PASS");
        $display("STATUS_FAULT_LATCHED_DURING_POST_CLEAR_RESET_WAIT=1");
        $display("FAULT_CODE_DURING_POST_CLEAR_RESET_WAIT=RETAIN_PRIOR_FIRST_CAUSE");
        $display("LATER_HEALTHY_CLEARS_COMPATIBILITY_STATUS=PASS");
        $display("POST_CLEAR_FAULT_REPLACES_WITH_NEW_FIRST_CAUSE=PASS");
        $display("RESET_CLEARS_COMPATIBILITY_STATUS=PASS");
        $display("ABI_1_1_READINESS_MATRIX=PASS");
        $display("ABI_1_1_BITMAP_MATRIX=PASS");
        $display("ABI_1_1_POLICY_IDENTITY_MATRIX=PASS");
        $display("ABI_1_1_DISCOVERY_CAPABILITY_MATRIX=PASS");
        $display("ABI_1_1_ACCESS_MATRIX=PASS");
        $display("ABI_1_1_SEQUENCE_WIDTH=%0d", OBS_SEQUENCE_WIDTH);
        $display("PRODUCTION_UNSAFE_PULSE_COUNT=%0d",
                 production_unsafe_pulse_count);
        $finish;
    end

endmodule

module tb_stage2h_abi_1_1_width16;
    tb_stage2g_production_path #(.OBS_SEQUENCE_WIDTH(16)) u_matrix();
endmodule

module tb_stage2h_abi_1_1_width24;
    tb_stage2g_production_path #(.OBS_SEQUENCE_WIDTH(24)) u_matrix();
endmodule

module tb_stage2h_abi_1_1_width32;
    tb_stage2g_production_path #(.OBS_SEQUENCE_WIDTH(32)) u_matrix();
endmodule
