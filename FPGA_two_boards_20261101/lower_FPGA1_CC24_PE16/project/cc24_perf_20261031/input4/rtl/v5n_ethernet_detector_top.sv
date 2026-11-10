// A2 classic-v5 application; private147 graph/parameters, original Y8N3 UDP wire ABI retained.
// Synthesizable fixed-graph detector integration at the proven uiudp_stack
// application boundary. A thin board wrapper binds these UDP signals to the
// reference RGMII/PHY/PLL and the DDR request signals to the PH1P DDR MC.
module v5n_ethernet_detector_top #(
 parameter integer ADDR_W=32,parameter integer DATA_W=128,parameter integer WORD_LSB_W=4,
 parameter integer FIXED_SPLIT_VIEWS=0,
 parameter integer CAMERA_INPUT=0,ENABLE_DEBUG=1,
 parameter [ADDR_W-1:0] FEATURE_BASE=32'h0000_0000,
 parameter [ADDR_W-1:0] WEIGHT_BASE=32'h0100_0000,
 parameter [ADDR_W-1:0] BIAS_BASE=32'h0140_0000,
 parameter [ADDR_W-1:0] REQUANT_BASE=32'h0150_0000,
 parameter [ADDR_W-1:0] LUT_BASE=32'h0160_0000
)(
 input wire clk_i,input wire rst_ni,input wire parameters_ready_i,
 output wire sd_cs_n,sd_sclk,sd_mosi,input wire sd_miso,
 input wire camera_frame_complete_i,input wire [31:0] camera_source_frame_id_i,
 output wire camera_model_ready_o,camera_image_idle_o,
 output reg [31:0] camera_model_load_count_o,
 output reg [31:0] camera_graph_start_count_o,camera_ai_done_count_o,
 input wire udp_rx_valid_i,input wire [7:0] udp_rx_data_i,input wire [15:0] udp_rx_length_i,
 input wire udp_tx_busy_i,output wire udp_tx_request_o,output wire udp_tx_valid_o,output wire [7:0] udp_tx_data_o,output wire [15:0] udp_tx_length_o,
 output wire ddr_req_valid_o,input wire ddr_req_ready_i,output wire ddr_req_write_o,output wire [ADDR_W-WORD_LSB_W-1:0] ddr_req_word_address_o,
 output wire [DATA_W-1:0] ddr_req_write_data_o,output wire [DATA_W/8-1:0] ddr_req_write_strobe_o,
 input wire ddr_read_valid_i,output wire ddr_read_ready_o,input wire [DATA_W-1:0] ddr_read_data_i,
 output wire accelerator_busy_o,output wire accelerator_done_o,output wire accelerator_error_o,output wire [7:0] active_layer_o,
 // CC13: TF boot status for telemetry (observation only) = {model_ready, first_error[7:0], boot_state[4:0], retries[1:0], recovery}
 output wire [16:0] tf_status_o
);
 wire rx_write_valid_w,rx_write_ready_w,rx_frame_start_w,rx_frame_complete_w,rx_error_w,rx_overflow_w,rx_sequence_w;
 wire [ADDR_W-1:0]rx_write_address_w;wire signed[7:0]rx_write_data_w;wire[31:0]rx_frame_id_w,rx_bytes_w,rx_checksum_w;
 generate if(!CAMERA_INPUT)begin:G_PC_INPUT
 v5n_udp_image_frame_rx #(.ADDR_W(ADDR_W)) image_rx(.clk_i(clk_i),.rst_ni(rst_ni),.udp_rx_valid_i(udp_rx_valid_i),.udp_rx_data_i(udp_rx_data_i),.udp_rx_length_i(udp_rx_length_i),
  .image_write_valid_o(rx_write_valid_w),.image_write_ready_i(rx_write_ready_w),.image_write_address_o(rx_write_address_w),.image_write_data_o(rx_write_data_w),
  .image_frame_start_o(rx_frame_start_w),.image_frame_complete_o(rx_frame_complete_w),.image_frame_id_o(rx_frame_id_w),
  .image_bytes_received_o(rx_bytes_w),.image_checksum_o(rx_checksum_w),.overflow_error_o(rx_overflow_w),.sequence_error_o(rx_sequence_w),.error_o(rx_error_w));
 end else begin:G_CAMERA_INPUT
 assign rx_write_valid_w=0;assign rx_write_address_w=0;assign rx_write_data_w=0;
 assign rx_frame_start_w=0;assign rx_frame_complete_w=camera_frame_complete_i;
 assign rx_frame_id_w=camera_source_frame_id_i;assign rx_bytes_w=307200;
 assign rx_checksum_w=0;assign rx_overflow_w=0;assign rx_sequence_w=0;assign rx_error_w=0;
 end endgenerate
 wire param_write_valid_w,param_write_ready_w,param_complete_w,param_error_w,param_overflow_w,param_sequence_w;
 wire[ADDR_W-1:0]param_write_address_w;wire signed[7:0]param_write_data_w;wire[3:0]param_mask_w;
 wire[31:0]weight_bytes_w,bias_bytes_w,requant_bytes_w,lut_bytes_w,weight_checksum_w,bias_checksum_w,requant_checksum_w,lut_checksum_w;
 reg camera_model_ready_r;
 wire model_source_valid,model_source_parser_reset_n,model_source_qualified,model_recovery;
 wire[7:0]model_source_data,tf_source_error;wire[15:0]model_source_length;
 wire[4:0]tf_boot_state;
 v5n_udp_parameter_loader parameter_loader(.clk_i(clk_i),.rst_ni(model_source_parser_reset_n),.udp_rx_valid_i(model_source_valid&&!camera_model_ready_r),.udp_rx_data_i(model_source_data),.udp_rx_length_i(model_source_length),
  .memory_write_valid_o(param_write_valid_w),.memory_write_ready_i(param_write_ready_w),.memory_write_address_o(param_write_address_w),.memory_write_data_o(param_write_data_w),
  .parameters_complete_o(param_complete_w),.section_complete_o(param_mask_w),.weight_bytes_received_o(weight_bytes_w),.bias_bytes_received_o(bias_bytes_w),
  .requant_bytes_received_o(requant_bytes_w),.lut_bytes_received_o(lut_bytes_w),.weight_checksum_o(weight_checksum_w),.bias_checksum_o(bias_checksum_w),
  .requant_checksum_o(requant_checksum_w),.lut_checksum_o(lut_checksum_w),.overflow_error_o(param_overflow_w),.sequence_error_o(param_sequence_w),.error_o(param_error_w));
 wire fifo_push_ready_w;assign rx_write_ready_w=fifo_push_ready_w&&!param_write_valid_w;assign param_write_ready_w=fifo_push_ready_w;
 wire fifo_valid_w,fifo_ready_w,fifo_empty_w;wire[ADDR_W-1:0]fifo_address_w;wire signed[7:0]fifo_data_w;
 v5n_ingress_fifo ingress_fifo(.clk_i(clk_i),.rst_ni(rst_ni),.push_i(rx_write_valid_w||param_write_valid_w),.push_ready_o(fifo_push_ready_w),
  .push_address_i(param_write_valid_w?param_write_address_w:(FEATURE_BASE+rx_write_address_w)),.push_data_i(param_write_valid_w?param_write_data_w:rx_write_data_w),
  .pop_valid_o(fifo_valid_w),.pop_ready_i(fifo_ready_w),.pop_address_o(fifo_address_w),.pop_data_o(fifo_data_w),.empty_o(fifo_empty_w));
 reg frame_pending_r,image_loaded_r;reg[31:0]frame_id_r;wire all_parameters_ready_w=CAMERA_INPUT?camera_model_ready_r:(parameters_ready_i||param_complete_w);
  wire ai_local_frame_ready_w,ai_owned_w,ai_result_ready_w,ai_boundary_error_w;
 wire [31:0] ai_frame_id_w,ai_result_frame_id_w;
 wire [ADDR_W-1:0] ai_frame_base_w;
 wire [63:0] ai_start_tick_w,ai_result_tick_w,ai_latency_cycles_w;
 wire scheduler_start_w;

 always @(posedge clk_i or negedge rst_ni)begin if(!rst_ni)begin frame_pending_r<=0;image_loaded_r<=0;frame_id_r<=0;end else begin
   if(rx_frame_start_w)image_loaded_r<=0;
   if(rx_frame_complete_w)begin frame_pending_r<=1;image_loaded_r<=1;frame_id_r<=rx_frame_id_w;end
   if(scheduler_start_w)frame_pending_r<=0;end end

 wire op_start_w,op_valid_w,op_accept_w,op_done_w,op_error_w;wire[7:0]op_node_w,op_dst_w;wire[3:0]op_opcode_w;wire[2:0]op_source_count_w;wire[31:0]op_sources_w;
 wire[9:0]op_ih_w,op_iw_w,op_ic_w,op_oh_w,op_ow_w,op_oc_w;wire[3:0]op_kh_w,op_kw_w,op_sh_w,op_sw_w,op_pt_w,op_pl_w,op_dil_w;wire[7:0]op_groups_w;
 wire[31:0]op_wo_w,op_wb_w,op_bo_w,op_bb_w,op_ro_w,op_rb_w,op_lo_w,op_lb_w;wire[5:0]op_conv_shift_w;wire signed[127:0]op_mult_w;wire[23:0]op_shift_w;wire[39:0]op_channels_w;wire[7:0]op_split_w,op_detect_stride_w;wire signed[7:0]op_zp_w;
 wire[1:0]scheduler_state_w;wire[47:0]layer_cycles_w,total_cycles_w;wire watchdog_timeout_w;
 v5n_fixed_graph_scheduler scheduler(.clk_i(clk_i),.rst_ni(rst_ni),.start_i(scheduler_start_w),.operation_start_o(op_start_w),.operation_valid_o(op_valid_w),.operation_node_id_o(op_node_w),.operation_opcode_o(op_opcode_w),
  .operation_source_count_o(op_source_count_w),.operation_sources_o(op_sources_w),.operation_destination_o(op_dst_w),.operation_input_h_o(op_ih_w),.operation_input_w_o(op_iw_w),.operation_input_c_o(op_ic_w),
  .operation_output_h_o(op_oh_w),.operation_output_w_o(op_ow_w),.operation_output_c_o(op_oc_w),.operation_kernel_h_o(op_kh_w),.operation_kernel_w_o(op_kw_w),.operation_stride_h_o(op_sh_w),.operation_stride_w_o(op_sw_w),
  .operation_pad_top_o(op_pt_w),.operation_pad_left_o(op_pl_w),.operation_dilation_h_o(op_dil_w),.operation_groups_o(op_groups_w),.operation_weight_offset_o(op_wo_w),.operation_weight_bytes_o(op_wb_w),
  .operation_bias_offset_o(op_bo_w),.operation_bias_bytes_o(op_bb_w),.operation_requant_offset_o(op_ro_w),.operation_requant_bytes_o(op_rb_w),.operation_lut_offset_o(op_lo_w),.operation_lut_bytes_o(op_lb_w),
  .operation_conv_shift_o(op_conv_shift_w),.operation_source_multiplier_o(op_mult_w),.operation_source_shift_o(op_shift_w),.operation_source_channels_o(op_channels_w),.operation_split_index_o(op_split_w),
  .operation_detect_stride_o(op_detect_stride_w),.operation_output_zero_point_o(op_zp_w),.operation_accept_i(op_accept_w),.operation_done_i(op_done_w),.operation_error_i(op_error_w),
  .busy_o(accelerator_busy_o),.done_o(accelerator_done_o),.error_o(accelerator_error_o),.active_layer_o(active_layer_o),
  .state_o(scheduler_state_w),.layer_cycle_count_o(layer_cycles_w),.total_cycle_count_o(total_cycles_w),.watchdog_timeout_o(watchdog_timeout_w));

 wire service_mem_valid_w,service_mem_ready_w,service_mem_write_w,service_mem_resp_valid_w,service_mem_resp_ready_w,service_mem_resp_error_w,service_mem_resp_write_w;
 wire service_line_valid_w,service_line_invalidate_w;
 wire [ADDR_W-1:0] service_line_address_w;
 wire [DATA_W-1:0] service_line_data_w;
 wire service_write_line_w;wire[127:0]service_write_line_data_w;
 wire[ADDR_W-1:0]service_mem_addr_w;wire signed[7:0]service_mem_wdata_w,service_mem_rdata_w;wire[8:0]detection_count_w;
 wire[2:0]service_state_w,bridge_state_w;wire[3:0]selected_runtime_w;wire selector_valid_w,illegal_selector_w;wire[9:0]tile_x_w,tile_y_w,channel_slice_w;
 v5n_operator_service #(.ADDR_W(ADDR_W),.SHAPE_W(10),.NUM_PE(16),.FIXED_SPLIT_VIEWS(FIXED_SPLIT_VIEWS),.SILU_WRITE_LINE(1),.CONV_WRITE_LINE(1),.CONCAT_WRITE_LINE(1)) operator_service(.clk_i(clk_i),.rst_ni(rst_ni),.frame_identity_i(ai_frame_id_w),.operation_start_i(op_start_w),.operation_valid_i(op_valid_w),.operation_node_id_i(op_node_w),.operation_opcode_i(op_opcode_w),.operation_source_count_i(op_source_count_w),.operation_sources_i(op_sources_w),.operation_destination_i(op_dst_w),
  .shared_memory_write_line_o(service_write_line_w),.shared_memory_write_line_data_o(service_write_line_data_w),
  .operation_input_h_i(op_ih_w),.operation_input_w_i(op_iw_w),.operation_input_c_i(op_ic_w),.operation_output_h_i(op_oh_w),.operation_output_w_i(op_ow_w),.operation_output_c_i(op_oc_w),.operation_kernel_h_i(op_kh_w),.operation_kernel_w_i(op_kw_w),.operation_stride_h_i(op_sh_w),.operation_stride_w_i(op_sw_w),.operation_pad_top_i(op_pt_w),.operation_pad_left_i(op_pl_w),
  .operation_weight_offset_i(op_wo_w),.operation_weight_bytes_i(op_wb_w),.operation_bias_offset_i(op_bo_w),.operation_bias_bytes_i(op_bb_w),.operation_requant_offset_i(op_ro_w),.operation_requant_bytes_i(op_rb_w),.operation_lut_offset_i(op_lo_w),.operation_lut_bytes_i(op_lb_w),.operation_conv_shift_i(op_conv_shift_w),.operation_source_multiplier_i(op_mult_w),.operation_source_shift_i(op_shift_w),.operation_source_channels_i(op_channels_w),.operation_split_index_i(op_split_w),.operation_detect_stride_i(op_detect_stride_w),.operation_output_zero_point_i(op_zp_w),
  .image_ready_i(1'b1),.feature_base_i(FEATURE_BASE),.weight_base_i(WEIGHT_BASE),.bias_base_i(BIAS_BASE),.requant_base_i(REQUANT_BASE),.lut_base_i(LUT_BASE),.operation_accept_o(op_accept_w),.operation_done_o(op_done_w),.operation_error_o(op_error_w),.busy_o(),.detection_count_o(detection_count_w),
  .service_state_o(service_state_w),.selected_runtime_o(selected_runtime_w),.selector_valid_o(selector_valid_w),.illegal_selector_error_o(illegal_selector_w),
  .tile_x_o(tile_x_w),.tile_y_o(tile_y_w),.channel_slice_o(channel_slice_w),.bridge_state_o(bridge_state_w),
  .shared_memory_valid_o(service_mem_valid_w),.shared_memory_ready_i(service_mem_ready_w),.shared_memory_write_o(service_mem_write_w),.shared_memory_address_o(service_mem_addr_w),.shared_memory_write_data_o(service_mem_wdata_w),
  .shared_memory_response_valid_i(service_mem_resp_valid_w),.shared_memory_response_ready_o(service_mem_resp_ready_w),.shared_memory_response_error_i(service_mem_resp_error_w),.shared_memory_response_is_write_i(service_mem_resp_write_w),.shared_memory_read_data_i(service_mem_rdata_w),
  .shared_read_line_valid_i(service_line_valid_w),.shared_read_line_address_i(service_line_address_w),
  .shared_read_line_data_i(service_line_data_w),.shared_line_invalidate_i(service_line_invalidate_w));

 wire det_read_req_w;wire[8:0]det_read_index_w;reg det_read_valid_r;reg[7:0]det_bytes_r[0:23];reg det_reader_busy_r,det_request_seen_r;wire exec_read_ready_w,exec_read_busy_w,exec_read_done_w,exec_read_valid_w,exec_read_last_w,exec_error_w;wire[ADDR_W-1:0]exec_read_offset_w;wire signed[7:0]exec_read_data_w;
 wire debug_tx_busy_w,debug_launch_w;
 wire det_exec_start_w=det_read_req_w&&!det_reader_busy_r&&!det_request_seen_r;wire[ADDR_W-1:0]det_exec_address_w=FEATURE_BASE+32'd8015168+(det_read_index_w*24);
 integer di;always @(posedge clk_i or negedge rst_ni)begin if(!rst_ni)begin det_reader_busy_r<=0;det_request_seen_r<=0;det_read_valid_r<=0;for(di=0;di<24;di=di+1)det_bytes_r[di]<=0;end else begin
   det_read_valid_r<=0;if(!det_read_req_w)det_request_seen_r<=0;
   if(det_exec_start_w&&!debug_tx_busy_w)begin det_reader_busy_r<=1;det_request_seen_r<=1;end
   if(exec_read_valid_w&&!debug_tx_busy_w)det_bytes_r[exec_read_offset_w[4:0]]<=exec_read_data_w;
   if(exec_read_done_w&&!debug_tx_busy_w)begin det_reader_busy_r<=0;det_read_valid_r<=1;end end end
 wire[31:0]det_class_word_w={det_bytes_r[3],det_bytes_r[2],det_bytes_r[1],det_bytes_r[0]};wire[31:0]det_score_word_w={det_bytes_r[7],det_bytes_r[6],det_bytes_r[5],det_bytes_r[4]};
 wire[31:0]det_x1_w={det_bytes_r[11],det_bytes_r[10],det_bytes_r[9],det_bytes_r[8]},det_y1_w={det_bytes_r[15],det_bytes_r[14],det_bytes_r[13],det_bytes_r[12]};
 wire[31:0]det_x2_w={det_bytes_r[19],det_bytes_r[18],det_bytes_r[17],det_bytes_r[16]},det_y2_w={det_bytes_r[23],det_bytes_r[22],det_bytes_r[21],det_bytes_r[20]};

 // A type-4 query is recognized from the common Y8N3 header.  The response
 // request is latched, so it cannot be lost while a detection packet is sent.
 reg status_rx_in_packet_r,status_rx_magic_r,status_pending_r,detection_pending_r;reg[15:0]status_rx_index_r;
 reg[7:0]control_type_r,debug_layer_r;reg[31:0]debug_offset_r,debug_count_r;reg debug_pending_r;
 wire status_query_byte_w=udp_rx_valid_i&&status_rx_in_packet_r&&(status_rx_index_r==16'd5)&&status_rx_magic_r&&(udp_rx_data_i==8'd4);
 wire det_tx_busy_w,status_tx_busy_w;wire det_launch_w=detection_pending_r&&!det_tx_busy_w&&!status_tx_busy_w&&!debug_tx_busy_w;
 wire status_launch_w=status_pending_r&&!detection_pending_r&&!accelerator_done_o&&!det_tx_busy_w&&!status_tx_busy_w&&!debug_tx_busy_w;
 always @(posedge clk_i or negedge rst_ni)begin
  if(!rst_ni)begin status_rx_in_packet_r<=0;status_rx_magic_r<=0;status_rx_index_r<=0;status_pending_r<=0;detection_pending_r<=0;
   control_type_r<=0;debug_layer_r<=0;debug_offset_r<=0;debug_count_r<=0;debug_pending_r<=0;end
  else begin
   if(CAMERA_INPUT?ai_result_ready_w:accelerator_done_o)detection_pending_r<=1;if(det_launch_w)detection_pending_r<=0;
   if(status_query_byte_w)status_pending_r<=1;if(status_launch_w)status_pending_r<=0;
   if(debug_launch_w)debug_pending_r<=0;
   if(udp_rx_valid_i)begin
    if(!status_rx_in_packet_r)begin status_rx_in_packet_r<=1;status_rx_index_r<=1;status_rx_magic_r<=(udp_rx_data_i==8'h59);control_type_r<=0;end
    else begin
     if((status_rx_index_r==1&&udp_rx_data_i!=8'h38)||(status_rx_index_r==2&&udp_rx_data_i!=8'h4e)||
        (status_rx_index_r==3&&udp_rx_data_i!=8'h33)||(status_rx_index_r==4&&udp_rx_data_i!=1))status_rx_magic_r<=0;
     if(status_rx_index_r==5)control_type_r<=udp_rx_data_i;
     if(status_rx_index_r==6)debug_layer_r<=udp_rx_data_i;
     if(status_rx_index_r==8)debug_offset_r[7:0]<=udp_rx_data_i;if(status_rx_index_r==9)debug_offset_r[15:8]<=udp_rx_data_i;
     if(status_rx_index_r==10)debug_offset_r[23:16]<=udp_rx_data_i;if(status_rx_index_r==11)debug_offset_r[31:24]<=udp_rx_data_i;
     if(status_rx_index_r==12)debug_count_r[7:0]<=udp_rx_data_i;if(status_rx_index_r==13)debug_count_r[15:8]<=udp_rx_data_i;
     if(status_rx_index_r==14)debug_count_r[23:16]<=udp_rx_data_i;if(status_rx_index_r==15)debug_count_r[31:24]<=udp_rx_data_i;
     if(status_rx_index_r+1>=udp_rx_length_i)begin
      status_rx_in_packet_r<=0;
      if(status_rx_magic_r&&control_type_r==8'd5&&udp_rx_length_i==16'd16)debug_pending_r<=1;
     end else status_rx_index_r<=status_rx_index_r+1'b1;
    end
   end
  end
 end

 wire ingress_error_w;wire[1:0]memory_owner_w,memory_adapter_state_w; wire [15:0] tf_status_w; // CC14: declared before use
 r10_tf_source model_source(.clk(clk_i),.rst_n(rst_ni),.model_ready_i(camera_model_ready_r),
  .ingress_idle_i(fifo_empty_w&&!fifo_valid_w&&memory_adapter_state_w==0),
  .writer_error_i(ingress_error_w||param_error_w),
  .writer_slot_ready_i(!param_write_valid_w||param_write_ready_w),.writer_pending_i(param_write_valid_w),
  .host_valid_i(udp_rx_valid_i),.host_data_i(udp_rx_data_i),.host_length_i(udp_rx_length_i),
  .parameter_valid_o(model_source_valid),.parameter_data_o(model_source_data),.parameter_length_o(model_source_length),
  .parser_reset_no(model_source_parser_reset_n),.model_qualified_o(model_source_qualified),
  .error_o(tf_source_error),.boot_state_o(tf_boot_state),.recovery_o(model_recovery),.status_o(tf_status_w),
  .sd_cs_n(sd_cs_n),.sd_sclk(sd_sclk),.sd_mosi(sd_mosi),.sd_miso(sd_miso));
 assign camera_model_ready_o=camera_model_ready_r;
 assign tf_status_o={camera_model_ready_r,tf_status_w};
 // Observability only: counts the actual scheduler start and commit-fenced
 // AI result, not PC packets or preprocessing jobs.
 always @(posedge clk_i or negedge rst_ni)begin
   if(!rst_ni)begin camera_graph_start_count_o<=0;camera_ai_done_count_o<=0;end
   else begin
     if(scheduler_start_w)camera_graph_start_count_o<=camera_graph_start_count_o+1'b1;
     if(ai_result_ready_w)camera_ai_done_count_o<=camera_ai_done_count_o+1'b1;
   end
 end
 assign camera_image_idle_o=camera_model_ready_r&&!accelerator_busy_o&&!ai_owned_w&&!frame_pending_r&&!detection_pending_r&&!det_tx_busy_w&&!status_tx_busy_w&&!debug_tx_busy_w;
 // One runtime model load. Complete byte counters alone are NOT a DDR fence.
 always @(posedge clk_i or negedge rst_ni)begin
   if(!rst_ni)begin camera_model_ready_r<=0;camera_model_load_count_o<=0;end
   else if(!camera_model_ready_r&&model_source_qualified&&param_complete_w&&fifo_empty_w&&memory_adapter_state_w==0&&!fifo_valid_w&&!ingress_error_w&&!param_error_w)begin
     camera_model_ready_r<=1;camera_model_load_count_o<=camera_model_load_count_o+1'b1;
   end
 end
 reg inference_started_r,graph_done_r,nms_started_r,nms_done_r;reg[15:0]last_error_r;
 wire ingress_commit_observed_w=(memory_owner_w==2'd0)&&(memory_adapter_state_w==2'd3);
 v5n_ai_frame_commit_fence #(.ADDR_W(ADDR_W)) frame_fence(
   .clk_i(clk_i),.rst_ni(rst_ni),.ingress_accept_i(fifo_valid_w&&fifo_ready_w),
   .ingress_commit_i(ingress_commit_observed_w),.ingress_error_i(ingress_error_w),
   .ingress_empty_i(fifo_empty_w),.frame_complete_i(rx_frame_complete_w),
   .frame_id_i(rx_frame_id_w),.frame_base_i(FEATURE_BASE),
   .parameters_ready_i(all_parameters_ready_w),
   .ai_accept_ready_i(!accelerator_busy_o),.graph_done_i(accelerator_done_o),
   .graph_error_i(accelerator_error_o),.nms_done_i(nms_done_r),
   .result_committed_i((memory_adapter_state_w==2'd0)&&(bridge_state_w==3'd0)&&!service_mem_valid_w),
   .frame_ready_o(ai_local_frame_ready_w),.ai_start_o(scheduler_start_w),
   .ai_owned_o(ai_owned_w),.ai_result_ready_o(ai_result_ready_w),
   .protocol_error_o(ai_boundary_error_w),.ai_frame_id_o(ai_frame_id_w),
   .result_frame_id_o(ai_result_frame_id_w),.ai_frame_base_o(ai_frame_base_w),
   .ai_start_tick_o(ai_start_tick_w),.ai_result_tick_o(ai_result_tick_w),
   .ai_latency_cycles_o(ai_latency_cycles_w));
 always @(posedge clk_i or negedge rst_ni)begin
  if(!rst_ni)begin inference_started_r<=0;graph_done_r<=0;nms_started_r<=0;nms_done_r<=0;last_error_r<=0;end
  else begin
   if(scheduler_start_w)begin inference_started_r<=1;graph_done_r<=0;nms_started_r<=0;nms_done_r<=0;last_error_r<=0;end
   else begin
    if(op_accept_w&&op_node_w==8'd146) nms_started_r<=1;
    if(op_done_w&&active_layer_o==8'd146)nms_done_r<=1;
    if(accelerator_done_o)graph_done_r<=1;
    if(rx_overflow_w)last_error_r[0]<=1;if(rx_sequence_w)last_error_r[1]<=1;
    if(param_overflow_w)last_error_r[2]<=1;if(param_sequence_w)last_error_r[3]<=1;
    if(ingress_error_w)last_error_r[4]<=1;if(exec_error_w)last_error_r[5]<=1;
    if(service_mem_resp_error_w)last_error_r[6]<=1;if(op_error_w)last_error_r[7]<=1;
    if(illegal_selector_w)last_error_r[8]<=1;if(watchdog_timeout_w)last_error_r[9]<=1;
    if(accelerator_error_o)last_error_r[10]<=1;
    last_error_r[15:11]<={model_recovery,tf_source_error[3:0]};
   end
  end
 end

 wire det_tx_request_w,det_tx_valid_w,det_tx_done_w;wire[7:0]det_tx_data_w;wire[15:0]det_tx_length_w;
 generate if(!CAMERA_INPUT)begin:G_LEGACY_DETECTION
 v5n_udp_detection_tx detection_tx(.clk_i(clk_i),.rst_ni(rst_ni),.start_i(det_launch_w),.frame_id_i(frame_id_r),.detection_count_i(detection_count_w),.detection_read_index_o(det_read_index_w),
  .detection_read_request_o(det_read_req_w),.detection_read_valid_i(det_read_valid_r),.detection_class_i(det_class_word_w[1:0]),.detection_confidence_q15_i(det_score_word_w[15:0]),
  .detection_x1_q16_i(det_x1_w),.detection_y1_q16_i(det_y1_w),.detection_x2_q16_i(det_x2_w),.detection_y2_q16_i(det_y2_w),.udp_busy_i(udp_tx_busy_i),
  .udp_request_o(det_tx_request_w),.udp_valid_o(det_tx_valid_w),.udp_data_o(det_tx_data_w),.udp_length_o(det_tx_length_w),.busy_o(det_tx_busy_w),.done_o(det_tx_done_w));
 end else begin:G_CAMERA_DETECTION
 camera_yolo_detection_tx detection_tx(.clk(clk_i),.rst_n(rst_ni),.start_i(det_launch_w),
   .source_frame_id_i(ai_result_frame_id_w),.latency_cycles_i(ai_latency_cycles_w[31:0]),.detection_count_i(detection_count_w),
   .detection_read_index_o(det_read_index_w),.detection_read_request_o(det_read_req_w),.detection_read_valid_i(det_read_valid_r),
   .detection_class_i(det_class_word_w[1:0]),.detection_confidence_i(det_score_word_w[15:0]),
   .x1_i(det_x1_w),.y1_i(det_y1_w),.x2_i(det_x2_w),.y2_i(det_y2_w),
   .udp_busy_i(udp_tx_busy_i),.udp_request_o(det_tx_request_w),.udp_valid_o(det_tx_valid_w),.udp_data_o(det_tx_data_w),.udp_length_o(det_tx_length_w),
   .busy_o(det_tx_busy_w),.done_o(det_tx_done_w),.error_o());
 end endgenerate

 wire status_tx_request_w,status_tx_valid_w,status_tx_done_w;wire[7:0]status_tx_data_w;wire[15:0]status_tx_length_w;
 wire[7:0]status_flags_w={nms_done_r,nms_started_r,graph_done_r,accelerator_busy_o,inference_started_r,
                          all_parameters_ready_w,image_loaded_r,frame_pending_r};
 wire[3:0]memory_state_w={memory_owner_w,memory_adapter_state_w};
 // CC3: type-4 status query responder removed (user-approved diagnostic removal).
 // Internal flags/counters (status_flags_w,last_error_r,total_cycles_w) are retained.
 generate if(0)begin:G_STATUS_TX
 v5n_udp_status_tx status_tx(.clk_i(clk_i),.rst_ni(rst_ni),.start_i(status_launch_w),.udp_busy_i(udp_tx_busy_i),
  .parameter_mask_i(param_mask_w),.flags_i(status_flags_w),.last_error_i(last_error_r),.frame_id_i(frame_id_r),
  .image_bytes_i(rx_bytes_w),.weight_bytes_i(weight_bytes_w),.bias_bytes_i(bias_bytes_w),.requant_bytes_i(requant_bytes_w),.lut_bytes_i(lut_bytes_w),
  .image_checksum_i(rx_checksum_w),.weight_checksum_i(weight_checksum_w),.bias_checksum_i(bias_checksum_w),.requant_checksum_i(requant_checksum_w),.lut_checksum_i(lut_checksum_w),
  .active_layer_i(active_layer_o),.active_opcode_i(op_opcode_w),.scheduler_state_i(scheduler_state_w),.service_state_i(service_state_w),
  .selected_runtime_i(selected_runtime_w),.bridge_state_i(bridge_state_w),.memory_state_i(memory_state_w),.tile_x_i(tile_x_w),.tile_y_i(tile_y_w),
  .channel_slice_i(channel_slice_w),.layer_cycles_i(layer_cycles_w),.total_cycles_i(total_cycles_w),.detection_count_i(detection_count_w),
  .udp_request_o(status_tx_request_w),.udp_valid_o(status_tx_valid_w),.udp_data_o(status_tx_data_w),.udp_length_o(status_tx_length_w),.busy_o(status_tx_busy_w),.done_o(status_tx_done_w));
 end else begin:G_NO_STATUS_TX
 assign status_tx_request_w=0;assign status_tx_valid_w=0;assign status_tx_data_w=0;assign status_tx_length_w=0;
 assign status_tx_busy_w=0;assign status_tx_done_w=0;
 end endgenerate
 wire debug_map_valid_w;wire[ADDR_W-1:0]debug_map_offset_w,debug_map_size_w;wire[9:0]debug_map_h_w,debug_map_w_w,debug_map_c_w;
 generate if(ENABLE_DEBUG)begin:G_DEBUG_MAP
 v5n_real_tensor_address_map debug_address_map(.tensor_id_i(debug_layer_r),.valid_o(debug_map_valid_w),.base_offset_o(debug_map_offset_w),.data_size_o(debug_map_size_w),.height_o(debug_map_h_w),.width_o(debug_map_w_w),.channels_o(debug_map_c_w));
 end else begin:G_NO_DEBUG_MAP
 assign debug_map_valid_w=0;assign debug_map_offset_w=0;assign debug_map_size_w=0;
 assign debug_map_h_w=0;assign debug_map_w_w=0;assign debug_map_c_w=0;
 end endgenerate
 wire debug_post_valid_w=1'b0;wire[ADDR_W-1:0]debug_post_offset_w=0,debug_post_size_w=0;
 // Reserved debug IDs expose the immutable parameter regions through the
 // same read-only transport.  Normal feature tensor IDs and all inference
 // traffic remain unchanged: 240=weights, 241=bias, 242=requant, 243=LUT.
 wire debug_parameter_valid_w=(debug_layer_r>=8'd240)&&(debug_layer_r<=8'd243);
 reg[ADDR_W-1:0]debug_dump_base_r,debug_dump_size_r;
 always @* begin
  debug_dump_base_r=FEATURE_BASE+(debug_post_valid_w?debug_post_offset_w:debug_map_offset_w);
  debug_dump_size_r=debug_post_valid_w?debug_post_size_w:debug_map_size_w;
  case(debug_layer_r)
   8'd240:begin debug_dump_base_r=WEIGHT_BASE;debug_dump_size_r=32'd1759744;end
   8'd241:begin debug_dump_base_r=BIAS_BASE;debug_dump_size_r=32'd19344;end
   8'd242:begin debug_dump_base_r=REQUANT_BASE;debug_dump_size_r=32'd19344;end
   8'd243:begin debug_dump_base_r=LUT_BASE;debug_dump_size_r=32'd17760;end
   default:begin end
  endcase
 end
 assign debug_launch_w=ENABLE_DEBUG&&debug_pending_r&&(debug_map_valid_w||debug_post_valid_w||debug_parameter_valid_w)&&graph_done_r&&!accelerator_busy_o&&!detection_pending_r&&!det_tx_busy_w&&!status_tx_busy_w&&!debug_tx_busy_w;
 wire debug_read_start_w;wire[ADDR_W-1:0]debug_read_address_w,debug_read_count_w;wire debug_tx_request_w,debug_tx_valid_w,debug_tx_done_w,debug_tx_error_w;wire[7:0]debug_tx_data_w;wire[15:0]debug_tx_length_w;
 generate if(ENABLE_DEBUG)begin:G_DEBUG_TX
 v5n_udp_tensor_dump_tx debug_tx(.clk_i(clk_i),.rst_ni(rst_ni),.start_i(debug_launch_w),.layer_i(debug_layer_r),.frame_id_i(frame_id_r),
  .tensor_base_i(debug_dump_base_r),.tensor_size_i(debug_dump_size_r),.request_offset_i(debug_offset_r),.request_count_i(debug_count_r),
  .read_start_o(debug_read_start_w),.read_address_o(debug_read_address_w),.read_count_o(debug_read_count_w),.read_ready_i(exec_read_ready_w),
  .read_done_i(exec_read_done_w),.read_data_valid_i(exec_read_valid_w),.read_data_offset_i(exec_read_offset_w),.read_data_i(exec_read_data_w),
  .udp_busy_i(udp_tx_busy_i),.udp_request_o(debug_tx_request_w),.udp_valid_o(debug_tx_valid_w),.udp_data_o(debug_tx_data_w),.udp_length_o(debug_tx_length_w),
  .busy_o(debug_tx_busy_w),.done_o(debug_tx_done_w),.error_o(debug_tx_error_w));
 end else begin:G_NO_DEBUG_TX
 assign debug_read_start_w=0;assign debug_read_address_w=0;assign debug_read_count_w=0;
 assign debug_tx_request_w=0;assign debug_tx_valid_w=0;assign debug_tx_data_w=0;assign debug_tx_length_w=0;
 assign debug_tx_busy_w=0;assign debug_tx_done_w=0;assign debug_tx_error_w=0;
 end endgenerate
 wire exec_read_start_w=debug_tx_busy_w?debug_read_start_w:(det_exec_start_w&&!debug_tx_busy_w);
 wire[ADDR_W-1:0]exec_read_address_w=debug_tx_busy_w?debug_read_address_w:det_exec_address_w;
 wire[ADDR_W-1:0]exec_read_count_mux_w=debug_tx_busy_w?debug_read_count_w:32'd24;

 // O_W_udp_busy is the vendor UDP/IP grant, not downstream idle readiness.
 // Retain the application request until that grant; payload and owner are unchanged.
 v5n_udp_request_hold request_hold(.clk_i(clk_i),.rst_ni(rst_ni),
  .request_i(debug_tx_request_w|det_tx_request_w|status_tx_request_w),
  .grant_i(udp_tx_busy_i),.request_o(udp_tx_request_o));
 assign udp_tx_valid_o=debug_tx_busy_w?debug_tx_valid_w:(det_tx_busy_w?det_tx_valid_w:status_tx_valid_w);
 assign udp_tx_data_o=debug_tx_busy_w?debug_tx_data_w:(det_tx_busy_w?det_tx_data_w:status_tx_data_w);
 assign udp_tx_length_o=debug_tx_busy_w?debug_tx_length_w:(det_tx_busy_w?det_tx_length_w:status_tx_length_w);

 v5n_shared_feature_memory_service #(.ADDR_W(ADDR_W),.DATA_W(DATA_W),.WORD_LSB_W(WORD_LSB_W),.FIXED_SPLIT_VIEWS(FIXED_SPLIT_VIEWS),.WRITE_LINE_ENABLE(1)) memory_service(.clk_i(clk_i),.rst_ni(rst_ni),
  .operator_memory_write_line_i(service_write_line_w),.operator_memory_write_line_data_i(service_write_line_data_w),
  .operator_read_line_valid_o(service_line_valid_w),.operator_read_line_address_o(service_line_address_w),
  .operator_read_line_data_o(service_line_data_w),.operator_line_invalidate_o(service_line_invalidate_w),
  .ingress_valid_i(fifo_valid_w),.ingress_ready_o(fifo_ready_w),.ingress_address_i(fifo_address_w),.ingress_data_i(fifo_data_w),.ingress_error_o(ingress_error_w),
  .operator_memory_valid_i(service_mem_valid_w),.operator_memory_ready_o(service_mem_ready_w),.operator_memory_write_i(service_mem_write_w),.operator_memory_address_i(service_mem_addr_w),.operator_memory_write_data_i(service_mem_wdata_w),
  .operator_memory_response_valid_o(service_mem_resp_valid_w),.operator_memory_response_ready_i(service_mem_resp_ready_w),.operator_memory_response_error_o(service_mem_resp_error_w),.operator_memory_response_is_write_o(service_mem_resp_write_w),.operator_memory_read_data_o(service_mem_rdata_w),
  .read_start_i(exec_read_start_w),.read_address_i(exec_read_address_w),.read_count_i(exec_read_count_mux_w),.read_ready_o(exec_read_ready_w),.read_busy_o(exec_read_busy_w),.read_done_o(exec_read_done_w),.read_data_valid_o(exec_read_valid_w),.read_data_ready_i(1'b1),.read_data_offset_o(exec_read_offset_w),.read_data_o(exec_read_data_w),.read_data_last_o(exec_read_last_w),
  .write_start_i(1'b0),.write_address_i(0),.write_count_i(0),.write_ready_o(),.write_busy_o(),.write_done_o(),.write_data_valid_i(1'b0),.write_data_ready_o(),.write_data_i(8'sd0),.write_data_last_i(1'b0),.exec_error_o(exec_error_w),
  .ddr_req_valid_o(ddr_req_valid_o),.ddr_req_ready_i(ddr_req_ready_i),.ddr_req_write_o(ddr_req_write_o),.ddr_req_word_address_o(ddr_req_word_address_o),.ddr_req_write_data_o(ddr_req_write_data_o),.ddr_req_write_strobe_o(ddr_req_write_strobe_o),.ddr_read_valid_i(ddr_read_valid_i),.ddr_read_ready_o(ddr_read_ready_o),.ddr_read_data_i(ddr_read_data_i),
  .debug_owner_o(memory_owner_w),.debug_adapter_state_o(memory_adapter_state_w));
endmodule
