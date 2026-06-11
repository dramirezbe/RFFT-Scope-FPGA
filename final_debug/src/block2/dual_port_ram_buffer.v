// ============================================================
// Módulo: dual_port_ram_buffer
// Bloque 2 - Memoria y Reordenamiento
//
// Función:
// Almacena muestras complejas de 16 bits real + 16 bits imag.
// Tiene un puerto de escritura y un puerto de lectura.
//
// Escritura:
//   wr_en = 1
//   mem[wr_addr] <= {wr_real, wr_imag}
//
// Lectura:
//   rd_addr selecciona la posición a leer.
//   rd_real y rd_imag entregan el dato registrado.
//
// Nota:
// Este módulo NO calcula bit-reverse.
// Este módulo NO controla valid/ready.
// Solo almacena y entrega datos.
// ============================================================

module dual_port_ram_buffer #(
    parameter ADDR_WIDTH = 10,
    parameter DATA_WIDTH = 16,
    parameter DEPTH = 1024
)(
    input  wire clk,

    // Puerto de escritura
    input  wire wr_en,
    input  wire [ADDR_WIDTH-1:0] wr_addr,
    input  wire signed [DATA_WIDTH-1:0] wr_real,
    input  wire signed [DATA_WIDTH-1:0] wr_imag,

    // Puerto de lectura
    input  wire [ADDR_WIDTH-1:0] rd_addr,
    output reg  signed [DATA_WIDTH-1:0] rd_real,
    output reg  signed [DATA_WIDTH-1:0] rd_imag
);

    // Memorias separadas para real e imaginario
    reg signed [DATA_WIDTH-1:0] mem_real [0:DEPTH-1];
    reg signed [DATA_WIDTH-1:0] mem_imag [0:DEPTH-1];

    always @(posedge clk) begin
        // Escritura síncrona
        if (wr_en) begin
            mem_real[wr_addr] <= wr_real;
            mem_imag[wr_addr] <= wr_imag;
        end

        // Lectura síncrona registrada
        rd_real <= mem_real[rd_addr];
        rd_imag <= mem_imag[rd_addr];
    end

endmodule