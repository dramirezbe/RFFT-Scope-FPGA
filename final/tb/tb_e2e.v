`timescale 1ns / 1ps

module tb_e2e;

    reg clk;
    reg rst_n;
    reg uart_rx_line;

    wire [15:0] complex_real;
    wire [15:0] complex_imag;
    wire        complex_valid;
    wire        frame_start;

    // instantiate top (uses uart_rx internally)
    block1_i2s_top dut (
        .clk(clk),
        .rst_n(rst_n),
        .uart_rx(uart_rx_line),
        .complex_real(complex_real),
        .complex_imag(complex_imag),
        .complex_valid(complex_valid),
        .frame_start(frame_start),
        .i2s_sample(),
        .i2s_sample_valid(),
        .fifo_overflow(),
        .frame_dropped()
    );

    // UART timing params (match uart_rx)
    localparam CLK_FREQ = 50000000;
    localparam BAUD = 921600;
    localparam BIT_TICKS = (CLK_FREQ + (BAUD/2)) / BAUD;

    // clock
    initial begin
        clk = 1'b0;
        forever #10 clk = ~clk; // 50 MHz
    end

    // send a byte LSB-first on uart_rx_line
    task send_byte(input [7:0] b);
        integer i;
        begin
            // start bit
            uart_rx_line = 1'b0;
            repeat (BIT_TICKS) @(posedge clk);

            for (i = 0; i < 8; i = i + 1) begin
                uart_rx_line = b[i];
                repeat (BIT_TICKS) @(posedge clk);
            end

            // stop bit
            uart_rx_line = 1'b1;
            repeat (BIT_TICKS) @(posedge clk);
            // short gap
            repeat (BIT_TICKS/2) @(posedge clk);
        end
    endtask

    integer i, sidx;
    integer errors;

    initial begin
        // init
        rst_n = 1'b0;
        uart_rx_line = 1'b1; // idle high
        errors = 0;
        repeat (10) @(posedge clk);
        rst_n = 1'b1;
        repeat (10) @(posedge clk);

        // Prepare frame: 2048 samples (ramp)
        // send header
        $display("TB E2E: sending frame 0");
        send_byte(8'hAA);
        send_byte(8'h55);
        // length 2048 -> 0x0800 (big-endian)
        send_byte(8'h08);
        send_byte(8'h00);

        for (sidx = 0; sidx < 2048; sidx = sidx + 1) begin
            // sample is 16-bit ramp: value = sidx
            send_byte(sidx[15:8]);
            send_byte(sidx[7:0]);
        end

        // send second frame immediately
        $display("TB E2E: sending frame 1");
        send_byte(8'hAA);
        send_byte(8'h55);
        send_byte(8'h08);
        send_byte(8'h00);

        for (sidx = 0; sidx < 2048; sidx = sidx + 1) begin
            send_byte(sidx[15:8]);
            send_byte(sidx[7:0]);
        end

        // wait for outputs to be produced
        // monitor will count
        repeat (1000000) @(posedge clk);

        $display("E2E TB done, errors=%0d", errors);
        $finish;
    end

    // expected checker: similar to tb_pack
    reg [15:0] expected_real [0:1023];
    reg [15:0] expected_imag [0:1023];
    integer pair_index;
    integer capture_count;
    integer frame_count;
    integer in_frame;

    initial begin
        // build expected vectors for ramp
        for (pair_index = 0; pair_index < 1024; pair_index = pair_index + 1) begin
            expected_real[pair_index] = (2*pair_index) & 16'hFFFF;
            expected_imag[pair_index] = (2*pair_index + 1) & 16'hFFFF;
        end
        pair_index = 0;
        capture_count = 0;
        frame_count = 0;
        in_frame = 0;
    end

    function integer signed16;
        input [15:0] value;
        begin
            signed16 = $signed(value);
        end
    endfunction

    function integer within_one_lsb;
        input [15:0] got;
        input [15:0] exp;
        integer diff;
        begin
            diff = signed16(got) - signed16(exp);
            if (diff < 0) diff = -diff;
            within_one_lsb = (diff <= 1);
        end
    endfunction

    always @(negedge clk) begin
        if (!rst_n) begin
            pair_index = 0;
            capture_count = 0;
            frame_count = 0;
            in_frame = 0;
        end else begin
            if (complex_valid) begin
                if (frame_start) begin
                    in_frame = 1;
                    pair_index = 0;
                    frame_count = frame_count + 1;
                    $display("Captured frame_start for output frame %0d", frame_count - 1);
                end else if (!in_frame) begin
                    $display("FAIL: complex_valid asserted without frame_start");
                    errors = errors + 1;
                end

                if (in_frame) begin
                    if (!within_one_lsb(complex_real, expected_real[pair_index]) ||
                        !within_one_lsb(complex_imag, expected_imag[pair_index])) begin
                        $display("FAIL frame %0d pair %0d: expected (%04h,%04h), got (%04h,%04h)",
                                 frame_count - 1, pair_index, expected_real[pair_index], expected_imag[pair_index], complex_real, complex_imag);
                        errors = errors + 1;
                    end

                    capture_count = capture_count + 1;

                    if (pair_index == 1023) begin
                        in_frame = 0;
                        pair_index = 0;
                    end else begin
                        pair_index = pair_index + 1;
                    end
                end
            end else begin
                if (frame_start) begin
                    $display("FAIL: frame_start asserted without complex_valid");
                    errors = errors + 1;
                end
                if (in_frame) begin
                    $display("FAIL: complex_valid gap inside frame at pair %0d", pair_index);
                    errors = errors + 1;
                    in_frame = 0;
                end
            end
        end
    end

endmodule
