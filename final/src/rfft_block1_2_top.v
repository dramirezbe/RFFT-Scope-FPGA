`timescale 1ns / 1ps
// ============================================================
// Fusion top - Bloque 1 + Bloque 2
//
// UART (ESP32/MAX9814, 921600 baud) -> Block1 (FIFO, ping-pong
// buffer, complex packing) -> Block2 (bit-reverse permutation)
// -> br_* stream toward the future Block 4 (FFT core).
//
// Block 1 does not consume backpressure: it streams a complete
// 1024-sample frame unconditionally. This is safe because Block 2
// absorbs the whole frame into RAM during its WRITE state before
// reading out; br_ready only gates the read-out side.
// ============================================================

module rfft_block1_2_top (
    input  wire        clk,            // 50 MHz
    input  wire        rst_n,          // active-low, asynchronous

    // Physical UART RX from ESP32 (MAX9814 samples, Q15)
    input  wire        uart_rx,

    // Handshake from future Block 4 (tie high for standalone bring-up)
    input  wire        br_ready,

    // Bit-reversed stream toward Block 4
    output wire [15:0] br_real,
    output wire [15:0] br_imag,
    output wire        br_valid,

    // Status (LEDs)
    output wire        fifo_overflow,
    output wire        frame_dropped
);

    // Block1 -> Block2 stream (direct wiring: Block 2 accepts
    // frame_start aligned with the first valid sample, which is how
    // Block 1 emits it)
    wire [15:0] complex_real;
    wire [15:0] complex_imag;
    wire        complex_valid;
    wire        frame_start;

    block1_i2s_top u_block1 (
        .clk              (clk),
        .rst_n            (rst_n),
        .uart_rx          (uart_rx),
        .complex_real     (complex_real),
        .complex_imag     (complex_imag),
        .complex_valid    (complex_valid),
        .frame_start      (frame_start),
        .i2s_sample       (),
        .i2s_sample_valid (),
        .fifo_overflow    (fifo_overflow),
        .frame_dropped    (frame_dropped)
    );

    block2_memory_bitreverse_top #(
        .ADDR_WIDTH (10),
        .DATA_WIDTH (16),
        .DEPTH      (1024)
    ) u_block2 (
        .clk           (clk),
        .rst_n         (rst_n),
        .complex_real  (complex_real),
        .complex_imag  (complex_imag),
        .complex_valid (complex_valid),
        .frame_start   (frame_start),
        .br_ready      (br_ready),
        .br_real       (br_real),
        .br_imag       (br_imag),
        .br_valid      (br_valid)
    );

endmodule
