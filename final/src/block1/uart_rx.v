// uart_rx.v
// UART receiver + frame parser for BLOCK1 input from ESP32
// - Detects header 0xAA 0x55
// - Reads 2-byte length (big-endian) indicating number of samples
// - Reads payload bytes (length * 2 bytes), assembles 16-bit samples (MSB first)
// - Emits `sample_valid` (1-cycle) and `sample_out[15:0]` for each reconstructed sample
// - Asserts `frame_start` (1-cycle) for first sample of frame
// Notes:
// - Adjust `CLK_FREQ` to match your FPGA clock. For robust baud generation consider
//   replacing the simple integer divider with a fractional/NCO generator.

module uart_rx #(
    parameter integer CLK_FREQ = 50000000, // FPGA clock in Hz
    parameter integer BAUD     = 921600    // UART baud rate
) (
    input  wire clk,
    input  wire rst_n,
    input  wire rx,               // UART RX (idle = 1)

    output reg        sample_valid,
    output reg [15:0] sample_out,
    output reg        frame_start,
    output reg        frame_done
);

// Simple integer divider approach: number of clock cycles per UART bit
localparam integer BIT_TICKS = (CLK_FREQ + (BAUD/2)) / BAUD; // rounded divider

// --- Byte receiver (LSB first) ---
reg [31:0] bit_timer;
reg [3:0]  bit_idx; // 0..7 data bits
reg        receiving;
reg [7:0]  rx_shift;
reg        rx_byte_valid;

// Start detection (detect falling edge -> start bit)
reg rx_sync0, rx_sync1;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        rx_sync0 <= 1'b1;
        rx_sync1 <= 1'b1;
    end else begin
        rx_sync0 <= rx;
        rx_sync1 <= rx_sync0;
    end
end

wire rx_f = rx_sync1;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        bit_timer      <= 0;
        receiving      <= 1'b0;
        bit_idx        <= 0;
        rx_shift       <= 8'd0;
        rx_byte_valid  <= 1'b0;
    end else begin
        rx_byte_valid <= 1'b0;
        if (!receiving) begin
            // wait for start bit (line goes low)
            if (rx_f == 1'b0) begin
                // start counting half bit to sample mid-bit
                bit_timer <= BIT_TICKS >> 1;
                receiving <= 1'b1;
                bit_idx <= 0;
            end
        end else begin
            if (bit_timer == 0) begin
                // sample bit
                if (bit_idx == 0) begin
                    // this is mid of start bit; if still low OK else abort
                    if (rx_f == 1'b0) begin
                        bit_timer <= BIT_TICKS - 1;
                        bit_idx <= bit_idx + 1;
                    end else begin
                        // false start
                        receiving <= 1'b0;
                    end
                end else if (bit_idx >= 1 && bit_idx <= 8) begin
                    // data bits (LSB first)
                    rx_shift <= {rx_f, rx_shift[7:1]};
                    bit_timer <= BIT_TICKS - 1;
                    bit_idx <= bit_idx + 1;
                end else begin
                    // stop bit (bit_idx == 9)
                    // optional: verify stop bit is high
                    receiving <= 1'b0;
                    rx_byte_valid <= 1'b1;
                end
            end else begin
                bit_timer <= bit_timer - 1;
            end
        end
    end
end

// Make rx_byte_valid and rx_shift available synchronous to clk
reg [7:0] rx_byte_reg;
reg       rx_byte_valid_reg;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        rx_byte_reg <= 8'd0;
        rx_byte_valid_reg <= 1'b0;
    end else begin
        rx_byte_valid_reg <= rx_byte_valid;
        if (rx_byte_valid) rx_byte_reg <= rx_shift;
    end
end

// --- Frame parser and sample assembler ---
// Header: 0xAA, 0x55
localparam [7:0] H0 = 8'hAA;
localparam [7:0] H1 = 8'h55;

reg [2:0] state;
localparam ST_IDLE     = 3'd0;
localparam ST_H0       = 3'd1;
localparam ST_H1       = 3'd2;
localparam ST_LEN_HI   = 3'd3;
localparam ST_LEN_LO   = 3'd4;
localparam ST_PAYLOAD  = 3'd5;
localparam ST_TAIL0    = 3'd6;

reg [15:0] expected_samples; // number of samples to read
reg [7:0]  len_hi;
reg [31:0] payload_bytes_expected;
reg [31:0] payload_bytes_count;
reg [7:0]  pending_byte; // for assembling sample MSB/LSB
reg        have_pending; // 1 when pending_byte holds MSB

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state <= ST_IDLE;
        expected_samples <= 0;
        payload_bytes_expected <= 0;
        payload_bytes_count <= 0;
        pending_byte <= 8'd0;
        have_pending <= 1'b0;
        sample_valid <= 1'b0;
        sample_out <= 16'd0;
        frame_start <= 1'b0;
        frame_done <= 1'b0;
    end else begin
        // default de-assert pulses
        sample_valid <= 1'b0;
        frame_start <= 1'b0;
        frame_done <= 1'b0;

        if (rx_byte_valid_reg) begin
            case (state)
                ST_IDLE: begin
                    if (rx_byte_reg == H0) state <= ST_H0;
                end
                ST_H0: begin
                    if (rx_byte_reg == H1) state <= ST_H1;
                    else if (rx_byte_reg == H0) state <= ST_H0; // stay
                    else state <= ST_IDLE;
                end
                ST_H1: begin
                    // length high byte
                    len_hi <= rx_byte_reg;
                    state <= ST_LEN_HI;
                end
                ST_LEN_HI: begin
                    // combine high and low to form 16-bit sample count (big-endian)
                    expected_samples <= {len_hi, rx_byte_reg};
                    payload_bytes_expected <= ({len_hi, rx_byte_reg}) * 2; // each sample = 2 bytes
                    payload_bytes_count <= 0;
                    have_pending <= 1'b0;
                    state <= ST_PAYLOAD;
                end
                ST_PAYLOAD: begin
                    // collect payload bytes and assemble 16-bit MSB-first
                    payload_bytes_count <= payload_bytes_count + 1;
                    if (!have_pending) begin
                        pending_byte <= rx_byte_reg; // MSB
                        have_pending <= 1'b1;
                    end else begin
                        // combine MSB (pending_byte) and current as LSB
                        sample_out <= {pending_byte, rx_byte_reg};
                        sample_valid <= 1'b1;
                        // first sample -> frame_start
                        if (payload_bytes_count == 1) begin
                            frame_start <= 1'b1;
                        end
                        have_pending <= 1'b0;
                    end

                    if (payload_bytes_count + 1 >= payload_bytes_expected) begin
                        // all payload bytes read; expect tail next
                        state <= ST_TAIL0;
                    end
                end
                ST_TAIL0: begin
                    // optional: verify tail bytes (e.g., 0x55 0xAA), but we consume and go to IDLE
                    state <= ST_IDLE;
                    frame_done <= 1'b1;
                end
                default: state <= ST_IDLE;
            endcase
        end
    end
end

endmodule
