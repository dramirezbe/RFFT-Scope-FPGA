`timescale 1ns / 1ps
// =============================================================================
// twiddle_rom.v – Bloque 3: ROM dual de twiddle factors
// Uses $readmemh for initialization (small ROMs: 512 + 1025 entries).
// =============================================================================

module twiddle_rom #(
    parameter DATA_WIDTH           = 16,
    parameter TWIDDLE_FFT_DEPTH    = 512,
    parameter TWIDDLE_RECOMB_DEPTH = 1025,
    parameter TWIDDLE_FFT_ADDR_W   = 9,
    parameter TWIDDLE_RECOMB_ADDR_W = 11,
    parameter FFT_MEM_FILE         = "src/block3/twiddles_fft.hex",
    parameter RECOMB_MEM_FILE      = "src/block3/twiddles_recomb.hex"
) (
    input  wire                                clk,
    input  wire                                rst_n,

    input  wire [TWIDDLE_FFT_ADDR_W-1:0]       tw_addr_fft,
    output reg  [2*DATA_WIDTH-1:0]             tw_data_fft,

    input  wire [TWIDDLE_RECOMB_ADDR_W-1:0]    tw_addr_recomb,
    output reg  [2*DATA_WIDTH-1:0]             tw_data_recomb
);

    (* ram_style = "block" *) reg [2*DATA_WIDTH-1:0] rom_fft    [0:TWIDDLE_FFT_DEPTH-1];
    (* ram_style = "block" *) reg [2*DATA_WIDTH-1:0] rom_recomb [0:TWIDDLE_RECOMB_DEPTH-1];

    initial begin
        $readmemh(FFT_MEM_FILE,    rom_fft);
        $readmemh(RECOMB_MEM_FILE, rom_recomb);
    end

    always @(posedge clk) begin
        tw_data_fft    <= rom_fft[tw_addr_fft];
        tw_data_recomb <= rom_recomb[tw_addr_recomb];
    end

endmodule
