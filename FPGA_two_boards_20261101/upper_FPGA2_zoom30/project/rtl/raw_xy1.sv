module raw_xy1(input wire clk,rst,de,vs,output reg[10:0]x,output reg[9:0]y);
 reg pd;
 always @(posedge clk or posedge rst)begin
  if(rst)begin x<=0;y<=0;pd<=0;end
  else begin
   pd<=de;if(de)x<=x+1'b1;else x<=0;
   if(vs)y<=0;else if(pd&&!de)y<=y+1'b1;
  end
 end
endmodule
