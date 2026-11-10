// Read-only actual RGB888 capture evidence. NOT YOLO input/output generation.
// Y8N3 type5 layer244, 26-byte header +64 bytes, original full-resolution RGB.
// Uses the already VIDEO-LOCKED DDR bank; release only after final UDP drain.
module camera_rgb888_snapshot_tx(
 input wire clk,rst_n,start_i,input wire [31:0] source_frame_id_i,source_byte_base_i,
 output wire busy_o,output reg done_o,
 output wire req_valid_o,input wire req_ready_i,output wire [27:0] req_address_o,
 input wire read_valid_i,output wire read_ready_o,input wire [127:0] read_data_i,
 input wire udp_busy_i,output wire udp_request_o,udp_valid_o,
 output wire [7:0] udp_data_o,output wire [15:0] udp_length_o
);
 localparam IDLE=0,READ_REQ=1,READ_WAIT=2,REQUEST=3,SEND=4,DRAIN=5,DONE=6;
 reg [2:0] state;reg [31:0] base,fid,offset;reg [15:0] packet_index;
 reg [1:0] line_index;reg [6:0] tx_index;
 // Mixed-width synchronous SDP inference, same TD template family as udp_pkg_buf.
 // Payload is written in four 128-bit returns, then read one byte/cycle.
 // The header gives a full cycle to prefetch byte zero. No external latency change.
 (* ram_style="bram" *) reg [7:0] payload[0:63];
 reg [7:0] payload_byte;
 wire [5:0] payload_read_address=tx_index-7'd25;
 integer k;
 always @(posedge clk) begin
   if(rst_n && state==READ_WAIT && read_valid_i)
     for(k=0;k<16;k=k+1)payload[{line_index,4'd0}+k]<=read_data_i[(15-k)*8+:8];
   if(state==SEND && tx_index>=25 && tx_index<89)
     payload_byte<=payload[payload_read_address];
 end
 assign busy_o=(state!=IDLE)&&(state!=DONE);
 assign req_valid_o=(state==READ_REQ);assign req_address_o=(base+offset+{26'd0,line_index,4'd0})>>4;
 assign read_ready_o=(state==READ_WAIT);assign udp_request_o=(state==REQUEST);assign udp_valid_o=(state==SEND);assign udp_length_o=90;
 reg [7:0] selected;always @*begin
   selected=0;
   case(tx_index)
     0:selected=8'h59;1:selected=8'h38;2:selected=8'h4e;3:selected=8'h33;
     4:selected=1;5:selected=5;6:selected=244;
     8,9,10,11:selected=fid[(tx_index-8)*8+:8];
     12:selected=packet_index[7:0];13:selected=packet_index[15:8];
     14:selected=8'hc0;15:selected=8'ha8; // 43200 packets (0xa8c0)
     16,17,18,19:selected=offset[(tx_index-16)*8+:8];
     20:selected=8'h00;21:selected=8'h30;22:selected=8'h2a;23:selected=0; //2764800
     24:selected=64;25:selected=0;
     default:if(tx_index>=26&&tx_index<90)selected=payload_byte;
   endcase
 end
 assign udp_data_o=selected;
 always @(posedge clk or negedge rst_n)begin
   if(!rst_n)begin state<=IDLE;base<=0;fid<=0;offset<=0;packet_index<=0;line_index<=0;tx_index<=0;done_o<=0;end
   else begin
     done_o<=0;
     case(state)
       IDLE,DONE:if(start_i)begin base<=source_byte_base_i;fid<=source_frame_id_i;offset<=0;packet_index<=0;line_index<=0;state<=READ_REQ;end
       READ_REQ:if(req_ready_i)state<=READ_WAIT;
       READ_WAIT:if(read_valid_i)begin
         if(line_index==3)begin tx_index<=0;state<=REQUEST;end else begin line_index<=line_index+1'b1;state<=READ_REQ;end
       end
       REQUEST:if(udp_busy_i)begin tx_index<=0;state<=SEND;end
       SEND:if(tx_index==89)state<=DRAIN;else tx_index<=tx_index+1'b1;
       DRAIN:if(!udp_busy_i)begin
         if(packet_index==43199)begin state<=DONE;done_o<=1;end
         else begin packet_index<=packet_index+1'b1;offset<=offset+64;line_index<=0;state<=READ_REQ;end
       end
       default:state<=IDLE;
     endcase
   end
 end
endmodule
