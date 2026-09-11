`timescale 1ns/1ps

module stage2e_transaction_observability_checker;
    task automatic checker_fail(input [8*96-1:0] reason);
        begin
            $display("STAGE2E CHECK FAILED: %0s", reason);
            $fatal(1);
            $finish;
        end
    endtask

    task automatic observe_backpressure(
        input valid,
        input ready,
        input drop_incremented
    );
        begin
            if (valid && !ready && drop_incremented)
                checker_fail("BACKPRESSURE_MISCLASSIFIED_AS_DROP");
        end
    endtask

    task automatic observe_withdrawal(
        input was_stalled,
        input valid_withdrawn,
        input violation_incremented
    );
        begin
            if (was_stalled && valid_withdrawn && !violation_incremented)
                checker_fail("VALID_WITHDRAWAL_NOT_RECORDED");
        end
    endtask

    task automatic observe_payload_change(
        input was_stalled,
        input payload_changed,
        input violation_incremented
    );
        begin
            if (was_stalled && payload_changed && !violation_incremented)
                checker_fail("STALLED_PAYLOAD_CHANGE_NOT_RECORDED");
        end
    endtask

    task automatic observe_episode_count(input integer episode_delta);
        begin
            if (episode_delta > 1)
                checker_fail("STALL_EPISODE_RECOUNTED");
        end
    endtask

    task automatic observe_duplicate_identity(
        input payload_equal,
        input sequence_equal,
        input duplicate_incremented
    );
        begin
            if (payload_equal && !sequence_equal && duplicate_incremented)
                checker_fail("PAYLOAD_EQUALITY_USED_AS_IDENTITY");
            if (sequence_equal && !duplicate_incremented)
                checker_fail("DUPLICATE_SEQUENCE_NOT_RECORDED");
        end
    endtask

    task automatic observe_atomic_fifo_word(input sequence_and_payload_atomic);
        begin
            if (!sequence_and_payload_atomic)
                checker_fail("SEQUENCE_NOT_ATOMIC_WITH_PAYLOAD");
        end
    endtask

    task automatic observe_accept_sequence(
        input accepted,
        input [31:0] previous_sequence,
        input [31:0] next_sequence
    );
        begin
            if (accepted && next_sequence !== previous_sequence + 1)
                checker_fail("SEQUENCE_NOT_INCREMENTED_ON_ACCEPTANCE");
            if (!accepted && next_sequence !== previous_sequence)
                checker_fail("SEQUENCE_INCREMENTED_WITHOUT_ACCEPTANCE");
        end
    endtask

    task automatic observe_delivery_accounting(
        input integer destination_delivery_count,
        input integer delivery_counter_delta
    );
        begin
            if (destination_delivery_count != delivery_counter_delta)
                checker_fail("DESTINATION_DELIVERY_COUNT_MISMATCH");
        end
    endtask

    task automatic observe_gap(
        input forward_gap,
        input gap_incremented
    );
        begin
            if (forward_gap && !gap_incremented)
                checker_fail("FORWARD_GAP_NOT_RECORDED");
        end
    endtask

    task automatic observe_sequence_relative_stale_or_reorder(
        input sequence_relative_stale_or_reorder,
        input reorder_incremented
    );
        begin
            if (sequence_relative_stale_or_reorder && !reorder_incremented)
                checker_fail(
                    "SEQUENCE_RELATIVE_STALE_OR_REORDER_NOT_RECORDED");
        end
    endtask

    task automatic observe_counter_cdc(
        input registered_gray_source,
        input two_stage_gray_destination,
        input binary_bus_synchronized_per_bit,
        input transition_coherent
    );
        begin
            if (!registered_gray_source || !two_stage_gray_destination ||
                binary_bus_synchronized_per_bit || !transition_coherent)
                checker_fail("BINARY_COUNTER_CDC_OR_UNREGISTERED_GRAY");
        end
    endtask

    task automatic observe_event_cdc(
        input event_is_monotonic_count_or_toggle,
        input short_pulse_directly_synchronized,
        input source_event_occurred,
        input destination_event_observed
    );
        begin
            if (!event_is_monotonic_count_or_toggle ||
                short_pulse_directly_synchronized ||
                (source_event_occurred && !destination_event_observed))
                checker_fail("SHORT_SOURCE_PULSE_DIRECTLY_SYNCHRONIZED");
        end
    endtask

    task automatic observe_saturation(
        input [31:0] saturated_value,
        input [31:0] value_after_increment,
        input saturation_sticky
    );
        begin
            if (saturated_value !== 32'hFFFF_FFFF ||
                value_after_increment !== 32'hFFFF_FFFF ||
                !saturation_sticky)
                checker_fail("DIAGNOSTIC_COUNTER_WRAPPED_OR_SATURATION_HIDDEN");
        end
    endtask

    task automatic observe_w1c_race(
        input clear_same_cycle,
        input new_event,
        input sticky_after_cycle
    );
        begin
            if (clear_same_cycle && new_event && !sticky_after_cycle)
                checker_fail("W1C_LOST_SAME_CYCLE_EVENT");
        end
    endtask

    task automatic observe_any_error_backpressure(
        input legal_backpressure_only,
        input any_error
    );
        begin
            if (legal_backpressure_only && any_error)
                checker_fail("ANY_ERROR_INCLUDES_LEGAL_BACKPRESSURE");
        end
    endtask

    task automatic observe_read_only_write(
        input [31:0] value_before,
        input [31:0] value_after
    );
        begin
            if (value_before !== value_after)
                checker_fail("READ_ONLY_COUNTER_IS_WRITABLE");
        end
    endtask

    task automatic observe_reset_state(
        input [31:0] counter_value,
        input [9:0] sticky_value,
        input has_last_delivery
    );
        begin
            if (counter_value !== 0 || sticky_value !== 0 ||
                has_last_delivery)
                checker_fail("OBSERVABILITY_RESET_STATE_NONZERO");
        end
    endtask

    task automatic observe_sequence_wrap(
        input wrap_transition,
        input sequence_error_incremented
    );
        begin
            if (wrap_transition && sequence_error_incremented)
                checker_fail("LEGAL_SEQUENCE_WRAP_MISCLASSIFIED");
        end
    endtask
endmodule
