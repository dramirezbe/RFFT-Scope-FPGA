`timescale 1ns / 1ps

module tb_pack;

    reg         clk;
    reg         rst_n;
    reg [15:0] sample_in;
    reg         sample_valid;
    wire        sample_ready;

    wire [15:0] complex_real;
    wire [15:0] complex_imag;
    wire        complex_valid;
    wire        frame_start;
    wire        fifo_overflow;
    wire        frame_dropped;

    reg [15:0] input_samples [0:2047];
    reg [15:0] expected_real [0:1023];
    reg [15:0] expected_imag [0:1023];

    integer errors;
    integer capture_count;
    integer frame_count;
    integer pair_index;
    integer scan_file;
    integer wait_cycles;
    integer in_frame;

    block1_top dut (
        .clk           (clk),
        .rst_n         (rst_n),
        .sample_in     (sample_in),
        .sample_valid  (sample_valid),
        .sample_ready  (sample_ready),
        .complex_real  (complex_real),
        .complex_imag  (complex_imag),
        .complex_valid (complex_valid),
        .frame_start   (frame_start),
        .fifo_overflow (fifo_overflow),
        .frame_dropped (frame_dropped)
    );

    always #10 clk = ~clk;

    function integer signed16;
        input [15:0] value;
        begin
            signed16 = $signed(value);
        end
    endfunction

    function integer within_one_lsb;
        input [15:0] got;
        input [15:0] expected;
        integer diff;
        begin
            diff = signed16(got) - signed16(expected);

            if (diff < 0)
                diff = -diff;

            within_one_lsb = (diff <= 1);
        end
    endfunction

    always @(negedge clk) begin
        if (!rst_n) begin
            capture_count = 0;
            frame_count = 0;
            pair_index = 0;
            in_frame = 0;
        end else begin
            if (fifo_overflow) begin
                $display("FAIL: FIFO overflow at time %0t", $time);
                errors = errors + 1;
            end

            if (frame_dropped) begin
                $display("FAIL: ping-pong buffer dropped a frame/sample at time %0t", $time);
                errors = errors + 1;
            end

            if (complex_valid) begin
                if (frame_start) begin
                    if (in_frame) begin
                        $display("FAIL: frame_start asserted before previous frame completed");
                        errors = errors + 1;
                    end

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
                                 frame_count - 1,
                                 pair_index,
                                 expected_real[pair_index],
                                 expected_imag[pair_index],
                                 complex_real,
                                 complex_imag);
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

    task apply_reset;
        begin
            rst_n = 1'b0;
            sample_in = 16'd0;
            sample_valid = 1'b0;
            repeat (4) @(posedge clk);
            rst_n = 1'b1;
            @(posedge clk);
        end
    endtask

    task feed_frames;
        input integer frame_total;
        integer idx;
        integer sample_index;
        begin
            for (idx = 0; idx < frame_total * 2048; idx = idx + 1) begin
                sample_index = idx % 2048;

                @(negedge clk);

                if (sample_ready !== 1'b1) begin
                    $display("FAIL: sample_ready low before input sample %0d", idx);
                    errors = errors + 1;
                end

                sample_in = input_samples[sample_index];
                sample_valid = 1'b1;
            end

            @(negedge clk);
            sample_in = 16'd0;
            sample_valid = 1'b0;
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b1;
        sample_in = 16'd0;
        sample_valid = 1'b0;
        errors = 0;
        capture_count = 0;
        frame_count = 0;
        pair_index = 0;
        wait_cycles = 0;
        in_frame = 0;

        $display("Generating input and expected vectors (internal)...");

        // simple ramp pattern for deterministic test
        for (pair_index = 0; pair_index < 2048; pair_index = pair_index + 1) begin
            input_samples[pair_index] = pair_index[15:0];
        end

        // build expected complex pairs: real = sample[2*m], imag = sample[2*m+1]
        for (pair_index = 0; pair_index < 1024; pair_index = pair_index + 1) begin
            expected_real[pair_index] = input_samples[2*pair_index];
            expected_imag[pair_index] = input_samples[2*pair_index + 1];
        end

        apply_reset();

        $display("TEST: feed two frames continuously through FIFO + ping-pong + pack");
        feed_frames(2);

        while (capture_count < 2048 && wait_cycles < 20000) begin
            @(posedge clk);
            wait_cycles = wait_cycles + 1;
        end

        if (capture_count != 2048) begin
            $display("FAIL: expected 2048 complex outputs, captured %0d", capture_count);
            errors = errors + 1;
        end

        if (frame_count != 2) begin
            $display("FAIL: expected 2 frame_start pulses, got %0d", frame_count);
            errors = errors + 1;
        end

        repeat (8) @(posedge clk);

        if (errors == 0)
            $display("PASS: block1_top FIFO + ping-pong + pack test");
        else
            $display("FAIL: tb_pack found %0d errors", errors);

        $finish;
    end

endmodule
