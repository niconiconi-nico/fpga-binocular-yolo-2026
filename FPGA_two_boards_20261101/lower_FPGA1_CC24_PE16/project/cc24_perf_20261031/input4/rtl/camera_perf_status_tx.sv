// Additive Y5PS v1/kind9, 32-byte atomic runtime diagnostic acknowledgement.
// flags[2:0]=applied mode, [3]=frozen, [4]=pending; others reserved zero.
// Six LE u32: applied sequence, actual source ID, strict graph starts,
// committed AI dones, committed Camera frames, routine video reader starts.
// Original Y5ST, RGB565 and detection wire formats remain unchanged.
module camera_perf_status_tx(
 input wire clk,rst_n,start_i,input wire [15:0] flags_i,
 input wire [191:0] counters_i,input wire udp_busy_i,
 output wire busy_o,output reg done_o,
 output wire udp_request_o,udp_valid_o,output reg [7:0] udp_data_o,
 output wire [15:0] udp_length_o
);
 reg [1:0] state;reg [5:0] index;
 reg [15:0] flags;reg [191:0] counters;reg [31:0] selected_word;
 assign busy_o=state!=0;assign udp_request_o=state==1;
 assign udp_valid_o=state==2;assign udp_length_o=16'd32;
 always @*begin
   selected_word=0;
   case(index[4:2])
     2:selected_word=counters[31:0];3:selected_word=counters[63:32];
     4:selected_word=counters[95:64];5:selected_word=counters[127:96];
     6:selected_word=counters[159:128];7:selected_word=counters[191:160];
   endcase
   case(index)
     0:udp_data_o=8'h59;1:udp_data_o=8'h35;2:udp_data_o=8'h50;3:udp_data_o=8'h53;
     4:udp_data_o=1;5:udp_data_o=9;6:udp_data_o=flags[7:0];7:udp_data_o=flags[15:8];
     default:udp_data_o=selected_word[index[1:0]*8+:8];
   endcase
 end
 always @(posedge clk or negedge rst_n)begin
   if(!rst_n)begin state<=0;index<=0;flags<=0;counters<=0;done_o<=0;end
   else begin
     done_o<=0;
     case(state)
       0:if(start_i)begin flags<=flags_i;counters<=counters_i;index<=0;state<=1;end
       1:if(udp_busy_i)state<=2;
       2:if(index==31)state<=3;else index<=index+1'b1;
       3:if(!udp_busy_i)begin state<=0;done_o<=1;end
     endcase
   end
 end
endmodule
