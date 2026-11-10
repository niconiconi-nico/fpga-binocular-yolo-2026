// Fixed-graph execution service for the frozen classic YOLOv5n-320/VOC4 image.
//
// This is deliberately not a programmable NPU front end.  It accepts only
// the transactions emitted by v5n_fixed_graph_scheduler, resolves the
// frozen tensor map, tiles cache-based operators, and forwards every byte
// request through one v5n_operator_memory_bridge.
`include "v5n_weight_capacity.vh"
(* multstyle = "logic" *) module v5n_operator_service #(
    parameter integer ADDR_W = 32,
    parameter integer SHAPE_W = 10,
    parameter integer NUM_PE = 4,
    parameter integer FIXED_SPLIT_VIEWS = 0,
    parameter integer SILU_WRITE_LINE = 0,
    parameter integer CONV_WRITE_LINE = 0,
    parameter integer CONCAT_WRITE_LINE = 0,
    parameter integer ADD_WRITE_LINE = 1,
    parameter integer CONCAT_READ_LINE = 1
) (
    input wire clk_i, input wire rst_ni,
    input wire [31:0] frame_identity_i,
    input wire operation_start_i, input wire operation_valid_i,
    input wire [7:0] operation_node_id_i, input wire [3:0] operation_opcode_i,
    input wire [2:0] operation_source_count_i, input wire [31:0] operation_sources_i,
    input wire [7:0] operation_destination_i,
    input wire [9:0] operation_input_h_i, operation_input_w_i, operation_input_c_i,
    input wire [9:0] operation_output_h_i, operation_output_w_i, operation_output_c_i,
    input wire [3:0] operation_kernel_h_i, operation_kernel_w_i,
    input wire [3:0] operation_stride_h_i, operation_stride_w_i,
    input wire [3:0] operation_pad_top_i, operation_pad_left_i,
    input wire [31:0] operation_weight_offset_i, operation_weight_bytes_i,
    input wire [31:0] operation_bias_offset_i, operation_bias_bytes_i,
    input wire [31:0] operation_requant_offset_i, operation_requant_bytes_i,
    input wire [31:0] operation_lut_offset_i, operation_lut_bytes_i,
    input wire [5:0] operation_conv_shift_i,
    input wire signed [127:0] operation_source_multiplier_i,
    input wire [23:0] operation_source_shift_i,
    input wire [39:0] operation_source_channels_i,
    input wire [7:0] operation_split_index_i,
    input wire [7:0] operation_detect_stride_i,
    input wire signed [7:0] operation_output_zero_point_i,
    input wire image_ready_i,
    input wire [ADDR_W-1:0] feature_base_i, weight_base_i, bias_base_i,
    input wire [ADDR_W-1:0] requant_base_i, lut_base_i,
    output wire operation_accept_o, output reg operation_done_o,
    output reg operation_error_o, output wire busy_o,
    output wire [8:0] detection_count_o,
    output wire [2:0] service_state_o,
    output wire [3:0] selected_runtime_o,
    output wire selector_valid_o,
    output reg illegal_selector_error_o,
    output wire [9:0] tile_x_o, output wire [9:0] tile_y_o,
    output wire [9:0] channel_slice_o,
    output wire [2:0] bridge_state_o,

    // Sole memory client.  Connect directly to shared_feature_memory_service.
    output wire shared_memory_valid_o, input wire shared_memory_ready_i,
    output wire shared_memory_write_o, output wire [ADDR_W-1:0] shared_memory_address_o,
    output wire signed [7:0] shared_memory_write_data_o,
    output wire shared_memory_write_line_o,
    output wire [127:0] shared_memory_write_line_data_o,
    input wire shared_memory_response_valid_i, output wire shared_memory_response_ready_o,
    input wire shared_memory_response_error_i, input wire shared_memory_response_is_write_i,
    input wire signed [7:0] shared_memory_read_data_i,
    input wire shared_read_line_valid_i,
    input wire [ADDR_W-1:0] shared_read_line_address_i,
    input wire [127:0] shared_read_line_data_i,
    input wire shared_line_invalidate_i

);

    localparam [3:0] OP_INPUT=0, OP_CONV=1, OP_SILU=2, OP_SPLIT=3,
                     OP_ADD=4, OP_CONCAT=5, OP_POOL=6, OP_UPSAMPLE=7,
                     OP_V5_DECODE=8, OP_NMS=9;
    localparam [2:0] ST_IDLE=0, ST_LAUNCH=1, ST_RUN=2, ST_NEXT=3,
                     ST_DONE=4, ST_FAIL=5, ST_CONV_CONFIG=6;

    reg [2:0] state_r;
    reg [7:0] node_id_r, destination_r;
    reg [3:0] opcode_r, kernel_h_r, kernel_w_r, stride_h_r, stride_w_r,
              pad_top_r, pad_left_r;
    reg [2:0] source_count_r;
    reg [31:0] sources_r;
    reg [9:0] input_h_r,input_w_r,input_c_r,output_h_r,output_w_r,output_c_r;
    reg [31:0] weight_offset_r,weight_bytes_r,bias_offset_r,bias_bytes_r,
               requant_offset_r,requant_bytes_r,lut_offset_r,lut_bytes_r;
    reg [5:0] conv_shift_r;
    reg signed [127:0] source_multiplier_r;
    reg [23:0] source_shift_r;
    reg [39:0] source_channels_r;
    reg [7:0] split_index_r,detect_stride_r;
    reg [9:0] tile_y_r,tile_x_r;


 wire[2:0]rq_req_valid,rq_req_ready,rq_rsp_valid,rq_rsp_error;
 wire[95:0]rq_source0,rq_source1,rq_mult0,rq_mult1,rq_bias;
 wire[17:0]rq_shift0,rq_shift1;wire[23:0]rq_rsp_code;
 wire[1:0]rq_select_w=opcode_r==OP_CONV?0:opcode_r==OP_ADD?1:2;
 wire rq_selected_w=opcode_r==OP_CONV||opcode_r==OP_ADD||opcode_r==OP_CONCAT;
 wire requant_ready_w,requant_valid_w,requant_error_w;wire signed[7:0]requant_code_w;
 reg rq_owned_r;reg[1:0]rq_owner_r;
 wire[2:0]ctx_req_valid,ctx_req_ready,ctx_rsp_valid,ctx_rsp_ready;
 wire[8:0]ctx_mode;wire[1535:0]ctx_words;
 wire[1:0]ctx_select_w=opcode_r==OP_V5_DECODE?1:opcode_r==OP_NMS?2:0;
 reg ctx_loading_r,ctx_owned_r;reg[1:0]ctx_owner_r;reg numeric_owner_error_r;
 wire[1:0]ctx_active_w=ctx_loading_r?ctx_owner_r:ctx_select_w;
 wire vm_valid_w=!ctx_owned_r&&ctx_req_valid[ctx_active_w];wire vm_ready_w,vm_rsp_valid_w,vm_rsp_ready_w;
 wire[31:0]context_rsp_data;wire[2:0]context_rsp_index;wire context_rsp_last,context_rsp_error;
 assign rq_req_ready=(!rq_owned_r&&rq_selected_w&&requant_ready_w)?(3'b001<<rq_select_w):0;
 assign rq_rsp_valid=(rq_owned_r&&requant_valid_w)?(3'b001<<rq_owner_r):0;
 assign rq_rsp_code={3{requant_code_w}};assign rq_rsp_error={3{requant_error_w||numeric_owner_error_r}};
 // CC1: dedicated Conv/Add/Concat requant engine (bit-exact to numeric_context1
 // PC_CONV/PC_ADD/PC_CONCAT); the shared VM now serves Decode/NMS only.
 cc_requant_pipe shared_requant(
 .clk_i(clk_i),.rst_ni(rst_ni),.req_valid(!rq_owned_r&&rq_selected_w&&rq_req_valid[rq_select_w]),
 .req_ready(requant_ready_w),.req_mode(opcode_r==OP_CONV?2'd0:opcode_r==OP_ADD?2'd1:2'd2),
 .req_source0(rq_source0[rq_select_w*32+:32]),.req_source1(rq_source1[rq_select_w*32+:32]),
 .req_mult0(rq_mult0[rq_select_w*32+:32]),.req_mult1(rq_mult1[rq_select_w*32+:32]),
 .req_bias(rq_bias[rq_select_w*32+:32]),.req_zero(32'sd0),.req_qmin(-32'sd128),.req_qmax(32'sd127),
 .req_shift0(rq_shift0[rq_select_w*6+:6]),.req_shift1(rq_shift1[rq_select_w*6+:6]),
 .rsp_valid(requant_valid_w),.rsp_ready(rq_owned_r),.rsp_code(requant_code_w),.rsp_error(requant_error_w));
 assign ctx_req_valid[0]=1'b0;assign ctx_mode[0+:3]=3'd0;assign ctx_words[0+:512]=512'd0;assign ctx_rsp_ready[0]=1'b0;
 r10_numeric_context_vm local_context(
 .clk(clk_i),.rst_n(rst_ni),.req_valid(vm_valid_w),.req_ready(vm_ready_w),
 .req_mode(ctx_mode[ctx_active_w*3+:3]),.req_words(ctx_words[ctx_active_w*512+:512]),
 .rsp_valid(vm_rsp_valid_w),.rsp_ready(vm_rsp_ready_w),.rsp_data(context_rsp_data),.rsp_index(context_rsp_index),
 .rsp_last(context_rsp_last),.rsp_error(context_rsp_error));
 assign ctx_req_ready=(!ctx_owned_r&&vm_ready_w)?(3'b001<<ctx_active_w):0;
 assign ctx_rsp_valid=(ctx_owned_r&&vm_rsp_valid_w)?(3'b001<<ctx_owner_r):0;
 assign vm_rsp_ready_w=ctx_owned_r&&ctx_rsp_ready[ctx_owner_r];
 always @(posedge clk_i or negedge rst_ni)begin
  if(!rst_ni)begin rq_owned_r<=0;rq_owner_r<=0;ctx_loading_r<=0;ctx_owned_r<=0;ctx_owner_r<=0;numeric_owner_error_r<=0;end
  else begin
   if(|(rq_req_valid&rq_req_ready))begin rq_owned_r<=1;rq_owner_r<=rq_select_w;end
   if(rq_owned_r&&requant_valid_w)rq_owned_r<=0;
   // Reserve the source BEFORE serial context loading, accept only its last
   // word, retain owner across all8 Decode result words through LAST drain.
   if(!ctx_owned_r&&!ctx_loading_r&&vm_valid_w)begin ctx_loading_r<=1;ctx_owner_r<=ctx_select_w;end
   if(vm_valid_w&&vm_ready_w)begin ctx_loading_r<=0;ctx_owned_r<=1;ctx_owner_r<=ctx_active_w;end
   if(ctx_owned_r&&vm_rsp_valid_w&&vm_rsp_ready_w&&context_rsp_last)ctx_owned_r<=0;
   if((rq_owned_r&&(!rq_selected_w||rq_select_w!=rq_owner_r))||
      ((ctx_owned_r||ctx_loading_r)&&ctx_select_w!=ctx_owner_r))numeric_owner_error_r<=1;
  end
 end

    wire [7:0] source0_id_w=sources_r[7:0], source1_id_w=sources_r[15:8];
    wire [7:0] source2_id_w=sources_r[23:16], source3_id_w=sources_r[31:24];
    wire src0_valid_w,src1_valid_w,src2_valid_w,src3_valid_w,dst_valid_w;
    wire [ADDR_W-1:0] src0_offset_w,src1_offset_w,src2_offset_w,src3_offset_w,dst_offset_w;
    wire [ADDR_W-1:0] unused_size0_w,unused_size1_w,unused_size2_w,unused_size3_w,unused_sized_w;
    wire [9:0] src0_h_w,src0_w_w,src0_c_w,src1_h_w,src1_w_w,src1_c_w;
    wire [9:0] src2_h_w,src2_w_w,src2_c_w,src3_h_w,src3_w_w,src3_c_w;
    wire [9:0] dst_h_w,dst_w_w,dst_c_w;
    v5n_real_tensor_address_map m0(.tensor_id_i(source0_id_w),.valid_o(src0_valid_w),.base_offset_o(src0_offset_w),.data_size_o(unused_size0_w),.height_o(src0_h_w),.width_o(src0_w_w),.channels_o(src0_c_w));
    v5n_real_tensor_address_map m1(.tensor_id_i(source1_id_w),.valid_o(src1_valid_w),.base_offset_o(src1_offset_w),.data_size_o(unused_size1_w),.height_o(src1_h_w),.width_o(src1_w_w),.channels_o(src1_c_w));
    v5n_real_tensor_address_map m2(.tensor_id_i(source2_id_w),.valid_o(src2_valid_w),.base_offset_o(src2_offset_w),.data_size_o(unused_size2_w),.height_o(src2_h_w),.width_o(src2_w_w),.channels_o(src2_c_w));
    v5n_real_tensor_address_map m3(.tensor_id_i(source3_id_w),.valid_o(src3_valid_w),.base_offset_o(src3_offset_w),.data_size_o(unused_size3_w),.height_o(src3_h_w),.width_o(src3_w_w),.channels_o(src3_c_w));
    v5n_real_tensor_address_map md(.tensor_id_i(destination_r),.valid_o(dst_valid_w),.base_offset_o(dst_offset_w),.data_size_o(unused_sized_w),.height_o(dst_h_w),.width_o(dst_w_w),.channels_o(dst_c_w));
    wire [ADDR_W-1:0] src0_base_w=feature_base_i+src0_offset_w;
    wire [ADDR_W-1:0] src1_base_w=feature_base_i+src1_offset_w;
    wire [ADDR_W-1:0] src2_base_w=feature_base_i+src2_offset_w;
    wire [ADDR_W-1:0] src3_base_w=feature_base_i+src3_offset_w;
    wire [ADDR_W-1:0] dst_base_w=feature_base_i+dst_offset_w;
    wire effective_dst_valid_w=dst_valid_w;

    // Cache-safe adaptive convolution tiling.  The source feature bank holds
    // 16 KiB.  Select the largest square whose complete stride-expanded 3x3
    // halo fits for the current input-channel count.  A 1x1 kernel consumes
    // no more storage than this conservative bound.  Conv owns its full
    // spatial traversal, so tile_y_r/tile_x_r are zero for this calculation.
    reg [9:0] conv_tile_extent_r;
    always @* begin
      if(kernel_h_r==6 && kernel_w_r==6) begin
        // 6 + (5-1)*2 = 14; all3 channels fit the actual16KiB halo.
        conv_tile_extent_r=10'd5;
      end else if(stride_h_r==2 || stride_w_r==2) begin
        if(input_c_r<=64)conv_tile_extent_r=10'd7;
        else if(input_c_r<=128)conv_tile_extent_r=10'd5;
        else if(input_c_r<=256)conv_tile_extent_r=10'd3;
        else conv_tile_extent_r=10'd2;
      end else begin
        if(input_c_r<=64)conv_tile_extent_r=10'd12;
        else if(input_c_r<=128)conv_tile_extent_r=10'd9;
        else if(input_c_r<=256)conv_tile_extent_r=10'd6;
        else conv_tile_extent_r=10'd3;
      end
    end
    wire [9:0] conv_tile_h_w=(output_h_r>conv_tile_extent_r)?conv_tile_extent_r:output_h_r;
    wire [9:0] conv_tile_w_w=(output_w_r>conv_tile_extent_r)?conv_tile_extent_r:output_w_r;
    wire [9:0] split_tile_h_w=((output_h_r-tile_y_r)>4)?10'd4:(output_h_r-tile_y_r);
    wire [9:0] split_tile_w_w=((output_w_r-tile_x_r)>4)?10'd4:(output_w_r-tile_x_r);
    wire [9:0] silu_tile_h_w=((output_h_r-tile_y_r)>16)?10'd16:(output_h_r-tile_y_r);
    wire [9:0] silu_tile_w_w=((output_w_r-tile_x_r)>16)?10'd16:(output_w_r-tile_x_r);
    wire [9:0] active_tile_h_w=(opcode_r==OP_CONV)?conv_tile_h_w:(opcode_r==OP_SPLIT)?split_tile_h_w:silu_tile_h_w;
    wire [9:0] active_tile_w_w=(opcode_r==OP_CONV)?conv_tile_w_w:(opcode_r==OP_SPLIT)?split_tile_w_w:silu_tile_w_w;
    wire tile_last_w=(tile_y_r+active_tile_h_w>=output_h_r)&&(tile_x_r+active_tile_w_w>=output_w_r);
    // Every convolution in the frozen classic YOLOv5n graph has groups=1.  Deriving
    // this value from the static tensor geometry avoids synthesizing a 32-bit
    // divider merely to recover input_c*kernel_h*kernel_w.
    // This private classic-v5 graph contains 1x1, 3x3 and one6x6 Conv.  Express the
    // per-output-channel parameter span without a cascaded pair of generic
    // multipliers; this value remains exactly Cin or 9*Cin, respectively.
    wire [31:0] input_c_bytes_w={22'd0,input_c_r};
    wire [31:0] weight_bytes_per_output_comb_w=
      ((kernel_h_r==4'd3)&&(kernel_w_r==4'd3))?
        ((input_c_bytes_w<<3)+input_c_bytes_w):
      ((kernel_h_r==4'd6)&&(kernel_w_r==4'd6))?
        ((input_c_bytes_w<<5)+(input_c_bytes_w<<2)):input_c_bytes_w;
    reg [9:0] max_conv_slice_channels_comb_r;
    always @* begin
      if(weight_bytes_per_output_comb_w<=`V5N_WEIGHT_CACHE_BYTES/64)max_conv_slice_channels_comb_r=64;
      else if(weight_bytes_per_output_comb_w<=`V5N_WEIGHT_CACHE_BYTES/32)max_conv_slice_channels_comb_r=32;
      else if(weight_bytes_per_output_comb_w<=`V5N_WEIGHT_CACHE_BYTES/16)max_conv_slice_channels_comb_r=16;
      else if(weight_bytes_per_output_comb_w<=`V5N_WEIGHT_CACHE_BYTES/8)max_conv_slice_channels_comb_r=8;
      else if(weight_bytes_per_output_comb_w<=`V5N_WEIGHT_CACHE_BYTES/4)max_conv_slice_channels_comb_r=4;
      else if(weight_bytes_per_output_comb_w<=`V5N_WEIGHT_CACHE_BYTES/2)max_conv_slice_channels_comb_r=2;
      else max_conv_slice_channels_comb_r=1;
    end

    // Native11 final routed setup path: Cin -> span/capacity -> slice limit
    // -> slice advance -> spatial register enable. Cut only that configuration
    // cone before launching Conv. Captured descriptor stays unchanged; no DMA,
    // child start or acceptance of a second descriptor in this extra clock.
    reg [31:0] weight_bytes_per_output_r;
    reg [9:0] max_conv_slice_channels_r;
    wire [31:0] weight_bytes_per_output_w=weight_bytes_per_output_r;

    // Common memory ABI from each existing operator runtime.
    wire [8:0] op_mvalid_w,op_mwrite_w,op_mhwc_w,op_mresp_ready_w;
    wire [9*ADDR_W-1:0] op_mraw_w,op_mtbase_w;
    wire [9*SHAPE_W-1:0] op_mth_w,op_mtw_w,op_mtc_w,op_my_w,op_mx_w,op_mc_w;
    wire signed [9*8-1:0] op_mwdata_w;
    localparam [3:0] RUNTIME_COUNT=4'd9, RUNTIME_INVALID=4'hf;
    wire [8:0] runtime_done_w,runtime_error_w;
    reg [3:0] selected_runtime_r;
    always @* begin
        case(opcode_r)
          OP_CONV:selected_runtime_r=0; OP_SILU:selected_runtime_r=1;
          OP_SPLIT:selected_runtime_r=2; OP_ADD:selected_runtime_r=3;
          OP_CONCAT:selected_runtime_r=4; OP_POOL:selected_runtime_r=5;
          OP_UPSAMPLE:selected_runtime_r=6; OP_V5_DECODE:selected_runtime_r=7;
          OP_NMS:selected_runtime_r=8; default:selected_runtime_r=RUNTIME_INVALID;
        endcase
    end
    wire selector_valid_w=(selected_runtime_r<RUNTIME_COUNT);
    wire selected_mvalid_w=selector_valid_w?op_mvalid_w[selected_runtime_r]:1'b0;
    wire selected_mwrite_w=selector_valid_w?op_mwrite_w[selected_runtime_r]:1'b0;
    wire selected_mhwc_w=selector_valid_w?op_mhwc_w[selected_runtime_r]:1'b0;
    wire [ADDR_W-1:0] selected_mraw_w=selector_valid_w?op_mraw_w[selected_runtime_r*ADDR_W +: ADDR_W]:{ADDR_W{1'b0}};
    wire [ADDR_W-1:0] selected_mtbase_w=selector_valid_w?op_mtbase_w[selected_runtime_r*ADDR_W +: ADDR_W]:{ADDR_W{1'b0}};
    wire [SHAPE_W-1:0] selected_mth_w=selector_valid_w?op_mth_w[selected_runtime_r*SHAPE_W +: SHAPE_W]:{SHAPE_W{1'b0}};
    wire [SHAPE_W-1:0] selected_mtw_w=selector_valid_w?op_mtw_w[selected_runtime_r*SHAPE_W +: SHAPE_W]:{SHAPE_W{1'b0}};
    wire [SHAPE_W-1:0] selected_mtc_w=selector_valid_w?op_mtc_w[selected_runtime_r*SHAPE_W +: SHAPE_W]:{SHAPE_W{1'b0}};
    wire [SHAPE_W-1:0] selected_my_w=selector_valid_w?op_my_w[selected_runtime_r*SHAPE_W +: SHAPE_W]:{SHAPE_W{1'b0}};
    wire [SHAPE_W-1:0] selected_mx_w=selector_valid_w?op_mx_w[selected_runtime_r*SHAPE_W +: SHAPE_W]:{SHAPE_W{1'b0}};
    wire [SHAPE_W-1:0] selected_mc_w=selector_valid_w?op_mc_w[selected_runtime_r*SHAPE_W +: SHAPE_W]:{SHAPE_W{1'b0}};
    wire signed [7:0] selected_mwdata_w=selector_valid_w?op_mwdata_w[selected_runtime_r*8 +: 8]:8'sd0;
    wire selected_mresp_ready_w=selector_valid_w?op_mresp_ready_w[selected_runtime_r]:1'b0;
    wire bridge_ready_w,bridge_resp_valid_w,bridge_resp_error_w,bridge_resp_write_w;
    wire signed [7:0] bridge_read_data_w;
    wire bridge_line_valid_w,bridge_line_invalidate_w;
    wire [ADDR_W-1:0] bridge_line_address_w;
    wire [127:0] bridge_line_data_w;
    wire silu_write_line_w;wire[127:0]silu_write_line_data_w;
    wire conv_write_line_w;wire[127:0]conv_write_line_data_w;
    wire concat_write_line_w;wire[127:0]concat_write_line_data_w;
    wire add_write_line_w;wire[127:0]add_write_line_data_w;
    wire selected_write_line_w=(selected_runtime_r==0&&conv_write_line_w)||
                              (selected_runtime_r==1&&silu_write_line_w)||
                              (selected_runtime_r==3&&add_write_line_w)||
                              (selected_runtime_r==4&&concat_write_line_w);
    wire[127:0]selected_write_line_data_w=(selected_runtime_r==0)?
                               conv_write_line_data_w:(selected_runtime_r==3)?add_write_line_data_w:
                               (selected_runtime_r==4)?
                               concat_write_line_data_w:silu_write_line_data_w;

    v5n_operator_memory_bridge #(.ADDR_W(ADDR_W),.SHAPE_W(SHAPE_W),.WRITE_LINE_ENABLE(SILU_WRITE_LINE||CONV_WRITE_LINE||CONCAT_WRITE_LINE||ADD_WRITE_LINE)) bridge(

      .operator_memory_write_line_i(selected_write_line_w),
      .operator_memory_write_line_data_i(selected_write_line_data_w),
      .shared_memory_write_line_o(shared_memory_write_line_o),.shared_memory_write_line_data_o(shared_memory_write_line_data_o),
      .shared_read_line_valid_i(shared_read_line_valid_i),.shared_read_line_address_i(shared_read_line_address_i),
      .shared_read_line_data_i(shared_read_line_data_i),.shared_line_invalidate_i(shared_line_invalidate_i),
      .operator_read_line_valid_o(bridge_line_valid_w),.operator_read_line_address_o(bridge_line_address_w),
      .operator_read_line_data_o(bridge_line_data_w),.operator_line_invalidate_o(bridge_line_invalidate_w),
      .clk_i(clk_i),.rst_ni(rst_ni),.operator_id_i(selected_runtime_r),
      .operator_memory_valid_i(selected_mvalid_w),.operator_memory_ready_o(bridge_ready_w),
      .operator_memory_write_i(selected_mwrite_w),.operator_memory_use_hwc_i(selected_mhwc_w),
      .operator_memory_byte_enable_i(1'b1),.operator_memory_raw_byte_address_i(selected_mraw_w),
      .operator_memory_tensor_base_i(selected_mtbase_w),.operator_memory_tensor_h_i(selected_mth_w),
      .operator_memory_tensor_w_i(selected_mtw_w),.operator_memory_tensor_c_i(selected_mtc_w),
      .operator_memory_y_i(selected_my_w),.operator_memory_x_i(selected_mx_w),
      .operator_memory_channel_i(selected_mc_w),.operator_memory_write_data_i(selected_mwdata_w),
      .operator_memory_response_valid_o(bridge_resp_valid_w),.operator_memory_response_ready_i(selected_mresp_ready_w),
      .operator_memory_response_error_o(bridge_resp_error_w),.operator_memory_response_is_write_o(bridge_resp_write_w),
      .operator_memory_read_data_o(bridge_read_data_w),.shared_memory_valid_o(shared_memory_valid_o),
      .shared_memory_ready_i(shared_memory_ready_i),.shared_memory_write_o(shared_memory_write_o),
      .shared_memory_address_o(shared_memory_address_o),.shared_memory_write_data_o(shared_memory_write_data_o),
      .shared_memory_response_valid_i(shared_memory_response_valid_i),
      .shared_memory_response_ready_o(shared_memory_response_ready_o),
      .shared_memory_response_error_i(shared_memory_response_error_i),
      .shared_memory_response_is_write_i(shared_memory_response_is_write_i),
      .shared_memory_read_data_i(shared_memory_read_data_i),.active_operator_id_o(),.busy_o(),.state_o(bridge_state_o));

`define COMMON_MEMORY_PORTS(N) \
      .memory_valid_o(op_mvalid_w[N]),.memory_ready_i((selected_runtime_r==N)?bridge_ready_w:1'b0), \
      .memory_write_o(op_mwrite_w[N]),.memory_use_hwc_o(op_mhwc_w[N]), \
      .memory_raw_byte_address_o(op_mraw_w[N*ADDR_W +: ADDR_W]), \
      .memory_tensor_base_o(op_mtbase_w[N*ADDR_W +: ADDR_W]), \
      .memory_tensor_h_o(op_mth_w[N*SHAPE_W +: SHAPE_W]),.memory_tensor_w_o(op_mtw_w[N*SHAPE_W +: SHAPE_W]), \
      .memory_tensor_c_o(op_mtc_w[N*SHAPE_W +: SHAPE_W]),.memory_y_o(op_my_w[N*SHAPE_W +: SHAPE_W]), \
      .memory_x_o(op_mx_w[N*SHAPE_W +: SHAPE_W]),.memory_channel_o(op_mc_w[N*SHAPE_W +: SHAPE_W]), \
      .memory_write_data_o(op_mwdata_w[N*8 +: 8]), \
      .memory_response_valid_i((selected_runtime_r==N)?bridge_resp_valid_w:1'b0),.memory_response_ready_o(op_mresp_ready_w[N]), \
      .memory_response_error_i(bridge_resp_error_w),.memory_response_is_write_i(bridge_resp_write_w),.memory_read_data_i(bridge_read_data_w)

    wire launch_conv_w=(state_r==ST_LAUNCH)&&(opcode_r==OP_CONV);
    wire launch_silu_w=(state_r==ST_LAUNCH)&&(opcode_r==OP_SILU);
    wire launch_split_w=(state_r==ST_LAUNCH)&&(opcode_r==OP_SPLIT);
    wire launch_add_w=(state_r==ST_LAUNCH)&&(opcode_r==OP_ADD);
    wire launch_concat_w=(state_r==ST_LAUNCH)&&(opcode_r==OP_CONCAT);
    wire launch_pool_w=(state_r==ST_LAUNCH)&&(opcode_r==OP_POOL);
    wire launch_upsample_w=(state_r==ST_LAUNCH)&&(opcode_r==OP_UPSAMPLE);
    wire launch_classic_decode_w=(state_r==ST_LAUNCH)&&(opcode_r==OP_V5_DECODE);
    wire launch_nms_w=(state_r==ST_LAUNCH)&&(opcode_r==OP_NMS);

    wire [9:0] conv_channel_slice_w;
    v5n_descriptor_conv_channel_slice_runtime #(.ADDR_W(ADDR_W),.SHAPE_W(SHAPE_W),.NUM_PE(NUM_PE),.LINE_PREFETCH(1),.WRITE_LINE_ENABLE(CONV_WRITE_LINE)) conv(.rq_req_valid(rq_req_valid[0]),.rq_req_ready(rq_req_ready[0]),.rq_source0(rq_source0[0+:32]),.rq_source1(rq_source1[0+:32]),.rq_mult0(rq_mult0[0+:32]),.rq_mult1(rq_mult1[0+:32]),.rq_bias(rq_bias[0+:32]),.rq_shift0(rq_shift0[0+:6]),.rq_shift1(rq_shift1[0+:6]),.rq_rsp_valid(rq_rsp_valid[0]),.rq_rsp_code(rq_rsp_code[0+:8]),.rq_rsp_error(rq_rsp_error[0]),


      .memory_write_line_o(conv_write_line_w),.memory_write_line_data_o(conv_write_line_data_w),
      .memory_line_valid_i(bridge_line_valid_w),.memory_line_address_i(bridge_line_address_w),
      .memory_line_data_i(bridge_line_data_w),.memory_line_invalidate_i(bridge_line_invalidate_w),
      .clk_i(clk_i),.rst_ni(rst_ni),.start_i(launch_conv_w),.descriptor_valid_i(1'b1),.descriptor_id_i(node_id_r),.opcode_i(opcode_r),
      .source_tensor_base_i(src0_base_w),.input_h_i(input_h_r),.input_w_i(input_w_r),.input_c_i(input_c_r),
      .destination_tensor_base_i(dst_base_w),.output_h_i(output_h_r),.output_w_i(output_w_r),.output_c_i(output_c_r),
      .kernel_h_i(kernel_h_r),.kernel_w_i(kernel_w_r),
      .stride_h_i(stride_h_r),.stride_w_i(stride_w_r),.pad_top_i(pad_top_r),.pad_left_i(pad_left_r),
      .requant_shift_i(conv_shift_r),.weight_address_i(weight_base_i+weight_offset_r),.weight_bytes_per_output_i(weight_bytes_per_output_w),
      .bias_address_i(bias_base_i+bias_offset_r),.requant_address_i(requant_base_i+requant_offset_r),.max_slice_channels_i(max_conv_slice_channels_r),
      .tile_origin_y_i(tile_y_r),.tile_origin_x_i(tile_x_r),.tile_h_i(conv_tile_h_w),.tile_w_i(conv_tile_w_w),
      .busy_o(),.done_o(runtime_done_w[0]),.error_o(runtime_error_w[0]),.state_o(),.cycle_count_o(),.channel_slice_o(conv_channel_slice_w),`COMMON_MEMORY_PORTS(0));

    v5n_silu_read16_runtime #(.ADDR_W(ADDR_W),.SHAPE_W(SHAPE_W),.WRITE_LINE_ENABLE(SILU_WRITE_LINE)) silu(
      .memory_write_line_o(silu_write_line_w),.memory_write_line_data_o(silu_write_line_data_w),
      .memory_read_line_valid_i(bridge_line_valid_w),.memory_read_line_address_i(bridge_line_address_w),
      .memory_read_line_data_i(bridge_line_data_w),
      .clk_i(clk_i),.rst_ni(rst_ni),.start_i(launch_silu_w),.descriptor_valid_i(1'b1),.descriptor_id_i(node_id_r),.opcode_i(opcode_r),
      .source_tensor_base_i(src0_base_w),.destination_tensor_base_i(dst_base_w),.tensor_h_i(output_h_r),.tensor_w_i(output_w_r),.tensor_c_i(output_c_r),
      .lut_address_i(lut_base_i+lut_offset_r),.lut_bytes_i(lut_bytes_r),.tile_origin_y_i(tile_y_r),.tile_origin_x_i(tile_x_r),
      .tile_h_i(silu_tile_h_w),.tile_w_i(silu_tile_w_w),.busy_o(),.done_o(runtime_done_w[1]),.error_o(runtime_error_w[1]),.state_o(),.cycle_count_o(),`COMMON_MEMORY_PORTS(1));

    assign runtime_done_w[2]=0; assign runtime_error_w[2]=1;
    assign op_mvalid_w[2]=0;assign op_mwrite_w[2]=0;assign op_mhwc_w[2]=0;assign op_mresp_ready_w[2]=0;
    assign op_mraw_w[2*ADDR_W +: ADDR_W]=0;assign op_mtbase_w[2*ADDR_W +: ADDR_W]=0;
    assign op_mth_w[2*SHAPE_W +: SHAPE_W]=0;assign op_mtw_w[2*SHAPE_W +: SHAPE_W]=0;
    assign op_mtc_w[2*SHAPE_W +: SHAPE_W]=0;assign op_my_w[2*SHAPE_W +: SHAPE_W]=0;
    assign op_mx_w[2*SHAPE_W +: SHAPE_W]=0;assign op_mc_w[2*SHAPE_W +: SHAPE_W]=0;assign op_mwdata_w[2*8 +: 8]=0;

    v5n_add_read16_runtime #(.ADDR_W(ADDR_W),.SHAPE_W(SHAPE_W),.WRITE_LINE_ENABLE(ADD_WRITE_LINE)) add(.rq_req_valid(rq_req_valid[1]),.rq_req_ready(rq_req_ready[1]),.rq_source0(rq_source0[32+:32]),.rq_source1(rq_source1[32+:32]),.rq_mult0(rq_mult0[32+:32]),.rq_mult1(rq_mult1[32+:32]),.rq_bias(rq_bias[32+:32]),.rq_shift0(rq_shift0[6+:6]),.rq_shift1(rq_shift1[6+:6]),.rq_rsp_valid(rq_rsp_valid[1]),.rq_rsp_code(rq_rsp_code[8+:8]),.rq_rsp_error(rq_rsp_error[1]),

      .memory_write_line_o(add_write_line_w),.memory_write_line_data_o(add_write_line_data_w),
      .memory_read_line_valid_i(bridge_line_valid_w),.memory_read_line_address_i(bridge_line_address_w),
      .memory_read_line_data_i(bridge_line_data_w),
      .clk_i(clk_i),.rst_ni(rst_ni),.start_i(launch_add_w),.descriptor_valid_i(1'b1),.opcode_i(opcode_r),
      .source0_base_i(src0_base_w),.source1_base_i(src1_base_w),.destination_base_i(dst_base_w),
      .tensor_h_i(output_h_r),.tensor_w_i(output_w_r),.tensor_c_i(output_c_r),
      .source0_multiplier_i(source_multiplier_r[31:0]),.source0_shift_i(source_shift_r[5:0]),
      .source1_multiplier_i(source_multiplier_r[63:32]),.source1_shift_i(source_shift_r[11:6]),
      .busy_o(),.done_o(runtime_done_w[3]),.error_o(runtime_error_w[3]),.state_o(),.cycle_count_o(),`COMMON_MEMORY_PORTS(3));

    // Tensor-map byte extents are fixed-ROM data, not per-pixel multipliers.
    // Conservatively disable input-line streaming for any overlapping source
    // and destination span; scalar gather retains the original alias behavior.
    wire concat_alias_safe_w=
      (({1'b0,src0_offset_w}+{1'b0,unused_size0_w}<={1'b0,dst_offset_w})||
       ({1'b0,dst_offset_w}+{1'b0,unused_sized_w}<={1'b0,src0_offset_w}))&&
      ((source_count_r<2)||
       ({1'b0,src1_offset_w}+{1'b0,unused_size1_w}<={1'b0,dst_offset_w})||
       ({1'b0,dst_offset_w}+{1'b0,unused_sized_w}<={1'b0,src1_offset_w}))&&
      ((source_count_r<3)||
       ({1'b0,src2_offset_w}+{1'b0,unused_size2_w}<={1'b0,dst_offset_w})||
       ({1'b0,dst_offset_w}+{1'b0,unused_sized_w}<={1'b0,src2_offset_w}))&&
      ((source_count_r<4)||
       ({1'b0,src3_offset_w}+{1'b0,unused_size3_w}<={1'b0,dst_offset_w})||
       ({1'b0,dst_offset_w}+{1'b0,unused_sized_w}<={1'b0,src3_offset_w}));
    v5n_descriptor_concat_runtime #(.ADDR_W(ADDR_W),.SHAPE_W(SHAPE_W),.WRITE_LINE_ENABLE(CONCAT_WRITE_LINE),.READ_LINE_ENABLE(CONCAT_READ_LINE)) concat(.rq_req_valid(rq_req_valid[2]),.rq_req_ready(rq_req_ready[2]),.rq_source0(rq_source0[64+:32]),.rq_source1(rq_source1[64+:32]),.rq_mult0(rq_mult0[64+:32]),.rq_mult1(rq_mult1[64+:32]),.rq_bias(rq_bias[64+:32]),.rq_shift0(rq_shift0[12+:6]),.rq_shift1(rq_shift1[12+:6]),.rq_rsp_valid(rq_rsp_valid[2]),.rq_rsp_code(rq_rsp_code[16+:8]),.rq_rsp_error(rq_rsp_error[2]),

      .memory_read_line_valid_i(bridge_line_valid_w),.memory_read_line_address_i(bridge_line_address_w),
      .memory_read_line_data_i(bridge_line_data_w),.line_alias_safe_i(concat_alias_safe_w),
      .memory_write_line_o(concat_write_line_w),.memory_write_line_data_o(concat_write_line_data_w),
      .clk_i(clk_i),.rst_ni(rst_ni),.start_i(launch_concat_w),.descriptor_valid_i(1'b1),.opcode_i(opcode_r),.source_count_i(source_count_r),
      .source0_base_i(src0_base_w),.source1_base_i(src1_base_w),.source2_base_i(src2_base_w),.source3_base_i(src3_base_w),.destination_base_i(dst_base_w),
      .tensor_h_i(output_h_r),.tensor_w_i(output_w_r),.source0_channels_i(source_channels_r[9:0]),.source1_channels_i(source_channels_r[19:10]),
      .source2_channels_i(source_channels_r[29:20]),.source3_channels_i(source_channels_r[39:30]),.destination_channels_i(output_c_r),
      .source0_multiplier_i(source_multiplier_r[31:0]),.source0_shift_i(source_shift_r[5:0]),.source1_multiplier_i(source_multiplier_r[63:32]),.source1_shift_i(source_shift_r[11:6]),
      .source2_multiplier_i(source_multiplier_r[95:64]),.source2_shift_i(source_shift_r[17:12]),.source3_multiplier_i(source_multiplier_r[127:96]),.source3_shift_i(source_shift_r[23:18]),
      .busy_o(),.done_o(runtime_done_w[4]),.error_o(runtime_error_w[4]),.state_o(),.cycle_count_o(),`COMMON_MEMORY_PORTS(4));

    v5n_descriptor_maxpool_vector_runtime #(.ADDR_W(ADDR_W),.SHAPE_W(SHAPE_W)) pool(
      .clk_i(clk_i),.rst_ni(rst_ni),.start_i(launch_pool_w),.descriptor_valid_i(1'b1),.opcode_i(opcode_r),
      .source_base_i(src0_base_w),.destination_base_i(dst_base_w),.tensor_h_i(output_h_r),.tensor_w_i(output_w_r),.channels_i(output_c_r),
      .tile_origin_y_i(tile_y_r),.tile_origin_x_i(tile_x_r),.tile_h_i(silu_tile_h_w),.tile_w_i(silu_tile_w_w),
      .busy_o(),.done_o(runtime_done_w[5]),.error_o(runtime_error_w[5]),`COMMON_MEMORY_PORTS(5));

    v5n_descriptor_upsample_runtime #(.ADDR_W(ADDR_W),.SHAPE_W(SHAPE_W)) upsample(
      .clk_i(clk_i),.rst_ni(rst_ni),.start_i(launch_upsample_w),.descriptor_valid_i(1'b1),.opcode_i(opcode_r),
      .source_base_i(src0_base_w),.destination_base_i(dst_base_w),.input_h_i(input_h_r),.input_w_i(input_w_r),.channels_i(output_c_r),
      .output_h_i(output_h_r),.output_w_i(output_w_r),.tile_origin_y_i(tile_y_r),.tile_origin_x_i(tile_x_r),.tile_h_i(silu_tile_h_w),.tile_w_i(silu_tile_w_w),
      .busy_o(),.done_o(runtime_done_w[6]),.error_o(runtime_error_w[6]),`COMMON_MEMORY_PORTS(6));

    // Own anchor/objectness decode. bias_offset is an anchor LUT offset ONLY
    // for these three fixed opcode8 rows; no v8 DFL path is instantiated.
    v5n_head_memory_runtime #(.ADDR_W(ADDR_W),.SHAPE_W(SHAPE_W)) classic_decode(.context_req_valid(ctx_req_valid[1]),.context_req_ready(ctx_req_ready[1]),.context_mode(ctx_mode[3+:3]),.context_words(ctx_words[512+:512]),.context_rsp_valid(ctx_rsp_valid[1]),.context_rsp_ready(ctx_rsp_ready[1]),.context_rsp_data(context_rsp_data),.context_rsp_index(context_rsp_index),.context_rsp_last(context_rsp_last),.context_rsp_error(context_rsp_error||numeric_owner_error_r),

      .clk_i(clk_i),.rst_ni(rst_ni),.start_i(launch_classic_decode_w),
      .head_base_i(src0_base_w),.destination_base_i(dst_base_w),
      .sigmoid_base_i(lut_base_i+lut_offset_r),.anchor_base_i(lut_base_i+bias_offset_r),
      .tensor_h_i(input_h_r),.tensor_w_i(input_w_r),.stride_i(detect_stride_r[5:0]),
      .busy_o(),.done_o(runtime_done_w[7]),.error_o(runtime_error_w[7]),`COMMON_MEMORY_PORTS(7));

    v5n_nms_memory_runtime #(.ADDR_W(ADDR_W),.SHAPE_W(SHAPE_W)) nms(.context_req_valid(ctx_req_valid[2]),.context_req_ready(ctx_req_ready[2]),.context_mode(ctx_mode[6+:3]),.context_words(ctx_words[1024+:512]),.context_rsp_valid(ctx_rsp_valid[2]),.context_rsp_ready(ctx_rsp_ready[2]),.context_rsp_data(context_rsp_data),.context_rsp_index(context_rsp_index),.context_rsp_last(context_rsp_last),.context_rsp_error(context_rsp_error||numeric_owner_error_r),

      .clk_i(clk_i),.rst_ni(rst_ni),.start_i(launch_nms_w),.descriptor_valid_i(1'b1),.opcode_i(opcode_r),
      .feature_base_i(feature_base_i+32'd7813568),.destination_base_i(dst_base_w),
      .detection_count_o(detection_count_o),.busy_o(),.done_o(runtime_done_w[8]),.error_o(runtime_error_w[8]),`COMMON_MEMORY_PORTS(8));
`undef COMMON_MEMORY_PORTS

    assign operation_accept_o=(state_r==ST_IDLE)&&operation_start_i&&operation_valid_i;
    assign busy_o=(state_r!=ST_IDLE);
    assign service_state_o=state_r;
    assign selected_runtime_o=selected_runtime_r;
    assign selector_valid_o=selector_valid_w;
    assign tile_x_o=tile_x_r; assign tile_y_o=tile_y_r;
    assign channel_slice_o=(selected_runtime_r==4'd0)?conv_channel_slice_w:10'd0;
    wire selected_done_w=selector_valid_w?runtime_done_w[selected_runtime_r]:1'b0;
    wire selected_error_w=numeric_owner_error_r||(selector_valid_w?runtime_error_w[selected_runtime_r]:1'b1);
    // Conv owns its complete channel-slice-outer/spatial-tile-inner schedule;
    // the remaining cache-based operators are still tiled by this service.
    wire tiled_opcode_w=(opcode_r==OP_SILU)||(opcode_r==OP_SPLIT)||
                        (opcode_r==OP_POOL)||(opcode_r==OP_UPSAMPLE);
    wire sources_valid_w=src0_valid_w && ((source_count_r<2)||src1_valid_w) &&
                         ((source_count_r<3)||src2_valid_w) && ((source_count_r<4)||src3_valid_w);

    always @(posedge clk_i or negedge rst_ni) begin
      if(!rst_ni) begin
        weight_bytes_per_output_r<=0;max_conv_slice_channels_r<=0;
        state_r<=ST_IDLE; operation_done_o<=0; operation_error_o<=0; illegal_selector_error_o<=0; tile_y_r<=0; tile_x_r<=0;
        node_id_r<=0;destination_r<=0;opcode_r<=0;source_count_r<=0;sources_r<=0;
        input_h_r<=0;input_w_r<=0;input_c_r<=0;output_h_r<=0;output_w_r<=0;output_c_r<=0;
        kernel_h_r<=0;kernel_w_r<=0;stride_h_r<=0;stride_w_r<=0;pad_top_r<=0;pad_left_r<=0;
        weight_offset_r<=0;weight_bytes_r<=0;bias_offset_r<=0;bias_bytes_r<=0;requant_offset_r<=0;requant_bytes_r<=0;lut_offset_r<=0;lut_bytes_r<=0;
        conv_shift_r<=0;source_multiplier_r<=0;source_shift_r<=0;source_channels_r<=0;split_index_r<=0;detect_stride_r<=0;
      end else begin
        operation_done_o<=0;
        case(state_r)
          ST_IDLE: if(operation_start_i) begin
            operation_error_o<=0; tile_y_r<=0;tile_x_r<=0;
            node_id_r<=operation_node_id_i;destination_r<=operation_destination_i;opcode_r<=operation_opcode_i;source_count_r<=operation_source_count_i;sources_r<=operation_sources_i;
            input_h_r<=operation_input_h_i;input_w_r<=operation_input_w_i;input_c_r<=operation_input_c_i;output_h_r<=operation_output_h_i;output_w_r<=operation_output_w_i;output_c_r<=operation_output_c_i;
            kernel_h_r<=operation_kernel_h_i;kernel_w_r<=operation_kernel_w_i;stride_h_r<=operation_stride_h_i;stride_w_r<=operation_stride_w_i;pad_top_r<=operation_pad_top_i;pad_left_r<=operation_pad_left_i;
            weight_offset_r<=operation_weight_offset_i;weight_bytes_r<=operation_weight_bytes_i;bias_offset_r<=operation_bias_offset_i;bias_bytes_r<=operation_bias_bytes_i;
            requant_offset_r<=operation_requant_offset_i;requant_bytes_r<=operation_requant_bytes_i;lut_offset_r<=operation_lut_offset_i;lut_bytes_r<=operation_lut_bytes_i;
            conv_shift_r<=operation_conv_shift_i;source_multiplier_r<=operation_source_multiplier_i;source_shift_r<=operation_source_shift_i;source_channels_r<=operation_source_channels_i;split_index_r<=operation_split_index_i;detect_stride_r<=operation_detect_stride_i;
            if(!operation_valid_i) begin operation_error_o<=1;state_r<=ST_FAIL;end
            else if(operation_opcode_i==OP_INPUT) begin state_r<=image_ready_i?ST_DONE:ST_FAIL; if(!image_ready_i)operation_error_o<=1;end
            else if(operation_opcode_i==OP_CONV) state_r<=ST_CONV_CONFIG;
            else if(operation_opcode_i<=OP_NMS && operation_opcode_i!=OP_SPLIT) state_r<=ST_LAUNCH;
            else begin operation_error_o<=1;state_r<=ST_FAIL;end
          end
          ST_CONV_CONFIG: begin
            weight_bytes_per_output_r<=weight_bytes_per_output_comb_w;
            max_conv_slice_channels_r<=max_conv_slice_channels_comb_r;
            state_r<=ST_LAUNCH;
          end
          ST_LAUNCH: begin
            if(!selector_valid_w) begin operation_error_o<=1;illegal_selector_error_o<=1;state_r<=ST_FAIL;end
            else if(((opcode_r!=OP_NMS)&&!sources_valid_w)||!effective_dst_valid_w||output_h_r==0||output_w_r==0||output_c_r==0||
               ((opcode_r==OP_CONV)&&!(((kernel_h_r==1)&&(kernel_w_r==1))||((kernel_h_r==3)&&(kernel_w_r==3))||((kernel_h_r==6)&&(kernel_w_r==6))))) begin operation_error_o<=1;state_r<=ST_FAIL;end
            else state_r<=ST_RUN;
          end
          ST_RUN: if(selected_error_w) begin operation_error_o<=1;state_r<=ST_FAIL;end
                  else if(selected_done_w) state_r<=tiled_opcode_w?(tile_last_w?ST_DONE:ST_NEXT):ST_DONE;
          ST_NEXT: begin
            if(tile_x_r+active_tile_w_w>=output_w_r) begin tile_x_r<=0;tile_y_r<=tile_y_r+active_tile_h_w;end
            else tile_x_r<=tile_x_r+active_tile_w_w;
            state_r<=ST_LAUNCH;
          end
          ST_DONE: begin operation_done_o<=1;state_r<=ST_IDLE;end
          ST_FAIL: begin operation_error_o<=1;state_r<=ST_IDLE;end
          default: begin operation_error_o<=1;state_r<=ST_FAIL;end
        endcase
      end
    end
endmodule
