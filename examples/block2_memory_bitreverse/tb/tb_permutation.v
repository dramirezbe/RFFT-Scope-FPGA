`timescale 1ns/1ps

module tb_permutation;

    parameter ADDR_WIDTH = 3;
    parameter DATA_WIDTH = 16;
    parameter DEPTH = 8;

    reg clk;
    reg rst_n;

    reg signed [DATA_WIDTH-1:0] complex_real;
    reg signed [DATA_WIDTH-1:0] complex_imag;
    reg complex_valid;
    reg frame_start;

    reg br_ready;

    wire signed [DATA_WIDTH-1:0] br_real;
    wire signed [DATA_WIDTH-1:0] br_imag;
    wire br_valid;

    integer i;
    integer out_count;
    integer error_count;

    reg [DATA_WIDTH-1:0] expected_real [0:DEPTH-1];
    reg [DATA_WIDTH-1:0] expected_imag [0:DEPTH-1];

    permutation_controller #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .DEPTH(DEPTH)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),

        .complex_real(complex_real),
        .complex_imag(complex_imag),
        .complex_valid(complex_valid),
        .frame_start(frame_start),

        .br_ready(br_ready),

        .br_real(br_real),
        .br_imag(br_imag),
        .br_valid(br_valid)
    );

    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    initial begin
        // Orden esperado para N = 8:
        // 0, 4, 2, 6, 1, 5, 3, 7

        expected_real[0] = 0; expected_imag[0] = 100;
        expected_real[1] = 4; expected_imag[1] = 104;
        expected_real[2] = 2; expected_imag[2] = 102;
        expected_real[3] = 6; expected_imag[3] = 106;
        expected_real[4] = 1; expected_imag[4] = 101;
        expected_real[5] = 5; expected_imag[5] = 105;
        expected_real[6] = 3; expected_imag[6] = 103;
        expected_real[7] = 7; expected_imag[7] = 107;
    end

    initial begin
        $display("======================================");
        $display(" TEST permutation_controller AUTO-CHECK");
        $display("======================================");

        rst_n = 0;

        complex_real  = 0;
        complex_imag  = 0;
        complex_valid = 0;
        frame_start   = 0;

        br_ready = 1;

        out_count   = 0;
        error_count = 0;

        #20;
        rst_n = 1;

        @(posedge clk);

        frame_start   <= 1;
        complex_valid <= 1;

        // Escritura de 8 muestras complejas
        for (i = 0; i < DEPTH; i = i + 1) begin
            @(posedge clk);

            complex_real <= i;
            complex_imag <= i + 100;

            $display("WRITE input_index=%0d real=%0d imag=%0d", i, i, i+100);
        end

        @(posedge clk);
        complex_valid <= 0;
        frame_start   <= 0;

        $display("");
        $display("----- CHECK OUTPUT BIT-REVERSED -----");

        // Captura hasta recibir DEPTH salidas válidas
        while (out_count < DEPTH) begin
            @(posedge clk);

            if (br_valid && br_ready) begin

                if ((br_real !== expected_real[out_count]) ||
                    (br_imag !== expected_imag[out_count])) begin

                    $display("ERROR output[%0d]: real=%0d imag=%0d | expected real=%0d imag=%0d",
                             out_count,
                             br_real,
                             br_imag,
                             expected_real[out_count],
                             expected_imag[out_count]);

                    error_count = error_count + 1;

                end else begin

                    $display("PASS  output[%0d]: real=%0d imag=%0d",
                             out_count,
                             br_real,
                             br_imag);

                end

                out_count = out_count + 1;
            end
        end

        $display("");
        $display("======================================");

        if (error_count == 0) begin
            $display("RESULTADO FINAL: PASS");
        end else begin
            $display("RESULTADO FINAL: ERROR, fallos=%0d", error_count);
        end

        $display("======================================");

        $finish;
    end

endmodule