// One local, exact unsigned modulo-2^32 arithmetic datapath. No DSP/multiply
// operator and no approximation. Four products serialize ONLY command setup;
// the original load/compute/store/physical-response engines continue running.
module v5n_tile_geometry_shared_alu #(parameter integer SHAPE_W=10)(
 input wire clk_i,rst_ni,start_i,
 input wire [SHAPE_W-1:0] local_h_i,local_w_i,input_c_i,
 input wire [SHAPE_W-1:0] tile_h_i,tile_w_i,output_c_i,
 output reg busy_o,done_o,
 output reg [31:0] area_o,capacity_o,output_bytes_o
);
 localparam integer COUNT_W=(SHAPE_W>1)?$clog2(SHAPE_W):1;
 reg [COUNT_W-1:0] count_r;
 reg [1:0] product_r;
 reg [31:0] accumulator_r,multiplicand_r;
 reg [SHAPE_W-1:0] multiplier_r,input_c_r,tile_h_r,tile_w_r,output_c_r;
 reg output_supported_r;
 wire [31:0] next_sum_w=accumulator_r+(multiplier_r[0]?multiplicand_r:32'd0);
 always @(posedge clk_i or negedge rst_ni) begin
  if(!rst_ni)begin
   busy_o<=0;done_o<=0;area_o<=0;capacity_o<=0;output_bytes_o<=0;
   count_r<=0;product_r<=0;accumulator_r<=0;multiplicand_r<=0;
   multiplier_r<=0;input_c_r<=0;tile_h_r<=0;tile_w_r<=0;output_c_r<=0;output_supported_r<=0;
  end else begin
   done_o<=0;
   if(!busy_o)begin
    if(start_i)begin
     busy_o<=1;count_r<=0;product_r<=0;accumulator_r<=0;
     multiplicand_r<=32'(local_h_i);multiplier_r<=local_w_i;
     input_c_r<=input_c_i;tile_h_r<=tile_h_i;tile_w_r<=tile_w_i;output_c_r<=output_c_i;
     // Preserve the former small_extent_product/default and output-channel
     // case behavior, including unsupported commands (which guards reject).
     output_supported_r<=tile_h_i>=1&&tile_h_i<=12&&
       (output_c_i==1||output_c_i==2||output_c_i==4||output_c_i==8||
        output_c_i==16||output_c_i==32||output_c_i==64);
    end
   end else begin
    if(count_r==SHAPE_W-1)begin
     count_r<=0;accumulator_r<=0;
     case(product_r)
      0:begin area_o<=next_sum_w;multiplicand_r<=next_sum_w;multiplier_r<=input_c_r;product_r<=1;end
      1:begin capacity_o<=next_sum_w;multiplicand_r<=32'(tile_h_r);multiplier_r<=tile_w_r;product_r<=2;end
      // The former 14-bit small_extent_product truncates BEFORE channel shift.
      2:begin multiplicand_r<={18'd0,next_sum_w[13:0]};multiplier_r<=output_c_r;product_r<=3;end
      3:begin output_bytes_o<=output_supported_r?next_sum_w:32'd0;busy_o<=0;done_o<=1;end
     endcase
    end else begin
     accumulator_r<=next_sum_w;multiplicand_r<=multiplicand_r<<1;
     multiplier_r<=multiplier_r>>1;count_r<=count_r+1'b1;
    end
   end
  end
 end
endmodule
