// Actual final ISP packer: four RGB888 pixels per input -> four RGB565
// pixels per64bit half; two accepted input beats -> one128bit DDR beat.
// RGB quantization is truncation R[7:3],G[7:2],B[7:3]. Pixel0 occupies LSB.
// No RGB888 frame storage. Frame/reset discards an unpaired64bit half.
module data_96bit_to_128bit(
 input wire I_clk,I_rst_n,I_96b_frame_start,I_96b_valid,
 input wire[95:0]I_96b_data,
 output reg O_128b_frame_start,O_128b_valid,output reg[127:0]O_128b_data
);
 reg half_valid;reg[63:0]half_data;
 function[63:0]quantize_four(input[95:0]v);
  integer k;reg[23:0]p;begin
   for(k=0;k<4;k=k+1)begin p=v[95-k*24-:24];quantize_four[k*16+:16]={p[23:19],p[15:10],p[7:3]};end
  end
 endfunction
 always @(posedge I_clk or negedge I_rst_n)begin
  if(!I_rst_n)begin half_valid<=0;half_data<=0;O_128b_frame_start<=0;O_128b_valid<=0;O_128b_data<=0;end
  else begin
   O_128b_frame_start<=I_96b_frame_start;O_128b_valid<=0;
   if(I_96b_frame_start)half_valid<=0;
   if(I_96b_valid)begin
    if(!half_valid||I_96b_frame_start)begin half_data<=quantize_four(I_96b_data);half_valid<=1;end
    else begin O_128b_data<={quantize_four(I_96b_data),half_data};O_128b_valid<=1;half_valid<=0;end
   end
  end
 end
endmodule
