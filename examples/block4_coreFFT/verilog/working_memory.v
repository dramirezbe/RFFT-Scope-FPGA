// working_memory.v - Versión True Dual-Port (2 lecturas simultáneas)
module working_memory #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 10
)(
    input  wire                  clk,
    // Escritura
    input  wire                  wr_en,
    input  wire                  wr_bank,
    input  wire [ADDR_WIDTH-1:0] wr_addr,
    input  wire [DATA_WIDTH-1:0] wr_data,
    // Lectura Puerto E
    input  wire                  rd_bank,
    input  wire [ADDR_WIDTH-1:0] rd_addr_e,
    output reg  [DATA_WIDTH-1:0] rd_data_e,
    // Lectura Puerto O
    input  wire [ADDR_WIDTH-1:0] rd_addr_o,
    output reg  [DATA_WIDTH-1:0] rd_data_o
);

    (* ram_style = "block" *)
    reg [DATA_WIDTH-1:0] mem_a [(1<<ADDR_WIDTH)-1:0];
    (* ram_style = "block" *)
    reg [DATA_WIDTH-1:0] mem_b [(1<<ADDR_WIDTH)-1:0];

    // Escritura
    always @(posedge clk) begin
        if (wr_en) begin
            if (wr_bank == 1'b0)
                mem_a[wr_addr] <= wr_data;
            else
                mem_b[wr_addr] <= wr_data;
        end
    end

    // Lectura E
    always @(posedge clk) begin
        if (rd_bank == 1'b0)
            rd_data_e <= mem_a[rd_addr_e];
        else
            rd_data_e <= mem_b[rd_addr_e];
    end

    // Lectura O
    always @(posedge clk) begin
        if (rd_bank == 1'b0)
            rd_data_o <= mem_a[rd_addr_o];
        else
            rd_data_o <= mem_b[rd_addr_o];
    end

endmodule