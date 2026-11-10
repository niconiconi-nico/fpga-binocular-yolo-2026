// Both local and remote DDR banks store eight RGB565 pixels per128bit beat.
// Native addresses are16bit words, not bytes. No DDR reversal (Sensor180).
module stereo_raw_reader1(
 input wire pixel_clk,ddr_clk,rst,calibrated,input wire frame_vs,stereo_mode_i,input wire[10:0]x,input wire[9:0]y,input wire de,
 input wire[1:0]local_bank,input wire[3:0]local_valid_banks,input wire[127:0]local_epochs,
 input wire remote_valid,input wire[1:0]remote_bank,input wire[31:0]remote_id,   // CLAUDE Z29: 3 banks
 output wire[15:0]local_pixel,remote_pixel,output wire[23:0]local_rgb888,output wire local_pixel_valid,remote_pixel_valid,
 output wire arvalid,input wire arready,output wire[24:0]araddr,input wire rvalid,input wire[127:0]rdata,
 output reg local_hold,output wire[1:0]held_local_bank,
 output reg safe_boundary,output reg[31:0]missed_lines,output reg protocol_error,input wire remote_full_i,pair_mode_i,
 input wire zoom_i,input wire[18:0]zstep_i,
 // CLAUDE Z25 LATENCY: camera slot of the bank selected for the next display frame (row 0 request), toggle + held slot
 input wire[7:0]local_sofs,output reg sel_tg,output reg[1:0]sel_idx
);
 // CLAUDE ZOOM6 (2026-10-28): digital zoom of the local full view, 0.25x .. 4.00x, nearest neighbour, centred.
 // zstep = 65536 / zoom (16384 .. 262144). Display (x, y) -> source ((x0 + x*zstep) >> 16, (y0 + y*zstep) >> 16),
 // x0 = 640*(65536 - zstep), y0 = 360*(65536 - zstep) (signed 16.16; negative below 1x). Source outside 0..1279 / 0..719
 // -> invalid (black border). Accumulators per pixel / per line, no multiplier.
 // Row prefetch for zoom uses VIRTUAL rows: the distinct source rows the frame needs, numbered 0, 1, 2, ... in display
 // order. The virtual row selects the cache bank / tag (bank v % 4, refill only when v <= display v + 3, same ownership rule
 // as rows), the real source row (wreal) travels with the request only for the DDR address. So below 1x (rows 2..4 apart)
 // the banks still rotate and one row is fetched per display line, as at 1x. zoom_i = 0: original behaviour.
 wire pr,dr;reset_domain_sync p_release(pixel_clk,rst,pr);reset_domain_sync d_release(ddr_clk,rst,dr);
 reg req,ack;(* async_reg="true" *)reg as1,as2,qs1,qs2;
 reg [9:0] next_row;
 reg[9:0]wanted,wreal;reg[1:0]rb;reg[31:0]rid,display_epoch,request_epoch;reg blank_sent;
 wire idle=req==as2;
 reg vs_seen,view_stereo,view_remote,view_pair,frame_prepared,view_zoom;reg[18:0]zstep;
 wire signed[19:0]zd=$signed(20'd65536)-$signed({1'b0,zstep});                      // 65536 - zstep
 wire signed[29:0]zs30=$signed({11'd0,zstep});
 // CLAUDE Z8D: frame constants registered (zstep is latched only in vertical blanking, mode_wait): x0 / y0 for the display
 // accumulators (used from x = 0 / y = 0 on), source row of line 719 for the request walk (starts after zinit). zinit itself
 // (one clock after zstep) keeps the direct y0f.
 reg signed[30:0]x0r;reg signed[29:0]y0r;reg signed[13:0]rowL;                        // rowL: source row of display line 719
 // CLAUDE Z10 AREA: the frame constants x0 = 640 zd, y0 = 360 zd and rowL = (y0 + 719 zstep) >> 16 by ONE adder over 13
 // clocks after zstep is latched (vertical blanking; z8d had 13 parallel 30-bit adders). zinit (first user, request walk)
 // waits for the result; the display accumulators use x0r / y0r from the next active line on. Same values as before.
 reg[3:0]kc;reg kbusy;reg signed[30:0]kacc,kop;
 wire signed[30:0]zdx={{11{zd[19]}},zd},zsx={12'd0,zstep};
 always @*case(kc)0:kop=zdx<<<9;1:kop=zdx<<<7;2:kop=zdx<<<8;3:kop=zdx<<<6;4:kop=zdx<<<5;5:kop=zdx<<<3;
  6:kop=zsx<<<9;7:kop=zsx<<<7;8:kop=zsx<<<6;9:kop=zsx<<<3;10:kop=zsx<<<2;11:kop=zsx<<<1;default:kop=zsx;endcase
 wire signed[30:0]ksum=((kc==4'd0||kc==4'd2)?31'sd0:kacc)+kop;
 always @(posedge pixel_clk)if(kbusy)begin
  kacc<=ksum;if(kc==4'd1)x0r<=ksum;if(kc==4'd5)y0r<=ksum[29:0];if(kc==4'd12)rowL<=ksum[29:16];
 end
 // display side: source column / row of the current pixel / line, virtual row of the current line
 reg signed[30:0]accx;reg signed[29:0]accy,accp;reg[9:0]yq;reg req_first,req_last;   // accp = accy + zstep (registered)
 wire signed[30:0]accx_c=(x==0)?x0r:accx;
 wire signed[14:0]sxs=accx_c[30:16];
 wire zx_ok=sxs>=15'sd0&&sxs<15'sd1280;
 wire signed[29:0]accy_n=(y==0)?y0r:(y!=yq)?accp:accy;          // current line (no lag at x = 0)
 wire signed[13:0]sys=accy_n[29:16];
 wire zy_ok=sys>=14'sd0&&sys<14'sd720;
 reg signed[10:0]dvq;reg[9:0]prq;reg pvq;                          // previous line: virtual row, source row, valid
 wire znew=zy_ok&&(!pvq||sys[9:0]!=prq);
 wire signed[10:0]dv_n=(y==0)?(zy_ok?11'sd0:-11'sd1):(y!=yq)?(znew?dvq+11'sd1:dvq):dvq;
 always @(posedge pixel_clk)begin
  if(de)accx<=accx_c+$signed({12'd0,zstep});
  yq<=y;accy<=accy_n;accp<=accy_n+zs30;
  if(y==0||y!=yq)begin dvq<=dv_n;pvq<=zy_ok;prq<=sys[9:0];end
 end
 wire[10:0]sx=view_zoom?(zx_ok&&zy_ok?sxs[10:0]:11'h7ff):x;        // >= 1280: cache reports invalid (black)
 wire[9:0]sy=view_zoom?(zy_ok?dv_n[9:0]:10'd1023):y;                // zoom: virtual row of this line
 // request side (zoom): walk the display lines, request each new source row once, in order
 reg signed[29:0]qacc;reg[9:0]qly,qpr,qv;reg qpv,zinit;
 wire signed[13:0]qrow=qacc[29:16];
 wire signed[29:0]qacc_n=qacc+zs30;
 wire signed[13:0]qrow_n=qacc_n[29:16];
 wire q_ok=qrow>=14'sd0&&qrow<14'sd720;
 wire q_new=q_ok&&(!qpv||qrow[9:0]!=qpr);
 wire q_last=qly==10'd719||qrow==14'sd719||qrow_n>14'sd719||qrow==rowL;
 wire q_elig=$signed({1'b0,qv})<=$signed(dv_n)+11'sd3;
 reg[2:0] mode_wait;
 reg request_stereo,request_remote;
 wire[9:0] view_row=view_stereo?(y-10'd180):y;
 wire[9:0] max_rows=view_stereo?10'd360:10'd720;
 wire prefetch_eligible=view_stereo?(y>=177&&y<540&&next_row<=y-177):
      (frame_prepared&&y<720&&next_row<=y+3);
 always @(posedge pixel_clk or posedge pr)begin
  if(pr)begin req<=0;as1<=0;as2<=0;wanted<=0;wreal<=0;next_row<=0;vs_seen<=0;view_stereo<=1;view_remote<=0;view_pair<=0;view_zoom<=0;zstep<=19'd65536;req_first<=0;req_last<=0;frame_prepared<=0;mode_wait<=0;request_stereo<=1;request_remote<=0;rb<=0;rid<=0;request_epoch<=0;display_epoch<=0;safe_boundary<=0;blank_sent<=0;missed_lines<=0;
   qacc<=0;qly<=10'd720;qpr<=0;qv<=0;qpv<=0;zinit<=0;kbusy<=0;kc<=0;end
  else begin
   as1<=ack;as2<=as1;safe_boundary<=0;
   vs_seen<=frame_vs;
   if(frame_vs&&!vs_seen)begin mode_wait<=3;frame_prepared<=0;end
   else if(mode_wait!=0)begin
    mode_wait<=mode_wait-1'b1;
    if(mode_wait==1)begin view_stereo<=stereo_mode_i;view_remote<=remote_full_i;view_pair<=pair_mode_i;frame_prepared<=1;
     view_zoom<=zoom_i&&!stereo_mode_i&&!remote_full_i;zstep<=zoom_i?zstep_i:19'd65536;kbusy<=1;kc<=0;end
   end
   if(kbusy)begin kc<=kc+1'b1;if(kc==4'd12)begin kbusy<=0;zinit<=1;end end   // frame constants (13 clocks)
   if(zinit)begin zinit<=0;qacc<=y0r;qly<=0;qpv<=0;qv<=0;end      // after the frame constants
   if(y==0)blank_sent<=0;
   if(y>=720&&idle&&!blank_sent)begin safe_boundary<=1;blank_sent<=1;display_epoch<=display_epoch+1'b1;next_row<=0;frame_prepared<=0;qly<=10'd720;end
   // Four banks, three-row lead. Refill bank r%4 only after row r-4
   // has finished scanning. Retry after ACK, never lose a row request.
   // y=177 primes row0; row4 cannot start until y=181 (row0 consumed).
   if(!view_zoom)begin
    if(prefetch_eligible&&next_row<max_rows&&idle)begin
     wanted<=next_row;wreal<=next_row;next_row<=next_row+1'b1;rb<=remote_bank;rid<=remote_id;
     req_first<=next_row==0;req_last<=next_row==(view_stereo?10'd359:10'd719);
     request_epoch<=display_epoch;request_stereo<=view_stereo;request_remote<=view_remote;req<=~req;
    end
   end else if(frame_prepared&&!zinit&&y<720&&qly<10'd720)begin
    if(!q_new)begin qly<=qly+1'b1;qacc<=qacc_n;end                    // outside the image / same row as before
    else if(q_elig&&idle)begin                                         // virtual row qv <- source row qrow
     wanted<=qv;wreal<=qrow[9:0];rb<=remote_bank;rid<=remote_id;req_first<=qv==0;req_last<=q_last;
     request_epoch<=display_epoch;request_stereo<=1'b0;request_remote<=1'b0;req<=~req;
     qpr<=qrow[9:0];qpv<=1;qv<=qv+1'b1;qly<=qly+1'b1;qacc<=qacc_n;
    end
   end
   if(!view_zoom&&de&&x==0&&(!view_stereo||(y>=180&&y<540))&&next_row<=view_row)missed_lines<=missed_lines+1'b1;
   if(view_zoom&&de&&x==0&&zy_ok&&$signed({1'b0,qv})<=dv_n)missed_lines<=missed_lines+1'b1;
  end
 end
 reg active;reg[8:0]issued,returned;reg[9:0]row;reg[6:0]pending;reg[24:0]lbaddr,rbaddr;
 reg[1:0]selected_bank;reg[31:0]selected_epoch,lid,rrid;reg local_ok;
 assign held_local_bank=selected_bank;
 reg cur_first,cur_last;
 wire[1:0]chosen_bank=req_first?local_bank:selected_bank;
 wire[31:0]chosen_epoch=local_epochs[chosen_bank*32+:32];
 function automatic[24:0]local_base(input[1:0]b);case(b)0:local_base=0;1:local_base=7000000;2:local_base=14000000;3:local_base=21000000;endcase endfunction
 wire[24:0]row25={15'd0,wreal};                                   // DDR address: real source row (virtual row = wanted for zoom)
 // Same four-bank/three-row ownership schedule, now direct16bit storage.
 reg current_stereo,current_remote;
 wire[8:0] row_beats=current_stereo?9'd320:9'd160;
 assign arvalid=active&&issued<row_beats&&pending<32&&calibrated;
 assign araddr=current_remote?rbaddr+({16'd0,issued}<<3):issued<160?lbaddr+({16'd0,issued}<<3):rbaddr+(({16'd0,issued}-25'd160)<<3);
 wire take=arvalid&&arready;wire response=rvalid&&active&&pending!=0;
 reg cw,cam,done;reg[1:0]cb;reg[7:0]beat;reg[127:0]data;reg[31:0]done_lid;
 always @(posedge ddr_clk or posedge dr)begin
  if(dr)begin
   qs1<=0;qs2<=0;ack<=0;active<=0;issued<=0;returned<=0;row<=0;pending<=0;
   lbaddr<=0;rbaddr<=0;selected_bank<=0;selected_epoch<=0;local_hold<=0;lid<=0;rrid<=0;local_ok<=0;sel_tg<=0;sel_idx<=0;
   cw<=0;cam<=0;cb<=0;beat<=0;data<=0;done<=0;done_lid<=0;protocol_error<=0;current_stereo<=1;current_remote<=0;cur_first<=0;cur_last<=0;
  end else begin
   qs1<=req;qs2<=qs1;cw<=0;done<=0;
   if(qs2!=ack&&!active&&!done&&calibrated)begin
    active<=1;issued<=0;returned<=0;pending<=0;row<=wanted;cb<=wanted[1:0];
    current_stereo<=request_stereo;current_remote<=request_remote;cur_first<=req_first;cur_last<=req_last;
    // Native addresses count16bit words:1280/row or2560 for source2*y.
    lbaddr<=local_base(chosen_bank)+(request_stereo?((row25<<11)+(row25<<9)):((row25<<10)+(row25<<8)));
    rbaddr<=(rb==2'd2 ? 25'd32000000 : rb==2'd1 ? 25'd30000000 : 25'd28000000)+(request_remote?((row25<<10)+(row25<<8)):((row25<<11)+(row25<<9)));
    lid<=request_epoch;rrid<=rid;
    if(req_first)begin local_hold<=!request_remote;selected_bank<=chosen_bank;selected_epoch<=chosen_epoch;
     sel_idx<=local_sofs[chosen_bank*2+:2];sel_tg<=~sel_tg;end
    local_ok<=!request_remote&&local_valid_banks[chosen_bank]&&(req_first||chosen_epoch==selected_epoch);
   end
   if(take)issued<=issued+1'b1;
   case({take,response})2'b10:pending<=pending+1'b1;2'b01:pending<=pending-1'b1;default:;endcase
   if(rvalid&&!response)protocol_error<=1;
   if(response)begin
    returned<=returned+1'b1;cw<=1;data<=rdata;
    cam<=current_remote||returned>=160;
    beat<=current_remote||returned<160?returned[7:0]:returned-9'd160;
    if(returned==row_beats-1'b1)begin
     active<=0;ack<=qs2;done<=1;
     if(cur_last)local_hold<=0;
     done_lid<=local_ok&&local_valid_banks[selected_bank]&&local_epochs[selected_bank*32+:32]==selected_epoch?lid:~lid;
    end
   end
  end
 end
 // Paired effects read both existing row RAMs at the SAME pane coordinate.
 // Both row caches hold full1280pixel RGB565 source rows; stereo panes select2*x.
 // No display-owned bank refill or extra DDR transactions are introduced.
 wire pair_window=view_pair&&view_stereo&&x<1280&&y>=180&&y<540;
 wire[10:0]pair_x=x<640?x:x-11'd640;
 wire local_request=de&&!view_remote&&(pair_window||!view_stereo||(x<640&&y>=180&&y<540));
 wire remote_request=de&&remote_valid&&(pair_window||view_remote||(view_stereo&&x>=640&&x<1280&&y>=180&&y<540));
 // Record every invalid requested pixel, separately from intentional bars or
 // absent remote source. Two cycles match the row RAM/lane-valid pipeline.
 // Kept snapshots are in the pixel domain; no unsynchronised DDR debug buses.
 reg[1:0] diag_local,diag_remote,diag_de;
 reg[10:0] diag_x0,diag_x1;reg[9:0]diag_y0,diag_y1;
 reg diag_line_bad,diag_local_seen,diag_remote_seen;
 // CLAUDE TRACK47_NR: simulation-only diagnostics (no consumer); keep attributes removed so synthesis trims them.
 reg[31:0]invalid_local_pixels,invalid_remote_pixels,invalid_lines;
 reg first_invalid_seen,runtime_first_invalid_seen;
 reg[10:0]first_invalid_x,runtime_first_invalid_x;
 reg[9:0]first_invalid_y,runtime_first_invalid_y;
 reg[31:0]first_invalid_epoch,runtime_first_invalid_epoch;
 reg[7:0]first_invalid_reason,runtime_first_invalid_reason;
 wire diag_left_bad=diag_local[1]&&!local_pixel_valid;
 wire diag_right_bad=diag_remote[1]&&!remote_pixel_valid;
 wire[9:0]diag_row=view_stereo?diag_y1-10'd180:diag_y1;
 wire[3:0]diag_known,diag_row_match,diag_lid_match,diag_rid_match;
 wire[7:0]diag_reason={!(diag_local_seen&&diag_remote_seen),!idle,
   !diag_rid_match[diag_row[1:0]],!diag_lid_match[diag_row[1:0]],
   !diag_row_match[diag_row[1:0]],!diag_known[diag_row[1:0]],diag_right_bad,diag_left_bad};
 always @(posedge pixel_clk or posedge pr)begin
  if(pr)begin
   diag_local<=0;diag_remote<=0;diag_de<=0;diag_x0<=0;diag_x1<=0;diag_y0<=0;diag_y1<=0;
   diag_line_bad<=0;diag_local_seen<=0;diag_remote_seen<=0;
   invalid_local_pixels<=0;invalid_remote_pixels<=0;invalid_lines<=0;
   first_invalid_seen<=0;runtime_first_invalid_seen<=0;first_invalid_x<=0;first_invalid_y<=0;
   first_invalid_epoch<=0;first_invalid_reason<=0;runtime_first_invalid_x<=0;runtime_first_invalid_y<=0;
   runtime_first_invalid_epoch<=0;runtime_first_invalid_reason<=0;
  end else begin
   diag_local<={diag_local[0],local_request};diag_remote<={diag_remote[0],remote_request};diag_de<={diag_de[0],de};
   diag_x0<=x;diag_x1<=diag_x0;diag_y0<=y;diag_y1<=diag_y0;
   if(local_pixel_valid)diag_local_seen<=1;if(remote_pixel_valid)diag_remote_seen<=1;
   if(!diag_de[1])diag_line_bad<=0;
   if(diag_left_bad)invalid_local_pixels<=invalid_local_pixels+1'b1;
   if(diag_right_bad)invalid_remote_pixels<=invalid_remote_pixels+1'b1;
   if(diag_left_bad||diag_right_bad)begin
    if(!diag_line_bad)begin invalid_lines<=invalid_lines+1'b1;diag_line_bad<=1;end
    if(!first_invalid_seen)begin
     first_invalid_seen<=1;first_invalid_x<=diag_x1;first_invalid_y<=diag_y1;
     first_invalid_epoch<=display_epoch;first_invalid_reason<=diag_reason;
    end
    if(diag_local_seen&&diag_remote_seen&&!runtime_first_invalid_seen)begin
     runtime_first_invalid_seen<=1;runtime_first_invalid_x<=diag_x1;runtime_first_invalid_y<=diag_y1;
     runtime_first_invalid_epoch<=display_epoch;runtime_first_invalid_reason<=diag_reason;
    end
   end
  end
 end
 stereo_line_cache3 cache(.ddr_clk(ddr_clk),.pixel_clk(pixel_clk),.rst(rst),
  .cache_write(cw),.cache_camera(cam),.cache_bank(cb),.cache_beat(beat),.cache_data(data),
  .line_done(done),.done_bank(cb),.done_row(row),.done_local_id(done_lid),.done_remote_id(rrid),
  .local_request(local_request),.remote_request(remote_request),.wanted_row(view_stereo?(y>=180&&y<540?y-180:10'd1023):sy),
  .local_x(view_stereo?((view_pair?pair_x:x)<<1):sx),.remote_x(view_pair?(pair_x<<1):view_remote?x:((x-11'd640)<<1)),.wanted_local_id(display_epoch),.wanted_remote_id(remote_id),
  .local_pixel(local_pixel),.remote_pixel(remote_pixel),.local_rgb888(local_rgb888),.local_valid(local_pixel_valid),.remote_valid(remote_pixel_valid),
  .diagnostic_row(diag_row),.diagnostic_known(diag_known),.diagnostic_row_match(diag_row_match),
  .diagnostic_local_id_match(diag_lid_match),.diagnostic_remote_id_match(diag_rid_match));
endmodule
