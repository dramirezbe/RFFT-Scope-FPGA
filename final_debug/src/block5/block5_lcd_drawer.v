`timescale 1ns / 1ps
// ============================================================
// block5_lcd_drawer - Bloque 5: drawer de espectro en LCD
//
// Nucleo integrable: conecta el stream de salida del Bloque 4
// (fft_real/imag/valid/done, dominio clk_sys) con el motor de
// dibujo del LCD (dominio clk_pix, coordenadas xpos/ypos del
// lcd_ctrl de los ejemplos lcd/sin_lcd).
//
//   Bloque 4 ──fft_*──▶ spectrum_buffer ──mag──▶ spectrum_draw ──▶ lcd_data
//              (clk_sys)   ping-pong RAM           (clk_pix)
//
// Display blanco y negro:
//   - barras de magnitud (lineal), 1 px por bin, 512 bins
//   - eje X estatico: frecuencia 0..24 kHz (3 kHz por division,
//     fs = 48 kHz), con ticks y etiquetas numericas
//   - eje Y estatico: magnitud, ticks cada 64 px (8192 LSB)
// ============================================================

module block5_lcd_drawer #(
    parameter BINS      = 512,
    parameter MAG_SHIFT = 7     // alto_barra = mag >> MAG_SHIFT
)(
    // ── Dominio sistema: stream del Bloque 4 ─────────────
    input  wire        clk_sys,
    input  wire        rst_n,
    input  wire [15:0] fft_real,
    input  wire [15:0] fft_imag,
    input  wire        fft_valid,
    input  wire        fft_done,

    // ── Dominio pixel: interfaz lcd_ctrl ─────────────────
    input  wire        clk_pix,
    input  wire [11:0] lcd_xpos,
    input  wire [11:0] lcd_ypos,
    output wire [23:0] lcd_data,

    input  wire [2:0]  current_vector
);

    wire [8:0]  rd_bin;
    wire [15:0] rd_mag;

    spectrum_buffer #(
        .BINS       (BINS),
        .ADDR_WIDTH (9)
    ) u_buffer (
        .clk_sys   (clk_sys),
        .rst_n     (rst_n),
        .fft_real  (fft_real),
        .fft_imag  (fft_imag),
        .fft_valid (fft_valid),
        .fft_done  (fft_done),
        .clk_pix   (clk_pix),
        .rd_bin    (rd_bin),
        .rd_mag    (rd_mag)
    );

    spectrum_draw #(
        .BINS      (BINS),
        .MAG_SHIFT (MAG_SHIFT)
    ) u_draw (
        .clk             (clk_pix),
        .rst_n           (rst_n),
        .lcd_xpos        (lcd_xpos),
        .lcd_ypos        (lcd_ypos),
        .rd_bin          (rd_bin),
        .rd_mag          (rd_mag),
        .lcd_data        (lcd_data),
        .current_vector  (current_vector)
    );

endmodule
