`include "G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/modes/mono_stage_reference4.sv"
module mono_display6 #(
 parameter integer WIDTH=1280,HEIGHT=720,HTOTAL=1650,DEBOUNCE_CYCLES=1500000,
 parameter integer SHOW_DIAG=0, ROI_W=128,ROI_H=128,SEARCH_STEP=4,ENABLE_TEMPLATE=1
)(input wire clk,rst_n,input wire[2:0]key_n,input wire capture_key_n,
 input wire[7:0] external_mode_i,
 input wire hs_i,vs_i,de_i,input wire[23:0]rgb_i,input wire[12:0]diag_flags_i,
 output reg hs_o,vs_o,de_o,output reg[23:0]rgb_o,output wire[7:0]active_mode_o,requested_mode_o,
 output wire det_found_o,output wire[11:0]det_x_o,det_y_o,output wire[10:0]det_score_o,
 output wire[2:0]det_status_o,output wire[31:0]det_epoch_o,
 input wire lat_ok,input wire[11:0]lat_bcd,input wire[15:0]cap_bcd,dsp_bcd,   // CLAUDE Z25 LATENCY (latency_meter1)
 input wire[1:0]lag,input wire[7:0]show_fps,udp_fps,input wire[15:0]mbps);   // CLAUDE Z28C MONITOR (latency_meter5)
 `include "G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/modes/mode_catalog.vh"
 `include "G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/modes/font5x7.vh"
 reg vs_d;
 always @(posedge clk or negedge rst_n)if(!rst_n)vs_d<=0;else vs_d<=vs_i;
 assign requested_mode_o=external_mode_i;
 assign active_mode_o=external_mode_i;
 localparam integer CW=$clog2(DEBOUNCE_CYCLES+1);
 (* async_reg="true" *)reg cap_meta,cap_sync;reg cap_stable,cap_pulse;reg[CW-1:0]cap_count;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin cap_meta<=1;cap_sync<=1;end else begin cap_meta<=capture_key_n;cap_sync<=cap_meta;end
 end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin cap_stable<=1;cap_count<=0;cap_pulse<=0;end
  else begin
   cap_pulse<=0;
   if(cap_sync==cap_stable)cap_count<=0;
   else if(cap_count==DEBOUNCE_CYCLES-1)begin cap_stable<=cap_sync;cap_count<=0;if(!cap_sync)cap_pulse<=1;end
   else cap_count<=cap_count+1'b1;
  end
 end
 wire ah,av,ad,bh,bv,bd;wire[23:0]ap,bp;wire[7:0]am,bm;wire[11:0]ax,ay,bx,by;
 mono_raster_stage4 #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.HTOTAL(HTOTAL)) stage1(clk,rst_n,hs_i,vs_i,de_i,rgb_i,active_mode_o,ah,av,ad,ap,am,ax,ay);
 // Compact menu removes OPEN/CLOSE, the only users of the second window.
 // Data, sync, mode and coordinates all use the same first-stage outputs.
 assign bh=ah;assign bv=av;assign bd=ad;assign bp=ap;
 assign bm=am;assign bx=ax;assign by=ay;
 wire match_done,match_found,match_binary,match_busy,template_valid;
 wire[11:0]match_x,match_y;wire[10:0]match_score;wire[31:0]match_epoch,match_cycles,template_epoch;wire[2:0]match_status;
 generate if(ENABLE_TEMPLATE)begin:TRADITIONAL_TEMPLATE
 template_search2 #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.ROI_W(ROI_W),.ROI_H(ROI_H),.STEP(SEARCH_STEP)) detector(
 clk,rst_n,vs_i,de_i,rgb_i,active_mode_o,cap_pulse,match_done,match_found,match_binary,
 match_x,match_y,match_score,match_epoch,match_cycles,match_status,match_busy,template_valid,template_epoch);
 end else begin:NO_TEMPLATE
  assign match_done=0;assign match_found=0;assign match_binary=0;assign match_busy=0;assign template_valid=0;
  assign match_x=0;assign match_y=0;assign match_score=0;assign match_epoch=0;assign match_cycles=0;assign template_epoch=0;assign match_status=0;
 end endgenerate
 // All computation, RAM and rendering use the SAME pixel clock. No result
 // CDC is introduced. Latch the complete result only at output VS boundary.
 reg output_vs_d,display_found,display_binary;reg[11:0]display_x,display_y;reg[10:0]display_score;reg[2:0]display_status;
 reg[31:0]display_epoch;   // CLAUDE TRACK47_NR: only drives the unconnected det_epoch_o, keep removed
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin output_vs_d<=0;display_found<=0;display_binary<=0;display_x<=0;display_y<=0;display_score<=0;display_status<=1;display_epoch<=0;end
  else begin
   output_vs_d<=bv;
   if(bv&&!output_vs_d)begin
    display_found<=match_found;display_binary<=match_binary;display_x<=match_x;display_y<=match_y;
    display_score<=match_score;display_status<=match_status;display_epoch<=match_epoch;
   end
  end
 end
 wire detect_mode=ENABLE_TEMPLATE&&(bm==27||bm==28);
 wire mode_ok=(bm==28)==display_binary;
 wire[2:0]view_status=detect_mode&&!mode_ok&&display_status!=1?3'd3:display_status;
 wire found=detect_mode&&mode_ok&&display_found&&view_status==4;
 wire box=bd&&found&&bx>=display_x&&bx<display_x+32&&by>=display_y&&by<display_y+32&&
 (bx<display_x+2||bx>=display_x+30||by<display_y+2||by>=display_y+30);
 localparam integer CAP_X=(WIDTH-ROI_W)/2+(ROI_W-32)/2,CAP_Y=(HEIGHT-ROI_H)/2+(ROI_H-32)/2;
 // Cyan capture guide only while explicitly CAPTURE; never a green/yellow
 // detection box or TRACK status. Actual matches are computed coordinates.
 wire capture_guide=bd&&detect_mode&&view_status==1&&bx>=CAP_X&&bx<CAP_X+32&&by>=CAP_Y&&by<CAP_Y+32&&
 (bx==CAP_X||bx==CAP_X+31||by==CAP_Y||by==CAP_Y+31);
 function automatic[7:0] status_char(input[2:0] st,input[10:0] sc,input[3:0] slot);
  reg[55:0]text;begin
   case(st)1:text="CAPTURE";3:text="SEARCH ";4:text="TRACK  ";5:text="LOST   ";default:text="READY  ";endcase
   if(slot<7)status_char=text[(6-slot)*8+:8];else if(slot==7)status_char=" ";
   else case(slot)8:status_char=8'd48+sc/1000;9:status_char=8'd48+(sc/100)%10;10:status_char=8'd48+(sc/10)%10;11:status_char=8'd48+sc%10;default:status_char=" ";endcase
  end
 endfunction
 // Pixel-clock observations, not fake-ready or test-pattern substitution.
 reg input_seen,stage1_seen,stage2_seen;reg[15:0]diag_frame;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin input_seen<=0;stage1_seen<=0;stage2_seen<=0;diag_frame<=0;end
  else begin
   if(de_i&&rgb_i!=0)input_seen<=1;
   if(ad&&ap!=0)stage1_seen<=1;
   if(bd&&bp!=0)stage2_seen<=1;
   if(bv&&!output_vs_d)diag_frame<={stage2_seen,stage1_seen,input_seen,diag_flags_i};
  end
 end
 function automatic[7:0] diag_char(input[3:0]slot,input[15:0]flags);
  reg[3:0]n;begin
   case(slot)
   0:diag_char="I";1:diag_char="D";2:diag_char=" ";
   3,4,5,6:begin
    case(slot)3:n=flags[15:12];4:n=flags[11:8];5:n=flags[7:4];default:n=flags[3:0];endcase
    diag_char=n<10?8'd48+n:8'd65+n-10;
   end
   default:diag_char=" ";endcase
  end
 endfunction
 wire diag_panel=SHOW_DIAG&&bd&&bx>=8&&bx<72&&by>=36&&by<48;
 wire[11:0]ddx=bx-12'd8,ddy=by-12'd36;
 wire[7:0]diag_character=diag_char(ddx[5:3],diag_frame);
 wire[4:0]diag_row=font_row(diag_character,ddy[3:0]-4'd2);
 wire diag_ink=diag_panel&&ddx[2:0]>=1&&ddx[2:0]<=5&&ddy[3:0]>=2&&ddy[3:0]<9&&diag_row[5-ddx[2:0]];
 // CLAUDE Z25 LATENCY / Z28 MONITOR (cyan, x from 112, right of the mode name), values from latency_meter3:
 //   row y 8..19 : "CAP 0125 DISP 0123 LAG 2 LAT 33.4MS"  newest captured camera frame, camera frame on screen, CAP - DISP,
 //                 mean capture -> display latency (Z28C: mean of 10 display frames). Not in 38 (remote camera view).
 //   row y 20..31: "SHOW 30FPS UDP 30FPS 442.4MBPS"  1 s hardware counts: new complete camera frames on screen (repeats
 //                 not counted), complete received UDP video frames, received video payload Mbit/s (Z28B: no CAM column).
 //                 In 38 only the UDP part, moved up to y 8..19 (the local-camera row is not shown there; the YOLO status
 //                 block x >= 1048, follow bar y 80.. and the logo are not covered).
 // Z28C: one character function for both rows, u = {row 2, slot}
 function automatic[7:0] mon_char(input[6:0]u);
  reg[3:0]d;begin
   case(u)4:d=cap_bcd[15:12];5:d=cap_bcd[11:8];6:d=cap_bcd[7:4];7:d=cap_bcd[3:0];
    14:d=dsp_bcd[15:12];15:d=dsp_bcd[11:8];16:d=dsp_bcd[7:4];17:d=dsp_bcd[3:0];23:d={2'd0,lag};
    29:d=lat_bcd[11:8];30:d=lat_bcd[7:4];32:d=lat_bcd[3:0];
    69:d=show_fps[7:4];70:d=show_fps[3:0];79:d=udp_fps[7:4];80:d=udp_fps[3:0];
    85:d=mbps[15:12];86:d=mbps[11:8];87:d=mbps[7:4];default:d=mbps[3:0];endcase
   case(u)0:mon_char="C";1:mon_char="A";2:mon_char="P";9:mon_char="D";10:mon_char="I";11:mon_char="S";12:mon_char="P";
    19:mon_char="L";20:mon_char="A";21:mon_char="G";25:mon_char="L";26:mon_char="A";27:mon_char="T";31:mon_char=".";
    33:mon_char="M";34:mon_char="S";
    64:mon_char="S";65:mon_char="H";66:mon_char="O";67:mon_char="W";75:mon_char="U";76:mon_char="D";77:mon_char="P";
    71,81:mon_char="F";72,82,92:mon_char="P";73,83,93:mon_char="S";88:mon_char=".";90:mon_char="M";91:mon_char="B";
    4,5,6,7,14,15,16,17,23,69,70,79,80,85,86,87,89:mon_char=8'd48+d;
    29,30,32:mon_char=lat_ok?8'd48+d:"-";
    default:mon_char=" ";endcase
  end
 endfunction
 wire m38=bm==8'd38;
 wire row1=bd&&!m38&&bx>=112&&bx<392&&by>=8&&by<20;
 wire row2=bd&&(m38?(bx>=112&&bx<264&&by>=8&&by<20):(bx>=112&&bx<352&&by>=20&&by<32));
 wire panel3=row1||row2;
 wire[11:0]lx=bx-12'd112;
 wire[6:0]mu={row2,(row2&&m38)?lx[8:3]+6'd11:lx[8:3]};
 wire panel1=bd&&bx>=8&&bx<104&&by>=8&&by<20;
 wire panel2=bd&&detect_mode&&bx>=8&&bx<104&&by>=20&&by<32;
 wire[11:0]dx=bx-12'd8,dy=(panel2||(row2&&!m38))?by-12'd20:by-12'd8;
 wire[7:0]character=panel3?mon_char(mu):panel2?status_char(view_status,display_score,dx[6:3]):mode_char(bm,dx[6:3]);
 wire[4:0]row=font_row(character,dy[3:0]-4'd2);
 wire ink=(panel1||panel2||panel3)&&dx[2:0]>=1&&dx[2:0]<=5&&dy[3:0]>=2&&dy[3:0]<9&&row[5-dx[2:0]];
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin hs_o<=0;vs_o<=0;de_o<=0;rgb_o<=0;end
  else begin
   hs_o<=bh;vs_o<=bv;de_o<=bd;
   rgb_o<=!bd?24'd0:diag_panel?(diag_ink?24'hffff00:24'h101010):(panel1||panel2)?(ink?24'hffff00:24'h101010):panel3?(ink?24'h00ffff:24'h101010):box?(bm==27?24'h00ff00:24'hffff00):capture_guide?24'h00ffff:bp;
  end
 end
 assign det_found_o=found;assign det_x_o=display_x;assign det_y_o=display_y;
 assign det_score_o=display_score;assign det_status_o=view_status;assign det_epoch_o=display_epoch;
endmodule
