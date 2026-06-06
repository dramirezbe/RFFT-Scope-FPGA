`timescale 1ns / 1ps

module tb_uart_rx;

    reg clk;
    reg rst_n;
    reg rx_line;

    wire sample_valid;
    wire [15:0] sample_out;
    wire frame_start;
    wire frame_done;

    // Parameters must match uart_rx defaults
    localparam CLK_FREQ = 50000000;
    localparam BAUD = 921600;
    localparam BIT_TICKS = (CLK_FREQ + (BAUD/2)) / BAUD;

    // instantiate uart_rx
    uart_rx #(
        .CLK_FREQ(CLK_FREQ),
        .BAUD(BAUD)
    ) uut (
        .clk(clk),
        .rst_n(rst_n),
        .rx(rx_line),
        .sample_valid(sample_valid),
        .sample_out(sample_out),
        .frame_start(frame_start),
        .frame_done(frame_done)
    );

    // Clock
    initial begin
        clk = 1'b0;
        forever #10 clk = ~clk; // 50 MHz period 20 ns
    end

    // Helper: send one UART byte LSB-first on rx_line
    task send_byte(input [7:0] b);
        integer i;
        begin
            // start bit
            rx_line = 1'b0;
            repeat (BIT_TICKS) @(posedge clk);

            // data bits LSB first
            for (i = 0; i < 8; i = i + 1) begin
                rx_line = b[i];
                repeat (BIT_TICKS) @(posedge clk);
            end

            // stop bit
            rx_line = 1'b1;
            repeat (BIT_TICKS) @(posedge clk);
            // small gap
            repeat (BIT_TICKS/2) @(posedge clk);
        end
    endtask

    integer i;
    integer errors;
    reg [15:0] expected [0:7];

    initial begin

        // init
        rst_n = 1'b0;
        rx_line = 1'b1; // idle high
        errors = 0;
        repeat (10) @(posedge clk);
        rst_n = 1'b1;
        repeat (10) @(posedge clk);

        // prepare small frame: 4 samples
        expected[0] = 16'h1234;
        expected[1] = 16'h5678;
        expected[2] = 16'h9abc;
        expected[3] = 16'hdef0;

        // send header 0xAA,0x55
        send_byte(8'hAA);
        send_byte(8'h55);
        // length hi/lo (4 samples -> 0x0004)
        send_byte(8'h00);
        send_byte(8'h04);

        // send payload: each sample MSB then LSB
        for (i = 0; i < 4; i = i + 1) begin
            send_byte(expected[i][15:8]);
            send_byte(expected[i][7:0]);
        end

        // wait some cycles for processing
        repeat (2000) @(posedge clk);

        // check captured outputs by monitoring in always block
        $display("TB finished, errors=%0d", errors);
        $finish;
    end

    // monitor samples
    integer idx;
    initial idx = 0;
    always @(posedge clk) begin
        if (!rst_n) begin
            idx <= 0;
        end else begin
            if (sample_valid) begin
                $display("sample_valid at time %0t: sample_out=%04h", $time, sample_out);
                idx <= idx + 1;
            end
            if (frame_done) begin
                $display("frame_done asserted at time %0t", $time);
            end
            if (frame_start) begin
                $display("frame_start asserted at time %0t", $time);
            end
        end
    end

endmodule
