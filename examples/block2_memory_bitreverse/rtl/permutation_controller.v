// ============================================================
// Módulo: permutation_controller
// Bloque 2 - Memoria y Reordenamiento Bit-Reverse
//
// Función:
// 1. Recibe 1024 muestras complejas en orden natural.
// 2. Las escribe en RAM.
// 3. Las lee en orden bit-reversed.
// 4. Entrega datos al Bloque 4 usando valid/ready.
//
// Nota:
// Este bloque NO escala, NO satura y NO modifica los datos.
// Solo reordena.
// ============================================================

module permutation_controller #(
    parameter ADDR_WIDTH = 10,
    parameter DATA_WIDTH = 16,
    parameter DEPTH = 1024
)(
    input  wire clk,
    input  wire rst_n,

    // Entrada desde Bloque 1
    input  wire signed [DATA_WIDTH-1:0] complex_real,
    input  wire signed [DATA_WIDTH-1:0] complex_imag,
    input  wire complex_valid,
    input  wire frame_start,

    // Entrada de handshake desde Bloque 4
    input  wire br_ready,

    // Salida hacia Bloque 4
    output reg  signed [DATA_WIDTH-1:0] br_real,
    output reg  signed [DATA_WIDTH-1:0] br_imag,
    output reg  br_valid
);

    // ========================================================
    // Estados de la FSM
    // ========================================================
    localparam IDLE         = 3'd0;
    localparam WRITE        = 3'd1;
    localparam SET_READ     = 3'd2;
    localparam WAIT_READ    = 3'd3;
    localparam OUTPUT_VALID = 3'd4;
    localparam DONE         = 3'd5;

    reg [2:0] state;

    // ========================================================
    // Contadores
    // ========================================================
    reg [ADDR_WIDTH-1:0] wr_counter;
    reg [ADDR_WIDTH-1:0] rd_counter;

    // ========================================================
    // Señales internas
    // ========================================================
    reg wr_en;
    reg [ADDR_WIDTH-1:0] wr_addr;
    reg [ADDR_WIDTH-1:0] rd_addr;

    wire [ADDR_WIDTH-1:0] bitrev_addr;

    wire signed [DATA_WIDTH-1:0] ram_real;
    wire signed [DATA_WIDTH-1:0] ram_imag;

    // ========================================================
    // Módulo bit_reverse
    // ========================================================
    bit_reverse #(
        .ADDR_WIDTH(ADDR_WIDTH)
    ) u_bit_reverse (
        .index_in(rd_counter),
        .index_out(bitrev_addr)
    );

    // ========================================================
    // RAM dual port
    // ========================================================
    dual_port_ram_buffer #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .DEPTH(DEPTH)
    ) u_ram (
        .clk(clk),

        .wr_en(wr_en),
        .wr_addr(wr_addr),
        .wr_real(complex_real),
        .wr_imag(complex_imag),

        .rd_addr(rd_addr),
        .rd_real(ram_real),
        .rd_imag(ram_imag)
    );

    // ========================================================
    // FSM principal
    // ========================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= IDLE;

            wr_counter <= {ADDR_WIDTH{1'b0}};
            rd_counter <= {ADDR_WIDTH{1'b0}};

            wr_en      <= 1'b0;
            wr_addr    <= {ADDR_WIDTH{1'b0}};
            rd_addr    <= {ADDR_WIDTH{1'b0}};

            br_real    <= {DATA_WIDTH{1'b0}};
            br_imag    <= {DATA_WIDTH{1'b0}};
            br_valid   <= 1'b0;
        end else begin

            // Valor por defecto
            wr_en <= 1'b0;

            case (state)

                // --------------------------------------------
                // IDLE: espera inicio de frame
                // --------------------------------------------
                IDLE: begin
                    br_valid   <= 1'b0;
                    wr_counter <= {ADDR_WIDTH{1'b0}};
                    rd_counter <= {ADDR_WIDTH{1'b0}};

                    if (frame_start) begin
                        state <= WRITE;
                    end
                end

                // --------------------------------------------
                // WRITE: guarda datos en orden natural
                // --------------------------------------------
                WRITE: begin
                    br_valid <= 1'b0;

                    if (complex_valid) begin
                        wr_en   <= 1'b1;
                        wr_addr <= wr_counter;

                        if (wr_counter == DEPTH-1) begin
                            wr_counter <= {ADDR_WIDTH{1'b0}};
                            rd_counter <= {ADDR_WIDTH{1'b0}};
                            state      <= SET_READ;
                        end else begin
                            wr_counter <= wr_counter + 1'b1;
                        end
                    end
                end

                // --------------------------------------------
                // SET_READ: coloca dirección bit-reversed
                // --------------------------------------------
                SET_READ: begin
                    br_valid <= 1'b0;
                    rd_addr  <= bitrev_addr;
                    state    <= WAIT_READ;
                end

                // --------------------------------------------
                // WAIT_READ: espera latencia de RAM síncrona
                // --------------------------------------------
                WAIT_READ: begin
                    state <= OUTPUT_VALID;
                end

                // --------------------------------------------
                // OUTPUT_VALID: dato listo para Bloque 4
                // Mantiene br_valid hasta br_ready
                // --------------------------------------------
                OUTPUT_VALID: begin
                    br_real  <= ram_real;
                    br_imag  <= ram_imag;
                    br_valid <= 1'b1;

                    if (br_ready) begin
                        br_valid <= 1'b0;

                        if (rd_counter == DEPTH-1) begin
                            rd_counter <= {ADDR_WIDTH{1'b0}};
                            state      <= DONE;
                        end else begin
                            rd_counter <= rd_counter + 1'b1;
                            state      <= SET_READ;
                        end
                    end
                end

                // --------------------------------------------
                // DONE: terminó el frame
                // --------------------------------------------
                DONE: begin
                    br_valid <= 1'b0;
                    state    <= IDLE;
                end

                default: begin
                    state <= IDLE;
                end

            endcase
        end
    end

endmodule