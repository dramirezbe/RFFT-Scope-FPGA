module fft_stage_controller #(
    parameter N_COMPLEX  = 1024,
    parameter LOG2_N     = 10,
    parameter DATA_WIDTH = 16,
    parameter ADDR_WIDTH = 10
)(
    input  wire                    clk, rst_n, start,
    input  wire [3:0]              stage,
    output reg                     stage_done,

    output reg  [ADDR_WIDTH-1:0]   rd_addr_e, rd_addr_o,
    input  wire [31:0]             rd_data_e, rd_data_o,

    output reg                     wr_en,
    output reg  [ADDR_WIDTH-1:0]   wr_addr_z1,   // Usado secuencialmente para Z1 y Z2
    output reg  [31:0]             wr_data_z1,

    output reg  [ADDR_WIDTH-1:0]   tw_addr_fft,
    input  wire [31:0]             tw_data_fft,

    output reg  [DATA_WIDTH-1:0]   e_real, e_imag, o_real, o_imag,
    output reg                     butterfly_en,
    input  wire                    butterfly_done,
    input  wire [DATA_WIDTH-1:0]   z1_real, z1_imag, z2_real, z2_imag
);

    wire [ADDR_WIDTH-1:0] stride      = 10'h001 << stage;
    wire [ADDR_WIDTH-1:0] group_size  = stride << 1;
    wire [ADDR_WIDTH:0]   num_groups  = (N_COMPLEX >> 1) >> stage;

    reg [ADDR_WIDTH-1:0] grp, bf;

    wire [ADDR_WIDTH-1:0] addr_e_next  = grp * group_size + bf;
    wire [ADDR_WIDTH-1:0] addr_o_next  = addr_e_next + stride;
    wire [ADDR_WIDTH-1:0] tw_step      = 10'd512 >> stage;
    wire [ADDR_WIDTH-1:0] tw_addr_next = bf * tw_step;

 // Agregamos un estado extra para la latencia de la memoria
    localparam ST_IDLE     = 3'd0,
               ST_READ     = 3'd1, // T: Enviar direcciones a cables
               ST_WAIT_MEM = 3'd2, // T+1: Esperar a que BSRAM registre dirección
               ST_LATCH    = 3'd3, // T+2: BSRAM escupe dato, disparar Mariposa
               ST_WAIT_MAC = 3'd4, // T+3: Esperar cálculo de mariposa
               ST_WRITE_Z1 = 3'd5, // T+4: Guardar Z1 
               ST_WRITE_Z2 = 3'd6; // T+5: Guardar Z2 

    reg [2:0] st;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st <= ST_IDLE;
            grp <= '0; bf <= '0;
            stage_done <= 1'b0; butterfly_en <= 1'b0; wr_en <= 1'b0;
        end else begin
            stage_done   <= 1'b0;
            butterfly_en <= 1'b0;
            wr_en        <= 1'b0;

            case (st)
                ST_IDLE: begin
                    if (start) begin
                        grp <= '0; bf <= '0;
                        st  <= ST_READ;
                    end
                end

                // [C4-1] T: Petición de lectura. Direcciones cambian al final de este ciclo.
                ST_READ: begin
                    tw_addr_fft <= tw_addr_next;
                    rd_addr_e   <= addr_e_next;
                    rd_addr_o   <= addr_o_next;
                    st          <= ST_WAIT_MEM; // Nuevo estado
                end

                // T+1: Las RAMs/ROM ven la dirección en este flanco y buscan el dato.
                ST_WAIT_MEM: begin
                    st <= ST_LATCH;
                end

                // [C4-1] T+2: Datos de RAM 100% estables. Capturamos y disparamos.
                ST_LATCH: begin
                    e_real       <= rd_data_e[31:16];
                    e_imag       <= rd_data_e[15:0];
                    o_real       <= rd_data_o[31:16];
                    o_imag       <= rd_data_o[15:0];
                    butterfly_en <= 1'b1;
                    st           <= ST_WAIT_MAC;
                end

                // T+3: La mariposa procesa internamente
                ST_WAIT_MAC: begin
                    if (butterfly_done) begin
                        st <= ST_WRITE_Z1;
                    end
                end

                // [C4-2] T+4: Aplicar Shift Aritmético y Guardar Z1
                ST_WRITE_Z1: begin
                    wr_addr_z1 <= rd_addr_e; // Reutilizamos dirección registrada
                    wr_data_z1 <= { {z1_real[15], z1_real[15:1]}, {z1_imag[15], z1_imag[15:1]} };
                    wr_en      <= 1'b1;
                    st         <= ST_WRITE_Z2;
                end

                // [C4-2] T+5: Aplicar Shift Aritmético y Guardar Z2
                ST_WRITE_Z2: begin
                    wr_addr_z1 <= rd_addr_o; // Reutilizamos dirección registrada
                    wr_data_z1 <= { {z2_real[15], z2_real[15:1]}, {z2_imag[15], z2_imag[15:1]} };
                    wr_en      <= 1'b1;

                    // Actualizar índices
                    if (bf == stride - 1) begin
                        bf <= '0;
                        if (grp == num_groups[ADDR_WIDTH-1:0] - 1) begin
                            grp        <= '0;
                            stage_done <= 1'b1;
                            st         <= ST_IDLE;
                        end else begin
                            grp <= grp + 1'b1;
                            st  <= ST_READ;
                        end
                    end else begin
                        bf <= bf + 1'b1;
                        st <= ST_READ;
                    end
                end
                
                default: st <= ST_IDLE;
            endcase
        end
    end
endmodule