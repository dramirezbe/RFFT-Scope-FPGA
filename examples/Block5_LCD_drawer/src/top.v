`timescale 1ns / 1ps
// ============================================================
// top - demo del Bloque 5 (drawer de espectro) en Tang Primer 20K
//
// Mismo esqueleto que examples/sin_lcd: PLL 40 MHz + lcd_ctrl
// 800x480@60. En lugar de la LUT de seno, el generador
// fft_stim_gen emula el stream del Bloque 4 y block5_lcd_drawer
// dibuja el espectro con ejes estaticos.
//
// Para integrar con el pipeline real: eliminar fft_stim_gen y
// conectar fft_real/imag/valid/done desde complex_fft_core
// (mismo clk de sistema).
// ============================================================

module top (
    input          clk,        // oscilador de placa (H11)
    input          rst_n,

    output [4:0]   lcd_r,
    output [5:0]   lcd_g,
    output [4:0]   lcd_b,
    output         lcd_de,
    output         lcd_hsync,
    output         lcd_vsync,
    output         lcd_clk,
    output         lcd_bl
);

    assign lcd_bl = 1'b1;

    wire clk_pix;
    pll_40m pll_40m_inst (
        .clkout (clk_pix),
        .clkin  (clk)
    );

    // ── stream estilo Bloque 4 (sintetico para la demo) ──
    wire [15:0] fft_real, fft_imag;
    wire        fft_valid, fft_done;

    fft_stim_gen u_stim (
        .clk       (clk),
        .rst_n     (rst_n),
        .fft_real  (fft_real),
        .fft_imag  (fft_imag),
        .fft_valid (fft_valid),
        .fft_done  (fft_done)
    );

    // ── controlador LCD (de examples/lcd y sin_lcd) ──────
    wire [23:0] lcd_rgb;
    wire [23:0] lcd_data;
    wire [11:0] lcd_xpos;
    wire [11:0] lcd_ypos;

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

    // ── Bloque 5: captura + dibujo ───────────────────────
    block5_lcd_drawer u_block5 (
        .clk_sys   (clk),
        .rst_n     (rst_n),
        .fft_real  (fft_real),
        .fft_imag  (fft_imag),
        .fft_valid (fft_valid),
        .fft_done  (fft_done),
        .clk_pix   (clk_pix),
        .lcd_xpos  (lcd_xpos),
        .lcd_ypos  (lcd_ypos),
        .lcd_data  (lcd_data)
    );

endmodule
