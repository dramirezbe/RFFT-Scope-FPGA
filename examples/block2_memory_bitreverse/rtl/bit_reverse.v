// ============================================================
// Módulo: bit_reverse
// Bloque 2 - Memoria y Reordenamiento
//
// Función:
// Invierte el orden de los bits de una dirección.
// Para N = 1024 se usan 10 bits de dirección.
//
// Ejemplo con 10 bits:
// index_in  = 0000000011  // decimal 3
// index_out = 1100000000  // decimal 768
// ============================================================

module bit_reverse #(
    parameter ADDR_WIDTH = 10
)(
    input  wire [ADDR_WIDTH-1:0] index_in,
    output wire [ADDR_WIDTH-1:0] index_out
);

    genvar i;

    generate
        for (i = 0; i < ADDR_WIDTH; i = i + 1) begin : REVERSE_BITS
            assign index_out[i] = index_in[ADDR_WIDTH-1-i];
        end
    endgenerate

endmodule