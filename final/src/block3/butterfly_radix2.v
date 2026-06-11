// =============================================================================
// butterfly_radix2.v – Bloque 3: Mariposa Radix-2 DIT compleja Q15
// Proyecto: RFFT en FPGA Tang Primer 20K (Gowin GW2A)
// =============================================================================
//
// Latencia: 1 ciclo. butterfly_en en T → salidas válidas + butterfly_done en T+1.
//
// CRÍTICO: NO aplica shift de 1 bit por etapa. Eso es responsabilidad del
// fft_stage_controller (Bloque 4).
// =============================================================================

`timescale 1ns / 1ps

module butterfly_radix2 #(
    parameter DATA_WIDTH = 16
) (
    input  wire                          clk,
    input  wire                          rst_n,

    // Entradas (desde Bloque 4)
    input  wire signed [DATA_WIDTH-1:0]  e_real,
    input  wire signed [DATA_WIDTH-1:0]  e_imag,
    input  wire signed [DATA_WIDTH-1:0]  o_real,
    input  wire signed [DATA_WIDTH-1:0]  o_imag,
    input  wire signed [DATA_WIDTH-1:0]  tw_real,
    input  wire signed [DATA_WIDTH-1:0]  tw_imag,
    input  wire                          butterfly_en,

    // Salidas (hacia Bloque 4)
    output reg  signed [DATA_WIDTH-1:0]  z1_real,
    output reg  signed [DATA_WIDTH-1:0]  z1_imag,
    output reg  signed [DATA_WIDTH-1:0]  z2_real,
    output reg  signed [DATA_WIDTH-1:0]  z2_imag,
    output reg                           butterfly_done
);

    // =========================================================================
    // Constantes de saturación Q15
    // =========================================================================
    localparam signed [31:0] Q15_MAX = 32'sh00007FFF;
    localparam signed [31:0] Q15_MIN = 32'shFFFF8000;

    // =========================================================================
    // Función: multiplicación Q15×Q15 → Q15 con saturación
    // El resultado intermedio de 32 bits evita truncar antes de saturar.
    // =========================================================================
    function automatic signed [DATA_WIDTH-1:0] mul_q15;
        input signed [DATA_WIDTH-1:0] a, b;
        reg signed [31:0] prod_q30, result_ext;
        begin
            prod_q30   = $signed(a) * $signed(b);       // 32-bit Q30
            result_ext = $signed(prod_q30) >>> 15;       // aritmético, sigue en 32 bits

            if      ($signed(result_ext) > Q15_MAX) mul_q15 = Q15_MAX[DATA_WIDTH-1:0];
            else if ($signed(result_ext) < Q15_MIN) mul_q15 = Q15_MIN[DATA_WIDTH-1:0];
            else                                    mul_q15 = result_ext[DATA_WIDTH-1:0];
        end
    endfunction

    // =========================================================================
    // Función: suma con saturación Q15
    // =========================================================================
    function automatic signed [DATA_WIDTH-1:0] add_sat;
        input signed [DATA_WIDTH-1:0] a, b;
        reg signed [31:0] s;
        begin
            s = $signed({{16{a[DATA_WIDTH-1]}}, a}) + $signed({{16{b[DATA_WIDTH-1]}}, b});
            if      ($signed(s) > Q15_MAX) add_sat = Q15_MAX[DATA_WIDTH-1:0];
            else if ($signed(s) < Q15_MIN) add_sat = Q15_MIN[DATA_WIDTH-1:0];
            else                           add_sat = s[DATA_WIDTH-1:0];
        end
    endfunction

    // =========================================================================
    // Función: resta con saturación Q15
    // =========================================================================
    function automatic signed [DATA_WIDTH-1:0] sub_sat;
        input signed [DATA_WIDTH-1:0] a, b;
        reg signed [31:0] d;
        begin
            d = $signed({{16{a[DATA_WIDTH-1]}}, a}) - $signed({{16{b[DATA_WIDTH-1]}}, b});
            if      ($signed(d) > Q15_MAX) sub_sat = Q15_MAX[DATA_WIDTH-1:0];
            else if ($signed(d) < Q15_MIN) sub_sat = Q15_MIN[DATA_WIDTH-1:0];
            else                           sub_sat = d[DATA_WIDTH-1:0];
        end
    endfunction

    // =========================================================================
    // Lógica combinacional: calcular W*O y la mariposa
    // Todo combinacional; se registra en el flanco de clk (1 ciclo de latencia).
    // =========================================================================
    wire signed [DATA_WIDTH-1:0] prod_rr_w, prod_ii_w, prod_ri_w, prod_ir_w;
    wire signed [DATA_WIDTH-1:0] wo_real_w, wo_imag_w;
    wire signed [DATA_WIDTH-1:0] z1_real_w, z1_imag_w;
    wire signed [DATA_WIDTH-1:0] z2_real_w, z2_imag_w;

    // 4 multiplicaciones Q15 (→ 4 DSPs en Gowin GW2A)
    assign prod_rr_w = mul_q15(tw_real, o_real);
    assign prod_ii_w = mul_q15(tw_imag, o_imag);
    assign prod_ri_w = mul_q15(tw_real, o_imag);
    assign prod_ir_w = mul_q15(tw_imag, o_real);

    // W*O
    assign wo_real_w = sub_sat(prod_rr_w, prod_ii_w);
    assign wo_imag_w = add_sat(prod_ri_w, prod_ir_w);

    // Mariposa
    assign z1_real_w = add_sat(e_real, wo_real_w);
    assign z1_imag_w = add_sat(e_imag, wo_imag_w);
    assign z2_real_w = sub_sat(e_real, wo_real_w);
    assign z2_imag_w = sub_sat(e_imag, wo_imag_w);

    // =========================================================================
    // Registro de salidas: 1 ciclo de latencia
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            z1_real        <= 16'sd0;
            z1_imag        <= 16'sd0;
            z2_real        <= 16'sd0;
            z2_imag        <= 16'sd0;
            butterfly_done <= 1'b0;
        end else begin
            butterfly_done <= butterfly_en;

            if (butterfly_en) begin
                z1_real <= z1_real_w;
                z1_imag <= z1_imag_w;
                z2_real <= z2_real_w;
                z2_imag <= z2_imag_w;
            end
            // Salidas se mantienen hasta el siguiente butterfly_en (hold)
        end
    end

    // =========================================================================
    // Notas de síntesis Gowin GW2A
    // =========================================================================
    // 1. Las 4 assign mul_q15 son combinacionales; Gowin EDA las infiere como
    //    multiplicadores 18×18 en los bloques DSP del GW2A-LV18.
    //    Si el sintetizador no los infiere automáticamente, agregar:
    //    (* use_dsp = "yes" *) a las señales prod_xx_w.
    //
    // 2. La ruta crítica es: DSP (multiplicación) → sub_sat (wo_real) → add_sat
    //    (z1_real) → FF. A 50 MHz esto cierra holgadamente en Gowin GW2A.
    //
    // 3. Si se necesita >100 MHz, insertar un registro entre los productos y la
    //    suma de mariposa, cambiando latencia a 2 ciclos. Actualizar butterfly_done
    //    con un delay adicional de 1 ciclo.
    // =========================================================================

endmodule
