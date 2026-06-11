`timescale 1ns / 1ps
// ============================================================
// tb_rfft_scope_e2e - cadena completa UART -> LCD
//
// 1. Envia por UART (921600 baud) un frame de 2048 muestras Q15
//    de un tono de 3 kHz (fs=48 kHz), generado por
//    scripts/gen_e2e_vectors.py.
// 2. El pipeline completo procesa: B1 (uart+pack) -> B2
//    (bit-reverse) -> B4 (FFT compleja, con butterfly+ROM del B3)
//    -> B5 (recombinacion RFFT + drawer).
// 3. Escanea un frame del LCD 800x480 y verifica:
//    - barra pico en la columna del bin golden (3 kHz -> x=128,
//      bajo la etiqueta "3"), con la altura golden (+-2 px)
//    - sin picos espurios en el resto del espectro
//    - ejes presentes, fondo negro
// 4. Vuelca la imagen a "rfft_scope_frame.pgm".
//
// El PLL se reemplaza por un stub que genera 40 MHz independiente
// (el TB corre clk_sys a 50 MHz y pasa CLK_FREQ=50_000_000).
//
// Correr desde final/ (tarda ~2-3 min: ~90 ms de tiempo simulado):
//   iverilog -g2012 -o tb_e2e_scope tb/tb_rfft_scope_e2e.v \
//     src/rfft_scope_top.v src/block1/*.v src/block2/*.v \
//     src/block3/butterfly_radix2.v src/block3/twiddle_rom.v \
//     src/block4/*.v src/block5/*.v src/lcd/lcd_ctrl.v
//   vvp tb_e2e_scope
// ============================================================

// stub de PLL solo para simulacion (reemplaza gowin_rpll/pll_40m.v)
module pll_40m (
    output reg clkout,
    input  wire clkin
);
    initial begin
        clkout = 1'b0;
        forever #12.5 clkout = ~clkout;   // 40 MHz
    end
endmodule

module tb_rfft_scope_e2e;

    `include "tb/vectors/e2e_params.vh"

    reg clk;          // 50 MHz (CLK_FREQ del top en este TB)
    reg rst_n;
    reg uart_rx_line;

    initial begin clk = 0; forever #10 clk = ~clk; end

    wire [4:0]  lcd_r;
    wire [5:0]  lcd_g;
    wire [4:0]  lcd_b;
    wire        lcd_de, lcd_hsync, lcd_vsync, lcd_clk, lcd_bl;
    wire        fifo_overflow, frame_dropped;

    rfft_scope_top #(
        .CLK_FREQ        (50000000),
        .BAUD            (921600),
        .FFT_MEM_FILE    ("src/block3/twiddles_fft.hex"),
        .RECOMB_MEM_FILE ("src/block3/twiddles_recomb.hex")
    ) dut (
        .clk           (clk),
        .rst_n         (rst_n),
        .uart_rx       (uart_rx_line),
        .lcd_r         (lcd_r),
        .lcd_g         (lcd_g),
        .lcd_b         (lcd_b),
        .lcd_de        (lcd_de),
        .lcd_hsync     (lcd_hsync),
        .lcd_vsync     (lcd_vsync),
        .lcd_clk       (lcd_clk),
        .lcd_bl        (lcd_bl),
        .fifo_overflow (fifo_overflow),
        .frame_dropped (frame_dropped)
    );

    // ── envio UART (igual que tb_e2e del Bloque 1) ───────
    localparam CLK_FREQ  = 50000000;
    localparam BAUD      = 921600;
    localparam BIT_TICKS = (CLK_FREQ + (BAUD/2)) / BAUD;

    task send_byte(input [7:0] b);
        integer i;
        begin
            uart_rx_line = 1'b0;
            repeat (BIT_TICKS) @(posedge clk);
            for (i = 0; i < 8; i = i + 1) begin
                uart_rx_line = b[i];
                repeat (BIT_TICKS) @(posedge clk);
            end
            uart_rx_line = 1'b1;
            repeat (BIT_TICKS) @(posedge clk);
            repeat (BIT_TICKS/2) @(posedge clk);
        end
    endtask

    reg [15:0] samples [0:2047];

    // ── captura del frame LCD ────────────────────────────
    localparam H_DISP = 800;
    localparam V_DISP = 480;
    localparam H_TOTAL = 1066;
    localparam V_TOTAL = 520;

    reg pix [0:H_DISP*V_DISP-1];

    wire clk_pix = dut.clk_pix;
    wire [11:0] cap_x = dut.lcd_ctrl_inst.hcnt - (12'd10 + 12'd46);
    wire [11:0] cap_y = dut.lcd_ctrl_inst.vcnt - (12'd4  + 12'd23);
    wire [23:0] cap_rgb = {lcd_r, 3'b0, lcd_g, 2'b0, lcd_b, 3'b0};

    always @(posedge clk_pix) begin
        if (lcd_de)
            pix[cap_y * H_DISP + cap_x] <= |lcd_b;   // B/N: basta un canal
    end

    function pixel;
        input integer x;
        input integer y;
        begin
            pixel = pix[y * H_DISP + x];
        end
    endfunction

    function white_near;     // tolerancia +-2 px (pipeline de dibujo)
        input integer x;
        input integer y;
        integer k;
        begin
            white_near = 0;
            for (k = x-2; k <= x+2; k = k+1)
                if (pixel(k, y)) white_near = 1;
        end
    endfunction

    integer errors;
    task check;
        input cond;
        input [255:0] msg;
        begin
            if (!cond) begin
                $display("FAIL: %0s", msg);
                errors = errors + 1;
            end
        end
    endtask

    // ── secuencia ────────────────────────────────────────
    integer s, x, y, fout;
    integer peak_x, bar_top;

    initial begin
        $readmemh("tb/vectors/e2e_input.hex", samples);

        rst_n = 0;
        uart_rx_line = 1'b1;
        errors = 0;
        for (s = 0; s < H_DISP*V_DISP; s = s + 1) pix[s] = 1'b0;
        repeat (10) @(posedge clk);
        rst_n = 1;
        repeat (10) @(posedge clk);

        // frame UART: header + len 2048 + muestras (MSB primero)
        $display("E2E: enviando frame UART (tono 3 kHz, 2048 muestras)...");
        send_byte(8'hAA);
        send_byte(8'h55);
        send_byte(8'h08);
        send_byte(8'h00);
        for (s = 0; s < 2048; s = s + 1) begin
            send_byte(samples[s][15:8]);
            send_byte(samples[s][7:0]);
        end
        $display("E2E: frame enviado, esperando pipeline (FFT+recomb)...");

        // pipeline: B2 (~5k) + FFT (~32k) + recomb (~3k) ciclos
        repeat (60000) @(posedge clk);
        check(!fifo_overflow,  "fifo_overflow activo");
        check(!frame_dropped,  "frame_dropped activo");

        // escanear ~1.5 frames de LCD
        $display("E2E: escaneando frame del LCD...");
        repeat ((H_TOTAL * V_TOTAL * 3) / 2) @(posedge clk_pix);

        // ── chequeos ─────────────────────────────────────
        peak_x  = 64 + E2E_PEAK_BIN;        // columna del pico (x=128)
        bar_top = 420 - E2E_PEAK_H;         // fila tope de la barra

        // ejes
        check(white_near(300, 420), "eje X ausente");
        check(white_near(63, 200),  "eje Y ausente");

        // pico de 3 kHz: presente, altura golden +-2 px
        check(white_near(peak_x, 419),        "pico 3 kHz ausente junto al eje");
        check(white_near(peak_x, bar_top+4),  "pico 3 kHz mas bajo que golden");
        check(!white_near(peak_x, bar_top-6), "pico 3 kHz mas alto que golden");

        // sin picos espurios (espectro limpio lejos del tono)
        check(!white_near(64+160, 350), "pico espurio en ~7.5 kHz");
        check(!white_near(64+320, 350), "pico espurio en ~15 kHz");
        check(!white_near(64+480, 350), "pico espurio en ~22.5 kHz");

        // fondo
        check(!white_near(700, 100), "fondo no negro");

        // ── volcado PGM ──────────────────────────────────
        fout = $fopen("rfft_scope_frame.pgm", "w");
        $fwrite(fout, "P2\n%0d %0d\n255\n", H_DISP, V_DISP);
        for (y = 0; y < V_DISP; y = y + 1) begin
            for (x = 0; x < H_DISP; x = x + 1)
                $fwrite(fout, "%0d ", pixel(x, y) ? 255 : 0);
            $fwrite(fout, "\n");
        end
        $fclose(fout);
        $display("Imagen en rfft_scope_frame.pgm");

        if (errors == 0)
            $display("TB E2E SCOPE: PASS (UART->B1->B2->B4(B3)->recomb->LCD)");
        else
            $display("TB E2E SCOPE: FAIL, errores=%0d", errors);
        $finish;
    end

endmodule
