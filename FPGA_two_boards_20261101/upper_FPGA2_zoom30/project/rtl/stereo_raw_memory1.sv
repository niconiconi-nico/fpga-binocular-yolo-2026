// New independent stereo integration in front of the preserved factory MC.
// No enhancement/matching/YOLO/OSD. Each pane640x360 on a1280x720 raster.
module stereo_raw_memory1(
 input wire ddr_clk,pixel_clk,rx_clk,rst,calibrated,
 input wire gmii_valid,gmii_error,input wire[7:0]gmii_data,
 input wire local_wr_en,local_wr_busy,input wire[24:0]local_addr,input wire[127:0]local_data,input wire[1:0]local_bank,
 output wire local_ready,
 output wire bridge_we,bridge_re,output wire[24:0]bridge_addr,output wire[127:0]bridge_wdata,
 input wire bridge_ready,bridge_rvalid,input wire[127:0]bridge_rdata,
 input wire native_accept,native_read,input wire[24:0]native_addr,
 input wire[10:0]x,input wire[9:0]y,input wire hs,vs,de,
 output reg out_hs,out_vs,out_de,output reg[23:0]out_rgb,
 output wire[31:0]remote_frames,missed_lines,output wire protocol_error,
 input wire stereo_mode_i,output wire local_reader_hold,output wire[1:0]local_reader_bank,input wire remote_full_i,yolo_overlay_i,
 input wire[3:0]pair_mode_i,input wire tracking_mode_i,
 input wire zoom_i,input wire[18:0]zstep_i,   // CLAUDE ZOOM: mode 51 step-less zoom of the local view
 // CLAUDE RANGE: received right-view pixels (rx clock): valid, pixel address y*1280+x, RGB565
 output wire rpx_valid,output wire[31:0]rpx_addr,output wire[15:0]rpx_data,
 // CLAUDE BOTTLE (mode 38 KEY4 = BOTTLE, tracking_mode_i): YOLO display results out, tracked bottle box (one entry) in
 output wire[319:0]yolo_tracks_o,output wire[31:0]yolo_id_o,output wire yolo_recent_o,output wire[7:0]yolo_vid_o,   // CLAUDE Z9: video id
 input wire[79:0]bt_entry_i,input wire[2:0]bt_status_i,
 // CLAUDE Z25 LATENCY: camera slot Gray in (pixel clock), selected-bank slot out (DDR clock: toggle + held slot)
 input wire[1:0]lat_sof_g,output wire lat_sel_tg,output wire[1:0]lat_sel_idx,
 // CLAUDE Z28 MONITOR (rx clock): accepted video pixel write (2 payload bytes), complete received video frame
 output wire net_px_o,net_frame_o
);
 wire rr,dr;reset_domain_sync rx_release(rx_clk,rst,rr);reset_domain_sync dd_release(ddr_clk,rst,dr);
 wire pv,prdy;wire[1:0]pb;wire[31:0]pa;wire[15:0]pd;wire safe,front_valid;wire[1:0]front_bank;wire[31:0]front_id;   // CLAUDE Z29: 3 banks
 wire result_v,result_s,result_l;wire[7:0]result_d;wire[15:0]result_len;wire[1:0]result_fmt;
 wire[319:0]rx_yolo_tracks,flow_tracks;wire[31:0]rx_yolo_id,flow_source;
 wire rx_yolo_seen,flow_seen;wire[8:0]rx_yolo_total,flow_total;wire[2:0]rx_yolo_selected,flow_selected,flow_status;
 wire received_frame_commit;wire[31:0]received_frame_id;
 assign rpx_valid=pv&&prdy;assign rpx_addr=pa;assign rpx_data=pd;
 assign net_px_o=pv&&prdy;assign net_frame_o=received_frame_commit;   // CLAUDE Z28 MONITOR
 // CLAUDE UPPER_V1: mode 47 (YOLO FLOW) removed -> the tracking chain video_motion_field1 / flow_history1 /
 // tracking_mailbox1 is gone; the box overlay always shows the received YOLO results (mode 38).

 wire commit;(*async_reg="true"*)reg c1,c2;reg seen,pending;
 always @(posedge rx_clk or posedge rr)begin
  if(rr)begin c1<=0;c2<=0;seen<=0;pending<=0;end
  else begin c1<=commit;c2<=c1;seen<=c2;
   if(c2!=seen)pending<=0;
   if(pv&&prdy&&pa==32'd921599)pending<=1;   // CLAUDE Z29B: from the LAST pixel (the next frame may start during the drain)
  end
 end
 remote_media_ingress5 ingress(.rx_clk(rx_clk),.pixel_clk(pixel_clk),.rst(rst),
  .gmii_valid(gmii_valid),.gmii_error(gmii_error),.gmii_data(gmii_data),
  .mem_valid(pv),.mem_bank(pb),.mem_ready(prdy),.mem_drained(!pending),
  .mem_pixel_addr(pa),.mem_pixel_data(pd),.display_safe_boundary(safe),
  .front_valid(front_valid),.front_bank(front_bank),.front_id(front_id),
  .complete_count(remote_frames),.bad_network_packets(),.bad_video_packets(),
  .result_valid(result_v),.result_start(result_s),.result_last(result_l),.result_data(result_d),.result_length(result_len),.result_format(result_fmt),
  .result_packets(),.ignored_packets(),.write_available(),.received_frame_commit(received_frame_commit),.received_frame_id(received_frame_id));
 wire bv,brdy,blast;wire[1:0]bb;wire[31:0]ba;wire[127:0]bd;wire[31:0]pack_bad;
 rgb565_beat_packer packer(rx_clk,rr,pv,pb,pa,pd,prdy,bv,brdy,bb,ba,bd,blast,pack_bad);
 wire fv,frdy;wire[162:0]fd;
 wire[24:0]wa=(bb==2'd2 ? 25'd32000000 : bb==2'd1 ? 25'd30000000 : 25'd28000000)+ba[24:0];   // CLAUDE Z29: bank 2 at 32,000,000 (frame 921,600 words)
 camera_framed_async_fifo fifo(.write_clk(rx_clk),.write_rst_n(!rr),.write_valid_i(bv),.write_ready_o(brdy),
  .write_data_i({8'd0,blast,bb[0],wa,bd}),.read_clk(ddr_clk),.read_rst_n(!dr),.read_valid_o(fv),.read_ready_i(frdy),.read_data_o(fd));
 wire arv,arr,rv;wire[24:0]ara;wire[127:0]rd;
 reg[1:0]fair;reg selection_pending,selected_write;
 wire choose_write=selection_pending?selected_write:fv&&(!arv||fair==3);
 wire request=fv||arv;wire granted;
 assign frdy=choose_write&&granted;
 assign arr=!choose_write&&granted;
 always @(posedge ddr_clk or posedge dr)begin
  if(dr)begin fair<=0;selection_pending<=0;selected_write<=0;end
  else begin
   if(request&&granted)begin fair<=fair+1'b1;selection_pending<=0;end
   else if(request&&!selection_pending)begin selection_pending<=1;selected_write<=choose_write;end
  end
 end
 wire[1:0]latest_local_bank;wire arb_error,read_error,commit_error;wire[3:0]valid_banks;wire[127:0]epochs;
 local_remote_mc_arbiter2 arb(.clk(ddr_clk),.rst_n(!rst),
  .local_wr_en(local_wr_en),.local_rd_en(1'b0),.local_wr_busy(local_wr_busy),.local_rd_busy(1'b0),
  .local_addr(local_addr),.local_write_data(local_data),.local_ready(local_ready),.local_read_valid(),.local_read_data(),
  .remote_valid(request),.remote_write(choose_write),.remote_frame_last(choose_write&&fd[154]),
  .remote_addr(choose_write?fd[152:128]:ara),.remote_write_data(fd[127:0]),.remote_ready(granted),.remote_read_valid(rv),.remote_read_data(rd),
  .bridge_wr_en(bridge_we),.bridge_rd_en(bridge_re),.bridge_addr(bridge_addr),.bridge_write_data(bridge_wdata),
  .bridge_ready(bridge_ready),.bridge_read_valid(bridge_rvalid),.bridge_read_data(bridge_rdata),
  .native_command_accepted(native_accept),.native_command_read(native_read),.remote_commit_toggle(commit),.protocol_error(arb_error));
 wire[7:0]bank_sofs;
 local_native_commit1 local_commit(ddr_clk,rst,native_accept,native_read,native_addr,valid_banks,epochs,commit_error,latest_local_bank,lat_sof_g,bank_sofs);
 wire[23:0]local_rgb;wire[15:0]lp,rp;wire lv,rvp;
 wire pair_enabled=pair_mode_i>=1&&pair_mode_i<=8;
 stereo_raw_reader1 reader(.pixel_clk(pixel_clk),.ddr_clk(ddr_clk),.rst(rst),.calibrated(calibrated),.frame_vs(vs),.stereo_mode_i(stereo_mode_i),.remote_full_i(remote_full_i),.pair_mode_i(pair_enabled),.x(x),.y(y),.de(de),
  .local_bank(latest_local_bank),.local_valid_banks(valid_banks),.local_epochs(epochs),
  .remote_valid(front_valid),.remote_bank(front_bank),.remote_id(front_id),
  .local_pixel(lp),.remote_pixel(rp),.local_rgb888(local_rgb),.local_pixel_valid(lv),.remote_pixel_valid(rvp),
  .arvalid(arv),.arready(arr),.araddr(ara),.rvalid(rv),.rdata(rd),.local_hold(local_reader_hold),.held_local_bank(local_reader_bank),.safe_boundary(safe),.missed_lines(missed_lines),.protocol_error(read_error),.zoom_i(zoom_i),.zstep_i(zstep_i),
  .local_sofs(bank_sofs),.sel_tg(lat_sel_tg),.sel_idx(lat_sel_idx));
 assign protocol_error=arb_error||read_error||commit_error;
 reg[1:0]hp,vp,dp;reg[10:0]ox0,ox1;reg[9:0]oy0,oy1;
 wire[319:0]yolo_tracks;wire[31:0]yolo_fid,yolo_video_fid;wire[8:0]yolo_total;wire[2:0]yolo_selected;wire yolo_exact,yolo_seen,yolo_ink_c,yolo_recent,yolo_delayed;wire[23:0]yolo_rgb_c;reg yolo_ink;reg[23:0]yolo_rgb;
 y5cd_tracks1 yolo(.rx_clk(rx_clk),.pixel_clk(pixel_clk),.rst(rst),.byte_valid(result_v),.packet_start(result_s),.packet_last(result_l),.byte_data(result_d),.packet_length(result_len),.packet_format(result_fmt),.frame_vs(vs),.display_front_valid(front_valid),.display_front_id(front_id),.display_tracks(yolo_tracks),.display_result_id(yolo_fid),.display_total(yolo_total),.display_selected(yolo_selected),.exact_display_match(yolo_exact),.display_seen(yolo_seen),.committed_results(),.bad_packets(),.bad_groups(),.busy_results(),.timed_out_groups(),.debug_req(),.debug_ack(),.recent_display_match(yolo_recent),.delayed_display_match(yolo_delayed),.display_video_id(yolo_video_fid),.receiver_tracks(rx_yolo_tracks),.receiver_result_id(rx_yolo_id),.receiver_seen(rx_yolo_seen),.receiver_total(rx_yolo_total),.receiver_selected(rx_yolo_selected));
 // CLAUDE BOTTLE: the tracking path of the box overlay now shows the bottle tracker (vision_core bottle_seed / range_meter).
 assign flow_tracks={240'd0,bt_entry_i};assign flow_source=yolo_fid;assign flow_status=bt_status_i;assign flow_seen=1'b1;
 assign flow_total=9'd1;assign flow_selected=3'd1;
 assign yolo_tracks_o=yolo_tracks;assign yolo_id_o=yolo_fid;assign yolo_recent_o=yolo_recent;assign yolo_vid_o=yolo_video_fid[7:0];
 wire pixel_reset;reset_domain_sync px_release(pixel_clk,rst,pixel_reset);
 // Cut the measured mode->metadata mux->glyph/edge critical path. The
 // frame-boundary snapshots settle during blanking; pixel/HS/VS/DE latency
 // remains unchanged. Metadata and its selected mode travel together.
 reg[319:0]box_tracks;reg[31:0]box_source,box_video;
 reg box_enable,box_usable,box_delayed,box_seen,box_tracking;
 reg[8:0]box_total;reg[2:0]box_selected,box_status;
 always @(posedge pixel_clk or posedge pixel_reset)begin
  if(pixel_reset)begin
   box_tracks<=0;box_source<=0;box_video<=0;box_enable<=0;
   box_usable<=0;box_delayed<=0;box_seen<=0;box_tracking<=0;
   box_total<=0;box_selected<=0;box_status<=0;
  end else begin
   box_tracks<=tracking_mode_i?flow_tracks:yolo_tracks;
   box_source<=tracking_mode_i?flow_source:yolo_fid;box_video<=yolo_video_fid;
   box_enable<=yolo_overlay_i;box_tracking<=tracking_mode_i;
   box_usable<=tracking_mode_i?(flow_status==0||flow_status==1||flow_status==4):yolo_recent;   // BOTTLE: box also while LOST (held), Z10: 1 = TRAK, last result without history
   box_delayed<=tracking_mode_i?1'b0:yolo_delayed;
   box_seen<=tracking_mode_i?flow_seen:yolo_seen;
   box_total<=tracking_mode_i?flow_total:yolo_total;
   box_selected<=tracking_mode_i?flow_selected:yolo_selected;box_status<=flow_status;
  end
 end
 // CLAUDE Z8D: overlay evaluated one clock early (ox0 / oy0 / dp[0]) and registered: same ink / rgb at the ox1 pixel (box_*
 // change only in blanking), the overlay logic no longer sits in front of base_rgb0.
 always @(posedge pixel_clk or posedge pixel_reset)if(pixel_reset)begin yolo_ink<=0;yolo_rgb<=0;end else begin yolo_ink<=yolo_ink_c;yolo_rgb<=yolo_rgb_c;end
 yolo_box_overlay1 boxes(.enable(box_enable),.de(dp[0]),.x(ox0),.y(oy0),.tracks(box_tracks),.usable_match(box_usable),.delayed_match(box_delayed),.result_id(box_source),.video_id(box_video),.seen(box_seen),.total(box_total),.selected(box_selected),.ink(yolo_ink_c),.rgb(yolo_rgb_c),.tracking_mode(box_tracking),.tracking_status(box_status));
 function automatic[23:0]rgb888(input[15:0]p);rgb888={p[15:11],p[15:13],p[10:5],p[10:9],p[4:0],p[4:2]};endfunction
 wire pair_valid,pair_missing;wire[31:0]pair_missing_count;   // CLAUDE TRACK47_NR: count is diagnostics only, keep removed
 wire[3:0]pair_mode_o;wire[10:0]pair_x_o;wire[9:0]pair_y_o;wire[15:0]pair_pixel;
 wire pair_de=pair_enabled&&dp[1]&&ox1<1280&&oy1>=180&&oy1<540;
 stereo_pair_selected1 paired(pixel_clk,pixel_reset,pair_de,lv,rvp,1'b1,
  pair_de&&ox1==0&&oy1==180,pair_mode_i,ox1<640?ox1:ox1-11'd640,oy1-10'd180,ox1>=640?rp:lp,
  pair_valid,pair_missing,pair_missing_count,pair_mode_o,pair_x_o,pair_y_o,pair_pixel);
 // All modes receive identical two-edge extra delay. Never switch only RGB
 // without delaying HS/VS/DE: that would reintroduce an intra-line phase error.
 reg[23:0]base_rgb0,base_rgb1;reg[1:0]base_hs,base_vs,base_de,pair_select;
 always @(posedge pixel_clk or posedge pixel_reset)begin
  if(pixel_reset)begin ox0<=0;ox1<=0;oy0<=0;oy1<=0;hp<=0;vp<=0;dp<=0;out_hs<=0;out_vs<=0;out_de<=0;out_rgb<=0;
   base_rgb0<=0;base_rgb1<=0;base_hs<=0;base_vs<=0;base_de<=0;pair_select<=0;
  end else begin
   ox0<=x;ox1<=ox0;oy0<=y;oy1<=oy0;hp<={hp[0],hs};vp<={vp[0],vs};dp<={dp[0],de};
   base_rgb0<=yolo_ink?yolo_rgb:lv?local_rgb:rvp?rgb888(rp):24'd0;base_rgb1<=base_rgb0;
   base_hs<={base_hs[0],hp[1]};base_vs<={base_vs[0],vp[1]};base_de<={base_de[0],dp[1]};
   pair_select<={pair_select[0],pair_enabled};
   out_hs<=base_hs[1];out_vs<=base_vs[1];out_de<=base_de[1];
   out_rgb<=pair_select[1]?(pair_valid?rgb888(pair_pixel):24'd0):base_rgb1;
  end
 end
endmodule
