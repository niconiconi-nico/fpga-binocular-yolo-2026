// Observe ACTUAL ordered native writes, never issue/FIFO-empty. Four inherited
// RGB565 banks,115200 contiguous128bit words each, native address unit16bit.
// CLAUDE Z25 LATENCY: sof_g = Gray slot of the newest camera frame (pixel clock, 2-FF here); bank_sofs = slot of the
// frame that started writing each bank (bank b at [2b+1:2b]).
module local_native_commit1(input wire clk,rst,accept,read_command,input wire[24:0]addr,
 output reg[3:0]valid_bank,output wire[127:0]bank_epochs,output reg protocol_error,output reg[1:0]latest_bank,
 input wire[1:0]sof_g,output wire[7:0]bank_sofs);
 reg tracking;reg[1:0]bank;reg[17:0]words;reg[24:0]expected;
 reg[31:0]epoch[0:3],serial;integer j;
 (* async_reg="true" *)reg[1:0]sg1,sg2;reg[1:0]bsof[0:3];
 assign bank_sofs={bsof[3],bsof[2],bsof[1],bsof[0]};
 assign bank_epochs={epoch[3],epoch[2],epoch[1],epoch[0]};
 wire local_write=accept&&!read_command&&addr<25'd28000000;
 wire start=addr==0||addr==7000000||addr==14000000||addr==21000000;
 wire[1:0]newbank=addr==0?0:addr==7000000?1:addr==14000000?2:3;
 always @(posedge clk or posedge rst)begin
  if(rst)begin sg1<=0;sg2<=0;bsof[0]<=0;bsof[1]<=0;bsof[2]<=0;bsof[3]<=0;end
  else begin sg1<=sof_g;sg2<=sg1;if(local_write&&start)bsof[newbank]<={sg2[1],sg2[1]^sg2[0]};end
 end
 always @(posedge clk or posedge rst)begin
  if(rst)begin tracking<=0;bank<=0;words<=0;expected<=0;valid_bank<=0;serial<=0;latest_bank<=0;protocol_error<=0;for(j=0;j<4;j=j+1)epoch[j]<=0;end
  else if(local_write)begin
   if(start)begin
    tracking<=1;bank<=newbank;words<=1;expected<=addr+8;valid_bank[newbank]<=0;
   end else if(tracking&&addr==expected)begin
    expected<=expected+8;words<=words+1'b1;
    if(words==115199)begin tracking<=0;valid_bank[bank]<=1;latest_bank<=bank;serial<=serial+1'b1;epoch[bank]<=serial+1'b1;end
   end else begin tracking<=0;protocol_error<=1;end
  end
 end
endmodule
