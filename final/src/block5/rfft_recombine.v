`timescale 1ns / 1ps
// ============================================================
// rfft_recombine - Bloque 5 (etapa de recombinacion RFFT)
//
// El Bloque 4 calcula la FFT compleja Z[0..1023] de la senal
// empaquetada z[n] = x[2n] + j*x[2n+1]. Este modulo la
// "desempaqueta" al espectro real X[0..511] (0..fs/2):
//
//   Xe[k] = (Z[k] + Z*[N-k]) / 2
//   Xo[k] = -j * (Z[k] - Z*[N-k]) / 2
//   X[k]  = Xe[k] + W2048^k * Xo[k]
//
// W2048^k viene de la tabla twiddles_recomb (1025 x 32 bits) a
// traves del puerto pass-through tw_addr/data_recomb del Bloque 4
// (latencia 1 ciclo, INTEGRATION-RULES seccion 7).
//
// La multiplicacion compleja + suma reutiliza butterfly_radix2
// (Bloque 3): con e = Xe, o = Xo, tw = W -> z1 = Xe + W*Xo = X[k]
// (z2 se descarta). Misma saturacion Q15 de todo el proyecto.
//
// Protocolo:
//   entrada: fft_real/imag, fft_valid (1024 bins), fft_done
//   salida:  g_real/imag, g_valid (512 pulsos con gaps), g_done
// La salida usa el mismo formato fft_* que consume el
// spectrum_buffer del drawer (acepta gaps entre valids).
//
// Decimacion de display: el espectro real tiene 1025 bins unicos
// (0..fs/2, paso fs/2048 = 23.44 Hz). El LCD muestra 512 columnas
// cubriendo 0..24 kHz, asi que se emite UN BIN DE CADA DOS
// (k = 0,2,...,1022): columna d = k/2 -> 46.88 Hz/px, y el eje
// estatico del drawer (64 px = 3 kHz) queda exactamente calibrado.
//
// Latencia total: 1024 ciclos de captura + ~5 ciclos/bin * 512
// ~= 2.6k ciclos de calculo (despreciable vs el frame de audio).
// ============================================================

module rfft_recombine #(
    parameter DATA_WIDTH = 16,
    parameter N          = 1024,
    parameter ADDR_WIDTH = 10,
    parameter OUT_BINS   = 512
)(
    input  wire                   clk,
    input  wire                   rst_n,

    // ── entrada: stream del Bloque 4 ─────────────────────
    input  wire [DATA_WIDTH-1:0]  fft_real,
    input  wire [DATA_WIDTH-1:0]  fft_imag,
    input  wire                   fft_valid,
    input  wire                   fft_done,

    // ── puerto recomb del twiddle_rom (via Bloque 4) ─────
    output reg  [10:0]            tw_addr_recomb,
    input  wire [31:0]            tw_data_recomb,

    // ── salida: espectro real hacia el drawer ────────────
    output reg  [DATA_WIDTH-1:0]  g_real,
    output reg  [DATA_WIDTH-1:0]  g_imag,
    output reg                    g_valid,
    output reg                    g_done
);

    // ----- memoria de captura Z[0..N-1] (dual read) -----
    reg [31:0] zmem [0:N-1];
    reg [31:0] rd_a, rd_b;             // Z[k], Z[N-k]
    reg [ADDR_WIDTH-1:0] rd_addr_a, rd_addr_b;

    always @(posedge clk) begin
        rd_a <= zmem[rd_addr_a];
        rd_b <= zmem[rd_addr_b];
    end

    // ----- FSM -----
    localparam S_CAPTURE = 3'd0;
    localparam S_SET     = 3'd1;  // direcciones RAM + twiddle
    localparam S_WAIT    = 3'd2;  // latencia RAM/ROM
    localparam S_LATCH   = 3'd3;  // registra Xe/Xo/W, dispara butterfly
    localparam S_BF      = 3'd4;  // butterfly_en activo
    localparam S_OUT     = 3'd5;  // z1 valido -> g_valid
    localparam S_DONE    = 3'd6;

    reg [2:0]            state;
    reg [ADDR_WIDTH-1:0] cap_cnt;
    reg [9:0]            k;

    // ----- Xe / Xo (combinacional desde rd_a / rd_b) -----
    wire signed [DATA_WIDTH-1:0] ar = rd_a[31:16];   // Z[k]
    wire signed [DATA_WIDTH-1:0] ai = rd_a[15:0];
    wire signed [DATA_WIDTH-1:0] br = rd_b[31:16];   // Z[N-k]
    wire signed [DATA_WIDTH-1:0] bi = rd_b[15:0];

    // sumas de 17 bits, luego /2 (>>>1): cabe exacto en 16 bits
    wire signed [DATA_WIDTH:0] sum_r  = ar + br;     // A + B*  (parte real)
    wire signed [DATA_WIDTH:0] sum_i  = ai - bi;     //         (parte imag)
    wire signed [DATA_WIDTH:0] dif_r  = ar - br;     // A - B*  (parte real)
    wire signed [DATA_WIDTH:0] dif_i  = ai + bi;     //         (parte imag)

    wire signed [DATA_WIDTH-1:0] xe_r = sum_r >>> 1;
    wire signed [DATA_WIDTH-1:0] xe_i = sum_i >>> 1;
    // Xo = -j * dif / 2 :  -j*(x + jy) = y - jx
    wire signed [DATA_WIDTH-1:0] xo_r = dif_i >>> 1;
    wire signed [DATA_WIDTH-1:0] xo_i = (-dif_r) >>> 1;

    // ----- registros de entrada del butterfly -----
    reg signed [DATA_WIDTH-1:0] e_real_q, e_imag_q;
    reg signed [DATA_WIDTH-1:0] o_real_q, o_imag_q;
    reg signed [DATA_WIDTH-1:0] tw_real_q, tw_imag_q;
    reg                         bf_en;

    wire signed [DATA_WIDTH-1:0] z1_real_w, z1_imag_w;
    wire                         bf_done_w;

    butterfly_radix2 #(
        .DATA_WIDTH (DATA_WIDTH)
    ) u_butterfly (
        .clk            (clk),
        .rst_n          (rst_n),
        .e_real         (e_real_q),
        .e_imag         (e_imag_q),
        .o_real         (o_real_q),
        .o_imag         (o_imag_q),
        .tw_real        (tw_real_q),
        .tw_imag        (tw_imag_q),
        .butterfly_en   (bf_en),
        .z1_real        (z1_real_w),
        .z1_imag        (z1_imag_w),
        .z2_real        (),                 // no se usa
        .z2_imag        (),
        .butterfly_done (bf_done_w)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state          <= S_CAPTURE;
            cap_cnt        <= {ADDR_WIDTH{1'b0}};
            k              <= 10'd0;
            rd_addr_a      <= {ADDR_WIDTH{1'b0}};
            rd_addr_b      <= {ADDR_WIDTH{1'b0}};
            tw_addr_recomb <= 11'd0;
            e_real_q       <= 0;  e_imag_q <= 0;
            o_real_q       <= 0;  o_imag_q <= 0;
            tw_real_q      <= 0;  tw_imag_q <= 0;
            bf_en          <= 1'b0;
            g_real         <= 0;
            g_imag         <= 0;
            g_valid        <= 1'b0;
            g_done         <= 1'b0;
        end else begin
            bf_en   <= 1'b0;
            g_valid <= 1'b0;
            g_done  <= 1'b0;

            case (state)

                // captura el frame Z del Bloque 4
                S_CAPTURE: begin
                    if (fft_valid) begin
                        zmem[cap_cnt] <= {fft_real, fft_imag};
                        cap_cnt       <= cap_cnt + 1'b1;
                    end
                    if (fft_done) begin
                        cap_cnt <= {ADDR_WIDTH{1'b0}};
                        k       <= 10'd0;
                        state   <= S_SET;
                    end
                end

                // direcciones: Z[k], Z[(N-k) mod N], W2048^k
                S_SET: begin
                    rd_addr_a      <= k[ADDR_WIDTH-1:0];
                    rd_addr_b      <= (10'd0 - k);        // (N-k) mod 1024
                    tw_addr_recomb <= {1'b0, k};
                    state          <= S_WAIT;
                end

                // 1 ciclo de latencia de RAM y ROM
                S_WAIT: state <= S_LATCH;

                // registra operandos y dispara butterfly
                S_LATCH: begin
                    e_real_q  <= xe_r;
                    e_imag_q  <= xe_i;
                    o_real_q  <= xo_r;
                    o_imag_q  <= xo_i;
                    tw_real_q <= tw_data_recomb[31:16];
                    tw_imag_q <= tw_data_recomb[15:0];
                    bf_en     <= 1'b1;
                    state     <= S_BF;
                end

                // butterfly procesando (1 ciclo)
                S_BF: state <= S_OUT;

                // z1 = Xe + W*Xo = X[k]
                S_OUT: begin
                    g_real  <= z1_real_w;
                    g_imag  <= z1_imag_w;
                    g_valid <= 1'b1;

                    if (k == (OUT_BINS-1)*2) begin   // ultimo bin par (1022)
                        g_done <= 1'b1;
                        state  <= S_DONE;
                    end else begin
                        k     <= k + 10'd2;          // decimacion: solo bins pares
                        state <= S_SET;
                    end
                end

                S_DONE: begin
                    state <= S_CAPTURE;
                end

                default: state <= S_CAPTURE;
            endcase
        end
    end

endmodule
