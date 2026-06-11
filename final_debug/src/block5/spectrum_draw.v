`timescale 1ns / 1ps
// ============================================================
// spectrum_draw - Bloque 5 (render)
//
// Genera el pixel blanco/negro para cada coordenada (x,y) del
// LCD 800x480 (mismo esquema xpos/ypos que sin_lcd/lcd_data.v):
//
//   - Barras del espectro: 512 bins, 1 pixel por bin.
//   - Ejes estaticos: X = frecuencia (0..24 kHz con fs=48 kHz),
//     Y = magnitud lineal.
//   - Ticks cada 64 px = 3 kHz en X, cada 64 px en Y.
//   - Etiquetas numericas (kHz) bajo cada tick X, fuente 5x7:
//     0  3  6  9  12  15  18  21  24
//
// Layout (pixeles):
//   area de barras: x en [X0 .. X0+511], bin = x - X0
//   eje Y vertical: x = X0-1,  y en [Y_AXIS-MAX_H .. Y_AXIS]
//   eje X horizontal: y = Y_AXIS, x en [X0-1 .. X0+512]
//   barras: alto = mag >> MAG_SHIFT (0..383 px), crecen hacia
//   arriba desde el eje X.
//
// Pipeline: rd_mag llega 1 ciclo despues de rd_bin (BRAM), por
// eso xpos/ypos se retrasan 1 ciclo (xq/yq) y la salida va
// registrada: la imagen completa queda corrida 1 px (invisible).
// ============================================================

module spectrum_draw #(
    parameter BINS      = 512,
    parameter X0        = 64,    // primer pixel del area de barras
    parameter Y_AXIS    = 420,   // fila del eje X
    parameter MAG_SHIFT = 7,     // alto_barra = mag >> 7 (max 383 px)
    parameter LBL_Y0    = 430    // fila superior de las etiquetas
)(
    input  wire        clk,      // reloj de pixel
    input  wire        rst_n,
    input  wire [11:0] lcd_xpos,
    input  wire [11:0] lcd_ypos,

    // lectura del spectrum_buffer (latencia 1 ciclo)
    output wire [8:0]  rd_bin,
    input  wire [15:0] rd_mag,

    input  wire [2:0]  current_vector,

    output reg  [23:0] lcd_data
);

    localparam WHITE = 24'hFFFFFF;
    localparam BLACK = 24'h000000;

    // ----- direccion de bin (prefetch, sin retrasar) -----
    wire        in_plot_x_now = (lcd_xpos >= X0) && (lcd_xpos < X0 + BINS);
    wire [11:0] bin_now       = lcd_xpos - X0;
    assign rd_bin = in_plot_x_now ? bin_now[8:0] : 9'd0;

    // ----- coordenadas alineadas con rd_mag -----
    reg [11:0] xq, yq;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            xq <= 12'd0;
            yq <= 12'd0;
        end else begin
            xq <= lcd_xpos;
            yq <= lcd_ypos;
        end
    end

    wire        in_plot_x = (xq >= X0) && (xq < X0 + BINS);
    wire [11:0] xr12      = xq - X0;
    wire [11:0] yd12      = Y_AXIS - yq;
    wire [9:0]  xr        = xr12[9:0];                  // 0..511 en area
    wire [9:0]  yd        = yd12[9:0];                  // altura sobre eje X

    // ----- barra del espectro -----
    wire [8:0] bar_h = rd_mag >> MAG_SHIFT;             // 0..383
    wire bar_px = in_plot_x && (yq < Y_AXIS) &&
                  (yd <= {1'b0, bar_h});

    // ----- ejes -----
    wire axis_y_px = (xq == X0-1) &&
                     (yq >= Y_AXIS-384) && (yq <= Y_AXIS);
    wire axis_x_px = (yq == Y_AXIS) &&
                     (xq >= X0-1) && (xq <= X0 + BINS);

    // ----- ticks: cada 64 px = 3 kHz en X, 64 px en Y -----
    wire in_plot_x_tick = (xq >= X0) && (xq <= X0 + BINS);   // incluye 24 kHz
    wire on_tick_x      = in_plot_x_tick && (xr[5:0] == 6'd0);
    wire tick_x_px      = on_tick_x && (yq > Y_AXIS) && (yq <= Y_AXIS+5);

    wire tick_y_px = (yd != 10'd0) && (yd <= 10'd384) && (yd[5:0] == 6'd0) &&
                     (xq >= X0-6) && (xq <= X0-2);

    // ----- etiquetas del eje X (kHz): 0,3,6,...,24 -----
    // Ventana de 11 px centrada en cada tick: 2 chars de 5 px + 1 espacio.
    // m = x relativo al inicio de la primera ventana (tick0 - 5).
    wire [11:0] m_full   = xq - (X0 - 5);
    wire        m_in_rng = (xq >= X0 - 5) && (xq <= X0 + BINS + 5);
    wire [3:0]  lbl_k    = m_full[9:6];          // indice de tick 0..8
    wire [5:0]  lbl_off  = m_full[5:0];          // posicion en la ventana
    wire        lbl_win  = m_in_rng && (lbl_k <= 4'd8) && (lbl_off <= 6'd10);

    // fila dentro del glifo (0..6)
    wire [11:0] lbl_row12 = yq - LBL_Y0;
    wire [9:0]  lbl_row10 = lbl_row12[9:0];
    wire        lbl_y_in  = (yq >= LBL_Y0) && (yq <= LBL_Y0 + 6);

    // digitos de la etiqueta k -> valor 3k (kHz)
    reg [3:0] dig_tens, dig_ones;
    always @(*) begin
        case (lbl_k)
            4'd0: begin dig_tens = 4'd10; dig_ones = 4'd0; end // "0"
            4'd1: begin dig_tens = 4'd10; dig_ones = 4'd3; end // "3"
            4'd2: begin dig_tens = 4'd10; dig_ones = 4'd6; end // "6"
            4'd3: begin dig_tens = 4'd10; dig_ones = 4'd9; end // "9"
            4'd4: begin dig_tens = 4'd1;  dig_ones = 4'd2; end // "12"
            4'd5: begin dig_tens = 4'd1;  dig_ones = 4'd5; end // "15"
            4'd6: begin dig_tens = 4'd1;  dig_ones = 4'd8; end // "18"
            4'd7: begin dig_tens = 4'd2;  dig_ones = 4'd1; end // "21"
            default: begin dig_tens = 4'd2; dig_ones = 4'd4; end // "24"
        endcase
    end
    // dig_tens = 10 significa "sin decena" (etiqueta de 1 digito)

    // fuente 5x7 de digitos: fila de 5 bits (MSB = columna izquierda)
    function [4:0] font5x7;
        input [3:0] d;
        input [2:0] r;
        begin
            case ({d, r})
                {4'd0,3'd0}: font5x7 = 5'b01110; {4'd0,3'd1}: font5x7 = 5'b10001;
                {4'd0,3'd2}: font5x7 = 5'b10011; {4'd0,3'd3}: font5x7 = 5'b10101;
                {4'd0,3'd4}: font5x7 = 5'b11001; {4'd0,3'd5}: font5x7 = 5'b10001;
                {4'd0,3'd6}: font5x7 = 5'b01110;
                {4'd1,3'd0}: font5x7 = 5'b00100; {4'd1,3'd1}: font5x7 = 5'b01100;
                {4'd1,3'd2}: font5x7 = 5'b00100; {4'd1,3'd3}: font5x7 = 5'b00100;
                {4'd1,3'd4}: font5x7 = 5'b00100; {4'd1,3'd5}: font5x7 = 5'b00100;
                {4'd1,3'd6}: font5x7 = 5'b01110;
                {4'd2,3'd0}: font5x7 = 5'b01110; {4'd2,3'd1}: font5x7 = 5'b10001;
                {4'd2,3'd2}: font5x7 = 5'b00001; {4'd2,3'd3}: font5x7 = 5'b00010;
                {4'd2,3'd4}: font5x7 = 5'b00100; {4'd2,3'd5}: font5x7 = 5'b01000;
                {4'd2,3'd6}: font5x7 = 5'b11111;
                {4'd3,3'd0}: font5x7 = 5'b11111; {4'd3,3'd1}: font5x7 = 5'b00010;
                {4'd3,3'd2}: font5x7 = 5'b00100; {4'd3,3'd3}: font5x7 = 5'b00010;
                {4'd3,3'd4}: font5x7 = 5'b00001; {4'd3,3'd5}: font5x7 = 5'b10001;
                {4'd3,3'd6}: font5x7 = 5'b01110;
                {4'd4,3'd0}: font5x7 = 5'b00010; {4'd4,3'd1}: font5x7 = 5'b00110;
                {4'd4,3'd2}: font5x7 = 5'b01010; {4'd4,3'd3}: font5x7 = 5'b10010;
                {4'd4,3'd4}: font5x7 = 5'b11111; {4'd4,3'd5}: font5x7 = 5'b00010;
                {4'd4,3'd6}: font5x7 = 5'b00010;
                {4'd5,3'd0}: font5x7 = 5'b11111; {4'd5,3'd1}: font5x7 = 5'b10000;
                {4'd5,3'd2}: font5x7 = 5'b11110; {4'd5,3'd3}: font5x7 = 5'b00001;
                {4'd5,3'd4}: font5x7 = 5'b00001; {4'd5,3'd5}: font5x7 = 5'b10001;
                {4'd5,3'd6}: font5x7 = 5'b01110;
                {4'd6,3'd0}: font5x7 = 5'b00110; {4'd6,3'd1}: font5x7 = 5'b01000;
                {4'd6,3'd2}: font5x7 = 5'b10000; {4'd6,3'd3}: font5x7 = 5'b11110;
                {4'd6,3'd4}: font5x7 = 5'b10001; {4'd6,3'd5}: font5x7 = 5'b10001;
                {4'd6,3'd6}: font5x7 = 5'b01110;
                {4'd7,3'd0}: font5x7 = 5'b11111; {4'd7,3'd1}: font5x7 = 5'b00001;
                {4'd7,3'd2}: font5x7 = 5'b00010; {4'd7,3'd3}: font5x7 = 5'b00100;
                {4'd7,3'd4}: font5x7 = 5'b01000; {4'd7,3'd5}: font5x7 = 5'b01000;
                {4'd7,3'd6}: font5x7 = 5'b01000;
                {4'd8,3'd0}: font5x7 = 5'b01110; {4'd8,3'd1}: font5x7 = 5'b10001;
                {4'd8,3'd2}: font5x7 = 5'b10001; {4'd8,3'd3}: font5x7 = 5'b01110;
                {4'd8,3'd4}: font5x7 = 5'b10001; {4'd8,3'd5}: font5x7 = 5'b10001;
                {4'd8,3'd6}: font5x7 = 5'b01110;
                {4'd9,3'd0}: font5x7 = 5'b01110; {4'd9,3'd1}: font5x7 = 5'b10001;
                {4'd9,3'd2}: font5x7 = 5'b10001; {4'd9,3'd3}: font5x7 = 5'b01111;
                {4'd9,3'd4}: font5x7 = 5'b00001; {4'd9,3'd5}: font5x7 = 5'b00010;
                {4'd9,3'd6}: font5x7 = 5'b01100;
                default:     font5x7 = 5'b00000;
            endcase
        end
    endfunction

    // pixel de etiqueta
    reg       lbl_px;
    reg [4:0] glyph_row;
    reg [2:0] glyph_col;
    always @(*) begin
        lbl_px    = 1'b0;
        glyph_row = 5'b00000;
        glyph_col = 3'd0;
        if (lbl_win && lbl_y_in) begin
            if (dig_tens == 4'd10) begin
                // 1 digito centrado: columnas 3..7 de la ventana
                if (lbl_off >= 6'd3 && lbl_off <= 6'd7) begin
                    glyph_row = font5x7(dig_ones, lbl_row10[2:0]);
                    glyph_col = lbl_off[2:0] - 3'd3;        // 0..4
                    lbl_px    = glyph_row[3'd4 - glyph_col];
                end
            end else begin
                // 2 digitos: cols 0..4 decena, 6..10 unidad
                if (lbl_off <= 6'd4) begin
                    glyph_row = font5x7(dig_tens, lbl_row10[2:0]);
                    glyph_col = lbl_off[2:0];               // 0..4
                    lbl_px    = glyph_row[3'd4 - glyph_col];
                end else if (lbl_off >= 6'd6) begin
                    glyph_row = font5x7(dig_ones, lbl_row10[2:0]);
                    glyph_col = lbl_off[3:0] - 4'd6;        // 0..4
                    lbl_px    = glyph_row[3'd4 - glyph_col];
                end
            end
        end
    end

    // ----- overlay: "V0".."V7" top-left corner (debug) -----
    localparam OVL_X0 = 2;
    localparam OVL_Y0 = 2;

    wire        ovl_x_in = (xq >= OVL_X0) && (xq < OVL_X0 + 11);
    wire        ovl_y_in = (yq >= OVL_Y0) && (yq < OVL_Y0 + 7);
    wire [3:0]  ovl_col  = xq[3:0] - OVL_X0[3:0];
    wire [2:0]  ovl_row  = yq[2:0] - OVL_Y0[2:0];

    function [4:0] glyph_V;
        input [2:0] r;
        begin
            case (r)
                3'd0: glyph_V = 5'b10001;
                3'd1: glyph_V = 5'b10001;
                3'd2: glyph_V = 5'b10001;
                3'd3: glyph_V = 5'b10001;
                3'd4: glyph_V = 5'b01010;
                3'd5: glyph_V = 5'b01010;
                3'd6: glyph_V = 5'b00100;
                default: glyph_V = 5'b00000;
            endcase
        end
    endfunction

    reg        ovl_px;
    reg [4:0]  ovl_glyph;
    reg [2:0]  ovl_gcol;
    always @(*) begin
        ovl_px    = 1'b0;
        ovl_glyph = 5'b00000;
        ovl_gcol  = 3'd0;
        if (ovl_x_in && ovl_y_in) begin
            if (ovl_col >= 3'd0 && ovl_col <= 3'd4) begin
                ovl_glyph = glyph_V(ovl_row);
                ovl_gcol  = ovl_col[2:0];
                ovl_px    = ovl_glyph[3'd4 - ovl_gcol];
            end else if (ovl_col >= 3'd6 && ovl_col <= 4'd10) begin
                ovl_glyph = font5x7({1'b0, current_vector}, ovl_row);
                ovl_gcol  = ovl_col[3:0] - 4'd6;
                ovl_px    = ovl_glyph[3'd4 - ovl_gcol];
            end
        end
    end

    // ----- composicion final (blanco y negro) -----
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            lcd_data <= BLACK;
        else if (axis_x_px || axis_y_px || tick_x_px || tick_y_px ||
                 lbl_px || bar_px || ovl_px)
            lcd_data <= WHITE;
        else
            lcd_data <= BLACK;
    end

endmodule
