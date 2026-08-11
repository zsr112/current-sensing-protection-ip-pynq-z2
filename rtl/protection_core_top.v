module protection_core_top #(
    parameter DATA_WIDTH = 12,
    parameter CNT_WIDTH  = 16,
    parameter HEALTH_CNT_WIDTH = 8
)(
    input  wire clk,
    input  wire rst_n,
    input  wire sample_valid,
    input  wire pwm_enable,
    input  wire clear_fault,
    input  wire [DATA_WIDTH-1:0] i_ch1,
    input  wire [DATA_WIDTH-1:0] i_ch2,
    input  wire [DATA_WIDTH-1:0] th_oc_ch1,
    input  wire [DATA_WIDTH-1:0] th_oc_ch2,
    input  wire [DATA_WIDTH-1:0] th_diff,
    input  wire [DATA_WIDTH-1:0] th_open,
    input  wire [DATA_WIDTH-1:0] th_sat,
    input  wire [DATA_WIDTH-1:0] th_stuck_delta,
    input  wire [HEALTH_CNT_WIDTH-1:0] th_persist,
    input  wire [CNT_WIDTH-1:0] period,
    input  wire [CNT_WIDTH-1:0] duty,
    output wire pwm_raw,
    output wire pwm_out,
    output wire oc_any,
    output wire oc_both,
    output wire mismatch_flag,
    output wire sensor_open_flag,
    output wire sensor_sat_flag,
    output wire sensor_stuck_flag,
    output wire fault_valid,
    output wire fault_latched,
    output wire [7:0] fault_code,
    output wire [7:0] fault_code_latched,
    output wire [3:0] fsm_state,
    output wire [DATA_WIDTH-1:0] abs_diff
);
    wire sample_accept_event;
    reg [(2*DATA_WIDTH)-1:0] accepted_sample_pair;
    reg accepted_sample_valid;
    reg sample_decision_valid;
    reg decision_oc_any;
    reg decision_oc_both;
    reg decision_mismatch_flag;

    wire [DATA_WIDTH-1:0] accepted_ch1;
    wire [DATA_WIDTH-1:0] accepted_ch2;
    wire oc_ch1, oc_ch2;
    wire pwm_disable;
    wire classifier_oc_any;
    wire classifier_oc_both;
    wire classifier_mismatch_flag;
    wire sensor_open_event;
    wire sensor_sat_event;
    wire sensor_stuck_event;
    wire classifier_sensor_open_flag;
    wire classifier_sensor_sat_flag;
    wire classifier_sensor_stuck_flag;

    assign sample_accept_event = rst_n && sample_valid;
    assign accepted_ch1 = accepted_sample_pair[(2*DATA_WIDTH)-1:DATA_WIDTH];
    assign accepted_ch2 = accepted_sample_pair[DATA_WIDTH-1:0];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            accepted_sample_pair <= {(2*DATA_WIDTH){1'b0}};
            accepted_sample_valid <= 1'b0;
            sample_decision_valid <= 1'b0;
            decision_oc_any <= 1'b0;
            decision_oc_both <= 1'b0;
            decision_mismatch_flag <= 1'b0;
        end else begin
            accepted_sample_valid <= sample_accept_event;
            if (sample_accept_event)
                accepted_sample_pair <= {i_ch1, i_ch2};

            sample_decision_valid <= accepted_sample_valid;
            if (accepted_sample_valid) begin
                decision_oc_any <= oc_any;
                decision_oc_both <= oc_both;
                decision_mismatch_flag <= mismatch_flag;
            end
        end
    end

    current_compare_dual #(.DATA_WIDTH(DATA_WIDTH)) u_cmp (
        .i_ch1(accepted_ch1), .i_ch2(accepted_ch2),
        .th_oc_ch1(th_oc_ch1), .th_oc_ch2(th_oc_ch2), .th_diff(th_diff),
        .oc_ch1(oc_ch1), .oc_ch2(oc_ch2), .oc_any(oc_any), .oc_both(oc_both),
        .mismatch_flag(mismatch_flag), .abs_diff(abs_diff)
    );

    sensor_health_monitor #(.DATA_WIDTH(DATA_WIDTH), .CNT_WIDTH(HEALTH_CNT_WIDTH)) u_health (
        .clk(clk), .rst_n(rst_n), .sample_valid(accepted_sample_valid),
        .i_ch1(accepted_ch1), .i_ch2(accepted_ch2),
        .th_open(th_open), .th_sat(th_sat), .th_stuck_delta(th_stuck_delta), .th_persist(th_persist),
        .sensor_open_flag(sensor_open_flag), .sensor_sat_flag(sensor_sat_flag),
        .sensor_stuck_flag(sensor_stuck_flag),
        .sensor_open_event(sensor_open_event), .sensor_sat_event(sensor_sat_event),
        .sensor_stuck_event(sensor_stuck_event)
    );

    assign classifier_oc_any = sample_decision_valid && decision_oc_any;
    assign classifier_oc_both = sample_decision_valid && decision_oc_both;
    assign classifier_mismatch_flag = sample_decision_valid && decision_mismatch_flag;
    assign classifier_sensor_open_flag = sample_decision_valid && sensor_open_event;
    assign classifier_sensor_sat_flag = sample_decision_valid && sensor_sat_event;
    assign classifier_sensor_stuck_flag = sample_decision_valid && sensor_stuck_event;

    fault_classifier u_classifier (
        .clk(clk), .rst_n(rst_n),
        .oc_any(classifier_oc_any), .oc_both(classifier_oc_both), .mismatch_flag(classifier_mismatch_flag),
        .sensor_open_flag(classifier_sensor_open_flag), .sensor_sat_flag(classifier_sensor_sat_flag),
        .sensor_stuck_flag(classifier_sensor_stuck_flag),
        .fault_valid(fault_valid), .fault_code(fault_code)
    );

    protection_fsm u_fsm (
        .clk(clk), .rst_n(rst_n),
        .fault_valid(fault_valid), .fault_code_in(fault_code), .clear_fault(clear_fault),
        .fault_latched(fault_latched), .pwm_disable(pwm_disable),
        .fault_code_latched(fault_code_latched), .state(fsm_state)
    );

    pwm_gen #(.CNT_WIDTH(CNT_WIDTH)) u_pwm (
        .clk(clk), .rst_n(rst_n), .enable(pwm_enable), .period(period), .duty(duty), .pwm_raw(pwm_raw)
    );

    pwm_gate u_gate (
        .pwm_raw(pwm_raw), .pwm_disable(pwm_disable), .pwm_out(pwm_out)
    );
endmodule

// Production Stage 2G raw-policy core.  The existing protection_core_top
// module above remains the compatibility surface used by prior-stage unit
// fixtures; the packaged asynchronous wrapper selects this implementation.
module stage2g_protection_core #(
    parameter DATA_WIDTH = 12,
    parameter CNT_WIDTH  = 16,
    parameter HEALTH_CNT_WIDTH = 8,
    parameter SEQUENCE_WIDTH = 32
)(
    input  wire clk,
    input  wire rst_n,
    input  wire sample_valid,
    input  wire [SEQUENCE_WIDTH-1:0] sample_sequence,
    input  wire sample_source_integrity_clean,
    input  wire sample_destination_integrity_clean,
    input  wire pwm_enable,
    input  wire clear_fault,
    input  wire [DATA_WIDTH-1:0] i_ch1,
    input  wire [DATA_WIDTH-1:0] i_ch2,
    input  wire [DATA_WIDTH-1:0] th_oc_ch1,
    input  wire [DATA_WIDTH-1:0] th_oc_ch2,
    input  wire [DATA_WIDTH-1:0] th_diff,
    input  wire [DATA_WIDTH-1:0] th_open,
    input  wire [DATA_WIDTH-1:0] th_sat,
    input  wire [DATA_WIDTH-1:0] th_stuck_delta,
    input  wire [HEALTH_CNT_WIDTH-1:0] th_persist,
    input  wire [CNT_WIDTH-1:0] period,
    input  wire [CNT_WIDTH-1:0] duty,
    output wire pwm_raw,
    output wire pwm_out,
    output wire oc_any,
    output wire oc_both,
    output wire mismatch_flag,
    output wire sensor_open_flag,
    output wire sensor_sat_flag,
    output wire sensor_stuck_flag,
    output wire fault_valid,
    output wire fault_latched,
    output wire [7:0] fault_code,
    output wire [7:0] fault_code_latched,
    output wire [3:0] fsm_state,
    output wire [DATA_WIDTH-1:0] abs_diff,
    output wire fault_eval_valid,
    output wire [SEQUENCE_WIDTH-1:0] fault_eval_sequence,
    output wire [5:0] fault_eval_bitmap,
    output wire [7:0] fault_eval_code,
    output wire fault_eval_integrity_clean,
    output wire clear_pending,
    output wire [7:0] first_fault_code,
    output wire [5:0] first_fault_bitmap,
    output wire [5:0] live_fault_bitmap,
    output wire [5:0] fault_seen_bitmap,
    output wire first_fault_event,
    output wire clear_resolution_event,
    output wire clear_accept_event,
    output wire [SEQUENCE_WIDTH-1:0] clear_resolution_sequence,
    output wire post_clear_recovery_pending
);
    wire sample_accept_event;
    reg [(2*DATA_WIDTH)-1:0] accepted_sample_pair;
    reg accepted_sample_valid;
    reg [SEQUENCE_WIDTH-1:0] accepted_sample_sequence;
    reg accepted_integrity_clean;

    reg sample_decision_valid;
    reg [SEQUENCE_WIDTH-1:0] decision_sequence;
    reg decision_integrity_clean;
    reg decision_oc_ch1;
    reg decision_oc_ch2;
    reg decision_mismatch_flag;

    wire [DATA_WIDTH-1:0] accepted_ch1;
    wire [DATA_WIDTH-1:0] accepted_ch2;
    wire oc_ch1;
    wire oc_ch2;
    wire pwm_disable;
    wire sensor_open_event;
    wire sensor_sat_event;
    wire sensor_stuck_event;
    wire episode_active;
    wire [7:0] episode_fault_code;

    assign sample_accept_event = rst_n && sample_valid;
    assign accepted_ch1 =
        accepted_sample_pair[(2*DATA_WIDTH)-1:DATA_WIDTH];
    assign accepted_ch2 = accepted_sample_pair[DATA_WIDTH-1:0];
    generate
        if ((SEQUENCE_WIDTH < 16) || (SEQUENCE_WIDTH > 32)) begin :
            g_invalid_sequence_width
            STAGE2G_PARAMETER_ERROR_SEQUENCE_WIDTH_MUST_BE_16_TO_32
                u_parameter_error();
        end
    endgenerate

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            accepted_sample_pair <= {(2*DATA_WIDTH){1'b0}};
            accepted_sample_valid <= 1'b0;
            accepted_sample_sequence <= {SEQUENCE_WIDTH{1'b0}};
            accepted_integrity_clean <= 1'b0;
            sample_decision_valid <= 1'b0;
            decision_sequence <= {SEQUENCE_WIDTH{1'b0}};
            decision_integrity_clean <= 1'b0;
            decision_oc_ch1 <= 1'b0;
            decision_oc_ch2 <= 1'b0;
            decision_mismatch_flag <= 1'b0;
        end else begin
            // Edge 0: accept exactly the atomic raw CDC destination delivery
            // and attach both
            // source-offer and destination-sequence integrity to that word.
            accepted_sample_valid <= sample_accept_event;
            if (sample_accept_event) begin
                accepted_sample_pair <= {i_ch1, i_ch2};
                accepted_sample_sequence <= sample_sequence;
                accepted_integrity_clean <=
                    sample_source_integrity_clean &&
                    sample_destination_integrity_clean;
            end

            // Edge 1: capture the raw comparator decision and carry the
            // transaction identity/integrity alongside the health decision.
            sample_decision_valid <= accepted_sample_valid;
            if (accepted_sample_valid) begin
                decision_sequence <= accepted_sample_sequence;
                decision_integrity_clean <= accepted_integrity_clean;
                decision_oc_ch1 <= oc_ch1;
                decision_oc_ch2 <= oc_ch2;
                decision_mismatch_flag <= mismatch_flag;
            end
        end
    end

    current_compare_dual #(.DATA_WIDTH(DATA_WIDTH)) u_cmp (
        .i_ch1(accepted_ch1),
        .i_ch2(accepted_ch2),
        .th_oc_ch1(th_oc_ch1),
        .th_oc_ch2(th_oc_ch2),
        .th_diff(th_diff),
        .oc_ch1(oc_ch1),
        .oc_ch2(oc_ch2),
        .oc_any(oc_any),
        .oc_both(oc_both),
        .mismatch_flag(mismatch_flag),
        .abs_diff(abs_diff)
    );

    sensor_health_monitor #(
        .DATA_WIDTH(DATA_WIDTH),
        .CNT_WIDTH(HEALTH_CNT_WIDTH)
    ) u_health (
        .clk(clk),
        .rst_n(rst_n),
        .sample_valid(accepted_sample_valid),
        .i_ch1(accepted_ch1),
        .i_ch2(accepted_ch2),
        .th_open(th_open),
        .th_sat(th_sat),
        .th_stuck_delta(th_stuck_delta),
        .th_persist(th_persist),
        .sensor_open_flag(sensor_open_flag),
        .sensor_sat_flag(sensor_sat_flag),
        .sensor_stuck_flag(sensor_stuck_flag),
        .sensor_open_event(sensor_open_event),
        .sensor_sat_event(sensor_sat_event),
        .sensor_stuck_event(sensor_stuck_event)
    );

    stage2g_fault_evaluation_pipeline #(
        .SEQUENCE_WIDTH(SEQUENCE_WIDTH)
    ) u_classifier (
        .clk(clk),
        .rst_n(rst_n),
        .evaluation_input_valid(sample_decision_valid),
        .evaluation_input_sequence(decision_sequence),
        .evaluation_input_integrity_clean(decision_integrity_clean),
        .cause_ch1_overcurrent(sample_decision_valid && decision_oc_ch1),
        .cause_ch2_overcurrent(sample_decision_valid && decision_oc_ch2),
        .cause_sensor_mismatch(
            sample_decision_valid && decision_mismatch_flag),
        .cause_sensor_open(sample_decision_valid && sensor_open_event),
        .cause_sensor_saturation(
            sample_decision_valid && sensor_sat_event),
        .cause_sensor_stuck(sample_decision_valid && sensor_stuck_event),
        .fault_eval_valid(fault_eval_valid),
        .fault_eval_sequence(fault_eval_sequence),
        .fault_eval_bitmap(fault_eval_bitmap),
        .fault_eval_code(fault_eval_code),
        .fault_eval_integrity_clean(fault_eval_integrity_clean)
    );

    assign fault_valid = fault_eval_valid &&
                         (fault_eval_bitmap != 6'd0);
    assign fault_code = fault_eval_code;

    stage2g_fault_episode_controller #(
        .SEQUENCE_WIDTH(SEQUENCE_WIDTH)
    ) u_fsm (
        .clk(clk),
        .rst_n(rst_n),
        .fault_eval_valid(fault_eval_valid),
        .fault_eval_sequence(fault_eval_sequence),
        .fault_eval_bitmap(fault_eval_bitmap),
        .fault_eval_code(fault_eval_code),
        .fault_eval_integrity_clean(fault_eval_integrity_clean),
        .clear_fault(clear_fault),
        .fault_latched(episode_active),
        .pwm_disable(pwm_disable),
        .fault_code_latched(episode_fault_code),
        .public_fault_latched_compat(fault_latched),
        .public_fault_code_compat(fault_code_latched),
        .post_clear_recovery_pending(post_clear_recovery_pending),
        .state(fsm_state),
        .clear_pending(clear_pending),
        .first_fault_code(first_fault_code),
        .first_fault_bitmap(first_fault_bitmap),
        .live_fault_bitmap(live_fault_bitmap),
        .fault_seen_bitmap(fault_seen_bitmap),
        .first_fault_event(first_fault_event),
        .clear_resolution_event(clear_resolution_event),
        .clear_accept_event(clear_accept_event),
        .clear_resolution_sequence(clear_resolution_sequence)
    );

    pwm_gen #(.CNT_WIDTH(CNT_WIDTH)) u_pwm (
        .clk(clk),
        .rst_n(rst_n),
        .enable(pwm_enable),
        .period(period),
        .duty(duty),
        .pwm_raw(pwm_raw)
    );

    pwm_gate u_gate (
        .pwm_raw(pwm_raw),
        .pwm_disable(pwm_disable),
        .pwm_out(pwm_out)
    );
endmodule
