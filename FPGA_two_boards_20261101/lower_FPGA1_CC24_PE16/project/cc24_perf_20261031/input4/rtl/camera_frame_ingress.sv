// Actual ISP128 word stream -> framed asynchronous FIFO. Each full RGB888
//1280x720 frame contains172800128-bit words. No synthetic pixels or resizing.
module camera_frame_ingress(
 input wire camera_clk,camera_rst_n,frame_start_i,word_valid_i,input wire [127:0] word_data_i,
 input wire ddr_clk,ddr_rst_n,output wire framed_valid_o,input wire framed_ready_i,
 output wire [162:0] framed_data_o,output reg [31:0] overflow_lines_o
);
 reg [31:0] fid;reg [17:0] count;reg first_pending,bad;
 wire fifo_ready;
 wire first=frame_start_i||first_pending;
 wire [17:0] index=first?18'd0:count;
 wire last=(index==172799);
 wire [31:0] word_fid=frame_start_i?fid+1'b1:fid;
 wire [162:0] payload={(first?1'b0:bad),last,first,word_fid,word_data_i};
 camera_framed_async_fifo queue(.write_clk(camera_clk),.write_rst_n(camera_rst_n),
   .write_valid_i(word_valid_i),.write_ready_o(fifo_ready),.write_data_i(payload),
   .read_clk(ddr_clk),.read_rst_n(ddr_rst_n),.read_valid_o(framed_valid_o),.read_ready_i(framed_ready_i),.read_data_o(framed_data_o));
 always @(posedge camera_clk or negedge camera_rst_n)begin
   if(!camera_rst_n)begin fid<=0;count<=0;first_pending<=0;bad<=0;overflow_lines_o<=0;end
   else begin
     if(frame_start_i)begin fid<=fid+1'b1;count<=0;first_pending<=1;bad<=0;end
     if(word_valid_i)begin
       first_pending<=0;count<=index+1'b1;
       if(!fifo_ready)begin bad<=1;overflow_lines_o<=overflow_lines_o+1'b1;end
     end
   end
 end
endmodule
