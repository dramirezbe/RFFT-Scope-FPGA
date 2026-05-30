`timescale 1ns/1ns

/* Timing reference
************	clk		 	H_SYNC 		H_BACK 		H_DISP 		H_FRONT 	H_TOTAL 		V_SYNC 		V_BACK 		V_DISP 		V_FRONT 	V_TOTAL		*
480x272@60Hz	9MHz		4			23			480 		13			520     		4			15			272 		9			300		    *
800x480@60Hz	40MHz		10			46 			800 		210			1066			4			23			480 		13			520		    *
1024x768@60Hz	65MHz		136			160 		1024 		24 			1344			6			29			768 		3			806		    *
1280x720@60Hz	74.25MHz	40			220 		1280 		110			1650			5			20			720 		5			750		    *
1280x1024@60Hz	108MHz		112			248 		1280 		48 			1688			3			38			1024		1			1066	    *
1920x1080@60Hz	148.5MHz	44			148 		1920 		88 			2200			5			36			1080		4			1125	    *
*/	
module lcd_ctrl
(
	input  wire			clk,			//LCD_CTL clock
	input  wire			rst_n,     		//sync reset
	input  wire	[23:0]	lcd_data,		//lcd data
	
	//lcd interface
	output wire			lcd_clk,   		//lcd pixel clock
	output wire			lcd_hs,	    	//lcd horizontal sync
	output wire			lcd_vs,	    	//lcd vertical sync
	output wire			lcd_de,			//lcd display enable; 1:Display Enable Signal;0: Disable Ddsplay
	output wire	[23:0]	lcd_rgb,		//lcd display data

	//user interface
	output wire	[11:0]	lcd_xpos,		//lcd horizontal coordinate
	output wire	[11:0]	lcd_ypos		//lcd vertical coordinate
);

`define _800_480

`ifdef _1280_1024
	parameter [11:0] H_SYNC = 12'd112	;
	parameter [11:0] H_BACK = 12'd248	;
	parameter [11:0] H_DISP = 12'd1280	;
	parameter [11:0] H_FRONT = 12'd48	;
	parameter [11:0] H_TOTAL = 12'd1688	;
			
	parameter [11:0] V_SYNC = 12'd3	;
	parameter [11:0] V_BACK = 12'd38	;
	parameter [11:0] V_DISP = 12'd1024	;
	parameter [11:0] V_FRONT = 12'd1	;
	parameter [11:0] V_TOTAL = 12'd1066	;
`endif

`ifdef _800_480
	parameter [11:0] H_SYNC = 12'd10	;
	parameter [11:0] H_BACK = 12'd46	;
	parameter [11:0] H_DISP = 12'd800	;
	parameter [11:0] H_FRONT = 12'd210	;
	parameter [11:0] H_TOTAL = 12'd1066	;
			
	parameter [11:0] V_SYNC = 12'd4	;
	parameter [11:0] V_BACK = 12'd23	;
	parameter [11:0] V_DISP = 12'd480	;
	parameter [11:0] V_FRONT = 12'd13	;
	parameter [11:0] V_TOTAL = 12'd520	;
`endif

`ifdef _480_272
	parameter [11:0] H_SYNC = 12'd4	;
	parameter [11:0] H_BACK = 12'd23	;
	parameter [11:0] H_DISP = 12'd480	;
	parameter [11:0] H_FRONT = 12'd13	;
	parameter [11:0] H_TOTAL = 12'd520	;
			
	parameter [11:0] V_SYNC = 12'd4	;
	parameter [11:0] V_BACK = 12'd15	;
	parameter [11:0] V_DISP = 12'd272	;
	parameter [11:0] V_FRONT = 12'd9	;
	parameter [11:0] V_TOTAL = 12'd300	;
`endif

 
localparam	H_AHEAD = 	12'd1;

reg [11:0] hcnt; 
reg [11:0] vcnt;
wire lcd_request;

/*******************************************
		SYNC--BACK--DISP--FRONT
*******************************************/ 
//h_sync counter & generator
always @ (posedge clk or negedge rst_n)
begin
	if (!rst_n)
		hcnt <= 12'd0;
	else
	begin
        if(hcnt < H_TOTAL - 1'b1)		//line over			
            hcnt <= hcnt + 1'b1;
        else
            hcnt <= 12'd0;
	end
end 

assign	lcd_hs = (hcnt <= H_SYNC - 1'b1) ? 1'b0 : 1'b1; // line over flag

//v_sync counter & generator
always@(posedge clk or negedge rst_n)
begin
	if (!rst_n)
		vcnt <= 12'b0;
	else if(hcnt == H_TOTAL - 1'b1)	//line over
		begin
		if(vcnt == V_TOTAL - 1'b1)		//frame over
			vcnt <= 12'd0;
		else
			vcnt <= vcnt + 1'b1;
		end
end

assign	lcd_vs = (vcnt <= V_SYNC - 1'b1) ? 1'b0 : 1'b1; // frame over flag

// Control Display
assign	lcd_de		=	(hcnt >= H_SYNC + H_BACK  && hcnt < H_SYNC + H_BACK + H_DISP) &&
						(vcnt >= V_SYNC + V_BACK  && vcnt < V_SYNC + V_BACK + V_DISP) 
						? 1'b1 : 1'b0;                   // Display Enable Signal
						
assign	lcd_rgb 	= 	lcd_de ? lcd_data : 24'h000000;	

//ahead x clock
assign	lcd_request	=	(hcnt >= H_SYNC + H_BACK - H_AHEAD && hcnt < H_SYNC + H_BACK + H_DISP - H_AHEAD) &&
						(vcnt >= V_SYNC + V_BACK && vcnt < V_SYNC + V_BACK + V_DISP) 
						? 1'b1 : 1'b0;
//lcd xpos & ypos
assign	lcd_xpos	= 	lcd_request ? (hcnt - (H_SYNC + H_BACK - H_AHEAD)) : 12'd0;
assign	lcd_ypos	= 	lcd_request ? (vcnt - (V_SYNC + V_BACK)) : 12'd0;

assign lcd_clk = clk ;

endmodule