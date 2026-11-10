// Resource-sharing Camera system application (no duplicate PHY/PLL/UDP/DDR IP).
// The real Camera board top owns those physical blocks. This module is their
// consumer: framed capture + bank locks + preprocess + frozen147 math + video
// and detection packet ownership. No PC image RX is elaborated in this build.
module camera_yolo_application #(
 parameter X_MAP_FILE="camera_resize_x.hex",Y_MAP_FILE="camera_resize_y.hex",QUANT_FILE="camera_quant_u8.hex"
)(
 input wire clk,rst_n,input wire camera_clk,camera_rst_n,
 output wire sd_cs_n,sd_sclk,sd_mosi,input wire sd_miso,
 input wire camera_frame_start_i,camera_word_valid_i,input wire [127:0] camera_word_data_i,
 input wire udp_rx_valid_i,input wire [7:0] udp_rx_data_i,input wire [15:0] udp_rx_length_i,
 input wire udp_busy_i,output wire udp_request_o,udp_valid_o,output wire [7:0] udp_data_o,output wire [15:0] udp_length_o,
 output wire memory_req_valid_o,input wire memory_req_ready_i,output wire memory_req_write_o,
 output wire [27:0] memory_req_address_o,output wire [127:0] memory_req_data_o,output wire [15:0] memory_req_strobe_o,
 input wire memory_read_valid_i,output wire memory_read_ready_o,input wire [127:0] memory_read_data_i,
 output wire model_ready_o,output wire [31:0] model_load_count_o,
 output wire yolo_busy_o,yolo_done_o,yolo_error_o,output wire [7:0] active_layer_o,
 output reg [31:0] yolo_start_count_o,yolo_done_count_o,
 output wire [31:0] yolo_source_frame_id_o,camera_commit_count_o,camera_skip_count_o,
 output wire [31:0] camera_bad_frames_o,camera_overflow_lines_o,
 // CC9 observability only (D1 telemetry spare bits): YOLO/video hand-off state for the startup-hang diagnosis.
 output wire [12:0] diag_state_o,
 output wire [16:0] tf_status_o
);
 wire framed_valid,framed_ready;wire [162:0] framed_data;
 camera_frame_ingress ingress(.camera_clk(camera_clk),.camera_rst_n(camera_rst_n),
   .frame_start_i(camera_frame_start_i),.word_valid_i(camera_word_valid_i),.word_data_i(camera_word_data_i),
   .ddr_clk(clk),.ddr_rst_n(rst_n),.framed_valid_o(framed_valid),.framed_ready_i(framed_ready),.framed_data_o(framed_data),.overflow_lines_o(camera_overflow_lines_o));
 wire frame_begin,frame_commit,frame_reject,capture_accept,capture_active;
 wire [31:0] capture_id;wire [1:0] capture_bank;
 wire cap_req;wire [27:0] cap_addr;wire [127:0] cap_data;
 wire [3:0] request_ready,read_valid,read_ready;
 wire [511:0] read_data;
 camera_frame_commit_writer capture(.clk(clk),.rst_n(rst_n),.framed_valid_i(framed_valid),.framed_ready_o(framed_ready),.framed_data_i(framed_data),
   .frame_begin_o(frame_begin),.frame_id_o(capture_id),.capture_accept_i(capture_accept),.capture_bank_i(capture_bank),
   .committed_o(frame_commit),.rejected_o(frame_reject),.req_valid_o(cap_req),.req_ready_i(request_ready[0]),.req_address_o(cap_addr),.req_data_o(cap_data),.bad_frames_o(camera_bad_frames_o));
 wire yolo_locked,video_locked,latest_valid,release_error;
 wire [1:0] yolo_bank,video_bank;wire [31:0] video_source_id;
 reg [3:0] ystate;reg [2:0] vstate;
 reg have_yolo_source;reg [31:0] last_yolo_id;
 wire core_idle,prep_busy,prep_done,prep_error,video_busy,video_done;
 // CC1: declarations moved before first use (ModelSim 10.3c); no logic change.
 wire perf_pending,video_udp_grant;reg raw_pending,raw_mode;
 wire yolo_acquire=(ystate==0)&&model_ready_o&&core_idle&&latest_valid&&!perf_pending;
 wire yolo_release=(ystate==5)||(ystate==6);
 wire video_permit,bank_frame_begin,capture_frozen,repeat_source;
 wire [2:0] perf_mode;wire [31:0] perf_sequence;
 reg [31:0] perf_ack_sequence,perf_video_starts;
 // A pending change stops NEW reader acquisitions, not in-flight activity.
 // Capture publication, preprocess, inference, bank locks and all UDP packets
 // must drain before applying it. No changed source ID or reused YOLO result.
 // core_idle includes model_ready. Before the one model load there cannot be
 // an owned graph; allow diagnostics without a model-upload/config deadlock.
 // CC3: diagnostic Y5PC perf/throttle control removed (user-approved). Its mode-0
 // behaviour is kept exactly: pass-through frame_begin, video always permitted,
 // no capture freeze and no repeated source.
 assign bank_frame_begin=frame_begin;assign video_permit=1'b1;assign capture_frozen=1'b0;
 assign repeat_source=1'b0;assign perf_mode=3'd0;assign perf_pending=1'b0;assign perf_sequence=32'd0;
 wire video_acquire=(vstate==0)&&latest_valid&&video_permit&&(!perf_pending||raw_pending);
 wire video_release=(vstate==3);
 camera_frame_bank_owner banks(.clk(clk),.rst_n(rst_n),.frame_begin_i(bank_frame_begin),.committed_i(frame_commit),.rejected_i(frame_reject),.camera_frame_id_i(capture_id),
   .capture_accept_o(capture_accept),.capture_bank_o(capture_bank),.capture_active_o(capture_active),
   .yolo_acquire_i(yolo_acquire),.yolo_release_i(yolo_release),.yolo_release_id_i(yolo_source_frame_id_o),.yolo_locked_o(yolo_locked),.yolo_bank_o(yolo_bank),.yolo_source_id_o(yolo_source_frame_id_o),
   .video_acquire_i(video_acquire),.video_release_i(video_release),.video_release_id_i(video_source_id),.video_locked_o(video_locked),.video_bank_o(video_bank),.video_source_id_o(video_source_id),
   .latest_valid_o(latest_valid),.committed_frames_o(camera_commit_count_o),.skipped_frames_o(camera_skip_count_o),.release_error_o(release_error));
 wire [31:0] yolo_source_base=32'h01800000+({30'd0,yolo_bank}<<22);
 wire [31:0] video_source_base=32'h01800000+({30'd0,video_bank}<<22);
 wire prep_req,prep_write;wire [27:0] prep_addr;wire [127:0] prep_data;wire [15:0] prep_strobe;
 camera_yolo_preprocess #(.X_MAP_FILE(X_MAP_FILE),.Y_MAP_FILE(Y_MAP_FILE),.QUANT_FILE(QUANT_FILE)) preprocess(
   .clk(clk),.rst_n(rst_n),.start_i(ystate==2),.source_frame_id_i(yolo_source_frame_id_o),.source_byte_base_i(yolo_source_base),.destination_byte_base_i(32'd0),
   .busy_o(prep_busy),.done_o(prep_done),.error_o(prep_error),.source_frame_id_o(),
   .req_valid_o(prep_req),.req_ready_i(request_ready[3]),.req_write_o(prep_write),.req_line_address_o(prep_addr),.req_write_data_o(prep_data),.req_write_strobe_o(prep_strobe),
   .read_valid_i(read_valid[3]),.read_ready_o(read_ready[3]),.read_data_i(read_data[384+:128]));
 wire core_req,core_write;wire [27:0] core_addr;wire [127:0] core_data;wire [15:0] core_strobe;
 wire core_tx_request,core_tx_valid,core_udp_grant;wire [7:0] core_tx_data;wire [15:0] core_tx_length;
 wire [31:0] strict_graph_starts,committed_ai_dones;
 v5n_ethernet_detector_top #(.CAMERA_INPUT(1),.ENABLE_DEBUG(0)) core(
   .sd_cs_n(sd_cs_n),.sd_sclk(sd_sclk),.sd_mosi(sd_mosi),.sd_miso(sd_miso),
   .clk_i(clk),.rst_ni(rst_n),.parameters_ready_i(1'b0),.camera_frame_complete_i(prep_done),.camera_source_frame_id_i(yolo_source_frame_id_o),
   .camera_model_ready_o(model_ready_o),.camera_image_idle_o(core_idle),.camera_model_load_count_o(model_load_count_o),
   .camera_graph_start_count_o(strict_graph_starts),.camera_ai_done_count_o(committed_ai_dones),
   .udp_rx_valid_i(udp_rx_valid_i),.udp_rx_data_i(udp_rx_data_i),.udp_rx_length_i(udp_rx_length_i),.udp_tx_busy_i(core_udp_grant),
   .udp_tx_request_o(core_tx_request),.udp_tx_valid_o(core_tx_valid),.udp_tx_data_o(core_tx_data),.udp_tx_length_o(core_tx_length),
   .ddr_req_valid_o(core_req),.ddr_req_ready_i(request_ready[2]),.ddr_req_write_o(core_write),.ddr_req_word_address_o(core_addr),.ddr_req_write_data_o(core_data),.ddr_req_write_strobe_o(core_strobe),
   .ddr_read_valid_i(read_valid[2]),.ddr_read_ready_o(read_ready[2]),.ddr_read_data_i(read_data[256+:128]),
   .accelerator_busy_o(yolo_busy_o),.accelerator_done_o(yolo_done_o),.accelerator_error_o(yolo_error_o),.active_layer_o(active_layer_o),.tf_status_o(tf_status_o));
 reg [31:0] last_video_id;
 wire video_req,pixel_valid,pixel_start,pixel_ready,packet_done;wire [27:0] video_addr;wire [15:0] rgb565;wire [31:0] video_owned_id;
 reg command_in_packet,command_magic,status_pending;reg [15:0] command_index;
 reg [7:0] command_kind;
 // CC3: RGB888 raw snapshot TX removed (user-approved); raw_mode is never entered.
 wire raw_req=1'b0,raw_read_ready=1'b0,raw_done=1'b0,raw_tx_request=1'b0,raw_tx_valid=1'b0;
 wire [27:0] raw_addr=28'd0;wire [7:0] raw_tx_data=8'd0;wire [15:0] raw_tx_length=16'd0;
 wire video_read_ready;
 camera_owned_video_reader video_reader(.clk(clk),.rst_n(rst_n),.start_i(vstate==2&&!raw_mode),.source_frame_id_i(video_source_id),.source_byte_base_i(video_source_base),
   .packet_frame_complete_i(packet_done),.pixel_ready_i(pixel_ready),.busy_o(video_busy),.done_o(video_done),.source_frame_id_o(video_owned_id),
   .pixel_valid_o(pixel_valid),.pixel_frame_start_o(pixel_start),.pixel_rgb565_o(rgb565),.req_valid_o(video_req),.req_ready_i(request_ready[1]),.req_address_o(video_addr),
   .read_valid_i(read_valid[1]&&!raw_mode),.read_ready_o(video_read_ready),.read_data_i(read_data[128+:128]));
 wire video_tx_request,video_tx_valid,video_fifo_full;wire [7:0] video_tx_data;wire [15:0] video_tx_length;
 assign pixel_ready=!video_fifo_full;
 camera_owned_rgb565_video_tx #(.IMAGE_WIDTH(1280),.IMAGE_HEIGHT(720),.PACKET_DATA_BYTES(636),.FIFO_ADDR_WIDTH_W(13)) video_tx(
   .I_rst(!rst_n),.I_enable(rst_n),.I_source_frame_id(video_owned_id),.O_frame_complete(packet_done),
   .I_video_clk(clk),.I_pixel_valid(pixel_valid),.I_frame_start(pixel_start),.I_pixel_rgb565(rgb565),.I_udp_clk(clk),.I_W_udp_busy(video_udp_grant&&!raw_mode),
   .O_W_udp_req(video_tx_request),.O_W_udp_valid(video_tx_valid),.O_W_udp_data(video_tx_data),.O_W_udp_len(video_tx_length),
   .O_fifo_full(video_fifo_full),.O_fifo_empty(),.O_fifo_rdusedw(),.O_dropped_pixels(),.O_frame_sequence(),.O_packet_sequence(),.O_frame_offset(),.O_tx_active());
 wire video_port_request=raw_mode?raw_tx_request:video_tx_request;
 wire video_port_valid=raw_mode?raw_tx_valid:video_tx_valid;
 wire [7:0] video_port_data=raw_mode?raw_tx_data:video_tx_data;
 wire [15:0] video_port_length=raw_mode?raw_tx_length:video_tx_length;
 wire video_port_req=raw_mode?raw_req:video_req;
 wire [27:0] video_port_addr=raw_mode?raw_addr:video_addr;
 assign read_ready[1]=raw_mode?raw_read_ready:video_read_ready;
 wire status_busy,status_req,status_valid,status_grant,media_grant,media_request,media_valid;
 wire [7:0] status_data,media_data;wire [15:0] status_length,media_length;
 wire legacy_request,legacy_valid,legacy_grant,perf_status_busy,perf_status_request,perf_status_valid,perf_status_grant;
 wire [7:0] legacy_data,perf_status_data;wire [15:0] legacy_length,perf_status_length;
 camera_udp_packet_arbiter packets(.clk(clk),.rst_n(rst_n),.request_i({core_tx_request,video_port_request}),.valid_i({core_tx_valid,video_port_valid}),
   .data_i({core_tx_data,video_port_data}),.length_i({core_tx_length,video_port_length}),.grant_o({core_udp_grant,video_udp_grant}),
   .request_o(udp_request_o),.valid_o(udp_valid_o),.data_o(udp_data_o),.length_o(udp_length_o),.vendor_busy_i(udp_busy_i),.active_o());
 // CC3: Y5ST status (type7) and perf status TX removed; video+detection arbiter drives UDP directly.
 assign read_ready[0]=1'b0;
 camera_shared_line_arbiter memory(.clk(clk),.rst_n(rst_n),.req_valid_i({prep_req,core_req,video_port_req,cap_req}),.req_ready_o(request_ready),
   .req_write_i({prep_write,core_write,1'b0,1'b1}),.req_address_i({prep_addr,core_addr,video_port_addr,cap_addr}),
   .req_data_i({prep_data,core_data,128'd0,cap_data}),.req_strobe_i({prep_strobe,core_strobe,16'd0,16'hffff}),
   .read_valid_o(read_valid),.read_ready_i(read_ready),.read_data_o(read_data),
   .memory_req_valid_o(memory_req_valid_o),.memory_req_ready_i(memory_req_ready_i),.memory_req_write_o(memory_req_write_o),
   .memory_req_address_o(memory_req_address_o),.memory_req_data_o(memory_req_data_o),.memory_req_strobe_o(memory_req_strobe_o),
   .memory_read_valid_i(memory_read_valid_i),.memory_read_ready_o(memory_read_ready_o),.memory_read_data_i(memory_read_data_i),.selected_client_o(),.read_pending_o());
 always @(posedge clk or negedge rst_n)begin
   if(!rst_n)begin ystate<=0;vstate<=0;last_video_id<=0;yolo_start_count_o<=0;yolo_done_count_o<=0;have_yolo_source<=0;last_yolo_id<=0;
     raw_pending<=0;raw_mode<=0;command_in_packet<=0;command_magic<=0;command_index<=0;command_kind<=0;status_pending<=0;
     perf_ack_sequence<=0;perf_video_starts<=0;end
   else begin
     if(vstate==2&&!raw_mode)perf_video_starts<=perf_video_starts+1'b1;
     // CC3: type6 raw-dump / type7 status UDP commands removed (user-approved).
     case(ystate)
       0:if(yolo_acquire)ystate<=1;
       // Acquire snapshots an owned bank. If no NEW complete Camera frame
       // arrived since the last start, release it without recomputing it.
       1:if(yolo_locked)ystate<=(have_yolo_source&&yolo_source_frame_id_o==last_yolo_id&&!repeat_source)?5:2;
       2:begin ystate<=3;yolo_start_count_o<=yolo_start_count_o+1'b1;have_yolo_source<=1;last_yolo_id<=yolo_source_frame_id_o;end
       3:if(prep_error)ystate<=6;else if(prep_done)ystate<=4;
       4:if(yolo_error_o)ystate<=6;else if(yolo_done_o)begin ystate<=5;yolo_done_count_o<=yolo_done_count_o+1'b1;end
       5:ystate<=0;
       6:ystate<=7; // release failed source once, then require explicit reset.
       default:ystate<=7;
     endcase
     case(vstate)
       0:if(video_acquire)vstate<=1;
       1:if(video_locked)begin
         if(raw_pending)begin raw_mode<=1;raw_pending<=0;vstate<=2;end
         else begin raw_mode<=0;vstate<=(video_source_id==last_video_id&&!repeat_source)?3:2;end
       end
       2:begin if(!raw_mode)last_video_id<=video_source_id;vstate<=4;end
       4:if(raw_mode?raw_done:video_done)vstate<=3;
       3:vstate<=0;
       default:vstate<=0;
     endcase
   end
 end
 assign diag_state_o={ystate,vstate,prep_busy,latest_valid,yolo_locked,video_locked,release_error,core_idle};
endmodule
