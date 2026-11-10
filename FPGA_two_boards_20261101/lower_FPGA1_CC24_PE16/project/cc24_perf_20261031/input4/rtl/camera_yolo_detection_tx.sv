// Y5CD v1 extension, matching pc_upper/camera_yolo_demo/detection_protocol.py.
// Existing RGB565 video packets remain unchanged. Same shared UDP application.
// No float conversion, threshold, clipping, sorting or detection computation.
module camera_yolo_detection_tx(
 input wire clk,rst_n,start_i,input wire [31:0] source_frame_id_i,latency_cycles_i,
 input wire [8:0] detection_count_i,
 output wire busy_o,output reg done_o,error_o,
 output wire detection_read_request_o,output wire [8:0] detection_read_index_o,
 input wire detection_read_valid_i,input wire [1:0] detection_class_i,
 input wire [15:0] detection_confidence_i,input wire signed [31:0] x1_i,y1_i,x2_i,y2_i,
 input wire udp_busy_i,output wire udp_request_o,output wire udp_valid_o,
 output wire [7:0] udp_data_o,output wire [15:0] udp_length_o
);
 localparam IDLE=0,READ=1,REQUEST=2,SEND=3,DRAIN=4,DONE=5,FAIL=6;
 reg [2:0] state;reg [8:0] count,index;reg [5:0] byte_index;
 reg [31:0] source_id,cycles;
 reg [1:0] class_id;reg [15:0] confidence;reg [31:0] box[0:3];
 wire summary=(index==count);
 assign busy_o=(state!=IDLE)&&(state!=DONE)&&(state!=FAIL);
 assign detection_read_request_o=(state==READ);
 assign detection_read_index_o=index;
 assign udp_request_o=(state==REQUEST);
 assign udp_valid_o=(state==SEND);
 assign udp_length_o=summary?16'd32:16'd51;
 reg [7:0] selected_byte;
 always @*begin
   selected_byte=0;
   case(byte_index)
     0:selected_byte=8'h59;1:selected_byte=8'h35;2:selected_byte=8'h43;3:selected_byte=8'h44;
     4:selected_byte=1;5:selected_byte=summary?2:1;
     6:selected_byte=1; // flags=STRICT_AI. cycles must use real owned start->committed result endpoint.
     8,9,10,11:selected_byte=source_id[(byte_index-8)*8+:8];
     12:selected_byte=count[7:0];13:selected_byte={7'd0,count[8]};
     14:selected_byte=index[7:0];15:selected_byte={7'd0,index[8]};
     16,17,18,19:selected_byte=cycles[(byte_index-16)*8+:8];
     20:selected_byte=0;21:selected_byte=4; // Camera width1024
     22:selected_byte=8'h58;23:selected_byte=2; // Camera height600
     24,26:selected_byte=8'h40;25,27:selected_byte=1; // input320x320
     32:selected_byte={6'd0,class_id};
     33:selected_byte=confidence[7:0];34:selected_byte=confidence[15:8];
     default:if(byte_index>=35&&byte_index<51)selected_byte=box[(byte_index-35)>>2][((byte_index-35)&3)*8+:8];
   endcase
 end
 assign udp_data_o=selected_byte;
 integer i;
 always @(posedge clk or negedge rst_n)begin
   if(!rst_n)begin
     state<=IDLE;count<=0;index<=0;byte_index<=0;source_id<=0;cycles<=0;
     class_id<=0;confidence<=0;done_o<=0;error_o<=0;for(i=0;i<4;i=i+1)box[i]<=0;
   end else begin
     done_o<=0;
     case(state)
       IDLE,DONE,FAIL:if(start_i)begin
         count<=detection_count_i;index<=0;source_id<=source_frame_id_i;cycles<=latency_cycles_i;
         byte_index<=0;error_o<=0;
         if(detection_count_i>300)begin error_o<=1;state<=FAIL;end
         else state<=(detection_count_i==0)?REQUEST:READ;
       end
       READ:if(detection_read_valid_i)begin
         class_id<=detection_class_i;confidence<=detection_confidence_i;
         box[0]<=x1_i;box[1]<=y1_i;box[2]<=x2_i;box[3]<=y2_i;
         if(detection_confidence_i>32768)begin error_o<=1;state<=FAIL;end else state<=REQUEST;
       end
       REQUEST:if(udp_busy_i)begin state<=SEND;byte_index<=0;end
       SEND:if(byte_index+1==udp_length_o)state<=DRAIN;else byte_index<=byte_index+1'b1;
       DRAIN:if(!udp_busy_i)begin
         if(summary)begin state<=DONE;done_o<=1;end
         else begin index<=index+1'b1;byte_index<=0;state<=(index+1==count)?REQUEST:READ;end
       end
       default:begin state<=FAIL;error_o<=1;end
     endcase
   end
 end
endmodule
