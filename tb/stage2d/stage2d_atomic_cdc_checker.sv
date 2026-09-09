`timescale 1ns/1ps

module stage2d_atomic_cdc_checker #(
    parameter DATA_WIDTH = 12,
    parameter MAX_PENDING = 64
);
    localparam PAYLOAD_WIDTH = 2 * DATA_WIDTH;
    localparam [DATA_WIDTH-1:0] PAIR_XOR = 12'h5A5;

    reg [PAYLOAD_WIDTH-1:0] pending [0:MAX_PENDING-1];
    reg [PAYLOAD_WIDTH-1:0] stale_history [0:MAX_PENDING-1];
    integer pending_head = 0;
    integer pending_tail = 0;
    integer stale_count = 0;
    integer deliveries_in_epoch = 0;
    reg last_delivery_valid = 1'b0;
    reg [PAYLOAD_WIDTH-1:0] last_delivery = {PAYLOAD_WIDTH{1'b0}};

    function automatic transform_ok;
        input [PAYLOAD_WIDTH-1:0] payload;
        begin
            transform_ok =
                (payload[DATA_WIDTH-1:0] ===
                 (payload[PAYLOAD_WIDTH-1:DATA_WIDTH] ^ PAIR_XOR));
        end
    endfunction

    function automatic pending_contains_after_head;
        input [PAYLOAD_WIDTH-1:0] payload;
        integer index;
        begin
            pending_contains_after_head = 1'b0;
            for (index = pending_head + 1; index < pending_tail;
                 index = index + 1) begin
                if (pending[index] === payload)
                    pending_contains_after_head = 1'b1;
            end
        end
    endfunction

    function automatic stale_contains;
        input [PAYLOAD_WIDTH-1:0] payload;
        integer index;
        begin
            stale_contains = 1'b0;
            for (index = 0; index < stale_count; index = index + 1) begin
                if (stale_history[index] === payload)
                    stale_contains = 1'b1;
            end
        end
    endfunction

    task automatic checker_fail;
        input [8*80-1:0] reason;
        begin
            $display("STAGE2D CHECK FAILED: %0s", reason);
            $fatal(1);
            $finish;
        end
    endtask

    task automatic reset_epoch;
        integer index;
        begin
            for (index = pending_head; index < pending_tail;
                 index = index + 1) begin
                if (stale_count >= MAX_PENDING)
                    checker_fail("STALE_HISTORY_OVERFLOW");
                stale_history[stale_count] = pending[index];
                stale_count = stale_count + 1;
            end
            if (last_delivery_valid) begin
                if (stale_count >= MAX_PENDING)
                    checker_fail("STALE_HISTORY_OVERFLOW");
                stale_history[stale_count] = last_delivery;
                stale_count = stale_count + 1;
            end
            pending_head = 0;
            pending_tail = 0;
            deliveries_in_epoch = 0;
            last_delivery_valid = 1'b0;
        end
    endtask

    task automatic source_accept;
        input [PAYLOAD_WIDTH-1:0] payload;
        begin
            if (!transform_ok(payload))
                checker_fail("SOURCE_PAIR_CONTRACT");
            if (pending_tail >= MAX_PENDING)
                checker_fail("CHECKER_QUEUE_OVERFLOW");
            pending[pending_tail] = payload;
            pending_tail = pending_tail + 1;
        end
    endtask

    task automatic destination_deliver;
        input [PAYLOAD_WIDTH-1:0] payload;
        begin
            if (!transform_ok(payload))
                checker_fail("TEARING");
            if (pending_head >= pending_tail) begin
                if (last_delivery_valid && payload === last_delivery) begin
                    if (deliveries_in_epoch == 1)
                        checker_fail("FIRST_TRANSACTION_DUPLICATE");
                    else
                        checker_fail("DUPLICATE");
                end else if (stale_contains(payload)) begin
                    checker_fail("STALE_REPLAY");
                end else begin
                    checker_fail("PHANTOM");
                end
            end
            if (payload !== pending[pending_head]) begin
                if (last_delivery_valid && payload === last_delivery)
                    checker_fail("DUPLICATE");
                else if (pending_contains_after_head(payload))
                    checker_fail("OUT_OF_ORDER");
                else if (stale_contains(payload))
                    checker_fail("STALE_REPLAY");
                else
                    checker_fail("PAYLOAD_MISMATCH");
            end
            pending_head = pending_head + 1;
            deliveries_in_epoch = deliveries_in_epoch + 1;
            last_delivery_valid = 1'b1;
            last_delivery = payload;
        end
    endtask

    task automatic observe_fifo_access;
        input read_enable;
        input empty;
        input write_enable;
        input full;
        begin
            if (read_enable && empty)
                checker_fail("READ_WHEN_EMPTY");
            if (write_enable && full)
                checker_fail("WRITE_WHEN_FULL_OR_OVERWRITE");
        end
    endtask

    task automatic observe_pointer_sync_use;
        input used_first_stage;
        begin
            if (used_first_stage)
                checker_fail("POINTER_SYNCHRONIZER_EARLY_USE");
        end
    endtask

    task automatic observe_stage2b_trigger;
        input fifo_nonempty;
        input destination_delivery_pulse;
        input stage2b_accept;
        begin
            if (stage2b_accept && fifo_nonempty && !destination_delivery_pulse)
                checker_fail("NONEMPTY_LEVEL_USED_INSTEAD_OF_DESTINATION_DELIVERY");
            if (stage2b_accept !== destination_delivery_pulse)
                checker_fail("STAGE2B_ACCEPT_DESTINATION_DELIVERY_MISMATCH");
        end
    endtask

    task automatic observe_reset_domains;
        input source_uses_source_local_reset;
        input destination_uses_destination_local_reset;
        begin
            if (!source_uses_source_local_reset ||
                !destination_uses_destination_local_reset)
                checker_fail("WRONG_LOCAL_RESET_DOMAIN");
        end
    endtask

    task automatic finalize;
        begin
            if (pending_head != pending_tail)
                checker_fail("DROPPED_ACCEPTED_TRANSACTION");
        end
    endtask
endmodule
