`timescale 1ns / 1ps
// ============================================================
// debug_rfft_scope_top - HIL debugging pipeline (no UART)
//
// Self-running spectrum demo: ROM player auto-cycles 8 test
// vectors (5 kHz sine + gaussian noise) through the full RFFT
// pipeline → LCD. No external MCU or UART required.
//
//   debug_test_rom_player → B1 (FIFO+pack) → B2 (bit-reverse)
//   → B4 (1024-pt complex FFT, B3 inside) → B5 recombine
//   → B5 spectrum_buffer → B5 spectrum_draw → lcd_ctrl → LCD
//
// Two clock domains: clk (27 MHz) and clk_pix (40.5 MHz PLL).
// CDC via spectrum_buffer dual-clock ping-pong RAM.
// ============================================================

module debug_rfft_scope_top #(
    parameter CLK_FREQ          = 27000000,
    parameter FFT_MEM_FILE      = "src/block3/twiddles_fft.hex",
    parameter RECOMB_MEM_FILE   = "src/block3/twiddles_recomb.hex"
)(
    input  wire        clk,
    input  wire        rst_n,

    output wire [4:0]  lcd_r,
    output wire [5:0]  lcd_g,
    output wire [4:0]  lcd_b,
    output wire        lcd_de,
    output wire        lcd_hsync,
    output wire        lcd_vsync,
    output wire        lcd_clk,
    output wire        lcd_bl,

    output wire        fifo_overflow,
    output wire        frame_dropped,

    output wire [2:0]  current_vector
);

    assign lcd_bl = 1'b1;

    wire clk_pix;
    pll_40m pll_40m_inst (
        .clkout (clk_pix),
        .clkin  (clk)
    );

    wire [15:0] complex_real, complex_imag;
    wire        complex_valid, frame_start;

    debug_block1_i2s_top #(
        .CLK_FREQ (CLK_FREQ)
    ) u_block1 (
        .clk              (clk),
        .rst_n            (rst_n),
        .complex_real     (complex_real),
        .complex_imag     (complex_imag),
        .complex_valid    (complex_valid),
        .frame_start      (frame_start),
        .i2s_sample       (),
        .i2s_sample_valid (),
        .fifo_overflow    (fifo_overflow),
        .frame_dropped    (frame_dropped),
        .current_vector   (current_vector)
    );

    wire [15:0] br_real, br_imag;
    wire        br_valid, br_ready;

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

    wire [15:0] fft_real, fft_imag;
    wire        fft_valid, fft_done;
    wire [10:0] tw_addr_recomb;
    wire [31:0] tw_data_recomb;

    complex_fft_core #(
        .N_COMPLEX       (1024),
        .LOG2_N          (10),
        .DATA_WIDTH      (16),
        .ADDR_WIDTH      (10),
        .FFT_MEM_FILE    (FFT_MEM_FILE),
        .RECOMB_MEM_FILE (RECOMB_MEM_FILE)
    ) u_block4 (
        .clk            (clk),
        .rst_n          (rst_n),
        .br_real        (br_real),
        .br_imag        (br_imag),
        .br_valid       (br_valid),
        .br_ready       (br_ready),
        .fft_real       (fft_real),
        .fft_imag       (fft_imag),
        .fft_valid      (fft_valid),
        .fft_done       (fft_done),
        .tw_addr_recomb (tw_addr_recomb),
        .tw_data_recomb (tw_data_recomb)
    );

    wire [15:0] g_real, g_imag;
    wire        g_valid, g_done;

    rfft_recombine #(
        .DATA_WIDTH (16),
        .N          (1024),
        .ADDR_WIDTH (10),
        .OUT_BINS   (512)
    ) u_recombine (
        .clk            (clk),
        .rst_n          (rst_n),
        .fft_real       (fft_real),
        .fft_imag       (fft_imag),
        .fft_valid      (fft_valid),
        .fft_done       (fft_done),
        .tw_addr_recomb (tw_addr_recomb),
        .tw_data_recomb (tw_data_recomb),
        .g_real         (g_real),
        .g_imag         (g_imag),
        .g_valid        (g_valid),
        .g_done         (g_done)
    );

    wire [23:0] lcd_rgb;
    wire [23:0] lcd_data;
    wire [11:0] lcd_xpos, lcd_ypos;

    localparam para = 8;
    assign lcd_r[4:0] = lcd_rgb[4 + para*2 : para*2];
    assign lcd_g[5:0] = lcd_rgb[5 + para*1 : para*1];
    assign lcd_b[4:0] = lcd_rgb[4 + para*0 : para*0];

    lcd_ctrl lcd_ctrl_inst (
        .clk      (clk_pix),
        .rst_n    (rst_n),
        .lcd_data (lcd_data),
        .lcd_clk  (lcd_clk),
        .lcd_hs   (lcd_hsync),
        .lcd_vs   (lcd_vsync),
        .lcd_de   (lcd_de),
        .lcd_rgb  (lcd_rgb),
        .lcd_xpos (lcd_xpos),
        .lcd_ypos (lcd_ypos)
    );

    block5_lcd_drawer #(
        .BINS      (512),
        .MAG_SHIFT (7)
    ) u_block5 (
        .clk_sys         (clk),
        .rst_n           (rst_n),
        .fft_real        (g_real),
        .fft_imag        (g_imag),
        .fft_valid       (g_valid),
        .fft_done        (g_done),
        .clk_pix         (clk_pix),
        .lcd_xpos        (lcd_xpos),
        .lcd_ypos        (lcd_ypos),
        .lcd_data        (lcd_data),
        .current_vector  (current_vector)
    );

endmodule
