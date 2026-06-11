`timescale 1ns / 1ps

module sample_fifo #(
    parameter DATA_WIDTH = 16,
    parameter ADDR_WIDTH = 6
) (
    input  wire                  clk,
    input  wire                  rst_n,

    input  wire                  wr_valid,
    input  wire [DATA_WIDTH-1:0] wr_data,
    output wire                  wr_ready,

    input  wire                  rd_ready,
    output wire                  rd_valid,
    output wire [DATA_WIDTH-1:0] rd_data,

    output reg                   overflow
);

    localparam [ADDR_WIDTH:0] DEPTH = (1 << ADDR_WIDTH);

    reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];
    reg [ADDR_WIDTH-1:0] wr_ptr;
    reg [ADDR_WIDTH-1:0] rd_ptr;
    reg [ADDR_WIDTH:0]   count;

    wire full  = (count == DEPTH);
    wire empty = (count == {(ADDR_WIDTH+1){1'b0}});

    wire do_wr = wr_valid && !full;
    wire do_rd = rd_ready && !empty;

    assign wr_ready = !full;
    assign rd_valid = !empty;
    assign rd_data  = mem[rd_ptr];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr   <= {ADDR_WIDTH{1'b0}};
            rd_ptr   <= {ADDR_WIDTH{1'b0}};
            count    <= {(ADDR_WIDTH+1){1'b0}};
            overflow <= 1'b0;
        end else begin
            overflow <= wr_valid && full;

            if (do_wr) begin
                mem[wr_ptr] <= wr_data;
                wr_ptr <= wr_ptr + 1'b1;
            end

            if (do_rd)
                rd_ptr <= rd_ptr + 1'b1;

            case ({do_wr, do_rd})
                2'b10: count <= count + 1'b1;
                2'b01: count <= count - 1'b1;
                default: count <= count;
            endcase
        end
    end

endmodule
