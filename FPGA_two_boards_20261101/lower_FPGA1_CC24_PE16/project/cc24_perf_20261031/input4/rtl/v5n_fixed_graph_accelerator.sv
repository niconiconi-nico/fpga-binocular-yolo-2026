// A2 classic-v5 fixed graph execution core. Actual scheduler/operator/cache
// instances, one sole shared-memory client. No Ethernet or DDR pin shell claim.
// PROTOTYPE until whole graph, TD/DRC/routed timing, and eligible board tests.
module v5n_fixed_graph_accelerator #(
    parameter integer NUM_PE=16,
    parameter [47:0] WATCHDOG_CYCLES=48'd60000000000
)(
    input wire clk_i,rst_ni,start_i,image_ready_i,
    input wire[31:0] feature_base_i,weight_base_i,bias_base_i,requant_base_i,lut_base_i,
    output wire busy_o,done_o,error_o,
    output wire[7:0] active_layer_o,output wire[8:0] detection_count_o,
    output wire[47:0] layer_cycle_count_o,total_cycle_count_o,
    output wire shared_memory_valid_o,input wire shared_memory_ready_i,
    output wire shared_memory_write_o,output wire[31:0] shared_memory_address_o,
    output wire signed[7:0] shared_memory_write_data_o,
    input wire shared_memory_response_valid_i,output wire shared_memory_response_ready_o,
    input wire shared_memory_response_error_i,shared_memory_response_is_write_i,
    input wire signed[7:0] shared_memory_read_data_i
);
    wire accept_w,operation_done_w,operation_error_w,scheduler_error_w;
    wire  operation_start_w;
    wire  operation_valid_w;
    wire [7:0] operation_node_id_w;
    wire [3:0] operation_opcode_w;
    wire [2:0] operation_source_count_w;
    wire [31:0] operation_sources_w;
    wire [7:0] operation_destination_w;
    wire [9:0] operation_input_h_w;
    wire [9:0] operation_input_w_w;
    wire [9:0] operation_input_c_w;
    wire [9:0] operation_output_h_w;
    wire [9:0] operation_output_w_w;
    wire [9:0] operation_output_c_w;
    wire [3:0] operation_kernel_h_w;
    wire [3:0] operation_kernel_w_w;
    wire [3:0] operation_stride_h_w;
    wire [3:0] operation_stride_w_w;
    wire [3:0] operation_pad_top_w;
    wire [3:0] operation_pad_left_w;
    wire [31:0] operation_weight_offset_w;
    wire [31:0] operation_weight_bytes_w;
    wire [31:0] operation_bias_offset_w;
    wire [31:0] operation_bias_bytes_w;
    wire [31:0] operation_requant_offset_w;
    wire [31:0] operation_requant_bytes_w;
    wire [31:0] operation_lut_offset_w;
    wire [31:0] operation_lut_bytes_w;
    wire [5:0] operation_conv_shift_w;
    wire signed [127:0] operation_source_multiplier_w;
    wire [23:0] operation_source_shift_w;
    wire [39:0] operation_source_channels_w;
    wire [7:0] operation_split_index_w;
    wire [7:0] operation_detect_stride_w;
    wire signed [7:0] operation_output_zero_point_w;
    v5n_fixed_graph_scheduler #(.WATCHDOG_CYCLES(WATCHDOG_CYCLES)) scheduler(
      .clk_i(clk_i),.rst_ni(rst_ni),.start_i(start_i),
      .operation_start_o(operation_start_w),
      .operation_valid_o(operation_valid_w),
      .operation_node_id_o(operation_node_id_w),
      .operation_opcode_o(operation_opcode_w),
      .operation_source_count_o(operation_source_count_w),
      .operation_sources_o(operation_sources_w),
      .operation_destination_o(operation_destination_w),
      .operation_input_h_o(operation_input_h_w),
      .operation_input_w_o(operation_input_w_w),
      .operation_input_c_o(operation_input_c_w),
      .operation_output_h_o(operation_output_h_w),
      .operation_output_w_o(operation_output_w_w),
      .operation_output_c_o(operation_output_c_w),
      .operation_kernel_h_o(operation_kernel_h_w),
      .operation_kernel_w_o(operation_kernel_w_w),
      .operation_stride_h_o(operation_stride_h_w),
      .operation_stride_w_o(operation_stride_w_w),
      .operation_pad_top_o(operation_pad_top_w),
      .operation_pad_left_o(operation_pad_left_w),
      .operation_weight_offset_o(operation_weight_offset_w),
      .operation_weight_bytes_o(operation_weight_bytes_w),
      .operation_bias_offset_o(operation_bias_offset_w),
      .operation_bias_bytes_o(operation_bias_bytes_w),
      .operation_requant_offset_o(operation_requant_offset_w),
      .operation_requant_bytes_o(operation_requant_bytes_w),
      .operation_lut_offset_o(operation_lut_offset_w),
      .operation_lut_bytes_o(operation_lut_bytes_w),
      .operation_conv_shift_o(operation_conv_shift_w),
      .operation_source_multiplier_o(operation_source_multiplier_w),
      .operation_source_shift_o(operation_source_shift_w),
      .operation_source_channels_o(operation_source_channels_w),
      .operation_split_index_o(operation_split_index_w),
      .operation_detect_stride_o(operation_detect_stride_w),
      .operation_output_zero_point_o(operation_output_zero_point_w),
      .operation_accept_i(accept_w),.operation_done_i(operation_done_w),.operation_error_i(operation_error_w),
      .busy_o(busy_o),.done_o(done_o),.error_o(scheduler_error_w),.active_layer_o(active_layer_o),
      .state_o(),.layer_cycle_count_o(layer_cycle_count_o),.total_cycle_count_o(total_cycle_count_o),
      .watchdog_timeout_o(),.operation_dilation_h_o(),.operation_groups_o());
    v5n_operator_service #(.NUM_PE(NUM_PE)) operator_service(
      .clk_i(clk_i),.rst_ni(rst_ni),
      .operation_start_i(operation_start_w),
      .operation_valid_i(operation_valid_w),
      .operation_node_id_i(operation_node_id_w),
      .operation_opcode_i(operation_opcode_w),
      .operation_source_count_i(operation_source_count_w),
      .operation_sources_i(operation_sources_w),
      .operation_destination_i(operation_destination_w),
      .operation_input_h_i(operation_input_h_w),
      .operation_input_w_i(operation_input_w_w),
      .operation_input_c_i(operation_input_c_w),
      .operation_output_h_i(operation_output_h_w),
      .operation_output_w_i(operation_output_w_w),
      .operation_output_c_i(operation_output_c_w),
      .operation_kernel_h_i(operation_kernel_h_w),
      .operation_kernel_w_i(operation_kernel_w_w),
      .operation_stride_h_i(operation_stride_h_w),
      .operation_stride_w_i(operation_stride_w_w),
      .operation_pad_top_i(operation_pad_top_w),
      .operation_pad_left_i(operation_pad_left_w),
      .operation_weight_offset_i(operation_weight_offset_w),
      .operation_weight_bytes_i(operation_weight_bytes_w),
      .operation_bias_offset_i(operation_bias_offset_w),
      .operation_bias_bytes_i(operation_bias_bytes_w),
      .operation_requant_offset_i(operation_requant_offset_w),
      .operation_requant_bytes_i(operation_requant_bytes_w),
      .operation_lut_offset_i(operation_lut_offset_w),
      .operation_lut_bytes_i(operation_lut_bytes_w),
      .operation_conv_shift_i(operation_conv_shift_w),
      .operation_source_multiplier_i(operation_source_multiplier_w),
      .operation_source_shift_i(operation_source_shift_w),
      .operation_source_channels_i(operation_source_channels_w),
      .operation_split_index_i(operation_split_index_w),
      .operation_detect_stride_i(operation_detect_stride_w),
      .operation_output_zero_point_i(operation_output_zero_point_w),
      .image_ready_i(image_ready_i),.feature_base_i(feature_base_i),.weight_base_i(weight_base_i),
      .bias_base_i(bias_base_i),.requant_base_i(requant_base_i),.lut_base_i(lut_base_i),
      .operation_accept_o(accept_w),.operation_done_o(operation_done_w),.operation_error_o(operation_error_w),
      .busy_o(),.detection_count_o(detection_count_o),.service_state_o(),.selected_runtime_o(),.selector_valid_o(),
      .illegal_selector_error_o(),.tile_x_o(),.tile_y_o(),.channel_slice_o(),.bridge_state_o(),
      .shared_memory_valid_o(shared_memory_valid_o),.shared_memory_ready_i(shared_memory_ready_i),
      .shared_memory_write_o(shared_memory_write_o),.shared_memory_address_o(shared_memory_address_o),
      .shared_memory_write_data_o(shared_memory_write_data_o),
      .shared_memory_response_valid_i(shared_memory_response_valid_i),
      .shared_memory_response_ready_o(shared_memory_response_ready_o),
      .shared_memory_response_error_i(shared_memory_response_error_i),
      .shared_memory_response_is_write_i(shared_memory_response_is_write_i),.shared_memory_read_data_i(shared_memory_read_data_i));
    assign error_o=scheduler_error_w|operation_error_w;
endmodule
