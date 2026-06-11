// =============================================================================
// complex_fft_core.v – Bloque 4: Controlador FFT Compleja
// Proyecto: RFFT en FPGA Tang Primer 20K (Gowin GW2A)
// =============================================================================
// CORRECCIONES respecto a la versión anterior:
//
//  [FIX-1] DEADLOCK en carga: br_ready ahora permanece en 1 durante
//          S_LOAD_DATA. Solo se baja al completar el frame (→ S_INIT_STAGE).
//          Antes: br_ready se bajaba en S_IDLE y nunca volvía a subir hasta
//          S_IDLE, causando deadlock con el protocolo valid/ready del TB.
//
//  [FIX-2] Off-by-one en load_cnt: El primer dato (i=0) se guarda en IDLE
//          en addr=0. S_LOAD_DATA empieza en load_cnt=1 para datos i=1..N-1.
//          Antes: load_cnt empezaba en 0, sobreescribiendo el dato 0 con el
//          dato 1, y el frame completaba 1 ciclo antes del último dato real.
//
//  [FIX-3] wm_rd_data sin driver: Se añade el assign que conecta rd_data_e
//          de la working_memory a la señal wm_rd_data usada en OUTPUT_STREAM.
//          Antes: wm_rd_data declarado como wire pero sin ningún assign,
//          resultando en X en toda la salida.
//
//  [FIX-4] z2 nunca escrito en memoria: Se añade un segundo ciclo de escritura
//          (ST_T2_Z2) en el stage_controller para guardar el resultado z2
//          (addr_o). Antes: el mux solo pasaba sc_wr_addr_z1/data_z1; las
//          posiciones impares del banco destino quedaban con basura, corrompiendo
//          todos los resultados de la FFT desde la etapa 1 en adelante.
//          NOTA: esta corrección requiere el fft_stage_controller.v actualizado
//          que se entrega junto a este archivo.
// =============================================================================

`timescale 1ns / 1ps

module complex_fft_core #(
    parameter N_COMPLEX  = 1024,
    parameter LOG2_N     = 10,
    parameter DATA_WIDTH = 16,
    parameter ADDR_WIDTH = 10,
    parameter FFT_MEM_FILE    = "twiddles_fft.hex",
    parameter RECOMB_MEM_FILE = "twiddles_recomb.hex"
)(
    input  wire                  clk,
    input  wire                  rst_n,

    // ── Bloque 2 (entrada bit-reversed) ──────────────────────────────
    input  wire [DATA_WIDTH-1:0] br_real,
    input  wire [DATA_WIDTH-1:0] br_imag,
    input  wire                  br_valid,
    output reg                   br_ready,   // [FIX-1] permanece en 1 en S_LOAD_DATA

    // ── Bloque 5 (salida espectro) ────────────────────────────────────
    output reg  [DATA_WIDTH-1:0] fft_real,
    output reg  [DATA_WIDTH-1:0] fft_imag,
    output reg                   fft_valid,
    output reg                   fft_done,

    // ── Puerto Recomb para Bloque 5 (pass-through twiddle_rom) ───────
    input  wire [10:0]           tw_addr_recomb,
    output wire [31:0]           tw_data_recomb
);

    // =========================================================================
    // Estados FSM principal
    // =========================================================================
    localparam [2:0]
        S_IDLE          = 3'd0,
        S_LOAD_DATA     = 3'd1,
        S_INIT_STAGE    = 3'd2,
        S_PROC_STAGE    = 3'd3,
        S_CHECK_STAGE   = 3'd4,
        S_OUTPUT_STREAM = 3'd5;

    reg [2:0]              state;
    reg [3:0]              stage_cnt;
    reg [ADDR_WIDTH-1:0]   load_cnt;
    reg [ADDR_WIDTH-1:0]   out_cnt;
    reg [ADDR_WIDTH-1:0]   out_rd_addr;
    reg                    out_started;   // [FIX-6] prefetch hecho
    reg                    active_bank;

    // =========================================================================
    // Señales de carga (S_LOAD_DATA → working_memory)
    // =========================================================================
    reg                    load_wr_en;
    reg [ADDR_WIDTH-1:0]   load_wr_addr;
    reg [31:0]             load_wr_data;

// =========================================================================
    // Señales del fft_stage_controller
    // =========================================================================
    reg                    sc_start;
    wire                   sc_done;

    wire [ADDR_WIDTH-1:0]  sc_rd_addr_e, sc_rd_addr_o;
    wire [31:0]            sc_rd_data_e, sc_rd_data_o;

    wire                   sc_wr_en;
    wire [ADDR_WIDTH-1:0]  sc_wr_addr; // Un solo cable de dirección
    wire [31:0]            sc_wr_data; // Un solo cable de datos

    // =========================================================================
    // Señales working_memory — muxes de puertos
    // =========================================================================
    wire                   wm_wr_en;
    wire [ADDR_WIDTH-1:0]  wm_wr_addr;
    wire [31:0]            wm_wr_data;
    wire                   wm_rd_bank;
    wire [ADDR_WIDTH-1:0]  wm_rd_addr;
    wire [31:0]            wm_rd_data;   // [FIX-3] ahora tiene driver vía assign

    // Escritura: en S_LOAD_DATA usa señales de carga; en S_PROC_STAGE usa
    // las del stage_controller. El stage_controller ya tiene ST_T2_Z2 interno
    // que alterna entre z1 y z2 usando un solo puerto de escritura [FIX-4].
    //
    // [FIX-5 integracion] El mux selecciona por load_wr_en y no por
    // (state == S_LOAD_DATA): load_wr_en es registrado, asi que la escritura
    // de la ULTIMA muestra (addr 1023) ocurre un ciclo despues de que la FSM
    // ya salto a S_INIT_STAGE. Con el mux por estado esa escritura se perdia
    // y mem[1023] quedaba sin inicializar, corrompiendo toda la FFT (el TB
    // original no lo detectaba porque las comparaciones con X dan falso).
    // active_bank aun no conmuta en ese ciclo, asi que el banco es correcto.
    assign wm_wr_en   = load_wr_en ? 1'b1         : sc_wr_en;
    assign wm_wr_addr = load_wr_en ? load_wr_addr : sc_wr_addr;
    assign wm_wr_data = load_wr_en ? load_wr_data : sc_wr_data;
    // Lectura: el banco de lectura es siempre el opuesto al de escritura
    assign wm_rd_bank = ~active_bank;
    assign wm_rd_addr = (state == S_OUTPUT_STREAM) ? out_rd_addr : sc_rd_addr_e;

    // [FIX-3] Conectar rd_data_e a wm_rd_data (antes era wire sin driver)
    assign wm_rd_data = sc_rd_data_e;

    // =========================================================================
    // Señales internas del Bloque 3 (ROM + butterfly)
    // =========================================================================
    wire [ADDR_WIDTH-1:0] tw_addr_fft;    // 9 bits → twiddle_rom (512 entradas W_1024)
    wire [31:0] tw_data_fft_w;    // {real[31:16], imag[15:0]} latencia 1 ciclo

    wire [DATA_WIDTH-1:0] e_real_w, e_imag_w;
    wire [DATA_WIDTH-1:0] o_real_w, o_imag_w;
    wire                  butterfly_en_w;
    wire                  butterfly_done_w;
    wire [DATA_WIDTH-1:0] z1_real_w, z1_imag_w;
    wire [DATA_WIDTH-1:0] z2_real_w, z2_imag_w;

    // =========================================================================
    // Instancia: working_memory (True Dual-Port: 1 wr + 2 rd simultáneos)
    // =========================================================================
    working_memory #(
        .DATA_WIDTH (32),           // {real[15:0], imag[15:0]}
        .ADDR_WIDTH (ADDR_WIDTH)
    ) u_working_memory (
        .clk        (clk),
        // Puerto escritura — muxeado entre carga y stage_controller
        .wr_en      (wm_wr_en),
        .wr_bank    (active_bank),  // banco destino de escritura
        .wr_addr    (wm_wr_addr),
        .wr_data    (wm_wr_data),
        // Puerto lectura E — compartido entre stage_controller y OUTPUT_STREAM
        .rd_bank    (wm_rd_bank),   // siempre lee del banco opuesto
        .rd_addr_e  (wm_rd_addr),
        .rd_data_e  (sc_rd_data_e),
        // Puerto lectura O — exclusivo del stage_controller
        .rd_addr_o  (sc_rd_addr_o),
        .rd_data_o  (sc_rd_data_o)
    );

    // =========================================================================
    // Instancia: twiddle_rom
    // tw_addr_fft: 9 bits (k = 0..511, accede a W_1024)
    // =========================================================================
    twiddle_rom #(
        .FFT_MEM_FILE    (FFT_MEM_FILE),
        .RECOMB_MEM_FILE (RECOMB_MEM_FILE)
    ) u_twiddle_rom (
        .clk             (clk),
        .rst_n           (rst_n),
        .tw_addr_fft     (tw_addr_fft[8:0]),   // [8:0] solo 9 bits
        .tw_data_fft     (tw_data_fft_w),
        .tw_addr_recomb  (tw_addr_recomb),
        .tw_data_recomb  (tw_data_recomb)
    );

    // =========================================================================
    // Instancia: butterfly_radix2
    // tw_real y tw_imag se extraen directamente de tw_data_fft_w estable en T+1
    // =========================================================================
    butterfly_radix2 #(
        .DATA_WIDTH (DATA_WIDTH)
    ) u_butterfly (
        .clk            (clk),
        .rst_n          (rst_n),
        .e_real         (e_real_w),
        .e_imag         (e_imag_w),
        .o_real         (o_real_w),
        .o_imag         (o_imag_w),
        .tw_real        (tw_data_fft_w[31:16]),  // bits [31:16] = real
        .tw_imag        (tw_data_fft_w[15:0]),   // bits [15: 0] = imag
        .butterfly_en   (butterfly_en_w),
        .z1_real        (z1_real_w),
        .z1_imag        (z1_imag_w),
        .z2_real        (z2_real_w),
        .z2_imag        (z2_imag_w),
        .butterfly_done (butterfly_done_w)
    );

    // =========================================================================
    // =========================================================================
    // Instanciación del Controlador de Etapas (Bloque 4 interno)
    // =========================================================================
    fft_stage_controller #(
        .N_COMPLEX(N_COMPLEX),
        .LOG2_N(LOG2_N),
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) u_stage_ctrl (
        .clk(clk),
        .rst_n(rst_n),
        .start(sc_start),
        .stage(stage_cnt),
        .stage_done(sc_done),

        // Lectura de la memoria (Working memory)
        .rd_addr_e(sc_rd_addr_e),
        .rd_addr_o(sc_rd_addr_o),
        .rd_data_e(sc_rd_data_e), 
        .rd_data_o(sc_rd_data_o), 

        // Escritura a la memoria (Unificada Z1 y Z2)
        .wr_en(sc_wr_en),
        .wr_addr_z1(sc_wr_addr),  
        .wr_data_z1(sc_wr_data),  

        // Conexiones a la ROM de Twiddles
        .tw_addr_fft(tw_addr_fft),
        .tw_data_fft(tw_data_fft_w), // ¡Con _w!

        // Conexiones a la Mariposa Radix-2
        .e_real(e_real_w),           // ¡Con _w!
        .e_imag(e_imag_w),           // ¡Con _w!
        .o_real(o_real_w),           // ¡Con _w!
        .o_imag(o_imag_w),           // ¡Con _w!
        .butterfly_en(butterfly_en_w),     // ¡Con _w!
        .butterfly_done(butterfly_done_w), // ¡Con _w!
        .z1_real(z1_real_w),         // ¡Con _w!
        .z1_imag(z1_imag_w),         // ¡Con _w!
        .z2_real(z2_real_w),         // ¡Con _w!
        .z2_imag(z2_imag_w)          // ¡Con _w!
    );

    // =========================================================================
    // FSM Principal
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= S_IDLE;
            stage_cnt    <= 4'd0;
            load_cnt     <= {ADDR_WIDTH{1'b0}};
            out_cnt      <= {ADDR_WIDTH{1'b0}};
            out_rd_addr  <= {ADDR_WIDTH{1'b0}};
            out_started  <= 1'b0;
            active_bank  <= 1'b0;
            br_ready     <= 1'b1;
            fft_valid    <= 1'b0;
            fft_done     <= 1'b0;
            fft_real     <= {DATA_WIDTH{1'b0}};
            fft_imag     <= {DATA_WIDTH{1'b0}};
            sc_start     <= 1'b0;
            load_wr_en   <= 1'b0;
            load_wr_addr <= {ADDR_WIDTH{1'b0}};
            load_wr_data <= 32'd0;
        end else begin
            sc_start   <= 1'b0;
            fft_done   <= 1'b0;
            fft_valid  <= 1'b0;
            load_wr_en <= 1'b0;

            case (state)

                // ── S_IDLE ────────────────────────────────────────────
                // Espera el primer dato. br_ready=1 siempre aquí.
                // Al detectar br_valid captura dato 0 en addr=0 y sube
                // load_cnt a 1 para que S_LOAD_DATA empiece por el dato 1.
                // [FIX-1] br_ready NO se baja aquí; se baja solo al
                // completar el frame (entrada a S_INIT_STAGE).
                S_IDLE: begin
                    br_ready <= 1'b1; // ¡CRÍTICO! Debe ser 1 para que el TB envíe el primer dato
                    if (br_valid) begin
                        load_wr_en   <= 1'b1;
                        load_wr_addr <= {ADDR_WIDTH{1'b0}};
                        load_wr_data <= {br_real, br_imag};
                        load_cnt     <= {{(ADDR_WIDTH-1){1'b0}}, 1'b1};
                        state        <= S_LOAD_DATA;
                    end else begin
                        load_wr_en   <= 1'b0;
                    end
                end

                // ── S_LOAD_DATA ───────────────────────────────────────
                // [FIX-1] br_ready=1 aquí para que el TB pueda seguir
                // enviando datos sin esperar.
                // [FIX-2] load_cnt empieza en 1 (dato 0 ya fue guardado
                // en S_IDLE). Condición de fin: load_cnt == N_COMPLEX-1.
                S_LOAD_DATA: begin
                    br_ready <= 1'b1;   // [FIX-1] mantener ready activo
                    if (br_valid) begin
                        load_wr_en   <= 1'b1;
                        load_wr_addr <= load_cnt;
                        load_wr_data <= {br_real, br_imag};
                        if (load_cnt == N_COMPLEX - 1) begin
                            // Frame completo → bajar br_ready y arrancar FFT
                            br_ready <= 1'b0;   // [FIX-1] único punto de bajada
                            state    <= S_INIT_STAGE;
                        end else begin
                            load_cnt <= load_cnt + 1'b1;
                        end
                    end
                end

                // ── S_INIT_STAGE ──────────────────────────────────────
                // Alterna banco Ping-Pong y lanza el stage_controller.
                // Etapa 0: active_bank 0→1 (lee banco 0, escribe banco 1).
                // Etapa 1: active_bank 1→0 (lee banco 1, escribe banco 0).
                S_INIT_STAGE: begin
                    active_bank <= ~active_bank;
                    sc_start    <= 1'b1;
                    state       <= S_PROC_STAGE;
                end

                // ── S_PROC_STAGE ──────────────────────────────────────
                S_PROC_STAGE: begin
                    if (sc_done) state <= S_CHECK_STAGE;
                end

                // ── S_CHECK_STAGE ─────────────────────────────────────
                S_CHECK_STAGE: begin
                    if (stage_cnt == LOG2_N - 1) begin
                        out_rd_addr <= {ADDR_WIDTH{1'b0}};
                        out_cnt     <= {ADDR_WIDTH{1'b0}};
                        active_bank <= ~active_bank; // Leer del banco opuesto para salida
                        state       <= S_OUTPUT_STREAM;
                    end else begin
                        stage_cnt <= stage_cnt + 1'b1;
                        state     <= S_INIT_STAGE;
                    end
                end

                // ── S_OUTPUT_STREAM ───────────────────────────────────
                // Lee del banco resultado (rd_bank = ~active_bank) via
                // wm_rd_data = sc_rd_data_e [FIX-3].
                // [FIX-6 integracion] La BSRAM tiene 1 ciclo de latencia:
                // el primer ciclo solo deja la direccion 0 en vuelo
                // (prefetch) sin asertar fft_valid. Antes la salida
                // quedaba corrida un bin: fft[k] = mem[k-1] y fft[0]
                // contenia basura del ultimo read de la etapa 9.
                S_OUTPUT_STREAM: begin
                    if (!out_started) begin
                        out_started <= 1'b1;             // prefetch addr 0
                        out_rd_addr <= out_rd_addr + 1'b1;
                    end else begin
                        fft_valid <= 1'b1;
                        fft_real  <= wm_rd_data[31:16];  // [FIX-3] tiene driver
                        fft_imag  <= wm_rd_data[15:0];
                        if (out_cnt == N_COMPLEX - 1) begin
                            fft_done    <= 1'b1;
                            out_started <= 1'b0;
                            state       <= S_IDLE;
                        end else begin
                            out_cnt     <= out_cnt + 1'b1;
                            out_rd_addr <= out_rd_addr + 1'b1;
                        end
                    end
                end

            endcase
        end
    end

endmodule