// Independent diagnostic control; not compiled into any qualified bit yet.
// Existing Y8N3/Y5ST/video/detection packets are untouched. New command only:
// Y5PC, version1, mode0..6, eight reserved zero bytes, CK (16 bytes).
// Commit mode at an application-provided idle/bank-safe boundary, never truncate
// a DDR write, video reader or UDP packet. Freeze only after a real full commit.
module camera_perf_runtime_control (
 input wire clk,rst_n,udp_valid_i,input wire [7:0] udp_data_i,
 input wire [15:0] udp_length_i,
 input wire apply_safe_i,frame_begin_i,frame_commit_i,video_start_i,raw_pending_i,
 output wire frame_begin_o,video_permit_o,repeat_source_o,
 output reg capture_frozen_o,output reg [2:0] mode_o,
 output reg pending_o,output reg [31:0] applied_sequence_o
);
 reg in_packet,magic_ok;reg [15:0] index;
 reg [2:0] proposed_mode,pending_mode;
 reg [31:0] video_wait;
 reg [31:0] interval;
 wire freeze_mode=mode_o>=5;
 wire video_enabled=mode_o!=6;
 assign frame_begin_o=frame_begin_i&&!capture_frozen_o;
 assign video_permit_o=raw_pending_i||(video_enabled&&video_wait==0);
 assign repeat_source_o=freeze_mode&&capture_frozen_o;
 always @*begin
   case(mode_o)
     1,5:interval=32'd5000000;
     2:interval=32'd6666667;
     3:interval=32'd10000000;
     4:interval=32'd20000000;
     default:interval=0;
   endcase
 end
 always @(posedge clk or negedge rst_n)begin
   if(!rst_n)begin
     in_packet<=0;magic_ok<=0;index<=0;proposed_mode<=0;pending_mode<=0;
     pending_o<=0;mode_o<=0;capture_frozen_o<=0;video_wait<=0;applied_sequence_o<=0;
   end else begin
     if(udp_valid_i)begin
       if(!in_packet)begin
         in_packet<=1;index<=1;magic_ok<=udp_data_i==8'h59&&udp_length_i==16;
       end else begin
         index<=index+1'b1;
         case(index)
           1:if(udp_data_i!=8'h35)magic_ok<=0;
           2:if(udp_data_i!=8'h50)magic_ok<=0;
           3:if(udp_data_i!=8'h43)magic_ok<=0;
           4:if(udp_data_i!=1)magic_ok<=0;
           5:begin proposed_mode<=udp_data_i[2:0];if(udp_data_i>6)magic_ok<=0;end
           14:if(udp_data_i!=8'h43)magic_ok<=0;
           15:begin
             if(udp_data_i!=8'h4b)magic_ok<=0;
           end
           default:if(udp_data_i!=0)magic_ok<=0;
         endcase
         if(udp_length_i!=16||index>=16)magic_ok<=0;
       end
     end else begin
       // Validate actual packet termination as well as its declared length.
       // A valid 16-byte prefix of an overlong packet must never apply a mode.
       if(in_packet&&magic_ok&&index==16)begin
         pending_mode<=proposed_mode;pending_o<=1;
       end
       in_packet<=0;index<=0;magic_ok<=0;
     end
     if(video_start_i&&interval!=0)video_wait<=interval-1;
     else if(video_wait!=0)video_wait<=video_wait-1;
     if(freeze_mode&&frame_commit_i)capture_frozen_o<=1;
     // Old in-flight packets/writes complete BEFORE apply_safe_i is asserted.
     // A completed new command stays pending for a separate safe edge.
     if(pending_o&&apply_safe_i&&!in_packet&&!udp_valid_i)begin
       mode_o<=pending_mode;pending_o<=0;applied_sequence_o<=applied_sequence_o+1;
       capture_frozen_o<=0;video_wait<=0;
     end
   end
 end
endmodule
