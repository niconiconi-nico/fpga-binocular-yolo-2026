// Single real CONV descriptor tile runtime.
//
// This is the data-side binding for one descriptor record read from the
// verified descriptor store. It deliberately handles the CONV record only:
// the following SILU record must run as a distinct descriptor transaction so
// tensor-1 (Conv output) remains observable and addressable in DDR.
`include "v5n_weight_capacity.vh"
(* multstyle = "logic" *) module v5n_descriptor_conv_tile_runtime #(
    parameter integer ADDR_W = 32,
    parameter integer SHAPE_W = 10,
    parameter integer NUM_PE = 4,
    parameter integer LINE_PREFETCH = 0,
    parameter integer WRITE_LINE_ENABLE = 0,
    parameter integer SPATIAL_OUTER_HALO = 0,
    // Must match the frozen Round3 feature ERAM bank capacity.  This guard
    // prevents an oversized halo from truncating its address and silently
    // overwriting the leading padding bytes.
    parameter integer FEATURE_TILE_BYTES = 16384
) (
    input wire clk_i, input wire rst_ni, input wire start_i,
    input wire memory_line_valid_i,input wire [ADDR_W-1:0] memory_line_address_i,
    input wire [127:0] memory_line_data_i,input wire memory_line_invalidate_i,
    input wire descriptor_valid_i, input wire [7:0] descriptor_id_i,
    input wire [3:0] opcode_i,
    input wire [ADDR_W-1:0] source_tensor_base_i,
    input wire [SHAPE_W-1:0] input_h_i,input wire [SHAPE_W-1:0] input_w_i,input wire [SHAPE_W-1:0] input_c_i,
    input wire [ADDR_W-1:0] destination_tensor_base_i,
    input wire [SHAPE_W-1:0] output_h_i,input wire [SHAPE_W-1:0] output_w_i,input wire [SHAPE_W-1:0] output_c_i,
    input wire [SHAPE_W-1:0] destination_tensor_c_i,input wire [SHAPE_W-1:0] destination_channel_offset_i,
    input wire [3:0] kernel_h_i,input wire [3:0] kernel_w_i,input wire [3:0] stride_h_i,input wire [3:0] stride_w_i,input wire [3:0] pad_top_i,input wire [3:0] pad_left_i,
    input wire [5:0] requant_shift_i,
    input wire [ADDR_W-1:0] weight_address_i,input wire [ADDR_W-1:0] weight_bytes_i,
    input wire [ADDR_W-1:0] bias_address_i,input wire [ADDR_W-1:0] bias_bytes_i,
    input wire [ADDR_W-1:0] requant_address_i,input wire [ADDR_W-1:0] requant_bytes_i,
    input wire [SHAPE_W-1:0] tile_origin_y_i,input wire [SHAPE_W-1:0] tile_origin_x_i,
    input wire [SHAPE_W-1:0] tile_h_i,input wire [SHAPE_W-1:0] tile_w_i,
    output wire busy_o,output reg done_o,output reg error_o,output wire [3:0] state_o,
    output wire [31:0] cycle_count_o,
    output wire memory_valid_o,input wire memory_ready_i,output wire memory_write_o,output wire memory_use_hwc_o,
    output wire [ADDR_W-1:0] memory_raw_byte_address_o,output wire [ADDR_W-1:0] memory_tensor_base_o,
    output wire [SHAPE_W-1:0] memory_tensor_h_o,memory_tensor_w_o,memory_tensor_c_o,memory_y_o,memory_x_o,memory_channel_o,
    output wire signed [7:0] memory_write_data_o,input wire memory_response_valid_i,output wire memory_response_ready_o,
    output wire memory_write_line_o,output wire [127:0] memory_write_line_data_o,
    input wire memory_response_error_i,input wire memory_response_is_write_i,input wire signed [7:0] memory_read_data_i,
output wire rq_req_valid,
input wire rq_req_ready,
output wire signed[31:0] rq_source0,
output wire signed[31:0] rq_source1,
output wire signed[31:0] rq_mult0,
output wire signed[31:0] rq_mult1,
output wire signed[31:0] rq_bias,
output wire[5:0] rq_shift0,
output wire[5:0] rq_shift1,
input wire rq_rsp_valid,
input wire signed[7:0] rq_rsp_code,
input wire rq_rsp_error
);
    localparam [3:0] ST_IDLE=4'd0,ST_PARAM_START=4'd1,ST_PARAM_WAIT=4'd2,ST_HALO_START=4'd3,ST_HALO_WAIT=4'd4,
                     ST_EXEC_START=4'd5,ST_EXEC_WAIT=4'd6,ST_WRITE_START=4'd7,ST_WRITE_WAIT=4'd8,ST_DONE=4'd9,ST_FAIL=4'd10;
    reg [3:0] state_r; reg [31:0] cycle_r; reg [ADDR_W-1:0] drain_offset_r;
    // Freeze the derived output byte count when a descriptor starts.  The
    // writer runs many cycles later, so recomputing this value from the live
    // descriptor shape on every drain cycle only creates a long, high-fanout
    // combinational path into drain_offset_r's clock enable.
    reg [ADDR_W-1:0] active_tile_bytes_r;
    // The parameter ERAMs survive between spatial tiles.  Tag their contents
    // so a repeated tile of the same descriptor/channel slice can begin with
    // the halo DMA instead of reloading identical weights, bias and requant
    // bytes from DDR.  Every field that affects the cached payload is part of
    // the match; a failed or replaced load invalidates the tag.
    reg parameter_tag_valid_r;
    // Never reuse across a new outer execution/frame: channel offset0 must
    // reload even if the source address and shape equal the preceding frame.
    // Runtime writes output bank1 only; source halo bank0 remains intact.
    localparam integer HALO_KEY_W=ADDR_W+8+7*SHAPE_W+24;
    wire [HALO_KEY_W-1:0] halo_key_w={source_tensor_base_i,descriptor_id_i,
      input_h_i,input_w_i,input_c_i,tile_origin_y_i,tile_origin_x_i,tile_h_i,tile_w_i,
      kernel_h_i,kernel_w_i,stride_h_i,stride_w_i,pad_top_i,pad_left_i};
    reg [HALO_KEY_W-1:0] halo_key_r;
    reg halo_tag_valid_r;
    wire halo_cache_hit_w=SPATIAL_OUTER_HALO && halo_tag_valid_r &&
      ((SPATIAL_OUTER_HALO==1)||((kernel_h_i==3)&&(kernel_w_i==3))) &&
      (destination_channel_offset_i!=0) && (halo_key_r==halo_key_w);
    reg [7:0] parameter_descriptor_id_r;
    reg [ADDR_W-1:0] parameter_weight_address_r,parameter_weight_bytes_r;
    reg [ADDR_W-1:0] parameter_bias_address_r,parameter_bias_bytes_r;
    reg [ADDR_W-1:0] parameter_requant_address_r,parameter_requant_bytes_r;
    reg [SHAPE_W-1:0] parameter_output_channels_r;
    wire parameter_cache_hit_w = parameter_tag_valid_r &&
        (parameter_descriptor_id_r == descriptor_id_i) &&
        (parameter_weight_address_r == weight_address_i) &&
        (parameter_weight_bytes_r == weight_bytes_i) &&
        (parameter_bias_address_r == bias_address_i) &&
        (parameter_bias_bytes_r == bias_bytes_i) &&
        (parameter_requant_address_r == requant_address_i) &&
        (parameter_requant_bytes_r == requant_bytes_i) &&
        (parameter_output_channels_r == output_c_i);
    wire param_busy,param_done,param_error,param_mvalid,param_mready,param_mresp_ready,param_wvalid,param_wready,param_wlast;
    wire [ADDR_W-1:0] param_maddr; wire [3:0] param_wlane; wire [14:0] param_woffset; wire [7:0] param_wdata;
    wire [9:0] executor_pindex; wire signed[31:0] executor_pmult,executor_pbias;
    wire halo_busy,halo_done,halo_error,halo_cache_valid,halo_cache_ready,halo_mvalid,halo_mready,halo_mresp_ready;
    wire [ADDR_W-1:0] halo_cache_offset,halo_tbase; wire signed[7:0] halo_cache_data;
    wire [SHAPE_W-1:0] halo_th,halo_tw,halo_tc,halo_y,halo_x,halo_c;
    wire exec_busy,exec_done,exec_error,exec_out_valid; wire [23:0] exec_feature_addr; wire signed[7:0] exec_feature_data;
    wire [NUM_PE*24-1:0] exec_weight_addr; wire signed[NUM_PE*8-1:0] exec_weight_data; wire [23:0] exec_out_addr; wire signed[7:0] exec_out_data;
    wire [13:0] cache_dest_read_addr = drain_offset_r[13:0]; wire [7:0] cache_dest_read_data;
    wire [7:0] feature_source_data; wire [1:0] cache_bank_valid; wire [NUM_PE*15-1:0] cache_weight_offsets; wire [NUM_PE*8-1:0] cache_weight_data;
    wire [((NUM_PE/2)>0 ? (NUM_PE/2)*27 : 1)-1:0] cache_packed_weight_data;
    wire writer_busy,writer_done,writer_error,writer_mvalid,writer_mready,writer_mresp_ready,writer_source_ready;
    wire [ADDR_W-1:0] writer_maddr; wire signed[7:0] writer_mdata;
    // Adaptive tiles range from 1 through 12.  Keep the small extent product
    // in shifts/adds and scale the resulting area by the power-of-two channel
    // slices used by the frozen graph.  This avoids two general configuration
    // multipliers on the runtime start/error path.
    function [13:0] small_extent_product;
        input [SHAPE_W-1:0] height_value;
        input [SHAPE_W-1:0] width_value;
        begin
            case (height_value)
                1:  small_extent_product = width_value;
                2:  small_extent_product = width_value << 1;
                3:  small_extent_product = (width_value << 1) + width_value;
                4:  small_extent_product = width_value << 2;
                5:  small_extent_product = (width_value << 2) + width_value;
                6:  small_extent_product = (width_value << 2) + (width_value << 1);
                7:  small_extent_product = (width_value << 3) - width_value;
                8:  small_extent_product = width_value << 3;
                9:  small_extent_product = (width_value << 3) + width_value;
                10: small_extent_product = (width_value << 3) + (width_value << 1);
                11: small_extent_product = (width_value << 3) + (width_value << 1) + width_value;
                12: small_extent_product = (width_value << 3) + (width_value << 2);
                default: small_extent_product = 14'd0;
            endcase
        end
    endfunction
    wire tile_shape_valid_w = (tile_h_i >= 1) && (tile_h_i <= 12) &&
                              (tile_w_i >= 1) && (tile_w_i <= 12);
    wire [13:0] tile_area_w = small_extent_product(tile_h_i,tile_w_i);
    reg [ADDR_W-1:0] tile_bytes_r;
    always @* begin
        case (output_c_i)
            1:  tile_bytes_r = tile_area_w;
            2:  tile_bytes_r = tile_area_w << 1;
            4:  tile_bytes_r = tile_area_w << 2;
            8:  tile_bytes_r = tile_area_w << 3;
            16: tile_bytes_r = tile_area_w << 4;
            32: tile_bytes_r = tile_area_w << 5;
            64: tile_bytes_r = tile_area_w << 6;
            default: tile_bytes_r = {ADDR_W{1'b0}};
        endcase
    end
    wire [ADDR_W-1:0] tile_bytes_w = tile_bytes_r;
    wire [SHAPE_W-1:0] tile_h_span_w = tile_h_i - 1'b1;
    wire [SHAPE_W-1:0] tile_w_span_w = tile_w_i - 1'b1;
    wire [SHAPE_W-1:0] local_h_w =
        {{(SHAPE_W-4){1'b0}},kernel_h_i} +
        ((stride_h_i == 2) ? (tile_h_span_w << 1) : tile_h_span_w);
    wire [SHAPE_W-1:0] local_w_w =
        {{(SHAPE_W-4){1'b0}},kernel_w_i} +
        ((stride_w_i == 2) ? (tile_w_span_w << 1) : tile_w_span_w);
    genvar g; generate for(g=0;g<NUM_PE;g=g+1) begin: G_WEIGHT_OFFSET
        assign cache_weight_offsets[g*15 +: 15] = exec_weight_addr[g*24 +: 15];
    end endgenerate
    assign exec_weight_data = cache_weight_data;
    assign exec_feature_data = $signed(feature_source_data);
    assign busy_o = (state_r != ST_IDLE) && (state_r != ST_DONE) && (state_r != ST_FAIL);
    assign state_o=state_r; assign cycle_count_o=cycle_r;

    v5n_conv_tile_parameter_loader #(.ADDR_W(ADDR_W),.NUM_PE(NUM_PE),.LINE_PREFETCH(LINE_PREFETCH)) parameters(
        .memory_line_valid_i(memory_line_valid_i),.memory_line_address_i(memory_line_address_i),
        .memory_line_data_i(memory_line_data_i),.memory_line_invalidate_i(memory_line_invalidate_i),
        .clk_i(clk_i),.rst_ni(rst_ni),.start_i(state_r==ST_PARAM_START),.weight_address_i(weight_address_i),.weight_bytes_i(weight_bytes_i),.bias_address_i(bias_address_i),.bias_bytes_i(bias_bytes_i),.requant_address_i(requant_address_i),.requant_bytes_i(requant_bytes_i),.output_channels_i(output_c_i),
        .busy_o(param_busy),.done_o(param_done),.error_o(param_error),.memory_valid_o(param_mvalid),.memory_ready_i(param_mready),.memory_raw_byte_address_o(param_maddr),.memory_response_valid_i(memory_response_valid_i),.memory_response_ready_o(param_mresp_ready),.memory_response_error_i(memory_response_error_i),.memory_read_data_i(memory_read_data_i),.weight_load_valid_o(param_wvalid),.weight_load_ready_i(param_wready),.weight_load_lane_o(param_wlane),.weight_load_offset_o(param_woffset),.weight_load_data_o(param_wdata),.weight_load_last_o(param_wlast),.parameter_index_i(executor_pindex),.parameter_multiplier_o(executor_pmult),.parameter_bias_o(executor_pbias));
    v5n_hwc_halo_tile_reader #(.ADDR_W(ADDR_W),.SHAPE_W(SHAPE_W),.LINE_PREFETCH(LINE_PREFETCH)) halo(
        .memory_line_valid_i(memory_line_valid_i),.memory_line_address_i(memory_line_address_i),
        .memory_line_data_i(memory_line_data_i),.memory_line_invalidate_i(memory_line_invalidate_i),
        .clk_i(clk_i),.rst_ni(rst_ni),.start_i(state_r==ST_HALO_START),.tensor_base_i(source_tensor_base_i),.input_h_i(input_h_i),.input_w_i(input_w_i),.input_c_i(input_c_i),.output_origin_y_i(tile_origin_y_i),.output_origin_x_i(tile_origin_x_i),.output_tile_h_i(tile_h_i),.output_tile_w_i(tile_w_i),.kernel_h_i(kernel_h_i),.kernel_w_i(kernel_w_i),.stride_h_i(stride_h_i),.stride_w_i(stride_w_i),.pad_top_i(pad_top_i),.pad_left_i(pad_left_i),.busy_o(halo_busy),.done_o(halo_done),.error_o(halo_error),.cache_valid_o(halo_cache_valid),.cache_ready_i(halo_cache_ready),.cache_offset_o(halo_cache_offset),.cache_data_o(halo_cache_data),.memory_valid_o(halo_mvalid),.memory_ready_i(halo_mready),.memory_tensor_base_o(halo_tbase),.memory_tensor_h_o(halo_th),.memory_tensor_w_o(halo_tw),.memory_tensor_c_o(halo_tc),.memory_y_o(halo_y),.memory_x_o(halo_x),.memory_c_o(halo_c),.memory_response_valid_i(memory_response_valid_i),.memory_response_ready_o(halo_mresp_ready),.memory_response_error_i(memory_response_error_i),.memory_read_data_i(memory_read_data_i));
    v5n_camera_paired_weight_cache #(.NUM_PE(NUM_PE),.TILE_BYTES(`V5N_WEIGHT_CACHE_BYTES),.ADDR_W(15),.CHANNEL_W(SHAPE_W)) parameter_cache(
        .read_packed_weight_o(cache_packed_weight_data),
        .clk_i(clk_i),.rst_ni(rst_ni),.compute_active_i(exec_busy),.compute_bank_i(1'b0),.read_offset_i(cache_weight_offsets),.read_weight_o(cache_weight_data),.active_channels_i(output_c_i),.load_begin_i(1'b0),.load_valid_i(param_wvalid),.load_ready_o(param_wready),.load_bank_i(1'b0),.load_lane_i(param_wlane),.load_offset_i(param_woffset),.load_data_i(param_wdata),.load_last_i(param_wlast),.bank_valid_o(cache_bank_valid));
    v5n_feature_tile_store_eram #(.TILE_BYTES(16384),.ADDR_W(14)) feature_cache(
        .clk_i(clk_i),.compute_active_i(exec_busy),.source_bank_i(1'b0),.source_addr_i(exec_feature_addr[13:0]),.source_data_o(feature_source_data),.destination_bank_i(1'b1),.destination_read_addr_i(cache_dest_read_addr),.destination_read_data_o(cache_dest_read_data),.destination_write_enable_i(exec_out_valid),.destination_write_addr_i(exec_out_addr[13:0]),.destination_write_data_i(exec_out_data),.dma_valid_i(halo_cache_valid),.dma_ready_o(halo_cache_ready),.dma_bank_i(1'b0),.dma_addr_i(halo_cache_offset[13:0]),.dma_data_i(halo_cache_data));
    v5n_conv_silu_tile_executor #(.NUM_PE(NUM_PE),.ADDR_W(24)) executor(.rq_req_valid(rq_req_valid),.rq_req_ready(rq_req_ready),.rq_source0(rq_source0),.rq_source1(rq_source1),.rq_mult0(rq_mult0),.rq_mult1(rq_mult1),.rq_bias(rq_bias),.rq_shift0(rq_shift0),.rq_shift1(rq_shift1),.rq_rsp_valid(rq_rsp_valid),.rq_rsp_code(rq_rsp_code),.rq_rsp_error(rq_rsp_error),

        .packed_weight_data_i(cache_packed_weight_data),
        .clk_i(clk_i),.rst_ni(rst_ni),.start_i(state_r==ST_EXEC_START),.cfg_output_origin_y_i(10'd0),.cfg_output_origin_x_i(10'd0),.cfg_tile_h_i(tile_h_i),.cfg_tile_w_i(tile_w_i),.cfg_input_h_i(local_h_w),.cfg_input_w_i(local_w_w),.cfg_input_c_i(input_c_i),.cfg_output_c_i(output_c_i),.cfg_kernel_h_i(kernel_h_i),.cfg_kernel_w_i(kernel_w_i),.cfg_stride_h_i(stride_h_i),.cfg_stride_w_i(stride_w_i),.cfg_pad_top_i(4'd0),.cfg_pad_left_i(4'd0),.cfg_requant_shift_i(requant_shift_i),.feature_read_offset_o(exec_feature_addr),.feature_read_data_i(exec_feature_data),.weight_read_offset_o(exec_weight_addr),.weight_read_data_i(exec_weight_data),.parameter_index_o(executor_pindex),.parameter_multiplier_i(executor_pmult),.parameter_bias_i(executor_pbias),.activation_enable_i(1'b0),.lut_cfg_write_enable_i(1'b0),.lut_cfg_address_i(8'd0),.lut_cfg_data_i(8'sd0),.output_write_valid_o(exec_out_valid),.output_write_offset_o(exec_out_addr),.output_write_data_o(exec_out_data),.busy_o(exec_busy),.done_o(exec_done),.error_o(exec_error),.cycle_count_o());
    wire writer_write_line_w;
    // The writer retains its gathered-line mode between tiles. Parameter and
    // halo reads must never inherit that stale write-only sideband: the shared
    // bridge correctly rejects a read marked as a full-line write.
    assign memory_write_line_o=(state_r==ST_WRITE_WAIT)&&writer_write_line_w;
    v5n_runtime_hwc_tile_write_dma #(.ADDR_W(ADDR_W),.SHAPE_W(SHAPE_W),.WRITE_LINE_ENABLE(WRITE_LINE_ENABLE)) writer(

        .memory_write_line_o(writer_write_line_w),.memory_write_line_data_o(memory_write_line_data_o),
        .clk_i(clk_i),.rst_ni(rst_ni),.start_i(state_r==ST_WRITE_START),.destination_tensor_base_i(destination_tensor_base_i),.output_w_i(output_w_i),.destination_tensor_c_i(destination_tensor_c_i),.source_c_i(output_c_i),.destination_channel_offset_i(destination_channel_offset_i),.tile_origin_y_i(tile_origin_y_i),.tile_origin_x_i(tile_origin_x_i),.tile_h_i(tile_h_i),.tile_w_i(tile_w_i),.busy_o(writer_busy),.done_o(writer_done),.error_o(writer_error),.source_valid_i(state_r==ST_WRITE_WAIT && drain_offset_r<active_tile_bytes_r),.source_ready_o(writer_source_ready),.source_data_i($signed(cache_dest_read_data)),.source_last_i(drain_offset_r+1>=active_tile_bytes_r),.memory_valid_o(writer_mvalid),.memory_ready_i(writer_mready),.memory_write_o(),.memory_raw_byte_address_o(writer_maddr),.memory_write_data_o(writer_mdata),.memory_response_valid_i(memory_response_valid_i),.memory_response_ready_o(writer_mresp_ready),.memory_response_error_i(memory_response_error_i),.memory_response_is_write_i(memory_response_is_write_i));

    assign memory_valid_o = (state_r==ST_PARAM_WAIT) ? param_mvalid : (state_r==ST_HALO_WAIT) ? halo_mvalid : (state_r==ST_WRITE_WAIT) ? writer_mvalid : 1'b0;
    assign memory_write_o = (state_r==ST_WRITE_WAIT) ? 1'b1 : 1'b0;
    assign memory_use_hwc_o = (state_r==ST_HALO_WAIT);
    assign memory_raw_byte_address_o = (state_r==ST_PARAM_WAIT) ? param_maddr : writer_maddr;
    assign memory_tensor_base_o=halo_tbase; assign memory_tensor_h_o=halo_th; assign memory_tensor_w_o=halo_tw; assign memory_tensor_c_o=halo_tc; assign memory_y_o=halo_y; assign memory_x_o=halo_x; assign memory_channel_o=halo_c;
    assign memory_write_data_o=writer_mdata;
    assign param_mready=(state_r==ST_PARAM_WAIT) ? memory_ready_i : 1'b0; assign halo_mready=(state_r==ST_HALO_WAIT) ? memory_ready_i : 1'b0; assign writer_mready=(state_r==ST_WRITE_WAIT) ? memory_ready_i : 1'b0;
    assign memory_response_ready_o=(state_r==ST_PARAM_WAIT)?param_mresp_ready:(state_r==ST_HALO_WAIT)?halo_mresp_ready:(state_r==ST_WRITE_WAIT)?writer_mresp_ready:1'b0;
    always @(posedge clk_i or negedge rst_ni) begin
        if(!rst_ni) begin
          state_r<=ST_IDLE;done_o<=0;error_o<=0;cycle_r<=0;drain_offset_r<=0;active_tile_bytes_r<=0;
          parameter_tag_valid_r<=0;parameter_descriptor_id_r<=0;
          halo_tag_valid_r<=0;halo_key_r<=0;
          parameter_weight_address_r<=0;parameter_weight_bytes_r<=0;
          parameter_bias_address_r<=0;parameter_bias_bytes_r<=0;
          parameter_requant_address_r<=0;parameter_requant_bytes_r<=0;
          parameter_output_channels_r<=0;
        end
        else begin done_o<=0; if(busy_o) cycle_r<=cycle_r+1'b1;
            case(state_r)
              ST_IDLE: if(start_i) begin cycle_r<=0;drain_offset_r<=0;active_tile_bytes_r<=tile_bytes_w;error_o<=0;
                if(destination_channel_offset_i==0)halo_tag_valid_r<=0;
                if(!descriptor_valid_i||opcode_i!=4'd1||!tile_shape_valid_w||
                   tile_bytes_w==0||tile_bytes_w>FEATURE_TILE_BYTES||
                   input_c_i==0||input_c_i>512||local_h_w==0||local_w_w==0||
                   local_h_w>15||local_w_w>15) begin
                  error_o<=1;state_r<=ST_FAIL;
                end else if(parameter_cache_hit_w) state_r<=halo_cache_hit_w?ST_EXEC_START:ST_HALO_START;
                else begin parameter_tag_valid_r<=0;state_r<=ST_PARAM_START;end
              end
              ST_PARAM_START: state_r<=ST_PARAM_WAIT;
              ST_PARAM_WAIT: if(param_error) begin parameter_tag_valid_r<=0;error_o<=1;state_r<=ST_FAIL;end
                else if(param_done) begin
                  parameter_tag_valid_r<=1;
                  parameter_descriptor_id_r<=descriptor_id_i;
                  parameter_weight_address_r<=weight_address_i;
                  parameter_weight_bytes_r<=weight_bytes_i;
                  parameter_bias_address_r<=bias_address_i;
                  parameter_bias_bytes_r<=bias_bytes_i;
                  parameter_requant_address_r<=requant_address_i;
                  parameter_requant_bytes_r<=requant_bytes_i;
                  parameter_output_channels_r<=output_c_i;
                  state_r<=halo_cache_hit_w?ST_EXEC_START:ST_HALO_START;
                end
              ST_HALO_START: state_r<=ST_HALO_WAIT;
              ST_HALO_WAIT: if(halo_error) begin halo_tag_valid_r<=0;error_o<=1;state_r<=ST_FAIL;end
                else if(halo_done)begin halo_tag_valid_r<=1;halo_key_r<=halo_key_w;state_r<=ST_EXEC_START;end
              ST_EXEC_START: state_r<=ST_EXEC_WAIT;
              ST_EXEC_WAIT: if(exec_error) begin error_o<=1;state_r<=ST_FAIL;end else if(exec_done) begin drain_offset_r<=0;state_r<=ST_WRITE_START;end
              ST_WRITE_START: state_r<=ST_WRITE_WAIT;
              ST_WRITE_WAIT: begin if(writer_error) begin error_o<=1;state_r<=ST_FAIL;end else if((state_r==ST_WRITE_WAIT)&&writer_source_ready&&(drain_offset_r<active_tile_bytes_r)) drain_offset_r<=drain_offset_r+1'b1; if(writer_done) state_r<=ST_DONE; end
              ST_DONE: begin done_o<=1;state_r<=ST_IDLE;end
              default: state_r<=ST_FAIL;
            endcase
        end
    end
endmodule
