// Official ANLOGIC artwork converted deterministically,80x80 two-colour palette.
// Shared final stage applies to EVERY mode. Transparent exterior and source-mask
// holes; equal TWO-register RGB/HS/VS/DE/marker latency. No frame memory writes.
module common_logo1 #(
 parameter ROM_FILE="logo80.hex",parameter integer LOGO_X=1192,LOGO_Y=48
)(input wire clk,rst_n,hs_i,vs_i,de_i,input wire[23:0]rgb_i,
 input wire first_local_i,
 output reg hs_o,vs_o,de_o,output reg[23:0]rgb_o,output reg first_local_o
);
 reg[15:0]rom[0:799];initial $readmemh(ROM_FILE,rom);
 reg[10:0]x;reg[9:0]y;reg pd;
 wire in_logo=de_i&&x>=LOGO_X&&x<LOGO_X+80&&y>=LOGO_Y&&y<LOGO_Y+80;
 wire[10:0]lx=x-LOGO_X;wire[9:0]ly=y-LOGO_Y;
 wire[9:0]address=(ly<<3)+(ly<<1)+(lx>>3);
 reg[15:0]word1;reg[2:0]lane1;reg hit1;
 reg hs1,vs1,de1,first1;reg[23:0]rgb1;
 wire[1:0]palette=(word1>>(lane1*2))&2'b11;
 always @(posedge clk)if(in_logo)word1<=rom[address];
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin x<=0;y<=0;pd<=0;lane1<=0;hit1<=0;
   hs1<=0;vs1<=0;de1<=0;rgb1<=0;first1<=0;
   hs_o<=0;vs_o<=0;de_o<=0;rgb_o<=0;first_local_o<=0;end
  else begin
   pd<=de_i;if(de_i)x<=x+1'b1;else x<=0;
   if(vs_i)y<=0;else if(pd&&!de_i)y<=y+1'b1;
   lane1<=lx[2:0];hit1<=in_logo;
   hs1<=hs_i;vs1<=vs_i;de1<=de_i;rgb1<=rgb_i;first1<=first_local_i;
   hs_o<=hs1;vs_o<=vs1;de_o<=de1;first_local_o<=first1;
   rgb_o<=hit1&&palette==1?24'h1f315c:hit1&&palette==2?24'hec1c2d:rgb1;
  end
 end
endmodule
