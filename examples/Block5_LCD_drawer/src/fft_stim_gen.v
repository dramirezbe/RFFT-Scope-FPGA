`timescale 1ns / 1ps
// ============================================================
// fft_stim_gen - generador sintetico de frames "Bloque 4"
//
// Solo para el top de demo / bring-up sin el pipeline completo:
// emite periodicamente un frame de 1024 bins con el mismo
// protocolo del Bloque 4 (fft_valid por bin + fft_done al final).
//
// Perfil: tres picos (3, 9 y 16.5 kHz con fs=48 kHz) sobre un
// piso bajo, para verificar la calibracion del eje X en el LCD.
// ============================================================

module fft_stim_gen #(
    parameter GAP_CYCLES = 24'd12_000_000   // pausa entre frames (~0.25 s @ 50 MHz)
)(
    input  wire        clk,
    input  wire        rst_n,
    output reg  [15:0] fft_real,
    output reg  [15:0] fft_imag,
    output reg         fft_valid,
    output reg         fft_done
);

    localparam S_GAP   = 1'b0;
    localparam S_FRAME = 1'b1;

    reg        state;
    reg [23:0] gap_cnt;
    reg [9:0]  bin;

    // picos en bins 64 (3 kHz), 192 (9 kHz) y 352 (16.5 kHz)
    function [15:0] synth_mag;
        input [9:0] b;
        begin
            if (b == 10'd64)        synth_mag = 16'd32000;
            else if (b == 10'd192)  synth_mag = 16'd20000;
            else if (b == 10'd352)  synth_mag = 16'd12000;
            else                    synth_mag = 16'd600;   // piso
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= S_GAP;
            gap_cnt   <= 24'd0;
            bin       <= 10'd0;
            fft_real  <= 16'd0;
            fft_imag  <= 16'd0;
            fft_valid <= 1'b0;
            fft_done  <= 1'b0;
        end else begin
            fft_valid <= 1'b0;
            fft_done  <= 1'b0;

            case (state)
                S_GAP: begin
                    if (gap_cnt == GAP_CYCLES) begin
                        gap_cnt <= 24'd0;
                        bin     <= 10'd0;
                        state   <= S_FRAME;
                    end else begin
                        gap_cnt <= gap_cnt + 1'b1;
                    end
                end

                S_FRAME: begin
                    fft_real  <= synth_mag(bin);
                    fft_imag  <= 16'd0;
                    fft_valid <= 1'b1;

                    if (bin == 10'd1023) begin
                        fft_done <= 1'b1;   // junto al ultimo bin
                        state    <= S_GAP;
                    end
                    bin <= bin + 1'b1;
                end
            endcase
        end
    end

endmodule
