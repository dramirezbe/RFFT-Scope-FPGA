`timescale 1ns/1ps
// =============================================================================
// tb_complex_fft.v – Testbench de validación numérica del complex_fft_core
// =============================================================================
// CORRECCIONES respecto a la versión anterior:
//
//  [TB-FIX-1] k no inicializado: la variable k del checker de salida
//             no tenía asignación inicial → valor X en simulación. Ahora
//             se inicializa en el bloque initial junto con el resto.
//
//  [TB-FIX-2] Protocolo de envío: el TB ya espera br_ready=1 antes de
//             cada dato con el while(). Ahora que el DUT mantiene br_ready=1
//             durante S_LOAD_DATA [FIX-1 del core], el loop no se atasca.
//
//  [TB-FIX-3] N y archivos .hex alineados: N=64, input_br.hex y
//             expected_fft.hex deben tener 64 líneas (generados por el
//             script tb_complex_fft.py con N=64).
// =============================================================================

module tb_complex_fft;
    localparam N         = 1024;      // Alineado con tb_complex_fft.py
    localparam DW        = 16;
    localparam TOLERANCE = 5;       // 5 LSB: redondeo Q15 acumulado en 10 etapas

    reg  clk, rst_n;
    reg  [DW-1:0] br_real_r, br_imag_r;
    reg  br_valid_r;
    wire br_ready_w;
    wire [DW-1:0] fft_real_w, fft_imag_w;
    wire fft_valid_w, fft_done_w;

    // ── Vectores de prueba ────────────────────────────────────────────
    reg [31:0] input_mem  [0:N-1];
    reg [31:0] expect_mem [0:N-1];
    integer    errors = 0, checks = 0;
    integer    i;
    integer    k;    // [TB-FIX-1] declarado aquí; inicializado en initial

    initial begin
        // tono complejo k=64 amp 0.5 (no satura -> golden numpy valido)
        $readmemh("tb/vectors/b4_input_br.hex",  input_mem);
        $readmemh("tb/vectors/b4_expected.hex",  expect_mem);
    end

    // ── DUT ───────────────────────────────────────────────────────────
    // Vectores full-scale del Bloque 4 (tono en k=64). Regresion rapida
    // de los FIX-5/FIX-6 aplicados al core en final/src/block4.
    complex_fft_core #(
        .N_COMPLEX (N),
        .LOG2_N    (10),         // log2(1024) = 10
        .DATA_WIDTH(DW),
        .ADDR_WIDTH(10),
        .FFT_MEM_FILE    ("src/block3/twiddles_fft.hex"),
        .RECOMB_MEM_FILE ("src/block3/twiddles_recomb.hex")
    ) dut (
        .clk           (clk),
        .rst_n         (rst_n),
        .br_real       (br_real_r),
        .br_imag       (br_imag_r),
        .br_valid      (br_valid_r),
        .br_ready      (br_ready_w),
        .fft_real      (fft_real_w),
        .fft_imag      (fft_imag_w),
        .fft_valid     (fft_valid_w),
        .fft_done      (fft_done_w),
        .tw_addr_recomb(11'd0),
        .tw_data_recomb()
    );

    // ── Reloj: 50 MHz (periodo = 20 ns) ──────────────────────────────
    always #10 clk = ~clk;

    // ── Estímulos: envío de N puntos con protocolo valid/ready ────────
    initial begin
        $dumpfile("tb_complex_fft.vcd");
        $dumpvars(0, tb_complex_fft);

        clk = 0; rst_n = 0; br_valid_r = 0;
        br_real_r = 0; br_imag_r = 0;
        k = 0;  // [TB-FIX-1] inicializar k antes de cualquier ciclo de reloj

        repeat(5) @(posedge clk); #1; rst_n = 1;
        repeat(5) @(posedge clk);

        $display("Iniciando envío de %0d puntos...", N);

        for (i = 0; i < N; i = i + 1) begin
            // Esperar que el DUT esté listo (br_ready=1)
            // Con [FIX-1] del core, br_ready=1 durante toda la carga
            @(posedge clk); #1;
            while (!br_ready_w) begin
                @(posedge clk); #1;
            end
            // Presentar dato
            br_real_r  <= input_mem[i][31:16];
            br_imag_r  <= input_mem[i][15:0];
            br_valid_r <= 1'b1;
            @(posedge clk); #1;
            br_valid_r <= 1'b0;
        end

        $display("Envío completo. Esperando resultado...");
    end

    // ── Verificación de salida (checker concurrente) ──────────────────
    // k se incrementa por cada bin recibido; se inicializó en 0 arriba.
    always @(posedge clk) begin
        if (fft_valid_w) begin : check_block
            integer got_re, got_im, exp_re, exp_im;
            integer err_re, err_im;

            got_re = $signed(fft_real_w);
            got_im = $signed(fft_imag_w);
            exp_re = $signed(expect_mem[k][31:16]);
            exp_im = $signed(expect_mem[k][15:0]);

            err_re = (got_re >= exp_re) ? (got_re - exp_re) : (exp_re - got_re);
            err_im = (got_im >= exp_im) ? (got_im - exp_im) : (exp_im - got_im);

            checks = checks + 1;
            // [TB-FIX] Detectar X explicitamente: el checker original solo
            // hacia 'err > TOL', y como 'X > 2' evalua falso en Verilog, los
            // valores indefinidos (memoria sin escribir) pasaban como OK.
            // Eso oculto el bug FIX-5 (mem[1023] sin escribir) durante meses.
            if ((^fft_real_w === 1'bx) || (^fft_imag_w === 1'bx)) begin
                $display("ERROR bin k=%0d: salida en X (memoria sin inicializar)", k);
                errors = errors + 1;
            end else if (err_re > TOLERANCE || err_im > TOLERANCE) begin
                $display("ERROR bin k=%0d: got(%0d,%0d) exp(%0d,%0d) err=(%0d,%0d)",
                         k, got_re, got_im, exp_re, exp_im, err_re, err_im);
                errors = errors + 1;
            end

            if (k % 16 == 0)
                $display("Progreso: bin %0d / %0d", k, N);

            k = k + 1;
        end

        if (fft_done_w) begin
            $display("─────────────────────────────────");
            $display("Bins verificados : %0d", checks);
            $display("Errores > %0d LSB: %0d", TOLERANCE, errors);
            if (errors == 0)
                $display("✓ PASS — Precisión dentro de tolerancia");
            else
                $display("✗ FAIL — %0d errores", errors);
            $display("─────────────────────────────────");
            $finish;
        end
    end

    // ── Timeout de seguridad ──────────────────────────────────────────
    // Con N=64, LOG2_N=6, 4 ciclos/mariposa:
    //   Carga:       64 ciclos
    //   Cómputo:     6 etapas × 32 mariposas × 4 ciclos = 768 ciclos
    //   Salida:      64 ciclos
    //   Total ~900 ciclos × 20 ns = 18 µs → timeout de 1 ms es suficiente
    initial begin
        #1_000_000; // 1 ms
        $display("ERROR: Timeout — simulación atascada en t=%0t", $time);
        $finish;
    end

endmodule