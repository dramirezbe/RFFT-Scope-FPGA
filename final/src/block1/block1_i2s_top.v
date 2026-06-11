`timescale 1ns / 1ps


module block1_i2s_top #(
    // Frecuencia real del clk de sistema (la placa Tang Primer 20K
    // entrega 27 MHz; los TB historicos usan 50 MHz) y baudrate UART.
    parameter CLK_FREQ = 50000000,
    parameter BAUD     = 921600
)(
    input  wire        clk,
    input  wire        rst_n,

    // Physical UART RX from ESP32 (replaces I2S receiver)
    input  wire        uart_rx,

    // Output stream toward Block 2.
    output wire [15:0] complex_real,
    output wire [15:0] complex_imag,
    output wire        complex_valid,
    output wire        frame_start,

    // Debug/status.
    output wire [15:0] i2s_sample,         // renamed: now driven by UART receiver
    output wire        i2s_sample_valid,
    output wire        fifo_overflow,
    output wire        frame_dropped
);

    // UART receiver instance (reconstructs 16-bit MSB-first samples)
    uart_rx #(
        .CLK_FREQ(CLK_FREQ),
        .BAUD(BAUD)
    ) u_rx (
        .clk          (clk),
        .rst_n        (rst_n),
        .rx           (uart_rx),
        .sample_valid (i2s_sample_valid),
        .sample_out   (i2s_sample),
        .frame_start  (),
        .frame_done   ()
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
