// FPGA2 renders actual received YOLO boxes/associated IDs on remote full720p.
// No local-image boxes or fabricated detections. Green SYNC is exact-source;
// amber HOLD is a bounded last real detection, NOT current-frame inference.
// CLAUDE UPPER_V1 (2026-10-25): each box carries its class name (record class[61:60] = person / car / chair / bottle,
// detection_protocol.CLASSES) as black text on a bar in the box colour; the status / FID block moved down by SY=44 lines
// to make room for the Anlogic logo in the top-right corner (anlogic_logo_overlay, y 8..47).
// CLAUDE BOTTLE (2026-10-28): tracking_mode = mode 38 BOTTLE (YOLO-seeded template tracker, one cyan BOTTLE box, status
// TRAK / LOST / WAIT); the FID line then reads "BOTTLE TRACK".
module yolo_box_overlay1(input wire enable,de,input wire[10:0]x,input wire[9:0]y,
 input wire[319:0]tracks,input wire usable_match,delayed_match,
 input wire[31:0]result_id,video_id,input wire seen,input wire[8:0]total,input wire[2:0]selected,
 output reg ink,output reg[23:0]rgb,input wire tracking_mode,input wire[2:0]tracking_status);
 `include "G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/modes/font5x7.vh"
 reg[79:0]e;reg[10:0]a,b,c,d;reg[7:0]ch;reg[4:0]bits;integer slot,col,row;
 reg[31:0]status_text;reg[23:0]status_rgb;
 function automatic[7:0]hexchar(input[3:0]n);hexchar=n<10?48+n:65+n-10;endfunction
 function automatic[7:0]bt_char(input integer k);reg[95:0]t;begin t="BOTTLE TRACK";bt_char=(k>=0&&k<12)?t[(11-k)*8+:8]:8'd32;end endfunction
 localparam integer SY=44;
 function automatic[7:0]class_char(input[1:0]c,input integer k);reg[47:0]nm;begin
  case(c)2'd0:nm="PERSON";2'd1:nm="CAR   ";2'd2:nm="CHAIR ";default:nm="BOTTLE";endcase
  class_char=(k>=0&&k<6)?nm[(5-k)*8+:8]:8'd32;end endfunction
 reg[1:0]cls;reg[5:0]lw;reg[23:0]box_rgb;
 always @*begin
  ink=0;rgb=0;e=0;a=0;b=0;c=0;d=0;ch=0;bits=0;slot=0;col=0;row=0;
  status_text=!seen?"WAIT":!usable_match?"OLD ":total==0?"NONE":selected==0?"LOW ":delayed_match?"HOLD":"SYNC";
  status_rgb=!seen?24'hffb000:!usable_match?24'hff3030:total==0?24'h0080ff:selected==0?24'hff00ff:delayed_match?24'hffb000:24'h00ff00;
  if(tracking_mode)begin
   case(tracking_status)
    0:status_text="TRAK";1:status_text="SRC?";2:status_text="GAP ";3:status_text="FUTR";
    4:status_text="LOST";5:status_text="WAIT";6:status_text="WAIT";7:status_text="OLD ";
   endcase
   status_rgb=tracking_status==0?24'h00ffff:tracking_status==4||tracking_status==7?24'hff3030:24'hffb000;
   // No eligible detector seed is NOT a pixel-motion or history failure.
   // Keep the same0.25 threshold and explicitly expose NONE/LOW in mode47.
   if(!seen)begin status_text="WAIT";status_rgb=24'hffb000;end
   else if(total==0)begin status_text="NONE";status_rgb=24'h0080ff;end
   else if(selected==0)begin status_text="LOW ";status_rgb=24'hff00ff;end
  end
  if(enable&&de)begin
   if(x>=1248&&x<1260&&y>=8+SY&&y<20+SY)begin ink=1;rgb=status_rgb;end
   if(x>=1208&&x<1240&&y>=8+SY&&y<15+SY)begin
    slot=(x-1208)/8;col=(x-1208)%8;row=y-8-SY;
    ch=status_text[(3-slot)*8+:8];bits=font_row(ch,4'(row));
    if(col>=1&&col<=5&&bits[5-col])begin ink=1;rgb=status_rgb;end
   end
   // Full source/result FIDs remain visible: S:xxxxxxxx V:xxxxxxxx (hex).
   // They describe delay honestly; HOLD does not claim optical-flow tracking.
   if(x>=1048&&x<1216&&y>=24+SY&&y<31+SY)begin
    slot=(x-1048)/8;col=(x-1048)%8;row=y-24-SY;
    case(slot)
     0:ch="S";1,12:ch=":";10:ch=" ";11:ch="V";
     default:begin
      if(slot>=2&&slot<10)ch=hexchar(result_id[(9-slot)*4+:4]);
      else if(slot>=13&&slot<21)ch=hexchar(video_id[(20-slot)*4+:4]);
      else ch=" ";
     end
    endcase
    if(tracking_mode)ch=bt_char(slot);
    bits=font_row(ch,4'(row));
    if(col>=1&&col<=5&&bits[5-col])begin ink=1;rgb=status_rgb;end
   end
   // Visible overflow indicator: top4 displayed, full count was validated.
   if(total>selected&&x>=1264&&x<1276&&y>=8+SY&&y<20+SY)begin ink=1;rgb=24'hff00ff;end
   for(integer k=0;k<4;k=k+1)begin
    e=tracks[k*80+:80];a=e[10:0];b=e[21:11];c=e[32:22];d=e[43:33];
    if(usable_match&&e[70]&&e[71]&&a<c&&b<d)begin
     box_rgb=tracking_mode?24'h00ffff:delayed_match?24'hffb000:24'h00ff00;
     if(x>=a&&x<c&&y>=b&&y<d&&(x<a+2||x+2>=c||y<b+2||y+2>=d))begin ink=1;rgb=box_rgb;end
     cls=e[61:60];lw=(cls==2'd1) ? 6'd26 : (cls==2'd2) ? 6'd42 : 6'd50;          // 8 px per character + 2 px margin
     if(x>=a&&x<a+lw&&x<1280&&y>=b&&y<b+10&&y<720)begin
      ink=1;rgb=box_rgb;
      if(x>a&&y>b)begin
       slot=(x-a-1)/8;col=(x-a-1)%8;row=y-b-1;
       ch=class_char(cls,slot);bits=font_row(ch,4'(row));
       if(col>=1&&col<=5&&row<7&&bits[5-col])rgb=24'h000000;
      end
     end
    end
   end
  end
 end
endmodule
