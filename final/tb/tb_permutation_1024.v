`timescale 1ns/1ps

module tb_permutation_1024;

    parameter ADDR_WIDTH = 10;
    parameter DATA_WIDTH = 16;
    parameter DEPTH = 1024;

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
    integer expected_index;
    integer cycle_count;

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

    function [ADDR_WIDTH-1:0] bit_reverse_ref;
        input [ADDR_WIDTH-1:0] value;
        integer j;
        begin
            for (j = 0; j < ADDR_WIDTH; j = j + 1)
                bit_reverse_ref[j] = value[ADDR_WIDTH-1-j];
        end
    endfunction

    initial begin
        $display("======================================");
        $display(" TEST permutation_controller N=1024 ");
        $display("======================================");

        rst_n = 0;

        complex_real  = 0;
        complex_imag  = 0;
        complex_valid = 0;
        frame_start   = 0;
        br_ready      = 1;

        out_count    = 0;
        error_count  = 0;
        cycle_count  = 0;

        #20;

        // Liberar reset antes de un flanco positivo
        @(negedge clk);
        rst_n = 1;

        // Pulso de inicio de frame
        @(negedge clk);
        frame_start = 1;

        @(negedge clk);
        frame_start = 0;

        // Escritura segura:
        // colocamos datos en negedge para que estén estables antes del posedge
        // (valid se alinea con el dato, como exige el handshake valid/ready)
        for (i = 0; i < DEPTH; i = i + 1) begin
            @(negedge clk);
            complex_valid = 1;
            complex_real = i;
            complex_imag = i + 1000;
        end

        @(negedge clk);
        complex_valid = 0;
        complex_real  = 0;
        complex_imag  = 0;

        $display("----- CHECK OUTPUT BIT-REVERSED N=1024 -----");

        while (out_count < DEPTH && cycle_count < 20000) begin
            @(posedge clk);
            cycle_count = cycle_count + 1;

            if (br_valid && br_ready) begin
                expected_index = bit_reverse_ref(out_count[ADDR_WIDTH-1:0]);

                if ((br_real !== expected_index) ||
                    (br_imag !== expected_index + 1000)) begin

                    $display("ERROR output[%0d]: real=%0d imag=%0d | expected real=%0d imag=%0d",
                             out_count,
                             br_real,
                             br_imag,
                             expected_index,
                             expected_index + 1000);

                    error_count = error_count + 1;
                end

                out_count = out_count + 1;
            end
        end

        $display("======================================");

        if (out_count != DEPTH) begin
            $display("RESULTADO FINAL N=1024: ERROR, timeout out_count=%0d cycle_count=%0d",
                     out_count, cycle_count);
        end else if (error_count == 0) begin
            $display("RESULTADO FINAL N=1024: PASS");
        end else begin
            $display("RESULTADO FINAL N=1024: ERROR, fallos=%0d", error_count);
        end

        $display("======================================");

        $finish;
    end

endmodule