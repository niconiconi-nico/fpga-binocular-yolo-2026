// CLAUDE Z11 (2026-10-30): ARP-only responder (ethernet_control_reply1 without ICMP / packet buffer). The lower board (CC24
// mini_arp) learns this board's MAC only from an ARP reply, then sends video / Y5CD; zoom10 had removed the responder and the
// right eye stayed black. Acceptance = ethernet_control_reply1 good_arp (64-byte frame, good FCS, dst = LOCAL_MAC or
// broadcast, 0806, 0001 0800 06 04 0001, ARP sender MAC = Ethernet source MAC, target IP = LOCAL_IP), checked byte by byte
// as the frame arrives; only the sender MAC / IP are kept. The reply (60 bytes + FCS, preamble, 12-byte gap) and the
// RX / TX handshake are those of ethernet_control_reply1, byte for byte. ICMP echo is not answered (user: no ping).
// Z11b AREA: the reply FCS is computed bit-serially over the 60 reply bytes (480 tx clocks, ~3.8 us) before the preamble
// instead of a byte-parallel CRC in the body loop; the transmitted bytes are unchanged, the reply leaves ~3.8 us later.
module arp_reply_lite #(
 parameter[47:0] LOCAL_MAC=48'h020000240002,
 parameter[31:0] LOCAL_IP=32'hc0a8f002
)(input wire rx_clk,tx_clk,rst,input wire rx_valid,rx_error,input wire[7:0]rx_data,
 output reg tx_valid,output reg[7:0]tx_data);
 wire rr,tr;reset_domain_sync rx_release(rx_clk,rst,rr);reset_domain_sync tx_release(tx_clk,rst,tr);
 function automatic[31:0]crc_step(input[31:0]old,input[7:0]b);
  reg[31:0]c;integer k;begin c=old^{24'd0,b};for(k=0;k<8;k=k+1)c=c[0]?(c>>1)^32'hedb88320:c>>1;crc_step=c;end
 endfunction
 reg receiving,discard,fault,dm_local,dm_bc,fixed_ok,smac_ok,tip_ok;reg[3:0]preamble;reg[11:0]count;reg[31:0]crc;
 reg[7:0]smac[0:5],sip[0:3];
 reg req,ack;(*async_reg="true"*)reg ack1,ack2,req1,req2;
 wire busy=req!=ack2;
 // expected byte of the fixed part 12..21
 function automatic[7:0]fixed_byte(input[3:0]i);
  case(i) 0:fixed_byte=8'h08;1:fixed_byte=8'h06;2:fixed_byte=8'h00;3:fixed_byte=8'h01;4:fixed_byte=8'h08;5:fixed_byte=8'h00;
   6:fixed_byte=8'h06;7:fixed_byte=8'h04;8:fixed_byte=8'h00;default:fixed_byte=8'h01;endcase
 endfunction
 wire good_arp=!discard&&!fault&&crc==32'hdebb20e3&&count==64&&(dm_local||dm_bc)&&fixed_ok&&smac_ok&&tip_ok;
 integer h;
 always @(posedge rx_clk or posedge rr)begin
  if(rr)begin
   receiving<=0;discard<=0;fault<=0;preamble<=0;count<=0;crc<=32'hffffffff;dm_local<=0;dm_bc<=0;fixed_ok<=0;smac_ok<=0;tip_ok<=0;
   req<=0;ack1<=0;ack2<=0;for(h=0;h<6;h=h+1)smac[h]<=0;for(h=0;h<4;h=h+1)sip[h]<=0;
  end else begin
   ack1<=ack;ack2<=ack1;
   if(rx_valid)begin
    if(!receiving)begin
     if(rx_data==8'h55)preamble<=preamble==7?7:preamble+1'b1;
     else if(rx_data==8'hd5&&preamble==7)begin
      receiving<=1;discard<=busy;fault<=rx_error;count<=0;crc<=32'hffffffff;preamble<=0;
      dm_local<=1;dm_bc<=1;fixed_ok<=1;smac_ok<=1;tip_ok<=1;
     end else preamble<=0;
    end else begin
     fault<=fault||rx_error;
     if(count<2048&&!discard)begin
      crc<=crc_step(crc,rx_data);
      if(count<6)begin if(rx_data!=LOCAL_MAC[(5-count)*8+:8])dm_local<=0;if(rx_data!=8'hff)dm_bc<=0;end
      else if(count<12)smac[count-6]<=rx_data;
      else if(count<22)begin if(rx_data!=fixed_byte(count-12))fixed_ok<=0;end
      else if(count<28)begin if(rx_data!=smac[count-22])smac_ok<=0;end
      else if(count<32)sip[count-28]<=rx_data;
      else if(count>=38&&count<42)begin if(rx_data!=LOCAL_IP[(41-count)*8+:8])tip_ok<=0;end
     end else discard<=1;
     if(count<4095)count<=count+1'b1;else discard<=1;
    end
   end else begin
    preamble<=0;
    if(receiving)begin receiving<=0;if(good_arp)req<=~req;end
   end
  end
 end
 reg[5:0]index;
 function automatic[7:0]reply_byte(input[5:0]i);
  begin
   if(i<6)reply_byte=smac[i];
   else if(i<12)reply_byte=LOCAL_MAC[(11-i)*8+:8];
   else case(i)
    12:reply_byte=8'h08;13:reply_byte=8'h06;14:reply_byte=0;15:reply_byte=1;
    16:reply_byte=8'h08;17:reply_byte=0;18:reply_byte=6;19:reply_byte=4;20:reply_byte=0;21:reply_byte=2;
    22,23,24,25,26,27:reply_byte=LOCAL_MAC[(27-i)*8+:8];
    28,29,30,31:reply_byte=LOCAL_IP[(31-i)*8+:8];
    32,33,34,35,36,37:reply_byte=smac[i-32];
    38,39,40,41:reply_byte=sip[i-38];
    default:reply_byte=0;
   endcase
  end
 endfunction
 reg[2:0]state,bb;reg[3:0]pre,gap;reg[1:0]fcs;reg[31:0]tx_crc;
 wire[7:0]body_byte=reply_byte(index);
 wire cb=tx_crc[0]^body_byte[bb];                                 // bit-serial CRC-32 (LSB first, as crc_step)
 always @(posedge tx_clk or posedge tr)begin
  if(tr)begin req1<=0;req2<=0;ack<=0;tx_valid<=0;tx_data<=0;state<=0;pre<=0;gap<=0;fcs<=0;index<=0;bb<=0;tx_crc<=32'hffffffff;end
  else begin
   req1<=req;req2<=req1;tx_valid<=0;
   case(state)
    0:if(req2!=ack)begin state<=5;pre<=0;index<=0;bb<=0;tx_crc<=32'hffffffff;end
    5:begin                                                      // FCS of the reply body, one bit per clock
     tx_crc<=(tx_crc>>1)^({32{cb}}&32'hedb88320);bb<=bb+1'b1;
     if(bb==3'd7)begin if(index==6'd59)begin index<=0;state<=1;end else index<=index+1'b1;end
    end
    1:begin tx_valid<=1;tx_data<=pre==7?8'hd5:8'h55;if(pre==7)begin state<=2;index<=0;end else pre<=pre+1'b1;end
    2:begin
     tx_valid<=1;tx_data<=body_byte;
     if(index==6'd59)begin state<=3;fcs<=0;end else index<=index+1'b1;
    end
    3:begin tx_valid<=1;tx_data<=~(tx_crc>>(fcs*8));if(fcs==3)begin state<=4;gap<=0;end else fcs<=fcs+1'b1;end
    4:if(gap==11)begin ack<=req2;state<=0;end else gap<=gap+1'b1;
    default:state<=0;
   endcase
  end
 end
endmodule
