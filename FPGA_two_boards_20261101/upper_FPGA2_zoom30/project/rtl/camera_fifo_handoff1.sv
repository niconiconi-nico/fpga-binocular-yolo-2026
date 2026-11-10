// Same 32-beat queue/output contract, with a prefetched head outside the RAM.
// Never depend on vendor mixed-port same-address read/write semantics.
module camera_fifo_handoff1 #(
 parameter integer AW=5
)(
 input wire clk,rst_n,frame_start,in_valid,
 input wire[127:0]in_data,
 input wire flush_done_toggle,
 output reg out_valid,output reg[127:0]out_data,
 output reg error,output reg[31:0]overflow_count,overlap_count
);
 localparam integer DEPTH=1<<AW;
 (* async_reg="true" *)reg ack1,ack2;
 reg ack_seen,waiting,streaming,discard;
 reg[AW-1:0]wp,rp;
 reg[AW:0]count;
 reg[127:0]prefix[0:DEPTH-1];
 reg[127:0]head_direct,ram_next;
 reg head_from_ram;
 wire ack_event=ack2!=ack_seen;
 wire pop=streaming&&!discard&&(count!=0);
 wire room=(count<DEPTH)||pop;
 wire push=in_valid&&!discard&&room;
 wire mem_we=rst_n&&(frame_start?in_valid:push);
 wire[AW-1:0]mem_wa=frame_start?{AW{1'b0}}:wp;
 wire ram_re=rst_n&&!frame_start&&pop&&(count>1);
 wire[AW-1:0]ram_ra=rp+1'b1;
 // At count>=2 the next head is already stored. The write pointer cannot
 // equal rp+1 unless count==1, where the incoming word is bypassed instead.
 // At full occupancy wp==rp: the outgoing head is held outside RAM and the
 // RAM reads rp+1, so the full-depth simultaneous pop/push is collision-free.
 always @(posedge clk)begin
  if(mem_we)prefix[mem_wa]<=in_data;
  if(ram_re)ram_next<=prefix[ram_ra];
  if(rst_n&&((frame_start&&in_valid)||(!frame_start&&push&&((count==0)||(pop&&count==1)))))
   head_direct<=in_data;
  if(rst_n&&!frame_start&&pop)out_data<=head_from_ram?ram_next:head_direct;
 end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)head_from_ram<=0;
  else if(frame_start)head_from_ram<=0;
  else if(ram_re)head_from_ram<=1;
  else if(push&&((count==0)||(pop&&count==1)))head_from_ram<=0;
 end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin ack1<=0;ack2<=0;end
  else begin ack1<=flush_done_toggle;ack2<=ack1;end
 end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   ack_seen<=0;waiting<=0;streaming<=0;discard<=1;
   wp<=0;rp<=0;count<=0;out_valid<=0;
   error<=0;overflow_count<=0;overlap_count<=0;
  end else begin
   ack_seen<=ack2;out_valid<=0;
   if(frame_start)begin
    wp<=in_valid?1:0;rp<=0;count<=in_valid?1:0;
    waiting<=1;streaming<=0;discard<=waiting;
    if(waiting)begin error<=1;overlap_count<=overlap_count+1'b1;end
   end else begin
    if(ack_event&&waiting)begin waiting<=0;streaming<=!discard;end
    if(in_valid&&!discard&&!room)begin
     error<=1;overflow_count<=overflow_count+1'b1;
     discard<=1;streaming<=0;count<=0;
    end else begin
     if(push)begin wp<=wp+1'b1;end
     if(pop)begin out_valid<=1;rp<=rp+1'b1;end
     case({push,pop})
      2'b10:count<=count+1'b1;
      2'b01:count<=count-1'b1;
      default:count<=count;
     endcase
    end
   end
  end
 end
endmodule
