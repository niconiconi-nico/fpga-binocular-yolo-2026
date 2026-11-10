// Actual CC12 Y5CD adapter: ordered records0..N-1 then summaryN, <=300.
// Wire header1024x600 describes the pinned central ROI, NOT full720p.
// Display-only top4 by confidence. Validate every record, including omitted ones.
// Detection-driven class/centre association, not optical flow or re-identification.
// Exact-source indicator remains strict. A separate, bounded HOLD display is
// explicitly labelled as delayed detection, never same-frame inference.
module y5cd_tracks1 #(
 parameter integer RX_TIMEOUT_CYCLES=250000000,MAX_DISPLAY_FRAMES=120,
 parameter[15:0]DISPLAY_MIN_CONFIDENCE=8192
)(input wire rx_clk,pixel_clk,rst,
 input wire byte_valid,packet_start,packet_last,input wire[7:0]byte_data,
 input wire[15:0]packet_length,input wire[1:0]packet_format,
 input wire frame_vs,input wire display_front_valid,input wire[31:0]display_front_id,
 output reg[319:0]display_tracks,output reg[31:0]display_result_id,
 output reg[8:0]display_total,output reg[2:0]display_selected,
 output wire exact_display_match,output reg display_seen,
 output reg[31:0]committed_results,bad_packets,bad_groups,busy_results,timed_out_groups,
 output wire debug_req,debug_ack,
 output wire recent_display_match,delayed_display_match,
 output reg[31:0]display_video_id,
 output wire[319:0]receiver_tracks,output wire[31:0]receiver_result_id,
 output wire receiver_seen,output wire[8:0]receiver_total,output wire[2:0]receiver_selected
);
 wire rr,pr;reset_domain_sync rx_release(rx_clk,rst,rr);reset_domain_sync px_release(pixel_clk,rst,pr);
 // Entry: FULL source x1[10:0],y1[21:11],x2[32:22],y2[43:33],
 // Q15[59:44],class[61:60],ID[69:62],valid70,observed71,reserved[79:72].
 function automatic[10:0]map_x(input signed[31:0]q,input upper);
  reg signed[63:0]n;reg[13:0]a;begin
   n=64'sd41943040+($signed(q)*64'sd16);
   if(n<=0)map_x=0;else if(n>=64'sd419430400)map_x=1280;
   else begin if(upper)n=n+64'sd327675;a=n>>>16;map_x=a/5;end
  end
 endfunction
 function automatic[10:0]map_y(input signed[31:0]q,input upper);
  reg signed[63:0]n;reg[15:0]a;begin
   n=64'sd184811520+($signed(q)-64'sd4325376)*64'sd150;
   if(n<=0)map_y=0;else if(n>=64'sd2217738240)map_y=720;
   else begin if(upper)n=n+64'sd3080145;a=n>>>16;map_y=a/47;end
  end
 endfunction
 function automatic newer(input[31:0]a,b);reg[31:0]v;begin v=a-b;newer=v!=0&&!v[31];end endfunction
 reg[5:0]pos;wire[5:0]at=packet_start?0:pos;
 reg collecting,packet_bad,pending;reg[7:0]typ,cls;
 reg[15:0]len,total,index,confidence;reg[31:0]fid,cycles;
 reg signed[31:0]x1,y1,x2,y2;
 reg active,seen_result;reg[31:0]active_id,active_cycles,last_id;
 reg[8:0]active_total,expected;reg[27:0]timeout_count;
 reg[79:0]candidate[0:3],track[0:3];reg[1:0]miss[0:3];
 reg[2:0]selected;reg[7:0]next_id,track_epoch;
 reg commit_pending;reg[31:0]commit_id;reg[8:0]commit_total;
 reg req,ack;(*async_reg="true"*)reg ack1,ack2,req1,req2;
 reg[319:0]held_tracks;reg[31:0]held_id;reg[8:0]held_total;reg[2:0]held_selected;
 wire mailbox_busy=req!=ack2;
 assign debug_req=req;assign debug_ack=ack;
 assign receiver_tracks=held_tracks;assign receiver_result_id=held_id;assign receiver_seen=seen_result;
 assign receiver_total=held_total;assign receiver_selected=held_selected;
 wire raw_record_ok=cls<4&&confidence<=32768&&x1<x2&&y1<y2;
 // Exact signed geometry, staged numerator -> clamp ->16 restoring divides.
 // Geometry completes before a bounded four-edge insertion per51B record;
 // no variable/constant combinational divider or unrolled sorting carry chain.
 // map_x/map_y above remain independent finite-test references, not used by
 // production dataflow.40bit numerator covers every signed32bit input safely.
 function automatic signed[39:0]numerator(input signed[31:0]q,input axis_y);
  reg signed[39:0]v;begin
   v={{8{q[31]}},q};
   if(axis_y)begin v=v-40'sd4325376;numerator=40'sd184811520+(v<<<7)+(v<<<4)+(v<<<2)+(v<<<1);end
   else numerator=40'sd41943040+(v<<<4);
  end
 endfunction
 // CLAUDE Z10 AREA: the four edges (x1, y1, x2, y2) are mapped one after another through ONE numerator / clamp / restoring
 // divider lane (was four parallel lanes): 4 x 18 clocks + 1 per record, records are >= 117 byte clocks apart on the wire.
 // Same arithmetic per edge (numerator, clamp, rounding constant for x2 / y2, divide by 5 / 47).
 reg[2:0]map_state;reg[3:0]divide_bit;reg record_ready;
 reg signed[31:0]mq[0:3];reg[1:0]mk;reg signed[39:0]mnum;reg[15:0]mdiv,mquo,quotient[0:3];reg[6:0]mrem;
 reg[31:0]record_id,record_cycles;reg[15:0]record_total,record_index,record_confidence;reg[1:0]record_class;
 wire[10:0]mx1=quotient[0][10:0],my1=quotient[1][10:0],mx2=quotient[2][10:0],my2=quotient[3][10:0];
 wire candidate_ok=record_confidence>=DISPLAY_MIN_CONFIDENCE&&mx1<mx2&&my1<my2;
 wire[79:0]mapped={8'd0,1'b1,1'b1,8'd0,record_class,record_confidence,my2,mx2,my1,mx1};
 wire[6:0]mtrial={mrem[5:0],mdiv[15]};wire[6:0]mdvs=mk[0]?7'd47:7'd5;   // mk[0]: y edge, mk[1]: x2 / y2
 // Capture geometry eligibility separately from confidence insertion. The
 // routed input5 failure chained quotient validity and all four comparisons
 // into a candidate CE (12levels). One registered carry/slot per edge retains
 // exact strict-greater insertion order, including equal-score stability.
 reg[79:0]record_mapped,sort_carry;
 reg record_eligible,sort_active;
 reg[1:0]sort_slot;
 wire[79:0]sort_old=candidate[sort_slot];
 wire sort_swap=!sort_old[70]||sort_carry[59:44]>sort_old[59:44];
 integer i,j;
 // The identical greedy policy is now one old/new pair per clock, not a
 // combinational16-pair network with32bit dynamic indices and cascaded muxes.
 // Coordinates are clipped to1280x720 before this13bit signed centre delta.
 localparam AS_IDLE=0,AS_SCAN=1,AS_WRITE=2,AS_RETAIN=3,AS_PUBLISH=4,AS_DELTA=5,AS_ABS=6,AS_SUM=7,AS_COMPARE=8;
 reg[3:0]association_state;reg[2:0]ci,fill;
 reg[1:0]ti,best;
 reg best_found;reg[8:0]best_distance;reg[3:0]used;
 reg[7:0]new_identity;
 reg[79:0]associated[0:3];reg[1:0]next_miss[0:3];
 wire association_busy=association_state!=AS_IDLE;
 wire[79:0]scan_new=candidate[ci[1:0]],scan_old=track[ti];
 // Actual input1 routed cause: candidate mux + centres + subtract +
 // absolute + sum + comparison exceeded8ns. Each edge now owns one step.
 reg[11:0]old_cx,old_cy,new_cx,new_cy;
 reg signed[12:0]dx,dy;reg[12:0]adx,ady;reg[13:0]distance;reg scan_eligible;
 always @(posedge rx_clk or posedge rr)begin
  if(rr)begin
   pos<=0;collecting<=0;packet_bad<=0;pending<=0;typ<=0;cls<=0;len<=0;total<=0;index<=0;confidence<=0;
   fid<=0;cycles<=0;x1<=0;y1<=0;x2<=0;y2<=0;active<=0;seen_result<=0;active_id<=0;active_cycles<=0;last_id<=0;
   active_total<=0;expected<=0;timeout_count<=0;selected<=0;next_id<=1;track_epoch<=0;
   commit_pending<=0;commit_id<=0;commit_total<=0;req<=0;ack1<=0;ack2<=0;
   held_tracks<=0;held_id<=0;held_total<=0;held_selected<=0;
   committed_results<=0;bad_packets<=0;bad_groups<=0;busy_results<=0;timed_out_groups<=0;
   map_state<=0;divide_bit<=0;record_ready<=0;mk<=0;mnum<=0;mdiv<=0;mquo<=0;mrem<=0;record_id<=0;record_cycles<=0;record_total<=0;record_index<=0;record_confidence<=0;record_class<=0;
   record_mapped<=0;record_eligible<=0;sort_carry<=0;sort_active<=0;sort_slot<=0;
   old_cx<=0;old_cy<=0;new_cx<=0;new_cy<=0;dx<=0;dy<=0;adx<=0;ady<=0;distance<=0;scan_eligible<=0;
   association_state<=AS_IDLE;ci<=0;ti<=0;fill<=0;best<=0;best_found<=0;best_distance<=257;used<=0;new_identity<=1;
   for(i=0;i<4;i=i+1)begin candidate[i]<=0;track[i]<=0;miss[i]<=0;associated[i]<=0;next_miss[i]<=0;mq[i]<=0;quotient[i]<=0;end
  end else begin
   ack1<=ack;ack2<=ack1;pending<=0;record_ready<=0;
   case(map_state)
    1:begin mnum<=numerator(mq[0],mk[0]);map_state<=4;end
    4:begin
     if(mnum<=0)mdiv<=0;
     else if(mnum>=(mk[0]?40'sd2217738240:40'sd419430400))mdiv<=mk[0]?16'd33840:16'd6400;
     else mdiv<=(mnum+(mk[1]?(mk[0]?40'sd3080145:40'sd327675):40'sd0))>>>16;
     mquo<=0;mrem<=0;divide_bit<=0;map_state<=2;
    end
    2:begin
     mdiv<={mdiv[14:0],1'b0};
     if(mtrial>=mdvs)begin mrem<=mtrial-mdvs;mquo<={mquo[14:0],1'b1};end
     else begin mrem<=mtrial;mquo<={mquo[14:0],1'b0};end
     if(divide_bit==15)map_state<=5;else divide_bit<=divide_bit+1'b1;
    end
    5:begin quotient[mk]<=mquo;mq[0]<=mq[1];mq[1]<=mq[2];mq[2]<=mq[3];mk<=mk+1'b1;map_state<=(mk==2'd3)?3'd3:3'd1;end
    3:begin record_mapped<=mapped;record_eligible<=candidate_ok;record_ready<=1;map_state<=0;end
   endcase
   if(sort_active)begin
    if(sort_swap)begin candidate[sort_slot]<=sort_carry;sort_carry<=sort_old;end
    if(sort_slot==3)sort_active<=0;else sort_slot<=sort_slot+1'b1;
   end
   if(active)begin
    if(timeout_count==RX_TIMEOUT_CYCLES-1)begin active<=0;timed_out_groups<=timed_out_groups+1'b1;end
    else timeout_count<=timeout_count+1'b1;
   end
   if(commit_pending)begin
    commit_pending<=0;association_state<=AS_SCAN;ci<=0;ti<=0;fill<=0;used<=0;best_found<=0;best_distance<=257;
    new_identity<=next_id>=248?1:next_id;
    for(i=0;i<4;i=i+1)begin associated[i]<=0;next_miss[i]<=0;end
   end
   case(association_state)
    AS_SCAN:begin
     if(ci==4||!scan_new[70])begin ti<=0;association_state<=AS_RETAIN;end
     else begin
      old_cx<={1'b0,scan_old[10:0]}+{1'b0,scan_old[32:22]};
      old_cy<={1'b0,scan_old[21:11]}+{1'b0,scan_old[43:33]};
      new_cx<={1'b0,scan_new[10:0]}+{1'b0,scan_new[32:22]};
      new_cy<={1'b0,scan_new[21:11]}+{1'b0,scan_new[43:33]};
      scan_eligible<=next_id<248&&scan_old[70]&&!used[ti]&&scan_old[61:60]==scan_new[61:60];
      association_state<=AS_DELTA;
     end
    end
    AS_DELTA:begin dx<=$signed({1'b0,old_cx})-$signed({1'b0,new_cx});dy<=$signed({1'b0,old_cy})-$signed({1'b0,new_cy});association_state<=AS_ABS;end
    AS_ABS:begin adx<=dx[12]?-dx:dx;ady<=dy[12]?-dy:dy;association_state<=AS_SUM;end
    AS_SUM:begin distance<={1'b0,adx}+{1'b0,ady};association_state<=AS_COMPARE;end
    AS_COMPARE:begin
     if(scan_eligible&&distance<best_distance)begin best<=ti;best_found<=1;best_distance<=distance[8:0];end
     if(ti==3)association_state<=AS_WRITE;else begin ti<=ti+1'b1;association_state<=AS_SCAN;end
    end
    AS_WRITE:begin
     associated[fill[1:0]]<=scan_new;
     associated[fill[1:0]][71]<=1;
     associated[fill[1:0]][69:62]<=best_found?track[best][69:62]:new_identity;
     if(best_found)used[best]<=1;else new_identity<=new_identity+1'b1;
     fill<=fill+1'b1;ci<=ci+1'b1;ti<=0;best_found<=0;best_distance<=257;association_state<=AS_SCAN;
    end
    AS_RETAIN:begin
     if(next_id<248&&fill<4&&scan_old[70]&&!used[ti]&&miss[ti]<2)begin
      associated[fill[1:0]]<=scan_old;associated[fill[1:0]][71]<=0;
      next_miss[fill[1:0]]<=miss[ti]+1'b1;fill<=fill+1'b1;
     end
     if(ti==3)association_state<=AS_PUBLISH;else ti<=ti+1'b1;
    end
    AS_PUBLISH:begin
     held_id<=commit_id;held_total<=commit_total;held_selected<=selected;
     for(i=0;i<4;i=i+1)begin track[i]<=associated[i];miss[i]<=next_miss[i];held_tracks[i*80+:80]<=associated[i];end
     next_id<=new_identity;if(next_id>=248)track_epoch<=track_epoch+1'b1;
     req<=~req;committed_results<=committed_results+1'b1;last_id<=commit_id;seen_result<=1;association_state<=AS_IDLE;
    end
   endcase
   if(byte_valid&&packet_format==2)begin
    if(packet_start)begin
     collecting<=1;packet_bad<=packet_length!=32&&packet_length!=51;len<=packet_length;
     typ<=0;total<=0;index<=0;fid<=0;cycles<=0;cls<=0;confidence<=0;x1<=0;y1<=0;x2<=0;y2<=0;
    end
    if(collecting||packet_start)begin
     pos<=at+1'b1;
     case(at)
      0:if(byte_data!=8'h59)packet_bad<=1;
      1:if(byte_data!=8'h35)packet_bad<=1;
      2:if(byte_data!=8'h43)packet_bad<=1;
      3:if(byte_data!=8'h44)packet_bad<=1;
      4:if(byte_data!=1)packet_bad<=1;
      5:typ<=byte_data;
      6:if(byte_data!=1)packet_bad<=1;
      7,20,28,29,30,31:if(byte_data!=0)packet_bad<=1;
      8,9,10,11:fid[(at-8)*8+:8]<=byte_data;
      12,13:total[(at-12)*8+:8]<=byte_data;
      14,15:index[(at-14)*8+:8]<=byte_data;
      16,17,18,19:cycles[(at-16)*8+:8]<=byte_data;
      21:if(byte_data!=4)packet_bad<=1;
      22:if(byte_data!=8'h58)packet_bad<=1;
      23:if(byte_data!=2)packet_bad<=1;
      24,26:if(byte_data!=8'h40)packet_bad<=1;
      25,27:if(byte_data!=1)packet_bad<=1;
      32:cls<=byte_data;
      33,34:confidence[(at-33)*8+:8]<=byte_data;
      35,36,37,38:x1[(at-35)*8+:8]<=byte_data;
      39,40,41,42:y1[(at-39)*8+:8]<=byte_data;
      43,44,45,46:x2[(at-43)*8+:8]<=byte_data;
      47,48,49,50:y2[(at-47)*8+:8]<=byte_data;
      default:packet_bad<=1;
     endcase
     if(packet_last)begin collecting<=0;pending<=1;if(at+1!=len)packet_bad<=1;end
    end
   end
   if(record_ready)begin
    if(record_index==0)begin
     if(mailbox_busy||commit_pending||association_busy)busy_results<=busy_results+1'b1;
     else if(seen_result&&!newer(record_id,last_id))bad_groups<=bad_groups+1'b1;
     else begin
      active<=1;active_id<=record_id;active_cycles<=record_cycles;active_total<=record_total;expected<=1;timeout_count<=0;
      selected<=record_eligible?1:0;candidate[0]<=record_eligible?record_mapped:80'd0;
      for(i=1;i<4;i=i+1)candidate[i]<=0;
     end
    end else begin
     if(!active||record_id!=active_id||record_cycles!=active_cycles||record_total!=active_total||record_index!=expected)begin active<=0;bad_groups<=bad_groups+1'b1;end
     else begin
      expected<=expected+1'b1;
      if(record_eligible)begin sort_carry<=record_mapped;sort_slot<=0;sort_active<=1;if(selected<4)selected<=selected+1'b1;end
     end
    end
   end
   // A malformed packet cancels pending geometry too; it cannot resurrect a
   // previously rejected/incomplete group when its divided coordinate returns.
   if(pending)begin
    if(packet_bad||total>300||!((typ==1&&len==51&&index<total)||(typ==2&&len==32&&index==total)))begin
     bad_packets<=bad_packets+1'b1;active<=0;map_state<=0;record_ready<=0;sort_active<=0;
    end else if(typ==1&&!raw_record_ok)begin bad_packets<=bad_packets+1'b1;active<=0;map_state<=0;record_ready<=0;sort_active<=0;end
    else if(typ==1)begin
     if(map_state!=0||sort_active)begin bad_groups<=bad_groups+1'b1;active<=0;map_state<=0;record_ready<=0;sort_active<=0;end
     else begin
      record_id<=fid;record_cycles<=cycles;record_total<=total;record_index<=index;record_confidence<=confidence;record_class<=cls[1:0];
      mq[0]<=x1;mq[1]<=y1;mq[2]<=x2;mq[3]<=y2;mk<=0;map_state<=1;
     end
    end else if(total==0)begin
     if(mailbox_busy||commit_pending||association_busy)busy_results<=busy_results+1'b1;
     else if(seen_result&&!newer(fid,last_id))bad_groups<=bad_groups+1'b1;
     else begin
      active<=0;selected<=0;for(i=0;i<4;i=i+1)candidate[i]<=0;
      commit_pending<=1;commit_id<=fid;commit_total<=0;
     end
    end else if(!active||fid!=active_id||cycles!=active_cycles||total!=active_total||expected!=active_total)begin active<=0;bad_groups<=bad_groups+1'b1;end
    else begin active<=0;commit_pending<=1;commit_id<=fid;commit_total<=total;end
   end
  end
 end
 reg vs_d;reg[7:0]display_age;reg display_video_valid;
 always @(posedge pixel_clk or posedge pr)begin
  if(pr)begin req1<=0;req2<=0;ack<=0;vs_d<=0;display_tracks<=0;display_result_id<=0;display_total<=0;display_selected<=0;display_seen<=0;display_age<=255;display_video_id<=0;display_video_valid<=0;end
  else begin
   req1<=req;req2<=req1;vs_d<=frame_vs;
   if(frame_vs&&!vs_d)begin
    // FRONT changes only at the reader's safe blanking boundary, before VS.
    // Hold this VIDEO identity for the complete output frame (including tail).
    display_video_id<=display_front_id;display_video_valid<=display_front_valid;
    if(req2!=ack)begin
     display_tracks<=held_tracks;display_result_id<=held_id;display_total<=held_total;display_selected<=held_selected;
     display_age<=0;display_seen<=1;ack<=req2;
    end else if(display_age!=255)display_age<=display_age+1'b1;
   end
  end
 end
 assign exact_display_match=display_seen&&display_front_valid&&display_front_id==display_result_id&&display_age<MAX_DISPLAY_FRAMES;
 // Not a prediction: retain only actual complete, validated detections.
 // Future results, stale results, zero-result clears and reset remain distinct.
 assign recent_display_match=display_seen&&display_video_valid&&display_age<MAX_DISPLAY_FRAMES&&
  (display_video_id==display_result_id||newer(display_video_id,display_result_id));
 assign delayed_display_match=recent_display_match&&display_video_id!=display_result_id;
endmodule
