`timescale 1ns / 1ps
// ============================================================
// Fusion smoke test - Block1 + Block2
//
// Drives one UART frame (header 0xAA55, 2048 ramp samples) into
// rfft_block1_2_top with br_ready=1 and checks that the br_*
// stream delivers 1024 complex samples in bit-reversed order:
//   br sample k == complex pair bitrev10(k)
//   pair n = (real = 2n, imag = 2n+1) for the ramp input.
// ============================================================

module tb_block1_2_fusion;

    reg clk;
    reg rst_n;
    reg uart_rx_line;
    reg br_ready;

    wire [15:0] br_real;
    wire [15:0] br_imag;
    wire        br_valid;
    wire        fifo_overflow;
    wire        frame_dropped;

    rfft_block1_2_top dut (
        .clk           (clk),
        .rst_n         (rst_n),
        .uart_rx       (uart_rx_line),
        .br_ready      (br_ready),
        .br_real       (br_real),
        .br_imag       (br_imag),
        .br_valid      (br_valid),
        .fifo_overflow (fifo_overflow),
        .frame_dropped (frame_dropped)
    );

    // UART timing params (match uart_rx)
    localparam CLK_FREQ  = 50000000;
    localparam BAUD      = 921600;
    localparam BIT_TICKS = (CLK_FREQ + (BAUD/2)) / BAUD;

    // clock
    initial begin
        clk = 1'b0;
        forever #10 clk = ~clk; // 50 MHz
    end

    // send a byte LSB-first on uart_rx_line
    task send_byte(input [7:0] b);
        integer i;
        begin
            uart_rx_line = 1'b0; // start bit
            repeat (BIT_TICKS) @(posedge clk);
            for (i = 0; i < 8; i = i + 1) begin
                uart_rx_line = b[i];
                repeat (BIT_TICKS) @(posedge clk);
            end
            uart_rx_line = 1'b1; // stop bit
            repeat (BIT_TICKS) @(posedge clk);
            repeat (BIT_TICKS/2) @(posedge clk);
        end
    endtask

    // 10-bit bit reversal (mirror of rtl/bit_reverse.v)
    function [9:0] bitrev10;
        input [9:0] idx;
        integer i;
        begin
            for (i = 0; i < 10; i = i + 1)
                bitrev10[i] = idx[9 - i];
        end
    endfunction

    integer sidx;
    integer errors;
    integer out_count;
    reg [9:0] src_pair;

    // output checker: one br sample per posedge where valid && ready
    always @(posedge clk) begin
        if (rst_n && br_valid && br_ready) begin
            src_pair = bitrev10(out_count[9:0]);
            if (br_real !== ((2 * src_pair) & 16'hFFFF) ||
                br_imag !== ((2 * src_pair + 1) & 16'hFFFF)) begin
                $display("FAIL out %0d: expected (%04h,%04h), got (%04h,%04h)",
                         out_count,
                         (2 * src_pair) & 16'hFFFF,
                         (2 * src_pair + 1) & 16'hFFFF,
                         br_real, br_imag);
                errors = errors + 1;
            end
            out_count = out_count + 1;
        end
    end

    initial begin
        rst_n = 1'b0;
        uart_rx_line = 1'b1; // idle high
        br_ready = 1'b1;     // future Block 4 always ready
        errors = 0;
        out_count = 0;
        repeat (10) @(posedge clk);
        rst_n = 1'b1;
        repeat (10) @(posedge clk);

        // one frame: header + length 2048 (big-endian) + ramp samples
        $display("TB FUSION: sending UART frame (2048 ramp samples)");
        send_byte(8'hAA);
        send_byte(8'h55);
        send_byte(8'h08);
        send_byte(8'h00);
        for (sidx = 0; sidx < 2048; sidx = sidx + 1) begin
            send_byte(sidx[15:8]);
            send_byte(sidx[7:0]);
        end

        // wait for the 1024 bit-reversed outputs (with timeout)
        sidx = 0;
        while (out_count < 1024 && sidx < 1000000) begin
            @(posedge clk);
            sidx = sidx + 1;
        end

        if (out_count != 1024) begin
            $display("FAIL: expected 1024 br_valid transfers, got %0d", out_count);
            errors = errors + 1;
        end
        if (fifo_overflow) begin
            $display("FAIL: fifo_overflow asserted");
            errors = errors + 1;
        end
        if (frame_dropped) begin
            $display("FAIL: frame_dropped asserted");
            errors = errors + 1;
        end

        if (errors == 0)
            $display("TB FUSION: PASS (1024 samples, bit-reversed order verified)");
        else
            $display("TB FUSION: FAIL, errors=%0d", errors);
        $finish;
    end

endmodule
