// Diagnostic equivalent storage alternative, not selected for integration yet.
// TD SWUG106 4.2.6/5.6.13: explicit synchronous-read BRAM template.
// Same eight 128-bit entries/six credits, RGB conversion and frame lifetime.
// One extra clock for each FIFO fetch; no change to mathematical pixel values.
module camera_owned_video_reader(
 input wire clk,rst_n,start_i,input wire [31:0] source_frame_id_i,source_byte_base_i,
 input wire packet_frame_complete_i,input wire pixel_ready_i,
 output wire busy_o,output reg done_o,output reg [31:0] source_frame_id_o,
 output wire pixel_valid_o,pixel_frame_start_o,output wire [15:0] pixel_rgb565_o,
 output wire req_valid_o,input wire req_ready_i,output wire [27:0] req_address_o,
 input wire read_valid_i,output wire read_ready_o,input wire [127:0] read_data_i
);
 localparam IDLE=0,STREAM=1,WAIT_PACKET=2,DONE=3;
 reg [1:0] state;
 reg [27:0] base_line;
 reg [17:0] issued;
 reg [19:0] pixels;
 reg [2:0] reserved,available,wr_ptr,rd_ptr;
 (* ram_style="bram" *) reg [127:0] words[0:7];
 reg [127:0] front_word;
 reg front_pending;
 reg [143:0] window_data;
 reg [7:0] bits_left;
 wire issue=req_valid_o&&req_ready_i;
 wire receive_line=read_valid_i&&read_ready_o;
 wire fetch_word=(state==STREAM)&&(bits_left<24)&&(available!=0)&&!front_pending;
 wire load_word=(state==STREAM)&&(bits_left<24)&&front_pending;
 wire emit_pixel=pixel_valid_o;
 wire [23:0] rgb=window_data[143:120];
 assign busy_o=(state==STREAM)||(state==WAIT_PACKET);
 assign req_valid_o=(state==STREAM)&&(issued<172800)&&(reserved<6);
 assign req_address_o=base_line+issued;
 assign read_ready_o=(state==STREAM)&&(available<6);
 assign pixel_valid_o=(state==STREAM)&&(bits_left>=24)&&pixel_ready_i;
 assign pixel_frame_start_o=(pixels==0);
 assign pixel_rgb565_o={rgb[23:19],rgb[15:10],rgb[7:3]};
 // No reset on memory or RAM output. Validity is carried separately.
 always @(posedge clk)begin
   if(receive_line)words[wr_ptr]<=read_data_i;
   if(fetch_word)front_word<=words[rd_ptr];
 end
 always @(posedge clk or negedge rst_n)begin
   if(!rst_n)begin
     state<=IDLE;base_line<=0;issued<=0;pixels<=0;reserved<=0;available<=0;
     wr_ptr<=0;rd_ptr<=0;bits_left<=0;window_data<=0;source_frame_id_o<=0;done_o<=0;front_pending<=0;
   end else begin
     done_o<=0;
     case(state)
       IDLE,DONE:if(start_i)begin
         state<=STREAM;base_line<=source_byte_base_i[31:4];source_frame_id_o<=source_frame_id_i;
         issued<=0;pixels<=0;reserved<=0;available<=0;wr_ptr<=0;rd_ptr<=0;bits_left<=0;front_pending<=0;
       end
       STREAM:begin
         case({issue,load_word})
           2'b10:reserved<=reserved+1'b1;
           2'b01:reserved<=reserved-1'b1;
         endcase
         case({receive_line,load_word})
           2'b10:available<=available+1'b1;
           2'b01:available<=available-1'b1;
         endcase
         if(issue)issued<=issued+1'b1;
         if(receive_line)wr_ptr<=wr_ptr+1'b1;
         if(fetch_word)front_pending<=1;
         if(load_word)begin
           front_pending<=0;rd_ptr<=rd_ptr+1'b1;bits_left<=bits_left+8'd128;
           case(bits_left)
             0:window_data<={front_word,16'b0};
             8:window_data<={window_data[143:136],front_word,8'b0};
             16:window_data<={window_data[143:128],front_word};
             default:window_data<=0;
           endcase
         end
         if(emit_pixel)begin
           window_data<={window_data[119:0],24'b0};bits_left<=bits_left-8'd24;
           pixels<=pixels+1'b1;
           if(pixels==921599)state<=WAIT_PACKET;
         end
       end
       WAIT_PACKET:if(packet_frame_complete_i)begin state<=DONE;done_o<=1;end
       default:state<=IDLE;
     endcase
   end
 end
`ifndef SYNTHESIS
 always @(posedge clk)if(rst_n)begin
   if(start_i&&((state==IDLE)||(state==DONE))&&source_byte_base_i[3:0]!=0)$fatal(1,"owned720 base must be line aligned");
   if(available>reserved||reserved>6)$fatal(1,"prefetch credit invariant");
   if(receive_line&&(available==reserved)&&!issue)$fatal(1,"unsolicited line");
   if(load_word&&(bits_left!=0)&&(bits_left!=8)&&(bits_left!=16))$fatal(1,"byte reservoir phase");
   if(emit_pixel&&load_word)$fatal(1,"reservoir conflicting update");
   if(fetch_word&&receive_line&&rd_ptr==wr_ptr)$fatal(1,"RAM same-address collision");
   if(front_pending&&available==0)$fatal(1,"RAM output without FIFO ownership");
   if(emit_pixel&&(pixels==921599)&&((bits_left!=24)||(reserved!=0)||(available!=0)||(issued!=172800)||front_pending))$fatal(1,"frame ended without draining all lines");
 end
`endif
endmodule
