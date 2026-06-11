`timescale 1ns / 1ps
// ============================================================
// rfft_scope_top - Pipeline RFFT completo (Bloques 1..5)
//
//                    dominio clk (27 MHz placa)
//  ┌─────────────────────────────────────────────────────────┐
//  uart_rx ─▶ B1 (uart+pack) ─complex_*→ B2 (bit-reverse)
//             ─br_*⇄ B4 complex_fft_core (usa B3: butterfly +
//             twiddle_rom) ─fft_*→ B5 rfft_recombine ─g_*→
//             B5 spectrum_buffer (puerto de escritura)
//  └─────────────────────────────────────────────────────────┘
//                    dominio clk_pix (40.5 MHz PLL)
//  ┌─────────────────────────────────────────────────────────┐
//   spectrum_buffer (lectura) ─▶ spectrum_draw ─▶ lcd_ctrl ─▶ LCD
//  └─────────────────────────────────────────────────────────┘
//
// El CDC entre dominios lo resuelve la RAM ping-pong de doble
// reloj del spectrum_buffer (banco publicado en g_done).
//
// CLK_FREQ: frecuencia real de "clk". La Tang Primer 20K entrega
// 27 MHz en H11; los testbenches usan 50 MHz. El divisor del UART
// (921600 baud) se deriva de este parametro.
// ============================================================

module rfft_scope_top #(
    parameter CLK_FREQ = 27000000,
    parameter BAUD     = 921600,
    // rutas relativas al directorio desde donde se corre la
    // simulacion / sintesis (final/)
    parameter FFT_MEM_FILE    = "src/block3/twiddles_fft.hex",
    parameter RECOMB_MEM_FILE = "src/block3/twiddles_recomb.hex"
)(
    input  wire        clk,         // 27 MHz placa (H11)
    input  wire        rst_n,

    // UART desde el ESP32 (MAX9814, 921600 baud)
    input  wire        uart_rx,

    // LCD RGB 800x480 (Dock)
    output wire [4:0]  lcd_r,
    output wire [5:0]  lcd_g,
    output wire [4:0]  lcd_b,
    output wire        lcd_de,
    output wire        lcd_hsync,
    output wire        lcd_vsync,
    output wire        lcd_clk,
    output wire        lcd_bl,

    // Status
    output wire        fifo_overflow,
    output wire        frame_dropped
);

    assign lcd_bl = 1'b1;

    // ── reloj de pixel (27 MHz -> 40.5 MHz) ──────────────
    wire clk_pix;
    pll_40m pll_40m_inst (
        .clkout (clk_pix),
        .clkin  (clk)
    );

    // ── Bloque 1: UART -> muestras complejas ─────────────
    wire [15:0] complex_real, complex_imag;
    wire        complex_valid, frame_start;

    block1_i2s_top #(
        .CLK_FREQ (CLK_FREQ),
        .BAUD     (BAUD)
    ) u_block1 (
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

    // ── Bloque 2: reordenamiento bit-reverse ─────────────
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

    // ── Bloque 4 (con Bloque 3 interno): FFT compleja ────
    // El B4 ya aplica >>1 por etapa internamente (escala total /1024) y
    // su testbench unitario pasa con entrada full-scale sin saturar, asi
    // que B2 se conecta directo (sin escalado extra a la entrada).
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

    // ── Bloque 5a: recombinacion RFFT (Z -> X real) ──────
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

    // ── controlador LCD ──────────────────────────────────
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

    // ── Bloque 5b: captura + dibujo del espectro ─────────
    block5_lcd_drawer #(
        .BINS      (512),
        .MAG_SHIFT (7)
    ) u_block5 (
        .clk_sys   (clk),
        .rst_n     (rst_n),
        .fft_real  (g_real),
        .fft_imag  (g_imag),
        .fft_valid (g_valid),
        .fft_done  (g_done),
        .clk_pix   (clk_pix),
        .lcd_xpos  (lcd_xpos),
        .lcd_ypos  (lcd_ypos),
        .lcd_data  (lcd_data)
    );

endmodule
