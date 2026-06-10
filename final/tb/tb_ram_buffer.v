`timescale 1ns/1ps

module tb_ram_buffer;

    // ============================================================
    // Parámetros
    // ============================================================
    parameter ADDR_WIDTH = 3;
    parameter DATA_WIDTH = 16;
    parameter DEPTH = 8;

    // ============================================================
    // Señales
    // ============================================================
    reg clk;

    // Escritura
    reg wr_en;
    reg [ADDR_WIDTH-1:0] wr_addr;
    reg signed [DATA_WIDTH-1:0] wr_real;
    reg signed [DATA_WIDTH-1:0] wr_imag;

    // Lectura
    reg [ADDR_WIDTH-1:0] rd_addr;
    wire signed [DATA_WIDTH-1:0] rd_real;
    wire signed [DATA_WIDTH-1:0] rd_imag;

    // ============================================================
    // Instancia DUT
    // ============================================================
    dual_port_ram_buffer #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .DEPTH(DEPTH)
    ) dut (
        .clk(clk),

        .wr_en(wr_en),
        .wr_addr(wr_addr),
        .wr_real(wr_real),
        .wr_imag(wr_imag),

        .rd_addr(rd_addr),
        .rd_real(rd_real),
        .rd_imag(rd_imag)
    );

    // ============================================================
    // Clock 100 MHz
    // ============================================================
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // ============================================================
    // Escritura de datos
    // ============================================================
    integer i;

    initial begin

        $display("======================================");
        $display(" TEST dual_port_ram_buffer ");
        $display("======================================");

        wr_en   = 0;
        wr_addr = 0;
        wr_real = 0;
        wr_imag = 0;
        rd_addr = 0;

        #20;

        // ========================================================
        // Escritura secuencial
        // ========================================================
        $display("");
        $display("----- ESCRITURA -----");

        wr_en = 1;

        for (i = 0; i < DEPTH; i = i + 1) begin

            @(posedge clk);

            wr_addr <= i;
            wr_real <= i;
            wr_imag <= i + 100;

            $display("WRITE addr=%0d real=%0d imag=%0d",
                     i, i, i+100);
        end

        @(posedge clk);
        wr_en <= 0;

        // ========================================================
        // Lectura normal
        // ========================================================
        $display("");
        $display("----- LECTURA NORMAL -----");

        for (i = 0; i < DEPTH; i = i + 1) begin

            @(posedge clk);
            rd_addr <= i;

            @(posedge clk);

            $display("READ addr=%0d real=%0d imag=%0d",
                     i, rd_real, rd_imag);
        end

        $display("");
        $display("======================================");
        $display(" FIN TEST dual_port_ram_buffer ");
        $display("======================================");

        $finish;
    end

endmodule