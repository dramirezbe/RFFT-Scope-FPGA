// =============================================================================
// twiddle_rom.v – Bloque 3: ROM dual de twiddle factors
// Proyecto: RFFT en FPGA Tang Primer 20K (Gowin GW2A)
// =============================================================================
//
// Implementa dos ROMs síncronas (BSRAM Gowin) para los twiddle factors:
//
//   Puerto FFT   : 512 entradas × 32 bits  → Wk_1024,  k = 0..511
//   Puerto Recomb: 1025 entradas × 32 bits → Wk_2048,  k = 0..1024
//
// Formato de cada palabra de 32 bits:
//   bits [31:16] = parte real  (Q15, complemento a 2)
//   bits [15: 0] = parte imag  (Q15, complemento a 2)
//
// LATENCIA: 1 ciclo de reloj (BSRAM síncrono Gowin).
//   Si la dirección se presenta en el ciclo T, el dato estará disponible en T+1.
//   El consumidor (Bloque 4 / Bloque 5) debe prefetchear con 1 ciclo de adelanto.
//
// Parámetros globales (del documento de integración):
//   clk    : reloj común ≥ 50 MHz
//   rst_n  : reset asíncrono activo bajo (no se usa en ROMs, incluido por consistencia)
//
// Interfaces:
//   Puerto FFT   (hacia Bloque 4):
//     tw_addr_fft[8:0]   → dirección (0..511)
//     tw_data_fft[31:0]  → {real[15:0], imag[15:0]} con 1 ciclo de latencia
//
//   Puerto Recomb (hacia Bloque 5):
//     tw_addr_recomb[10:0] → dirección (0..1024)
//     tw_data_recomb[31:0] → {real[15:0], imag[15:0]} con 1 ciclo de latencia
//
// Archivos de inicialización (generados por gen_twiddles.py):
//   twiddles_fft.hex    : 512 palabras de 32 bits
//   twiddles_recomb.hex : 1025 palabras de 32 bits
//
// Nota de síntesis Gowin:
//   Se usa la primitiva `pROM` o inferencia de BRAM con atributo `syn_romstyle`.
//   Para forzar BSRAM se incluye el atributo (* ram_style = "block" *).
//   El atributo `$readmemh` se usa para simulación; Gowin EDA usa los .mi en síntesis.
// =============================================================================

`timescale 1ns / 1ps

module twiddle_rom #(
    // Parámetros locales del Bloque 3 (no modificar sin acuerdo del arquitecto)
    parameter DATA_WIDTH          = 16,    // Ancho Q15
    parameter TWIDDLE_FFT_DEPTH   = 512,   // Entradas para FFT
    parameter TWIDDLE_RECOMB_DEPTH= 1025,  // Entradas para recombinación
    parameter TWIDDLE_FFT_ADDR_W  = 9,     // ceil(log2(512)) = 9
    parameter TWIDDLE_RECOMB_ADDR_W = 11,  // 11 bits (se usan solo 1025 de 2048)
    // Archivos de inicialización (path relativo al proyecto)
    parameter FFT_MEM_FILE    = "twiddles_fft.hex",
    parameter RECOMB_MEM_FILE = "twiddles_recomb.hex"
) (
    input  wire                          clk,
    input  wire                          rst_n,    // no usado en ROM; por consistencia global

    // ── Puerto FFT (Bloque 4) ────────────────────────────────────────────────
    input  wire [TWIDDLE_FFT_ADDR_W-1:0]    tw_addr_fft,      // dirección 0..511
    output reg  [2*DATA_WIDTH-1:0]          tw_data_fft,      // {real,imag}, latencia 1 ciclo

    // ── Puerto Recomb (Bloque 5) ─────────────────────────────────────────────
    input  wire [TWIDDLE_RECOMB_ADDR_W-1:0] tw_addr_recomb,   // dirección 0..1024
    output reg  [2*DATA_WIDTH-1:0]          tw_data_recomb    // {real,imag}, latencia 1 ciclo
);

    // =========================================================================
    // Declaración de memorias
    // Atributo (* ram_style = "block" *) fuerza uso de BSRAM en Gowin EDA.
    // El $readmemh permite simulación con Icarus Verilog / ModelSim.
    // =========================================================================

    (* ram_style = "block" *)
    reg [2*DATA_WIDTH-1:0] rom_fft    [0:TWIDDLE_FFT_DEPTH-1];

    (* ram_style = "block" *)
    reg [2*DATA_WIDTH-1:0] rom_recomb [0:TWIDDLE_RECOMB_DEPTH-1];

    // ── Inicialización desde archivos .mi / hex ───────────────────────────────
    // En síntesis Gowin: los archivos .mi se especifican en el IP de BSRAM.
    // En simulación: $readmemh carga los valores (formato hex, una entrada por línea,
    // sin la cabecera del .mi → usar el .txt o generar un .hex limpio con gen_twiddles.py).
    initial begin
        $readmemh(FFT_MEM_FILE,    rom_fft);
        $readmemh(RECOMB_MEM_FILE, rom_recomb);
    end

    // =========================================================================
    // Puerto FFT – lectura síncrona (latencia 1 ciclo)
    // =========================================================================
    always @(posedge clk) begin
        tw_data_fft <= rom_fft[tw_addr_fft];
    end

    // =========================================================================
    // Puerto Recomb – lectura síncrona (latencia 1 ciclo)
    // =========================================================================
    always @(posedge clk) begin
        tw_data_recomb <= rom_recomb[tw_addr_recomb];
    end

    // =========================================================================
    // Acceso auxiliar: extracción de componentes (para uso en instanciación)
    // El consumidor puede conectar tw_data_fft[31:16] y tw_data_fft[15:0]
    // directamente a las entradas tw_real / tw_imag del butterfly_radix2.
    // =========================================================================
    // Ejemplo de conexión en el módulo padre:
    //   .tw_real (tw_data_fft[31:16]),
    //   .tw_imag (tw_data_fft[15:0])

endmodule
