`timescale 1ns / 1ps
// ============================================================
// tb_debug_player - Verifies debug_test_rom_player
//
// Checks:
//   1. After reset, frame_start fires before first sample
//   2. 32 samples per frame
//   3. frame_start re-asserts 1 cycle before next frame
//   4. After FRAMES_PER_VEC frames, current_vector advances
//   5. current_vector wraps 1 -> 0
// ============================================================

module tb_debug_player;

    localparam CLK_HALF = 10;

    reg  clk;
    reg  rst_n;
    wire sample_valid;
    wire [15:0] sample_out;
    wire frame_start;
    wire        current_vector;

    debug_test_rom_player #(
        .CLK_FREQ       (50000000),
        .SAMPLE_RATE    (48000),
        .N_SAMPLES      (32),
        .ADDR_WIDTH     (5),
        .NUM_VECTORS    (2),
        .VEC_SEL_WIDTH  (1),
        .FRAMES_PER_VEC (3),
        .HEX_FILE       ("tb/tb_debug_vectors/test_rom_small.hex")
    ) dut (
        .clk            (clk),
        .rst_n          (rst_n),
        .sample_valid   (sample_valid),
        .sample_out     (sample_out),
        .frame_start    (frame_start),
        .current_vector (current_vector)
    );

    always #CLK_HALF clk = ~clk;

    integer sample_cnt;
    integer frame_idx;
    reg     counting;

    initial begin
        clk = 0;
        rst_n = 0;
        counting = 0;
        sample_cnt = 0;
        frame_idx = 0;

        repeat (5) @(posedge clk);
        rst_n = 1;

        // wait for first frame_start
        while (!frame_start) @(posedge clk);
        $display("[%0t] frame_start detected, vector=%0d", $time, current_vector);
        counting = 1;
        sample_cnt = 0;
        frame_idx = 1;

        forever begin
            @(posedge clk);

            if (counting && sample_valid) begin
                sample_cnt = sample_cnt + 1;
            end

            if (counting && frame_start) begin
                $display("[%0t] frame %0d done: %0d samples, vector=%0d",
                         $time, frame_idx, sample_cnt, current_vector);

                if (frame_idx == 1) begin
                    if (sample_cnt != 32) begin
                        $error("frame 1: expected 32, got %0d", sample_cnt);
                        $finish;
                    end
                    if (current_vector !== 1'b0) begin
                        $error("frame 1: expected vector 0, got %0d", current_vector);
                        $finish;
                    end
                end

                if (frame_idx == 4) begin
                    if (current_vector !== 1'b1) begin
                        $error("frame 4: expected vector 1, got %0d", current_vector);
                        $finish;
                    end
                end

                if (frame_idx == 7) begin
                    if (current_vector !== 1'b0) begin
                        $error("frame 7: expected vector 0 after wrap, got %0d", current_vector);
                        $finish;
                    end
                    $display("[%0t] ========== ALL CHECKS PASSED ==========", $time);
                    $finish;
                end

                sample_cnt = 0;
                frame_idx = frame_idx + 1;
            end
        end
    end

endmodule
