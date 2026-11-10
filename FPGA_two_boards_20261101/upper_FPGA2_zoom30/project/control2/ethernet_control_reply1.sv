// Small validated ARP/ICMP responder. VIDEO retains its independent checked RX.
// One held packet bank; RX metadata/data remain stable until TX/FCS/IFG ACK.
module ethernet_control_reply1 #(
 parameter[47:0] LOCAL_MAC=48'h020000240002,
 parameter[31:0] LOCAL_IP=32'hc0a8f002
)(input wire rx_clk,tx_clk,rst,input wire rx_valid,rx_error,input wire[7:0]rx_data,
 output reg tx_valid,output reg[7:0]tx_data,
 output reg[31:0]replies,bad_control,busy_drops);
 wire rr,tr;reset_domain_sync rx_release(rx_clk,rst,rr);reset_domain_sync tx_release(tx_clk,rst,tr);
 reg[7:0] packet[0:2047]; /* fehdl force_ram=1, ram_style="bram" */
 reg[7:0] header[0:41];
 reg receiving,discard,fault;reg[3:0]preamble;reg[11:0]count;
 reg[31:0]crc,ip_sum,icmp_sum;reg[7:0]hi;
 reg req,ack;(*async_reg="true"*)reg ack1,ack2,req1,req2;
 reg reply_arp;reg[10:0]reply_bytes;reg[15:0]reply_checksum;
 wire busy=req!=ack2;
 wire[47:0]dest_mac={header[0],header[1],header[2],header[3],header[4],header[5]};
 wire[47:0]source_mac={header[6],header[7],header[8],header[9],header[10],header[11]};
 wire[15:0]ethertype={header[12],header[13]};
 wire[15:0]ip_length={header[16],header[17]},fragment={header[20],header[21]};
 wire[31:0]dest_ip={header[30],header[31],header[32],header[33]};
 wire[31:0]arp_target={header[38],header[39],header[40],header[41]};
 wire[11:0]ip_body=12'd14+{1'b0,ip_length[10:0]};
 wire[11:0]ip_physical=(ip_body<60?12'd60:ip_body)+12'd4;
 function automatic[31:0]crc_step(input[31:0]old,input[7:0]b);
  reg[31:0]c;integer k;begin c=old^{24'd0,b};for(k=0;k<8;k=k+1)c=c[0]?(c>>1)^32'hedb88320:c>>1;crc_step=c;end
 endfunction
 function automatic[15:0]fold(input[31:0]s);
  reg[16:0]v;begin v={1'b0,s[15:0]}+s[31:16];fold=v[15:0]+v[16];end
 endfunction
 wire good_fcs=!discard&&!fault&&crc==32'hdebb20e3;
 wire good_arp=good_fcs&&count==64&&ethertype==16'h0806&&
  (dest_mac==LOCAL_MAC||dest_mac==48'hffffffffffff)&&
  {header[14],header[15],header[16],header[17]}==32'h00010800&&
  {header[18],header[19],header[20],header[21]}==32'h06040001&&
  {header[22],header[23],header[24],header[25],header[26],header[27]}==source_mac&&arp_target==LOCAL_IP;
 wire good_icmp=good_fcs&&count==ip_physical&&ethertype==16'h0800&&dest_mac==LOCAL_MAC&&
  header[14]==8'h45&&header[23]==1&&header[22]!=0&&dest_ip==LOCAL_IP&&
  ip_length>=28&&ip_length<=1500&&(fragment&16'hbfff)==0&&
  header[34]==8'd8&&header[35]==0&&fold(ip_sum)==16'hffff&&fold(icmp_sum)==16'hffff;
 integer h;
 always @(posedge rx_clk or posedge rr)begin
  if(rr)begin
   receiving<=0;discard<=0;fault<=0;preamble<=0;count<=0;crc<=32'hffffffff;
   ip_sum<=0;icmp_sum<=0;hi<=0;req<=0;ack1<=0;ack2<=0;reply_arp<=0;reply_bytes<=0;reply_checksum<=0;
   replies<=0;bad_control<=0;busy_drops<=0;
   for(h=0;h<42;h=h+1)header[h]<=0;
  end else begin
   ack1<=ack;ack2<=ack1;
   if(rx_valid)begin
    if(!receiving)begin
     if(rx_data==8'h55)preamble<=preamble==7?7:preamble+1'b1;
     else if(rx_data==8'hd5&&preamble==7)begin
      receiving<=1;discard<=busy;fault<=rx_error;count<=0;crc<=32'hffffffff;ip_sum<=0;icmp_sum<=0;hi<=0;preamble<=0;
      if(busy)busy_drops<=busy_drops+1'b1;
     end else preamble<=0;
    end else begin
     fault<=fault||rx_error;
     if(count<2048&&!discard)begin
      packet[count[10:0]]<=rx_data;if(count<42)header[count]<=rx_data;
      crc<=crc_step(crc,rx_data);
      if(count>=14)begin
       if(!count[0])hi<=rx_data;
       if(count>=14&&count<34&&count[0])ip_sum<=ip_sum+{hi,rx_data};
       if(count>=34&&count<ip_body)begin
        if(count[0])icmp_sum<=icmp_sum+{hi,rx_data};
        else if(count==ip_body-1)icmp_sum<=icmp_sum+{rx_data,8'd0};
       end
      end
     end else discard<=1;
     if(count<4095)count<=count+1'b1;else discard<=1;
    end
   end else begin
    preamble<=0;
    if(receiving)begin
     receiving<=0;
     if(good_arp||good_icmp)begin
      reply_arp<=good_arp;reply_bytes<=good_arp?11'd60:(ip_body<60?11'd60:ip_body[10:0]);
      reply_checksum<=fold({16'd0,header[36],header[37]}+32'h800);
      req<=~req;replies<=replies+1'b1;
     end else if(!discard&&(ethertype==16'h0806||(ethertype==16'h0800&&header[23]==1)))bad_control<=bad_control+1'b1;
    end
   end
  end
 end
 reg[7:0]ram_q;reg[10:0]index;
 // Ahead-of-use synchronous read; every body cycle loads the next byte.
 always @(posedge tx_clk)ram_q<=packet[index+11'd1];
 function automatic[7:0]reply_byte(input[10:0]i);
  begin
   if(i<6)reply_byte=header[6+i];
   else if(i<12)reply_byte=LOCAL_MAC[(11-i)*8+:8];
   else if(reply_arp)begin
    case(i)
     12:reply_byte=8'h08;13:reply_byte=8'h06;14:reply_byte=0;15:reply_byte=1;
     16:reply_byte=8'h08;17:reply_byte=0;18:reply_byte=6;19:reply_byte=4;20:reply_byte=0;21:reply_byte=2;
     22,23,24,25,26,27:reply_byte=LOCAL_MAC[(27-i)*8+:8];
     28,29,30,31:reply_byte=LOCAL_IP[(31-i)*8+:8];
     32,33,34,35,36,37:reply_byte=header[i-26];
     38,39,40,41:reply_byte=header[i-10];
     default:reply_byte=0;
    endcase
   end else if(i>=ip_body)reply_byte=0;
   else case(i)
    26,27,28,29:reply_byte=header[i+4];
    30,31,32,33:reply_byte=header[i-4];
    34:reply_byte=0;
    36:reply_byte=reply_checksum[15:8];37:reply_byte=reply_checksum[7:0];
    default:reply_byte=i<42?header[i]:ram_q;
   endcase
  end
 endfunction
 reg[2:0]state;reg[3:0]pre,gap;reg[1:0]fcs;reg[31:0]tx_crc;
 wire[7:0]body_byte=reply_byte(index);
 always @(posedge tx_clk or posedge tr)begin
  if(tr)begin req1<=0;req2<=0;ack<=0;tx_valid<=0;tx_data<=0;state<=0;pre<=0;gap<=0;fcs<=0;index<=0;tx_crc<=32'hffffffff;end
  else begin
   req1<=req;req2<=req1;tx_valid<=0;
   case(state)
    // Re-prime the byte address during preamble, so the first byte is
    // evaluated from this newly validated header even on the first reply.
    0:if(req2!=ack)begin state<=1;pre<=0;index<=2047;tx_crc<=32'hffffffff;end
    1:begin tx_valid<=1;tx_data<=pre==7?8'hd5:8'h55;if(pre==7)begin state<=2;index<=0;end else pre<=pre+1'b1;end
    2:begin
     tx_valid<=1;tx_data<=body_byte;tx_crc<=crc_step(tx_crc,body_byte);
     if(index==reply_bytes-1)begin state<=3;fcs<=0;end else index<=index+1'b1;
    end
    3:begin tx_valid<=1;tx_data<=~(tx_crc>>(fcs*8));if(fcs==3)begin state<=4;gap<=0;end else fcs<=fcs+1'b1;end
    4:if(gap==11)begin ack<=req2;state<=0;end else gap<=gap+1'b1;
    default:state<=0;
   endcase
  end
 end
endmodule
