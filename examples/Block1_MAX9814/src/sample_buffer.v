`timescale 1ns / 1ps

module sample_buffer (
    input  wire        clk,
    input  wire        rst_n,

    // Incoming real samples
    input  wire [15:0] sample_in,
    input  wire        sample_valid,
    output wire        sample_ready,

    // Pair read interface for pack_real_to_complex
    input  wire [9:0]  buf_rd_pair_addr,
    output reg  [15:0] buf_rd_real,
    output reg  [15:0] buf_rd_imag,

    // Frame status
    output reg         frame_done,
    input  wire        buf_ack,

    // Debug/status
    output reg         frame_dropped,
    output reg         active_read_bank
);

    localparam LAST_REAL_ADDR = 11'd2047;

    // Bank 0: even samples feed real, odd samples feed imag.
    reg [15:0] mem0_even [0:1023];
    reg [15:0] mem0_odd  [0:1023];

    // Bank 1: second ping-pong bank.
    reg [15:0] mem1_even [0:1023];
    reg [15:0] mem1_odd  [0:1023];

    reg [10:0] wr_addr;
    reg        wr_bank;
    reg        rd_bank;
    reg        full0;
    reg        full1;
    reg        read_active;

    wire wr_bank_full    = wr_bank ? full1 : full0;
    wire other_bank_full = wr_bank ? full0 : full1;

    assign sample_ready = !wr_bank_full;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_addr          <= 11'd0;
            wr_bank          <= 1'b0;
            rd_bank          <= 1'b0;
            active_read_bank <= 1'b0;
            full0            <= 1'b0;
            full1            <= 1'b0;
            read_active      <= 1'b0;
            frame_done       <= 1'b0;
            frame_dropped    <= 1'b0;
        end else begin
            frame_dropped <= 1'b0;

            if (buf_ack && read_active) begin
                if (rd_bank == 1'b0)
                    full0 <= 1'b0;
                else
                    full1 <= 1'b0;

                read_active <= 1'b0;
                frame_done  <= 1'b0;

                if (wr_bank_full) begin
                    wr_bank <= rd_bank;
                    wr_addr <= 11'd0;
                end
            end

            if (sample_valid) begin
                if (!wr_bank_full) begin
                    if (wr_bank == 1'b0) begin
                        if (wr_addr[0] == 1'b0)
                            mem0_even[wr_addr[10:1]] <= sample_in;
                        else
                            mem0_odd[wr_addr[10:1]] <= sample_in;
                    end else begin
                        if (wr_addr[0] == 1'b0)
                            mem1_even[wr_addr[10:1]] <= sample_in;
                        else
                            mem1_odd[wr_addr[10:1]] <= sample_in;
                    end

                    if (wr_addr == LAST_REAL_ADDR) begin
                        if (wr_bank == 1'b0)
                            full0 <= 1'b1;
                        else
                            full1 <= 1'b1;

                        wr_addr <= 11'd0;

                        if (!other_bank_full)
                            wr_bank <= ~wr_bank;
                    end else begin
                        wr_addr <= wr_addr + 11'd1;
                    end
                end else begin
                    frame_dropped <= 1'b1;
                end
            end

            if (!read_active && !frame_done) begin
                if (full0) begin
                    rd_bank          <= 1'b0;
                    active_read_bank <= 1'b0;
                    read_active      <= 1'b1;
                    frame_done       <= 1'b1;
                end else if (full1) begin
                    rd_bank          <= 1'b1;
                    active_read_bank <= 1'b1;
                    read_active      <= 1'b1;
                    frame_done       <= 1'b1;
                end
            end
        end
    end

    always @(posedge clk) begin
        if (rd_bank == 1'b0) begin
            buf_rd_real <= mem0_even[buf_rd_pair_addr];
            buf_rd_imag <= mem0_odd[buf_rd_pair_addr];
        end else begin
            buf_rd_real <= mem1_even[buf_rd_pair_addr];
            buf_rd_imag <= mem1_odd[buf_rd_pair_addr];
        end
    end

endmodule
