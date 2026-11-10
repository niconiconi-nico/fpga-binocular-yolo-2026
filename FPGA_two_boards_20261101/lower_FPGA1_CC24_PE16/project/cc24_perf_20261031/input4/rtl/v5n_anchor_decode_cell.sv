// A2 routed-path experiment. Exact original64-bit modular v5 arithmetic.
// Four clock stages; head-memory runtime already waits for actual valid_o.
module v5n_anchor_decode_cell (
 input wire clk_i, rst_ni, valid_i,
 input wire [15:0] sx_i,sy_i,sw_i,sh_i,obj_i,c0_i,c1_i,c2_i,c3_i,
 input wire [9:0] grid_x_i,grid_y_i,
 input wire [5:0] stride_i,
 input wire [31:0] anchor_w_q16_i,anchor_h_q16_i,
 output reg valid_o,
 output reg signed [31:0] x1_o,y1_o,x2_o,y2_o,
 output reg [15:0] score0_o,score1_o,score2_o,score3_o
);
 reg v1_r,v2_r,v3_r;
 reg signed [63:0] base_x1_r,base_y1_r,cx2_r,cy2_r,cx3_r,cy3_r;
 reg [63:0] square_w1_r,square_h1_r,product_w2_r,product_h2_r,half_w3_r,half_h3_r;
 reg [31:0] anchor_w1_r,anchor_h1_r;
 reg [5:0] stride1_r;
 reg [31:0] score_product1_r[0:3],score_product2_r[0:3];
 reg [15:0] score3_r[0:3];
 integer i;
 always @(posedge clk_i or negedge rst_ni) begin
  if(!rst_ni) begin
   v1_r<=0;v2_r<=0;v3_r<=0;valid_o<=0;
   base_x1_r<=0;base_y1_r<=0;cx2_r<=0;cy2_r<=0;cx3_r<=0;cy3_r<=0;
   square_w1_r<=0;square_h1_r<=0;product_w2_r<=0;product_h2_r<=0;half_w3_r<=0;half_h3_r<=0;
   anchor_w1_r<=0;anchor_h1_r<=0;stride1_r<=0;
   x1_o<=0;y1_o<=0;x2_o<=0;y2_o<=0;score0_o<=0;score1_o<=0;score2_o<=0;score3_o<=0;
   for(i=0;i<4;i=i+1)begin score_product1_r[i]<=0;score_product2_r[i]<=0;score3_r[i]<=0;end
  end else begin
   v1_r<=valid_i;v2_r<=v1_r;v3_r<=v2_r;valid_o<=v3_r;
   if(valid_i) begin
    base_x1_r<=$signed({1'b0,sx_i})*64'sd2+$signed({1'b0,grid_x_i})*64'sd32768-64'sd16384;
    base_y1_r<=$signed({1'b0,sy_i})*64'sd2+$signed({1'b0,grid_y_i})*64'sd32768-64'sd16384;
    square_w1_r<=({48'd0,sw_i}*64'd2)*({48'd0,sw_i}*64'd2);
    square_h1_r<=({48'd0,sh_i}*64'd2)*({48'd0,sh_i}*64'd2);
    anchor_w1_r<=anchor_w_q16_i;anchor_h1_r<=anchor_h_q16_i;stride1_r<=stride_i;
    score_product1_r[0]<=obj_i*c0_i;score_product1_r[1]<=obj_i*c1_i;
    score_product1_r[2]<=obj_i*c2_i;score_product1_r[3]<=obj_i*c3_i;
   end
   if(v1_r)begin
    // Identical modulo2^64 product as original tw*tw*anchor before rounding.
    product_w2_r<=square_w1_r*anchor_w1_r;product_h2_r<=square_h1_r*anchor_h1_r;
    cx2_r<=base_x1_r*$signed({1'b0,stride1_r})*64'sd2;
    cy2_r<=base_y1_r*$signed({1'b0,stride1_r})*64'sd2;
    for(i=0;i<4;i=i+1)score_product2_r[i]<=score_product1_r[i];
   end
   if(v2_r)begin
    // Rounding additions remain64 bits, in the same exact order.
    half_w3_r<=(((product_w2_r+64'd536870912)>>30)+64'd1)>>1;
    half_h3_r<=(((product_h2_r+64'd536870912)>>30)+64'd1)>>1;
    cx3_r<=cx2_r;cy3_r<=cy2_r;
    for(i=0;i<4;i=i+1)score3_r[i]<=(score_product2_r[i]+32'd16384)>>15;
   end
   if(v3_r)begin
    // Original64-bit add/sub was truncated to32-bit output. Modular32 add/sub
    // of the low operands is mathematically identical, including wrap cases.
    x1_o<=cx3_r[31:0]-half_w3_r[31:0];y1_o<=cy3_r[31:0]-half_h3_r[31:0];
    x2_o<=cx3_r[31:0]+half_w3_r[31:0];y2_o<=cy3_r[31:0]+half_h3_r[31:0];
    score0_o<=score3_r[0];score1_o<=score3_r[1];score2_o<=score3_r[2];score3_o<=score3_r[3];
   end
  end
 end
endmodule
