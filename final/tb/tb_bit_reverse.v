`timescale 1ns/1ps

module tb_bit_reverse;

    // ============================================================
    // DUT 1 : N = 8  -> ADDR_WIDTH = 3
    // ============================================================
    reg  [2:0] index_in_8;
    wire [2:0] index_out_8;

    bit_reverse #(
        .ADDR_WIDTH(3)
    ) dut_8 (
        .index_in(index_in_8),
        .index_out(index_out_8)
    );

    // ============================================================
    // DUT 2 : N = 16 -> ADDR_WIDTH = 4
    // ============================================================
    reg  [3:0] index_in_16;
    wire [3:0] index_out_16;

    bit_reverse #(
        .ADDR_WIDTH(4)
    ) dut_16 (
        .index_in(index_in_16),
        .index_out(index_out_16)
    );

    // ============================================================
    // DUT 3 : N = 1024 -> ADDR_WIDTH = 10
    // ============================================================
    reg  [9:0] index_in_1024;
    wire [9:0] index_out_1024;

    bit_reverse #(
        .ADDR_WIDTH(10)
    ) dut_1024 (
        .index_in(index_in_1024),
        .index_out(index_out_1024)
    );

    // ============================================================
    // TASK N = 8
    // ============================================================
    task check_8;
        input [2:0] in_value;
        input [2:0] expected_value;
        begin
            index_in_8 = in_value;
            #10;

            if (index_out_8 !== expected_value) begin
                $display("ERROR N=8 : in=%0d out=%0d expected=%0d",
                         in_value, index_out_8, expected_value);
            end else begin
                $display("PASS  N=8 : in=%0d out=%0d",
                         in_value, index_out_8);
            end
        end
    endtask

    // ============================================================
    // TASK N = 16
    // ============================================================
    task check_16;
        input [3:0] in_value;
        input [3:0] expected_value;
        begin
            index_in_16 = in_value;
            #10;

            if (index_out_16 !== expected_value) begin
                $display("ERROR N=16 : in=%0d out=%0d expected=%0d",
                         in_value, index_out_16, expected_value);
            end else begin
                $display("PASS  N=16 : in=%0d out=%0d",
                         in_value, index_out_16);
            end
        end
    endtask

    // ============================================================
    // TASK N = 1024
    // ============================================================
    task check_1024;
        input [9:0] in_value;
        input [9:0] expected_value;
        begin
            index_in_1024 = in_value;
            #10;

            if (index_out_1024 !== expected_value) begin
                $display("ERROR N=1024 : in=%0d out=%0d expected=%0d",
                         in_value, index_out_1024, expected_value);
            end else begin
                $display("PASS  N=1024 : in=%0d out=%0d",
                         in_value, index_out_1024);
            end
        end
    endtask

    // ============================================================
    // PRUEBAS
    // ============================================================
    initial begin

        $display("======================================");
        $display(" TEST BIT_REVERSE ");
        $display("======================================");

        // ========================================================
        // N = 8
        // ========================================================
        $display("");
        $display("----- TEST N = 8 -----");

        check_8(3'd0, 3'd0);
        check_8(3'd1, 3'd4);
        check_8(3'd2, 3'd2);
        check_8(3'd3, 3'd6);
        check_8(3'd4, 3'd1);
        check_8(3'd5, 3'd5);
        check_8(3'd6, 3'd3);
        check_8(3'd7, 3'd7);

        // ========================================================
        // N = 16
        // ========================================================
        $display("");
        $display("----- TEST N = 16 -----");

        check_16(4'd0,  4'd0);
        check_16(4'd1,  4'd8);
        check_16(4'd2,  4'd4);
        check_16(4'd3,  4'd12);
        check_16(4'd4,  4'd2);
        check_16(4'd5,  4'd10);
        check_16(4'd6,  4'd6);
        check_16(4'd7,  4'd14);

        // ========================================================
        // N = 1024
        // ========================================================
        $display("");
        $display("----- TEST N = 1024 -----");

        check_1024(10'd0,   10'd0);
        check_1024(10'd1,   10'd512);
        check_1024(10'd2,   10'd256);
        check_1024(10'd3,   10'd768);
        check_1024(10'd4,   10'd128);
        check_1024(10'd5,   10'd640);
        check_1024(10'd15,  10'd960);
        check_1024(10'd31,  10'd992);

        $display("");
        $display("======================================");
        $display(" FIN TEST BIT_REVERSE ");
        $display("======================================");

        $finish;
    end

endmodule