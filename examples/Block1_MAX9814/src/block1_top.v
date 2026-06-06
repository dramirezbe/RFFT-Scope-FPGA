`timescale 1ns / 1ps

module block1_top (
    input  wire        clk,
    input  wire        rst_n,

    // Logical sample input. Use block1_i2s_top for physical I2S input.
    input  wire [15:0] sample_in,
    input  wire        sample_valid,
    output wire        sample_ready,

    // Output stream toward Block 2.
    output wire [15:0] complex_real,
    output wire [15:0] complex_imag,
    output wire        complex_valid,
    output wire        frame_start,

    // Debug/status.
    output wire        fifo_overflow,
    output wire        frame_dropped
);

    wire        fifo_rd_valid;
    wire [15:0] fifo_rd_data;
    wire        buffer_sample_ready;
    wire        fifo_rd_ready;

    wire        frame_done;
    wire [9:0]  buf_rd_pair_addr;
    wire [15:0] buf_rd_real;
    wire [15:0] buf_rd_imag;
    wire        buf_ack;
    assign fifo_rd_ready = fifo_rd_valid && buffer_sample_ready;

    sample_fifo #(
        .DATA_WIDTH(16),
        .ADDR_WIDTH(6)
    ) input_fifo (
        .clk      (clk),
        .rst_n    (rst_n),
        .wr_valid (sample_valid),
        .wr_data  (sample_in),
        .wr_ready (sample_ready),
        .rd_ready (fifo_rd_ready),
        .rd_valid (fifo_rd_valid),
        .rd_data  (fifo_rd_data),
        .overflow (fifo_overflow)
    );

    sample_buffer sb (
        .clk              (clk),
        .rst_n            (rst_n),
        .sample_in        (fifo_rd_data),
        .sample_valid     (fifo_rd_ready),
        .sample_ready     (buffer_sample_ready),
        .buf_rd_pair_addr (buf_rd_pair_addr),
        .buf_rd_real      (buf_rd_real),
        .buf_rd_imag      (buf_rd_imag),
        .frame_done       (frame_done),
        .buf_ack          (buf_ack),
        .frame_dropped    (frame_dropped),
        .active_read_bank ()
    );

    pack_real_to_complex pc (
        .clk              (clk),
        .rst_n            (rst_n),
        .frame_done       (frame_done),
        .buf_rd_pair_addr (buf_rd_pair_addr),
        .buf_rd_real      (buf_rd_real),
        .buf_rd_imag      (buf_rd_imag),
        .buf_ack          (buf_ack),
        .complex_real     (complex_real),
        .complex_imag     (complex_imag),
        .complex_valid    (complex_valid),
        .frame_start      (frame_start)
    );

endmodule
