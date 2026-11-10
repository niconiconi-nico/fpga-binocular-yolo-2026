// Isolated experiment: same source/late ACK/control/byte pipeline;
// capture stable held payload in destination domain before body serialization.
module sc520_ae_telemetry #(
 parameter integer PERIOD_CYCLES=2400000
)(
 input wire source_clk,dest_clk,common_reset_n,
 input wire [255:0] values_i,
 input wire udp_busy_i,
 output wire udp_request_o,udp_valid_o,
 output wire [7:0] udp_data_o,
 output wire [15:0] udp_length_o
);
 (* async_reg="true" *) reg [1:0] source_reset_sync,dest_reset_sync;
 always @(posedge source_clk or negedge common_reset_n)
   if(!common_reset_n)source_reset_sync<=0;
   else source_reset_sync<={source_reset_sync[0],1'b1};
 always @(posedge dest_clk or negedge common_reset_n)
   if(!common_reset_n)dest_reset_sync<=0;
   else dest_reset_sync<={dest_reset_sync[0],1'b1};
 wire srst=source_reset_sync[1],drst=dest_reset_sync[1];
 reg [21:0] period_count;
 reg [255:0] held_values;
 reg request_toggle,ack_toggle;
 (* async_reg="true" *) reg ack_meta,ack_sync,req_meta,req_sync;
 always @(posedge source_clk or negedge srst)begin
   if(!srst)begin period_count<=0;held_values<=0;request_toggle<=0;ack_meta<=0;ack_sync<=0;end
   else begin
     ack_meta<=ack_toggle;ack_sync<=ack_meta;
     if(period_count==PERIOD_CYCLES-1)begin
       period_count<=0;
       if(request_toggle==ack_sync)begin held_values<=values_i;request_toggle<=~request_toggle;end
     end else period_count<=period_count+1'b1;
   end
 end
 reg [1:0] state;
 reg [5:0] index;
 reg [7:0] data_encoded;
 reg [255:0] snapshot_values;
 always @(posedge dest_clk or negedge drst)begin
   if(!drst)snapshot_values<=0;
   else if(state==0 && req_sync!=ack_toggle)snapshot_values<=held_values;
 end
 wire [5:0] next_index = (state==0 && req_sync!=ack_toggle) ? 6'd0 :
                          (state==2 && index!=39) ? index+6'd1 : index;
 assign udp_request_o=state==1;
 assign udp_valid_o=state==2;
 assign udp_length_o=16'd40;
 assign udp_data_o=data_encoded ^ 8'h59;
 function automatic [7:0] byte_at;
   input [5:0] at;
   reg [31:0] selected;
   begin
     selected=0;
     case(at[5:2])
       2:selected=snapshot_values[31:0];3:selected=snapshot_values[63:32];
       4:selected=snapshot_values[95:64];5:selected=snapshot_values[127:96];
       6:selected=snapshot_values[159:128];7:selected=snapshot_values[191:160];
       8:selected=snapshot_values[223:192];9:selected=snapshot_values[255:224];
     endcase
     case(at)
       0:byte_at=8'h59;1:byte_at=8'h35;2:byte_at=8'h41;3:byte_at=8'h45;
       4:byte_at=1;5:byte_at=10;6,7:byte_at=0;
       default:byte_at=selected[at[1:0]*8+:8];
     endcase
   end
 endfunction
 always @(posedge dest_clk or negedge drst)begin
   if(!drst)data_encoded<=0;
   else data_encoded<=byte_at(next_index) ^ 8'h59;
 end
 always @(posedge dest_clk or negedge drst)begin
   if(!drst)begin req_meta<=0;req_sync<=0;ack_toggle<=0;state<=0;index<=0;end
   else begin
     req_meta<=request_toggle;req_sync<=req_meta;
     case(state)
       0:if(req_sync!=ack_toggle)begin index<=0;state<=1;end
       1:if(udp_busy_i)state<=2;
       2:if(index==39)state<=3;else index<=index+1'b1;
       3:if(!udp_busy_i)begin ack_toggle<=req_sync;state<=0;end
     endcase
   end
 end
 // synthesis translate_off
 initial if(PERIOD_CYCLES<4 || PERIOD_CYCLES>4194304)$fatal(1,"Unsupported telemetry period");
 // synthesis translate_on
endmodule
