// ============================================================
// Módulo TOP - Bloque 2
// Memoria y Reordenamiento Bit-Reverse
//
// Función:
// Módulo superior del Bloque 2.
//
// Recibe:
//   - datos complejos desde Bloque 1
//
// Entrega:
//   - datos en orden bit-reversed hacia Bloque 4
//
// ============================================================

module block2_memory_bitreverse_top #(
    parameter ADDR_WIDTH = 10,
    parameter DATA_WIDTH = 16,
    parameter DEPTH = 1024
)(
    input  wire clk,
    input  wire rst_n,

    // ========================================================
    // Entrada desde Bloque 1
    // ========================================================
    input  wire signed [DATA_WIDTH-1:0] complex_real,
    input  wire signed [DATA_WIDTH-1:0] complex_imag,

    input  wire complex_valid,
    input  wire frame_start,

    // ========================================================
    // Handshake desde Bloque 4
    // ========================================================
    input  wire br_ready,

    // ========================================================
    // Salida hacia Bloque 4
    // ========================================================
    output wire signed [DATA_WIDTH-1:0] br_real,
    output wire signed [DATA_WIDTH-1:0] br_imag,

    output wire br_valid
);

    // ========================================================
    // Instancia principal del controlador
    // ========================================================
    permutation_controller #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .DEPTH(DEPTH)
    ) u_permutation_controller (
        .clk(clk),
        .rst_n(rst_n),

        .complex_real(complex_real),
        .complex_imag(complex_imag),

        .complex_valid(complex_valid),
        .frame_start(frame_start),

        .br_ready(br_ready),

        .br_real(br_real),
        .br_imag(br_imag),

        .br_valid(br_valid)
    );

endmodule