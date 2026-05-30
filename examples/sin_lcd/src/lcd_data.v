`timescale 1ns/1ns

module lcd_data
#(
	parameter H_DISP = 800,
	parameter V_DISP = 480
)
( 
	input  wire	 		clk,	
	input  wire			rst_n,	
	input  wire	[11:0]	lcd_xpos,	//lcd horizontal coordinate
	input  wire	[11:0]	lcd_ypos,	//lcd vertical coordinate
	
	output reg  [23:0]	lcd_data	//lcd data
);

`define WHITE 	24'hFFFFFF 
`define BLACK 	24'h000000 

reg [8:0] sin_lut [0:799];
reg [8:0] sin_val;

initial begin
	$readmemb("src/sin_lut.mem", sin_lut);
end

always@(*) begin
	if (lcd_xpos < H_DISP)
		sin_val = sin_lut[lcd_xpos];
	else
		sin_val = 9'd240;
end

always@(posedge clk or negedge rst_n)
begin
	if(!rst_n)
		lcd_data <= `BLACK;
	else
		begin
		if ((lcd_ypos >= sin_val - 1) && (lcd_ypos <= sin_val + 1))
			lcd_data <= `WHITE;
		else
			lcd_data <= `BLACK;
		end
end

endmodule
