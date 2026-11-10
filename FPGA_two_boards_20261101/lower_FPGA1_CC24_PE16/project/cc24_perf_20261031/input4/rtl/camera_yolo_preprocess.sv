// Central1024x600 ROI of full1280x720 RGB888 -> 320x188 INTER_LINEAR + (top,bottom)=66 + RGB HWC int8.
// Camera DDR words are MSB-byte-first, YOLO words are LSB-byte-first.
// One memory request at a time; req_ready on WRITES must be physical commit,
// not queue acceptance. Input frame stays reader-locked until done/error.
// Mapping/quant ROMs are generated offline from the frozen input contract.
module camera_yolo_preprocess #(
 parameter X_MAP_FILE="camera_resize_x.hex",Y_MAP_FILE="camera_resize_y.hex",
 parameter QUANT_FILE="camera_quant_u8.hex"
)(
 input wire clk,rst_n,start_i,input wire [31:0] source_frame_id_i,
 input wire [31:0] source_byte_base_i,destination_byte_base_i,
 output wire busy_o,output reg done_o,error_o,output reg [31:0] source_frame_id_o,
 output wire req_valid_o,input wire req_ready_i,output wire req_write_o,
 output wire [27:0] req_line_address_o,output wire [127:0] req_write_data_o,
 output wire [15:0] req_write_strobe_o,
 input wire read_valid_i,output wire read_ready_o,input wire [127:0] read_data_i
);
 localparam IDLE=0,MAP=1,ADDRESS=2,READ_REQ=3,READ_WAIT=4,
    HORIZONTAL=5,VERTICAL=6,ROUND=7,QUANT=8,PACK=9,WRITE_REQ=10,DONE=11,FAIL=12;
 reg [3:0] state;
 reg [8:0] x,y;reg [1:0] channel,sample;
 reg [31:0] source_base,dest_base,dest_offset,source_address;
 `include "camera_preprocess_rom.vh"
 reg [21:0] xm,ym;
 wire [9:0] sx=xm[21:12],sy=ym[21:12];
 wire [11:0] ax=xm[11:0],ay=ym[11:0];
 reg [7:0] pixels[0:3];reg [19:0] horizontal0,horizontal1;reg horizontal_row;
 wire [7:0] horizontal_left=horizontal_row?pixels[2]:pixels[0];
 wire [7:0] horizontal_right=horizontal_row?pixels[3]:pixels[1];
 wire [19:0] horizontal_mix=horizontal_left*(12'd2048-ax)+horizontal_right*ax;
 reg [27:0] vertical0,vertical1;
 reg [7:0] resized;reg [6:0] quantized;
 reg [127:0] write_word,cache_data;reg [27:0] cache_tag;reg cache_valid;
 wire padding=(y<66)||(y>=254);
 wire [27:0] source_line=source_address[31:4];
 wire cache_hit=cache_valid&&cache_tag==source_line;
 wire [127:0] sample_line=cache_data;
 wire [31:0] sample_row={22'd0,sy}+{31'd0,sample[1]};
 wire [31:0] sample_pixel=((sample_row+32'd60)<<10)+((sample_row+32'd60)<<8)+32'd128+{22'd0,sx}+{31'd0,sample[0]};
 wire [31:0] sample_byte=(sample_pixel<<1)+sample_pixel+{30'd0,channel};
 assign busy_o=(state!=IDLE)&&(state!=DONE)&&(state!=FAIL);
 assign req_valid_o=((state==READ_REQ)&&!cache_hit)||(state==WRITE_REQ);
 assign req_write_o=(state==WRITE_REQ);
 assign req_line_address_o=(state==WRITE_REQ)?(dest_base+dest_offset-15)>>4:source_line;
 assign req_write_data_o=write_word;assign req_write_strobe_o=16'hffff;
 assign read_ready_o=(state==READ_WAIT);
 always @(posedge clk or negedge rst_n)begin
   if(!rst_n)begin
     state<=IDLE;x<=0;y<=0;channel<=0;sample<=0;source_base<=0;dest_base<=0;
     source_frame_id_o<=0;dest_offset<=0;source_address<=0;cache_valid<=0;cache_tag<=0;cache_data<=0;
     xm<=0;ym<=0;horizontal0<=0;horizontal1<=0;vertical0<=0;vertical1<=0;
     resized<=0;quantized<=0;write_word<=0;done_o<=0;error_o<=0;horizontal_row<=0;
     pixels[0]<=0;pixels[1]<=0;pixels[2]<=0;pixels[3]<=0;
   end else begin
     done_o<=0;
     case(state)
       IDLE,DONE,FAIL:if(start_i)begin
         source_base<=source_byte_base_i;dest_base<=destination_byte_base_i;source_frame_id_o<=source_frame_id_i;
         x<=0;y<=0;channel<=0;sample<=0;dest_offset<=0;cache_valid<=0;error_o<=0;write_word<=0;
         if(source_byte_base_i[3:0]!=0||destination_byte_base_i[3:0]!=0)begin state<=FAIL;error_o<=1;end
         else state<=MAP;
       end
       MAP:begin
         xm<=camera_x_map(x);ym<=camera_y_map(padding?9'd0:(y-9'd66));sample<=0;horizontal_row<=0;
         if(padding)begin resized<=114;state<=QUANT;end else state<=ADDRESS;
       end
       ADDRESS:begin
         // Constant1280 stride + central ROI offset, original resize/quant math unchanged.
         source_address<=source_base+sample_byte;
         state<=READ_REQ;
       end
       READ_REQ:if(cache_hit)begin
         pixels[sample]<=sample_line[(15-source_address[3:0])*8+:8];
         if(sample==3)state<=HORIZONTAL;else begin sample<=sample+1'b1;state<=ADDRESS;end
       end else if(req_ready_i)state<=READ_WAIT;
       READ_WAIT:if(read_valid_i)begin
         cache_data<=read_data_i;cache_tag<=source_line;cache_valid<=1;
         pixels[sample]<=read_data_i[(15-source_address[3:0])*8+:8];
         if(sample==3)state<=HORIZONTAL;else begin sample<=sample+1'b1;state<=ADDRESS;end
       end
       HORIZONTAL:begin
         if(!horizontal_row)begin horizontal0<=horizontal_mix;horizontal_row<=1;end
         else begin horizontal1<=horizontal_mix;state<=VERTICAL;end
       end
       VERTICAL:begin
         // OpenCV CV_8U specialized vertical stage truncates BEFORE final rounding.
         // Full22bit bilinear rounding is NOT bit-exact (empirically 22,888/180,480 differ).
         vertical0<=horizontal0[19:4]*(12'd2048-ay);
         vertical1<=horizontal1[19:4]*ay;state<=ROUND;
       end
       ROUND:begin resized<=((vertical0>>16)+(vertical1>>16)+2)>>2;state<=QUANT;end
       QUANT:begin quantized<=camera_input_quant(resized);state<=PACK;end
       PACK:begin
         write_word[dest_offset[3:0]*8+:8]<={1'b0,quantized};
         if(dest_offset[3:0]==15)state<=WRITE_REQ;
         else begin
           dest_offset<=dest_offset+1;
           if(channel!=2)channel<=channel+1'b1;
           else begin channel<=0;if(x==319)begin x<=0;y<=y+1'b1;end else x<=x+1'b1;end
           state<=MAP;
         end
       end
       WRITE_REQ:if(req_ready_i)begin
         // The final 16 bytes have physically committed, not merely entered FIFO.
         cache_valid<=0;
         if(dest_offset==307199)begin state<=DONE;done_o<=1;end
         else begin
           dest_offset<=dest_offset+1;
           if(channel!=2)channel<=channel+1'b1;
           else begin channel<=0;if(x==319)begin x<=0;y<=y+1'b1;end else x<=x+1'b1;end
           state<=MAP;
         end
       end
       default:begin state<=FAIL;error_o<=1;end
     endcase
   end
 end
endmodule
