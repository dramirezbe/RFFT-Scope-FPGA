`timescale 1ns / 1ps
// ============================================================
// spectrum_buffer - Bloque 5 (captura)
//
// Recibe el stream del Bloque 4 (fft_real/imag, fft_valid,
// fft_done), calcula la magnitud aproximada de cada bin y la
// guarda en una RAM ping-pong de doble reloj:
//
//   - Puerto de escritura: clk_sys (dominio del pipeline FFT)
//   - Puerto de lectura:   clk_pix (dominio del LCD)
//
// Solo se capturan los primeros BINS bins de cada frame
// (la mitad inferior del espectro, 0..fs/2).
//
// Magnitud (sin sqrt, aprox alpha-max beta-min):
//   mag = max(|re|,|im|) + min(|re|,|im|)/2
// Error < 12% vs sqrt(re^2+im^2); suficiente para display.
// Rango: 0..49151, cabe en 16 bits sin saturar.
//
// El banco que ve el display se conmuta en fft_done, asi el
// LCD siempre lee un frame completo y estable (sin tearing).
// ============================================================

module spectrum_buffer #(
    parameter BINS       = 512,
    parameter ADDR_WIDTH = 9
)(
    // ── Dominio sistema (Bloque 4) ───────────────────────
    input  wire                  clk_sys,
    input  wire                  rst_n,
    input  wire [15:0]           fft_real,
    input  wire [15:0]           fft_imag,
    input  wire                  fft_valid,
    input  wire                  fft_done,

    // ── Dominio pixel (LCD) ──────────────────────────────
    input  wire                  clk_pix,
    input  wire [ADDR_WIDTH-1:0] rd_bin,
    output reg  [15:0]           rd_mag
);

    // ----- magnitud aproximada -----
    wire [15:0] re_abs = fft_real[15] ? (~fft_real + 1'b1) : fft_real;
    wire [15:0] im_abs = fft_imag[15] ? (~fft_imag + 1'b1) : fft_imag;
    wire [15:0] mx     = (re_abs > im_abs) ? re_abs : im_abs;
    wire [15:0] mn     = (re_abs > im_abs) ? im_abs : re_abs;
    wire [15:0] mag    = mx + (mn >> 1);   // max 49151, sin overflow

    // ----- RAM ping-pong (2 bancos) -----
    reg [15:0] mem [0:2*BINS-1];

    reg                  wr_bank;   // banco que se esta escribiendo
    reg [ADDR_WIDTH-1:0] wr_cnt;
    reg                  wr_full;   // ya se capturaron los BINS bins del frame

    integer i;
    initial begin
        for (i = 0; i < 2*BINS; i = i + 1)
            mem[i] = 16'd0;
    end

    always @(posedge clk_sys or negedge rst_n) begin
        if (!rst_n) begin
            wr_bank <= 1'b0;
            wr_cnt  <= {ADDR_WIDTH{1'b0}};
            wr_full <= 1'b0;
        end else begin
            // los bins BINS..1023 del frame del Bloque 4 se descartan
            if (fft_valid && !wr_full) begin
                mem[{wr_bank, wr_cnt}] <= mag;
                if (wr_cnt == BINS-1)
                    wr_full <= 1'b1;
                else
                    wr_cnt <= wr_cnt + 1'b1;
            end
            if (fft_done) begin
                wr_bank <= ~wr_bank;  // publica el frame al display
                wr_cnt  <= {ADDR_WIDTH{1'b0}};
                wr_full <= 1'b0;
            end
        end
    end

    // ----- lectura en dominio pixel -----
    // sincronizador 2FF del banco publicado
    reg wr_bank_m, wr_bank_s;
    always @(posedge clk_pix or negedge rst_n) begin
        if (!rst_n) begin
            wr_bank_m <= 1'b0;
            wr_bank_s <= 1'b0;
        end else begin
            wr_bank_m <= wr_bank;
            wr_bank_s <= wr_bank_m;
        end
    end

    wire rd_bank = ~wr_bank_s;   // el display lee el banco NO escrito

    always @(posedge clk_pix) begin
        rd_mag <= mem[{rd_bank, rd_bin}];
    end

endmodule
