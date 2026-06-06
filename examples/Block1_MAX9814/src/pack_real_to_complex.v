`timescale 1ns / 1ps

module pack_real_to_complex (
    input  wire        clk,
    input  wire        rst_n,

    // From sample_buffer
    input  wire        frame_done,
    output reg  [9:0]  buf_rd_pair_addr,
    input  wire [15:0] buf_rd_real,
    input  wire [15:0] buf_rd_imag,
    output reg         buf_ack,

    // To Block 2
    output reg  [15:0] complex_real,
    output reg  [15:0] complex_imag,
    output reg         complex_valid,
    output reg         frame_start
);

    localparam IDLE       = 3'd0;
    localparam PRIME      = 3'd1;
    localparam RUN        = 3'd2;
    localparam DONE       = 3'd3;
    localparam WAIT_CLEAR = 3'd4;

    reg [2:0] state;
    reg [9:0] pair_cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state            <= IDLE;
            pair_cnt         <= 10'd0;
            buf_rd_pair_addr <= 10'd0;
            buf_ack          <= 1'b0;
            complex_real     <= 16'd0;
            complex_imag     <= 16'd0;
            complex_valid    <= 1'b0;
            frame_start      <= 1'b0;
        end else begin
            buf_ack       <= 1'b0;
            complex_valid <= 1'b0;
            frame_start   <= 1'b0;

            case (state)
                IDLE: begin
                    pair_cnt <= 10'd0;

                    if (frame_done) begin
                        buf_rd_pair_addr <= 10'd0;
                        state <= PRIME;
                    end
                end

                PRIME: begin
                    buf_rd_pair_addr <= 10'd1;
                    state <= RUN;
                end

                RUN: begin
                    complex_real  <= buf_rd_real;
                    complex_imag  <= buf_rd_imag;
                    complex_valid <= 1'b1;

                    if (pair_cnt == 10'd0)
                        frame_start <= 1'b1;

                    if (pair_cnt < 10'd1022)
                        buf_rd_pair_addr <= pair_cnt + 10'd2;

                    if (pair_cnt == 10'd1023) begin
                        state <= DONE;
                    end else begin
                        pair_cnt <= pair_cnt + 10'd1;
                    end
                end

                DONE: begin
                    buf_ack <= 1'b1;
                    state <= WAIT_CLEAR;
                end

                WAIT_CLEAR: begin
                    if (!frame_done)
                        state <= IDLE;
                end

                default: begin
                    state <= IDLE;
                end
            endcase
        end
    end

endmodule
