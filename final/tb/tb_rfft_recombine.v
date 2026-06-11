`timescale 1ns / 1ps
// ============================================================
// tb_rfft_recombine - unitario de la recombinacion RFFT
//
// Inyecta Z[0..1023] (FFT compleja /1024 de un tono empaquetado,
// generada por scripts/gen_e2e_vectors.py) con el protocolo
// fft_valid/fft_done del Bloque 4, y compara los 512 X[k]
// (bins pares decimados) contra el golden numpy bit-exacto.
//
// Tolerancia: +-4 LSB (twiddle del RTL vs golden +-1, butterfly
// +-2 acumulado por los 4 productos Q15).
//
// Correr desde final/:
//   iverilog -g2012 -o tb_rec tb/tb_rfft_recombine.v \
//     src/block5/rfft_recombine.v src/block3/butterfly_radix2.v \
//     src/block3/twiddle_rom.v
//   vvp tb_rec
// ============================================================

module tb_rfft_recombine;

    localparam TOL = 4;

    reg clk, rst_n;
    initial begin clk = 0; forever #10 clk = ~clk; end

    reg  [15:0] fft_real, fft_imag;
    reg         fft_valid, fft_done;
    wire [10:0] tw_addr_recomb;
    wire [31:0] tw_data_recomb;
    wire [15:0] g_real, g_imag;
    wire        g_valid, g_done;

    // twiddle ROM del Bloque 3 (el mismo que instancia el B4)
    twiddle_rom #(
        .FFT_MEM_FILE    ("src/block3/twiddles_fft.hex"),
        .RECOMB_MEM_FILE ("src/block3/twiddles_recomb.hex")
    ) u_rom (
        .clk            (clk),
        .rst_n          (rst_n),
        .tw_addr_fft    (9'd0),
        .tw_data_fft    (),
        .tw_addr_recomb (tw_addr_recomb),
        .tw_data_recomb (tw_data_recomb)
    );

    rfft_recombine dut (
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

    reg [31:0] z_in   [0:1023];
    reg [31:0] x_gold [0:511];

    integer i, out_cnt, errors;
    integer got_r, got_i, exp_r, exp_i, er, ei;
    reg done_seen;

    // checker de salida
    always @(posedge clk) begin
        if (rst_n && g_valid) begin
            got_r = $signed(g_real);
            got_i = $signed(g_imag);
            exp_r = $signed(x_gold[out_cnt][31:16]);
            exp_i = $signed(x_gold[out_cnt][15:0]);
            er = (got_r > exp_r) ? got_r - exp_r : exp_r - got_r;
            ei = (got_i > exp_i) ? got_i - exp_i : exp_i - got_i;
            if (er > TOL || ei > TOL) begin
                if (errors < 16)
                    $display("FAIL bin %0d: got (%0d,%0d) exp (%0d,%0d)",
                             out_cnt, got_r, got_i, exp_r, exp_i);
                errors = errors + 1;
            end
            out_cnt = out_cnt + 1;
        end
        if (rst_n && g_done) done_seen = 1'b1;
    end

    initial begin
        $readmemh("tb/vectors/recomb_z_in.hex",   z_in);
        $readmemh("tb/vectors/recomb_x_gold.hex", x_gold);

        rst_n = 0;
        fft_real = 0; fft_imag = 0; fft_valid = 0; fft_done = 0;
        out_cnt = 0; errors = 0; done_seen = 0;
        repeat (5) @(posedge clk);
        rst_n = 1;
        repeat (5) @(posedge clk);

        // frame Z: 1024 valids consecutivos, done con el ultimo
        for (i = 0; i < 1024; i = i + 1) begin
            @(posedge clk);
            fft_real  <= z_in[i][31:16];
            fft_imag  <= z_in[i][15:0];
            fft_valid <= 1'b1;
            fft_done  <= (i == 1023);
        end
        @(posedge clk);
        fft_valid <= 1'b0;
        fft_done  <= 1'b0;

        // esperar los 512 bins (~5 ciclos/bin) con timeout
        i = 0;
        while (!done_seen && i < 20000) begin
            @(posedge clk);
            i = i + 1;
        end

        if (out_cnt != 512) begin
            $display("FAIL: se esperaban 512 bins, llegaron %0d", out_cnt);
            errors = errors + 1;
        end
        if (!done_seen) begin
            $display("FAIL: g_done nunca llego");
            errors = errors + 1;
        end

        if (errors == 0)
            $display("TB RECOMBINE: PASS (512 bins vs golden, tol +-%0d LSB)", TOL);
        else
            $display("TB RECOMBINE: FAIL, errores=%0d", errors);
        $finish;
    end

endmodule
