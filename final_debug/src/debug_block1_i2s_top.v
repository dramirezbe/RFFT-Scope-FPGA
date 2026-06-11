`timescale 1ns / 1ps

module debug_block1_i2s_top #(
    parameter CLK_FREQ = 27000000
)(
    input  wire        clk,
    input  wire        rst_n,

    output wire [15:0] complex_real,
    output wire [15:0] complex_imag,
    output wire        complex_valid,
    output wire        frame_start,

    output wire [15:0] i2s_sample,
    output wire        i2s_sample_valid,
    output wire        fifo_overflow,
    output wire        frame_dropped,

    output wire [2:0]  current_vector
);

    debug_test_rom_player #(
        .CLK_FREQ    (CLK_FREQ),
        .SAMPLE_RATE (48000)
    ) u_rom_player (
        .clk            (clk),
        .rst_n          (rst_n),
        .sample_valid   (i2s_sample_valid),
        .sample_out     (i2s_sample),
        .frame_start    (),
        .current_vector (current_vector)
    );

    block1_top core (
        .clk           (clk),
        .rst_n         (rst_n),
        .sample_in     (i2s_sample),
        .sample_valid  (i2s_sample_valid),
        .sample_ready  (),
        .complex_real  (complex_real),
        .complex_imag  (complex_imag),
        .complex_valid (complex_valid),
        .frame_start   (frame_start),
        .fifo_overflow (fifo_overflow),
        .frame_dropped (frame_dropped)
    );

endmodule
