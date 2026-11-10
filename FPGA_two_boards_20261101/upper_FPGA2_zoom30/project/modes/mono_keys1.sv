// Three documented active-low board keys. One pulse per debounced press.
// CLAUDE Z10 GIMBAL (board22 key feel in the multi-mode build): K3 (key 2) acts on RELEASE (back to mode 1) unless it was
// held HOLD_CYCLES (1 s) in a follow-capable mode while the gimbal is not armed -> arm_pulse instead (no mode change).
// While armed, the first press of any mode key is a STOP only (stop_pulse, no mode change).
// CLAUDE Z11 AREA: MS_TICK = 1 -> debounce (DEBOUNCE_MS) and K3 hold (HOLD_MS) count the shared 1 ms tick ms (5 / 10-bit
// counters instead of 21 / 27-bit clock counters; deadlines move by < 1 ms). MS_TICK = 0: clock counting as before.
module mono_keys1 #(
 parameter integer DEBOUNCE_CYCLES=1500000, parameter integer LAST_MODE=37, DEFAULT_MODE=37,SKIP_TEMPLATE=0,HOLD_CYCLES=75000000,
 parameter integer MS_TICK=0,DEBOUNCE_MS=20,HOLD_MS=1000
)(input wire clk,rst_n,input wire [2:0] key_n,input wire frame_boundary,
 output reg [7:0] requested_mode,active_mode,
 input wire follow_mode,armed,output reg arm_pulse,stop_pulse,input wire ms);
 localparam integer DB=MS_TICK?DEBOUNCE_MS:DEBOUNCE_CYCLES, HD=MS_TICK?HOLD_MS:HOLD_CYCLES;
 localparam integer CW=$clog2(DB+1);
 wire step=MS_TICK?ms:1'b1;
 (* async_reg="true" *) reg [2:0] key_meta,key_sync;
 reg [2:0] stable;
 reg [CW-1:0] count[0:2];
 reg [2:0] press,release_;
 reg [$clog2(HD+1)-1:0] hold;reg k3_used;
 integer i;
 `include "G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/modes/mode_tables.vh"
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n)begin key_meta<=3'b111;key_sync<=3'b111;end
  else begin key_meta<=key_n;key_sync<=key_meta;end
 end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   stable<=3'b111;press<=0;release_<=0;
   for(i=0;i<3;i=i+1)count[i]<=0;
  end else begin
   press<=0;release_<=0;
   for(i=0;i<3;i=i+1)begin
    if(key_sync[i]==stable[i])count[i]<=0;
    else if(count[i]==DB-1 && step)begin
     stable[i]<=key_sync[i];count[i]<=0;
     if(!key_sync[i])press[i]<=1;else release_[i]<=1;
    end else if(step) count[i]<=count[i]+1'b1;
   end
  end
 end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin requested_mode<=DEFAULT_MODE;active_mode<=DEFAULT_MODE;hold<=0;k3_used<=0;arm_pulse<=0;stop_pulse<=0;end
  else begin
   arm_pulse<=0;stop_pulse<=0;
   if(press[2])begin hold<=0;k3_used<=armed;if(armed)stop_pulse<=1;end
   else if(!stable[2])begin
    if(hold!=HD && step)hold<=hold+1'b1;
    if(hold==HD-1 && step && !k3_used && follow_mode && !armed)begin arm_pulse<=1;k3_used<=1;end
   end
   if(armed && (press[0]||press[1]))stop_pulse<=1;
   else if(release_[2])begin if(!k3_used)requested_mode<=1;end
   // CLAUDE Z10: key cycle over the reachable modes (mode_tables.vh, generated); LAST_MODE / SKIP_TEMPLATE unused
   else if(press[0] && !press[1])requested_mode<=next_mode(requested_mode);
   else if(press[1] && !press[0])requested_mode<=prev_mode(requested_mode);
   if(frame_boundary)active_mode<=requested_mode;
  end
 end
endmodule
