// Productionmode_keys only enables IDs1..47; six bits preserve every mode.
// HS/VS/DE/mode latency unchanged. Actual storage reduction requires ownTD.
// Two real raster stages. Stage2 completes OPEN/CLOSE; all other modes
// retain the exact centre RGB through the same timing. No DDR rotation.
module mono_raster_stage4 #(parameter integer WIDTH=1280,HEIGHT=720,HTOTAL=1650,SECOND_STAGE=0)(
 input wire clk,rst_n,input wire hs_i,vs_i,de_i,input wire [23:0] rgb_i,input wire [7:0] mode_i,
 output reg hs_o,vs_o,de_o,output reg [23:0] rgb_o,output reg [7:0] mode_o,
 output reg [11:0] x_o,y_o);
 wire wv;wire [11:0] wx,wy;wire [23:0] wrgb;wire [71:0] grey;
 mono_window2 #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.HTOTAL(HTOTAL)) window(clk,rst_n,vs_i,de_i,rgb_i,wv,wx,wy,wrgb,grey);
 wire av;wire [7:0] am;wire [11:0] ax,ay;wire [23:0] argb;
 mono_algorithms4 #(.SECOND_STAGE(SECOND_STAGE)) algorithms(clk,rst_n,wv,mode_i,wx,wy,wrgb,grey,av,am,ax,ay,argb);
 localparam integer DELAY=HTOTAL+6;
 // CLAUDE MERGE: sync delay line as one ERAM primitive (was 2048x9 LUT-RAM, ~270 slices). Same timing: the read address is
 // sampled at the clock edge and its word appears one clock later; zero until the delay line is warm.
 reg [10:0] pointer;reg [11:0] warm;reg warm_q;wire [8:0] syncd;
 wire [10:0] read_pointer=pointer-DELAY;
 always @(posedge clk) warm_q <= rst_n&&warm>=DELAY;
 wire [8:0] syncq = warm_q ? syncd : 9'd0;
 PH1P_LOGIC_ERAM #(.DATA_WIDTH_A(9),.DATA_WIDTH_B(9),.ADDR_WIDTH_A(11),.ADDR_WIDTH_B(11),.DATA_DEPTH_A(2048),.DATA_DEPTH_B(2048),
   .MODE("DP"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),.WRITEMODE_A("READBEFOREWRITE"),.WRITEMODE_B("READBEFOREWRITE"),
   .CLKMODE("SYNC"),.SSROVERCE("DISABLE"),.OREGSET_A("RESET"),.OREGSET_B("RESET"),.RESETMODE_A("ASYNC"),.RESETMODE_B("ASYNC"),
   .ASYNC_RESET_RELEASE_A("ASYNC"),.ASYNC_RESET_RELEASE_B("ASYNC"),.ECC_ENCODE("DISABLE"),.ECC_DECODE("DISABLE"),
   .IMPLEMENT("20K(FAST)"),.INIT_FILE("NONE"),.FILL_ALL("NONE")) syncram(
   .dia({hs_i,vs_i,de_i,mode_i[5:0]}),.addra(pointer),.cea(1'b1),.ocea(1'b0),.clka(clk),.wea(rst_n),.rsta(1'b0),.bea(1'b0),
   .dib(9'd0),.addrb(read_pointer),.ceb(1'b1),.oceb(1'b0),.clkb(clk),.web(1'b0),.rstb(1'b0),.beb(1'b0),
   .ecc_sbiterrinj(1'b0),.ecc_dbiterrinj(1'b0),.doa(),.dob(syncd),.ecc_sbiterr(),.ecc_dbiterr());
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin pointer<=0;warm<=0;end
  else begin pointer<=pointer+1'b1;if(warm<DELAY)warm<=warm+1'b1;end
 end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin hs_o<=0;vs_o<=0;de_o<=0;rgb_o<=0;mode_o<=1;x_o<=0;y_o<=0;end
  else begin
   hs_o<=syncq[8];vs_o<=syncq[7];de_o<=syncq[6];mode_o<={2'b00,syncq[5:0]};x_o<=ax;y_o<=ay;
   rgb_o<=syncq[6]&&av?argb:24'd0;
  end
 end
endmodule
