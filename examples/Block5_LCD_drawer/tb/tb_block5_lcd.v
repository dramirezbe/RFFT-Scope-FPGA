`timescale 1ns / 1ps
// ============================================================
// tb_block5_lcd - test del drawer de espectro (Bloque 5)
//
// 1. Emula un frame del Bloque 4 (1024 bins, picos en los bins
//    64, 192 y 352 -> 3, 9 y 16.5 kHz) por el dominio clk_sys.
// 2. Escanea un frame completo del LCD 800x480 via lcd_ctrl en
//    el dominio clk_pix y captura los pixeles.
// 3. Auto-chequea: ejes, barras (altura esperada), ticks,
//    etiquetas y fondo negro.
// 4. Vuelca la imagen a "block5_frame.pgm" para inspeccion
//    visual (abrir con cualquier visor de imagenes).
// ============================================================

module tb_block5_lcd;

    // dos dominios de reloj como en el top real
    reg clk_sys;  // 50 MHz
    reg clk_pix;  // 40 MHz
    reg rst_n;

    initial begin clk_sys = 0; forever #10.0  clk_sys = ~clk_sys; end
    initial begin clk_pix = 0; forever #12.5  clk_pix = ~clk_pix; end

    // ── stream estilo Bloque 4 ──────────────────────────
    reg  [15:0] fft_real, fft_imag;
    reg         fft_valid, fft_done;

    function [15:0] synth_mag;
        input [9:0] b;
        begin
            if (b == 10'd64)        synth_mag = 16'd32000; // 3 kHz
            else if (b == 10'd192)  synth_mag = 16'd20000; // 9 kHz
            else if (b == 10'd352)  synth_mag = 16'd12000; // 16.5 kHz
            else                    synth_mag = 16'd600;
        end
    endfunction

    // ── DUT: lcd_ctrl + bloque 5 ────────────────────────
    wire [23:0] lcd_rgb;
    wire [23:0] lcd_data;
    wire [11:0] lcd_xpos, lcd_ypos;
    wire        lcd_de, lcd_hs, lcd_vs, lcd_clk_o;

    lcd_ctrl u_ctrl (
        .clk      (clk_pix),
        .rst_n    (rst_n),
        .lcd_data (lcd_data),
        .lcd_clk  (lcd_clk_o),
        .lcd_hs   (lcd_hs),
        .lcd_vs   (lcd_vs),
        .lcd_de   (lcd_de),
        .lcd_rgb  (lcd_rgb),
        .lcd_xpos (lcd_xpos),
        .lcd_ypos (lcd_ypos)
    );

    block5_lcd_drawer u_block5 (
        .clk_sys   (clk_sys),
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

    // ── captura de la imagen ────────────────────────────
    localparam H_DISP = 800;
    localparam V_DISP = 480;
    localparam H_TOTAL = 1066;
    localparam V_TOTAL = 520;

    reg pix [0:H_DISP*V_DISP-1];   // 1 = blanco

    // coordenadas de captura derivadas de los contadores del ctrl
    wire [11:0] cap_x = u_ctrl.hcnt - (12'd10 + 12'd46); // H_SYNC+H_BACK
    wire [11:0] cap_y = u_ctrl.vcnt - (12'd4  + 12'd23); // V_SYNC+V_BACK

    always @(posedge clk_pix) begin
        if (lcd_de)
            pix[cap_y * H_DISP + cap_x] <= lcd_rgb[0];
    end

    // ── helpers de chequeo ──────────────────────────────
    integer errors;

    function pixel;
        input integer x;
        input integer y;
        begin
            pixel = pix[y * H_DISP + x];
        end
    endfunction

    // blanco en alguna columna de [x-2, x+2] (tolerancia del
    // corrimiento de 1 px del pipeline de dibujo)
    function white_near;
        input integer x;
        input integer y;
        integer k;
        begin
            white_near = 0;
            for (k = x-2; k <= x+2; k = k+1)
                if (pixel(k, y)) white_near = 1;
        end
    endfunction

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

    // ── secuencia principal ─────────────────────────────
    integer b, x, y, fout;

    initial begin
        rst_n = 0;
        fft_real = 0; fft_imag = 0; fft_valid = 0; fft_done = 0;
        errors = 0;
        repeat (10) @(posedge clk_sys);
        rst_n = 1;
        repeat (10) @(posedge clk_sys);

        // 1) frame del Bloque 4
        for (b = 0; b < 1024; b = b + 1) begin
            @(posedge clk_sys);
            fft_real  <= synth_mag(b[9:0]);
            fft_imag  <= 16'd0;
            fft_valid <= 1'b1;
            fft_done  <= (b == 1023);
        end
        @(posedge clk_sys);
        fft_valid <= 1'b0;
        fft_done  <= 1'b0;

        // margen para el swap de banco + sincronizadores
        repeat (20) @(posedge clk_pix);

        // 2) escanear ~1.5 frames de LCD para capturar la imagen completa
        repeat ((H_TOTAL * V_TOTAL * 3) / 2) @(posedge clk_pix);

        // 3) chequeos
        // eje X (y=420) y eje Y (x=63)
        check(white_near(300, 420), "eje X no dibujado en (300,420)");
        check(white_near(63, 200),  "eje Y no dibujado en (63,200)");

        // pico de 3 kHz: bin 64 -> x=128, alto 32000>>7=250 -> tope y=170
        check(white_near(128, 300), "barra 3 kHz ausente en (128,300)");
        check(white_near(128, 419), "barra 3 kHz ausente junto al eje");
        check(!white_near(128, 160), "barra 3 kHz demasiado alta (160)");

        // pico de 9 kHz: bin 192 -> x=256, alto 156 -> tope y=264
        check(white_near(256, 300), "barra 9 kHz ausente en (256,300)");
        check(!white_near(256, 250), "barra 9 kHz demasiado alta (250)");

        // pico de 16.5 kHz: bin 352 -> x=416, alto 93 -> tope y=327
        check(white_near(416, 380), "barra 16.5 kHz ausente en (416,380)");
        check(!white_near(416, 310), "barra 16.5 kHz demasiado alta (310)");

        // tick X de 3 kHz bajo el eje (x=128, y=423)
        check(white_near(128, 423), "tick X de 3 kHz ausente");

        // etiqueta "3" bajo el tick (banda y=430..436)
        begin : lbl_scan
            integer found;
            found = 0;
            for (x = 122; x <= 134; x = x + 1)
                for (y = 430; y <= 436; y = y + 1)
                    if (pixel(x, y)) found = 1;
            check(found, "etiqueta '3' ausente bajo el tick de 3 kHz");
        end

        // fondo negro fuera del area de plot
        check(!white_near(700, 100), "fondo no negro en (700,100)");
        check(!white_near(40, 100),  "fondo no negro en (40,100)");

        // 4) volcar imagen PGM
        fout = $fopen("block5_frame.pgm", "w");
        $fwrite(fout, "P2\n%0d %0d\n255\n", H_DISP, V_DISP);
        for (y = 0; y < V_DISP; y = y + 1) begin
            for (x = 0; x < H_DISP; x = x + 1)
                $fwrite(fout, "%0d ", pixel(x, y) ? 255 : 0);
            $fwrite(fout, "\n");
        end
        $fclose(fout);
        $display("Imagen guardada en block5_frame.pgm");

        if (errors == 0)
            $display("TB BLOCK5: PASS (ejes, barras, ticks y etiquetas OK)");
        else
            $display("TB BLOCK5: FAIL, errores=%0d", errors);
        $finish;
    end

    initial begin
        // inicializa framebuffer en negro
        integer i;
        for (i = 0; i < H_DISP*V_DISP; i = i + 1) pix[i] = 1'b0;
    end

endmodule
