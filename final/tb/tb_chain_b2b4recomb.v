`timescale 1ns/1ps
// ============================================================
// tb_chain_b2b4recomb - cadena de procesamiento B2 -> B4 -> recomb
//
// Alimenta el Bloque 2 con la senal empaquetada directamente (sin el
// UART lento del B1), con frame_start alineado al primer dato como lo
// emite el B1 real. Verifica:
//   - el Z del B4 (FFT compleja) contra el golden numpy
//   - el X de la recombinacion contra el golden numpy
//   - detecta cualquier X (memoria sin inicializar)
//
// Es la regresion RAPIDA del nucleo de procesamiento (~1.2 us sim),
// complementa el TB E2E completo (~68 ms) que ademas valida UART+LCD.
//
// Correr desde final/ (tras python3 scripts/gen_e2e_vectors.py):
//   iverilog -g2012 -o tb_chain tb/tb_chain_b2b4recomb.v src/block2/*.v \
//     src/block3/butterfly_radix2.v src/block3/twiddle_rom.v \
//     src/block4/*.v src/block5/rfft_recombine.v
//   vvp tb_chain
// ============================================================
module tb_chain_b2b4recomb;
    localparam ZTOL = 6;   // LSB (FFT 10 etapas)
    localparam XTOL = 8;   // LSB (FFT + recombinacion)

    reg clk, rst_n;
    initial begin clk=0; forever #10 clk=~clk; end

    reg [31:0] pack  [0:1023];
    reg [31:0] zgold [0:1023];
    reg [31:0] xgold [0:511];

    reg  [15:0] complex_real, complex_imag;
    reg         complex_valid, frame_start;
    wire [15:0] br_real, br_imag;
    wire        br_valid, br_ready;

    block2_memory_bitreverse_top u_b2 (
        .clk(clk), .rst_n(rst_n),
        .complex_real(complex_real), .complex_imag(complex_imag),
        .complex_valid(complex_valid), .frame_start(frame_start),
        .br_ready(br_ready), .br_real(br_real), .br_imag(br_imag), .br_valid(br_valid));

    wire [15:0] fft_real, fft_imag;
    wire        fft_valid, fft_done;
    wire [10:0] tw_addr_recomb;
    wire [31:0] tw_data_recomb;

    complex_fft_core #(
        .FFT_MEM_FILE("src/block3/twiddles_fft.hex"),
        .RECOMB_MEM_FILE("src/block3/twiddles_recomb.hex")
    ) u_b4 (
        .clk(clk), .rst_n(rst_n),
        .br_real(br_real), .br_imag(br_imag), .br_valid(br_valid), .br_ready(br_ready),
        .fft_real(fft_real), .fft_imag(fft_imag), .fft_valid(fft_valid), .fft_done(fft_done),
        .tw_addr_recomb(tw_addr_recomb), .tw_data_recomb(tw_data_recomb));

    wire [15:0] g_real, g_imag;
    wire        g_valid, g_done;
    rfft_recombine u_rc (
        .clk(clk), .rst_n(rst_n),
        .fft_real(fft_real), .fft_imag(fft_imag), .fft_valid(fft_valid), .fft_done(fft_done),
        .tw_addr_recomb(tw_addr_recomb), .tw_data_recomb(tw_data_recomb),
        .g_real(g_real), .g_imag(g_imag), .g_valid(g_valid), .g_done(g_done));

    // capturas
    integer zc, xc; reg [31:0] zcap [0:1023]; reg [31:0] xcap [0:511];
    initial begin zc=0; xc=0; end
    always @(posedge clk) if (rst_n && fft_valid) begin zcap[zc]={fft_real,fft_imag}; zc=zc+1; end
    always @(posedge clk) if (rst_n && g_valid)   begin xcap[xc]={g_real,g_imag};     xc=xc+1; end

    function integer adiff; input [15:0] a, b; integer d;
        begin d = $signed(a)-$signed(b); adiff = (d<0)?-d:d; end endfunction

    integer i, errors;
    initial begin
        $readmemh("tb/vectors/pack_z.hex", pack);
        $readmemh("tb/vectors/recomb_z_in.hex", zgold);
        $readmemh("tb/vectors/recomb_x_gold.hex", xgold);
        errors=0;
        complex_real=0; complex_imag=0; complex_valid=0; frame_start=0;
        rst_n=0; repeat(6) @(posedge clk); rst_n=1; repeat(4) @(posedge clk);

        for (i=0;i<1024;i=i+1) begin
            @(negedge clk); complex_valid=1; frame_start=(i==0);
            complex_real=pack[i][31:16]; complex_imag=pack[i][15:0];
        end
        @(negedge clk); complex_valid=0; frame_start=0;
        repeat(60000) @(posedge clk);

        if (zc != 1024) begin $display("FAIL: Z capturados=%0d (esperado 1024)", zc); errors=errors+1; end
        if (xc != 512)  begin $display("FAIL: X capturados=%0d (esperado 512)", xc);  errors=errors+1; end

        for (i=0;i<1024;i=i+1) begin
            if (^zcap[i] === 1'bx) begin
                if (errors<8) $display("FAIL Z[%0d] en X", i); errors=errors+1;
            end else if (adiff(zcap[i][31:16],zgold[i][31:16])>ZTOL ||
                         adiff(zcap[i][15:0], zgold[i][15:0])>ZTOL) begin
                if (errors<8) $display("FAIL Z[%0d]: cap %08h gold %08h", i, zcap[i], zgold[i]);
                errors=errors+1;
            end
        end
        for (i=0;i<512;i=i+1) begin
            if (^xcap[i] === 1'bx) begin
                if (errors<8) $display("FAIL X[%0d] en X", i); errors=errors+1;
            end else if (adiff(xcap[i][31:16],xgold[i][31:16])>XTOL ||
                         adiff(xcap[i][15:0], xgold[i][15:0])>XTOL) begin
                if (errors<8) $display("FAIL X[%0d]: cap %08h gold %08h", i, xcap[i], xgold[i]);
                errors=errors+1;
            end
        end

        if (errors==0)
            $display("TB CHAIN: PASS (Z y X vs golden numpy, sin X indefinidos)");
        else
            $display("TB CHAIN: FAIL, errores=%0d", errors);
        $finish;
    end
endmodule
