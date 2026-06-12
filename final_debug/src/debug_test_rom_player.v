`timescale 1ns / 1ps
// ============================================================
// debug_test_rom_player - ROM-based autonomous test vector injector
//
// Synchronous BSRAM read with 1-cycle read latency.
// FSM emits exactly N_SAMPLES per frame without duplication.
//
// Pipeline:
//   Cycle N:   rom_addr = {vec_sel, sample_addr}
//   Cycle N+1: rom_data <= rom[rom_addr]  (BSRAM output)
//   Cycle N+2: consumer emits rom_data
// ============================================================

module debug_test_rom_player #(
    parameter CLK_FREQ          = 27000000,
    parameter SAMPLE_RATE       = 48000,
    parameter N_SAMPLES         = 2048,
    parameter ADDR_WIDTH        = 11,
    parameter NUM_VECTORS       = 8,
    parameter VEC_SEL_WIDTH     = 3,
    parameter FRAMES_PER_VEC    = 70,
    parameter HEX_FILE          = "src/debug_hex/debug_vectors.hex"
)(
    input  wire                          clk,
    input  wire                          rst_n,

    output wire                          sample_valid,
    output wire [15:0]                   sample_out,
    output wire                          frame_start,
    output wire [VEC_SEL_WIDTH-1:0]      current_vector
);

    // FIX (Gowin): syn_romstyle fuerza BSRAM (el atributo Xilinx ram_style
    // lo ignora GowinSynthesis y esta ROM de 16384x16 = 256 Kbit caia a
    // flip-flops -> excede recursos, o quedaba sin inicializar -> entrada
    // basura al pipeline. Ver SUG550 sec. 5.17.
    reg [15:0] rom [0:NUM_VECTORS*N_SAMPLES-1] /* synthesis syn_romstyle="block_rom" */;

    initial begin
        $readmemh("src/debug_hex/debug_vectors.hex", rom);
    end

    localparam integer TICK_MAX = (CLK_FREQ + (SAMPLE_RATE/2)) / SAMPLE_RATE;
    localparam TIMER_W = 10;

    reg [TIMER_W-1:0]        timer;
    wire                     tick = (timer == 0);

    reg [VEC_SEL_WIDTH-1:0]  vec_sel;
    reg [ADDR_WIDTH-1:0]     sample_addr;
    reg [ADDR_WIDTH-1:0]     emit_cnt;
    reg [6:0]                frame_cnt;
    reg [1:0]                state;

    assign current_vector = vec_sel;

    wire [ADDR_WIDTH+VEC_SEL_WIDTH-1:0] rom_addr;
    assign rom_addr = {vec_sel, sample_addr};

    reg [15:0] rom_data;
    always @(posedge clk) begin
        rom_data <= rom[rom_addr];
    end

    reg              sample_valid_r;
    reg [15:0]       sample_out_r;
    reg              frame_start_r;

    assign sample_valid = sample_valid_r;
    assign sample_out   = sample_out_r;
    assign frame_start  = frame_start_r;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            timer          <= 0;
            vec_sel        <= 0;
            sample_addr    <= 0;
            emit_cnt       <= 0;
            frame_cnt      <= 0;
            state          <= 2'd0;
            sample_valid_r <= 1'b0;
            sample_out_r   <= 16'd0;
            frame_start_r  <= 1'b0;
        end else begin
            sample_valid_r <= 1'b0;
            frame_start_r  <= 1'b0;

            if (timer == 0)
                timer <= TICK_MAX - 1;
            else
                timer <= timer - 1;

            if (tick) begin
                case (state)
                    // frame_start + prime address 0
                    2'd0: begin
                        sample_addr   <= 0;
                        emit_cnt      <= 0;
                        frame_start_r <= 1'b1;
                        state         <= 2'd1;
                    end

                    // prefetch: mantener address 0 para que rom_data quede en
                    // rom[0] al entrar a emit. (FIX off-by-one: antes ponia
                    // sample_addr<=1 y el primer emit sacaba rom[1], saltando la
                    // muestra 0 y colando rom[2048] = muestra 0 del vector siguiente.)
                    2'd1: begin
                        sample_addr <= 0;
                        state       <= 2'd2;
                    end

                    // emit pipeline: rom_data now holds the value from the
                    // PREVIOUS cycle's address. Emit it and queue next address.
                    2'd2: begin
                        sample_valid_r <= 1'b1;
                        sample_out_r   <= rom_data;
                        emit_cnt       <= emit_cnt + 1;

                        if (emit_cnt == N_SAMPLES - 1) begin
                            sample_addr <= 0;
                            emit_cnt    <= 0;

                            if (frame_cnt == FRAMES_PER_VEC - 1) begin
                                frame_cnt <= 0;
                                if (vec_sel == NUM_VECTORS - 1)
                                    vec_sel <= 0;
                                else
                                    vec_sel <= vec_sel + 1;
                            end else begin
                                frame_cnt <= frame_cnt + 1;
                            end

                            state <= 2'd0;
                        end else begin
                            sample_addr <= sample_addr + 1;
                        end
                    end

                    default: state <= 2'd0;
                endcase
            end
        end
    end

endmodule
