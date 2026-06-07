`timescale 1ns/1ps
module tb_stage_ctrl;
    // ── Parámetros ────────────────────────────────────────────────
    localparam N  = 1024, LN = 10, DW = 16, AW = 10;
    localparam CLK_PERIOD = 20;

    reg  clk, rst_n, start;
    reg  [3:0] stage;

    // Señales del DUT
    wire [AW-1:0]          tw_addr_fft;
    wire [2*DW-1:0]        tw_data_fft;
    wire                   butterfly_en;
    wire                   butterfly_done;
    wire [DW-1:0]          e_real, e_imag, o_real, o_imag;
    wire [DW-1:0]          z1_real, z1_imag, z2_real, z2_imag;
    wire                   wr_en;
    wire [AW-1:0]          wr_addr_z1, wr_addr_z2;
    wire [2*DW-1:0]        wr_data_z1, wr_data_z2;
    wire                   stage_done;

    // Modelo simple de ROM (W0 = 1 + j0)
    reg [2*DW-1:0] tw_data_reg;
    always @(posedge clk)
        tw_data_reg <= {16'h7FFF, 16'h0000};

    // Modelo simple de Butterfly (latencia 1 ciclo)
    reg bf_done_q;
    always @(posedge clk or negedge rst_n)
        if (!rst_n) bf_done_q <= 1'b0;
        else        bf_done_q <= butterfly_en;
    assign butterfly_done = bf_done_q;

    // ── Instancia del DUT (completa) ─────────────────────────────────
    fft_stage_controller #(
        .N_COMPLEX(N),
        .LOG2_N(LN),
        .DATA_WIDTH(DW),
        .ADDR_WIDTH(AW)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .stage(stage),
        .stage_done(stage_done),
        .rd_addr_e(), .rd_addr_o(),           // no usados en este TB
        .rd_data_e(32'h0), .rd_data_o(32'h0), // datos dummy
        .wr_en(wr_en),
        .wr_addr_z1(wr_addr_z1), .wr_addr_z2(wr_addr_z2),
        .wr_data_z1(wr_data_z1), .wr_data_z2(wr_data_z2),
        .tw_addr_fft(tw_addr_fft),
        .tw_data_fft(tw_data_reg),
        .e_real(e_real), .e_imag(e_imag),
        .o_real(o_real), .o_imag(o_imag),
        .butterfly_en(butterfly_en),
        .butterfly_done(butterfly_done),
        .z1_real(z1_real), .z1_imag(z1_imag),
        .z2_real(z2_real), .z2_imag(z2_imag)
    );

    // ── Clock ─────────────────────────────────────────────────────
    always #(CLK_PERIOD/2) clk = ~clk;

    // ── Estímulos ─────────────────────────────────────────────────
    initial begin
        $dumpfile("tb_stage_ctrl.vcd");
        $dumpvars(0, tb_stage_ctrl);

        clk = 0; rst_n = 0; start = 0; stage = 0;
        repeat(5) @(posedge clk);
        rst_n = 1;
        repeat(5) @(posedge clk);

        // Prueba Etapa 0
        $display("Probando Etapa 0...");
        start = 1; @(posedge clk); start = 0;
        wait(stage_done);
        @(posedge clk);

        // Prueba Etapa 5
        $display("Probando Etapa 5...");
        stage = 5;
        start = 1; @(posedge clk); start = 0;
        wait(stage_done);
        @(posedge clk);

        $display("Simulación completada. Revisa el VCD en GTKWave.");
        #100 $finish;
    end

endmodule