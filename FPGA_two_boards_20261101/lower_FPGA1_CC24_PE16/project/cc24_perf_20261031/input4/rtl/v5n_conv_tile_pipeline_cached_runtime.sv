// Independent physical_friendly_v1: two input banks, one fixed output bank.
// Load overlaps compute/store; compute and store are mutually exclusive.
// Retain IFM descriptor through final physical writer ACK. Fresh own proofs required.
`include "v5n_weight_capacity.vh"
(* multstyle = "logic" *) module v5n_conv_tile_pipeline_cached_runtime #(
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
    // One fixed layer/channel-slice job; all layer configuration stays stable
    // through done/error. Command geometry is captured on tile_valid/ready.
    input wire clk_i, input wire rst_ni, input wire start_i,
    input wire tile_valid_i, output wire tile_ready_o, input wire tile_last_i,
    input wire [15:0] tile_id_i, input wire [31:0] frame_id_i,
    output reg tile_done_o, output reg [15:0] tile_done_id_o,
    output reg [31:0] result_frame_id_o,
    output wire [2:0] stage_active_o,
    output reg [31:0] load_compute_overlap_o, compute_store_overlap_o,
    output reg [31:0] triple_overlap_o,
    output reg [31:0] issued_tiles_o, committed_tiles_o,
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
    input wire memory_response_error_i,input wire memory_response_is_write_i,input wire signed [7:0] memory_read_data_i
);
    localparam [3:0] ST_IDLE=0,ST_REARM=1,ST_PARAM_START=2,ST_PARAM_WAIT=3,
                     ST_RUN=4,ST_DONE=5,ST_FAIL=6;
    localparam [1:0] PH_IDLE=0,PH_START=1,PH_WAIT=2;
    localparam [1:0] IF_FREE=0,IF_LOAD=1,IF_READY=2,IF_COMPUTE=3;
    localparam [1:0] OF_FREE=0,OF_COMPUTE=1,OF_READY=2,OF_STORE=3;
    localparam [1:0] OWNER_NONE=0,OWNER_PARAM=1,OWNER_HALO=2,OWNER_STORE=3;
    reg [3:0] state_r;
    reg [31:0] cycle_r;
    reg [1:0] load_phase_r,compute_phase_r,store_phase_r;
    reg [1:0] ifm_state_r[0:1];
    reg [1:0] ofm_state_r;
    reg [SHAPE_W-1:0] ifm_y_r[0:1],ifm_x_r[0:1],ifm_h_r[0:1],ifm_w_r[0:1];
    reg [15:0] ifm_id_r[0:1];
    reg [ADDR_W-1:0] drain_offset_r,active_tile_bytes_r;
    reg load_slot_r,next_ifm_r;
    reg compute_ifm_slot_r;
    reg last_seen_r;
    wire ownership_error_w;
    // Retain the parent's exact parameter-payload key, not a second weight bank.
    localparam integer PARAM_KEY_W=8+6*ADDR_W+SHAPE_W;
    wire [PARAM_KEY_W-1:0] parameter_key_w={descriptor_id_i,
        weight_address_i,weight_bytes_i,bias_address_i,bias_bytes_i,
        requant_address_i,requant_bytes_i,output_c_i};
    reg parameter_tag_valid_r;
    reg [PARAM_KEY_W-1:0] parameter_key_r;
    wire parameter_cache_hit_w=parameter_tag_valid_r&&parameter_key_r==parameter_key_w;
    // Bank tags name actual fully loaded bytes, including frame identity.
    // Offset0 always reloads, as in the original spatial-outer runtime.
    localparam integer HALO_JOB_KEY_W=32+ADDR_W+8+3*SHAPE_W+24;
    localparam integer HALO_TILE_KEY_W=4*SHAPE_W;
    // The layer configuration is stable for a job. Share its full identity,
    // never a hash/truncated key. Changing ANY header field invalidates both
    // banks at accepted start, before any tile can be accepted. This may evict
    // old-job bytes, but cannot return a false hit.
    wire [HALO_JOB_KEY_W-1:0] start_halo_job_key_w={frame_id_i,
        source_tensor_base_i,descriptor_id_i,input_h_i,input_w_i,input_c_i,
        kernel_h_i,kernel_w_i,stride_h_i,stride_w_i,pad_top_i,pad_left_i};
    reg [HALO_JOB_KEY_W-1:0] halo_job_key_r;
    wire [HALO_TILE_KEY_W-1:0] command_halo_key_w={
        tile_origin_y_i,tile_origin_x_i,tile_h_i,tile_w_i};
    wire [HALO_TILE_KEY_W-1:0] loaded_halo_key_w={
        ifm_y_r[load_slot_r],ifm_x_r[load_slot_r],ifm_h_r[load_slot_r],ifm_w_r[load_slot_r]};
    reg [HALO_TILE_KEY_W-1:0] halo_key_r[0:1];
    reg halo_tag_valid_r[0:1];
    // One accepted command owns the free slot until validation completes.
    // No halo tag, DMA, IF_READY or issued count commits before exact guards.
    reg [1:0] validation_phase_r;
    reg validation_slot_r,validation_last_r,validation_guard_r;
    reg validation_halo_allowed_r,validation_halo_hit_r;
    // Accepted payload lives once in its reserved/free IFM descriptor.
    wire [15:0] validation_id_r=ifm_id_r[validation_slot_r];
    wire [SHAPE_W-1:0] validation_y_r=ifm_y_r[validation_slot_r];
    wire [SHAPE_W-1:0] validation_x_r=ifm_x_r[validation_slot_r];
    wire [SHAPE_W-1:0] validation_h_r=ifm_h_r[validation_slot_r];
    wire [SHAPE_W-1:0] validation_w_r=ifm_w_r[validation_slot_r];
    reg [SHAPE_W-1:0] validation_local_h_r,validation_local_w_r,validation_input_c_r;
    wire [31:0] validation_area_r,validation_bytes_r,validation_output_bytes_w;
    wire validation_alu_done_w,validation_alu_busy_w;
    reg [ADDR_W-1:0] ifm_output_bytes_r[0:1];

    reg [HALO_TILE_KEY_W-1:0] validation_halo_key_r;
    reg [31:0] parameter_hits_r,halo_hits_r;
    wire child_rst_ni=rst_ni && state_r!=ST_REARM;
    wire [SHAPE_W-1:0] compute_local_h_w=kernel_h_i+
        ((stride_h_i==2)?((ifm_h_r[compute_ifm_slot_r]-1'b1)<<1):
                          (ifm_h_r[compute_ifm_slot_r]-1'b1));
    wire [SHAPE_W-1:0] compute_local_w_w=kernel_w_i+
        ((stride_w_i==2)?((ifm_w_r[compute_ifm_slot_r]-1'b1)<<1):
                          (ifm_w_r[compute_ifm_slot_r]-1'b1));
    // Physical request grant is held under backpressure. There is exactly one
    // accepted-but-unanswered request; response ownership is not recomputed
    // from current producer states or the next arbitration choice.
    reg grant_valid_r,pending_r,prefer_store_r;
    reg [1:0] grant_owner_r,response_owner_r;
    reg [1:0] choice_w;
    wire param_response_valid_w=memory_response_valid_i && pending_r && response_owner_r==OWNER_PARAM;
    wire halo_response_valid_w=memory_response_valid_i && pending_r && response_owner_r==OWNER_HALO;
    wire writer_response_valid_w=memory_response_valid_i && pending_r && response_owner_r==OWNER_STORE;
    wire param_busy,param_done,param_error,param_mvalid,param_mready,param_mresp_ready,param_wvalid,param_wready,param_wlast;
    wire [ADDR_W-1:0] param_maddr; wire [3:0] param_wlane; wire [13:0] param_woffset; wire [7:0] param_wdata;
    wire [9:0] executor_pindex; wire signed[31:0] executor_pmult,executor_pbias;
    wire halo_busy,halo_done,halo_error,halo_cache_valid,halo_cache_ready,halo_mvalid,halo_mready,halo_mresp_ready;
    wire [ADDR_W-1:0] halo_cache_offset,halo_tbase; wire signed[7:0] halo_cache_data;
    wire [SHAPE_W-1:0] halo_th,halo_tw,halo_tc,halo_y,halo_x,halo_c;
    wire exec_busy,exec_done,exec_error,exec_out_valid; wire [23:0] exec_feature_addr; wire signed[7:0] exec_feature_data;
    wire [NUM_PE*24-1:0] exec_weight_addr; wire signed[NUM_PE*8-1:0] exec_weight_data; wire [23:0] exec_out_addr; wire signed[7:0] exec_out_data;
    wire [13:0] cache_dest_read_addr = drain_offset_r[13:0]; wire [7:0] cache_dest_read_data;
    wire [7:0] feature_source_data; wire [1:0] cache_bank_valid; wire [NUM_PE*14-1:0] cache_weight_offsets; wire [NUM_PE*8-1:0] cache_weight_data;
    wire [(NUM_PE/2)*27-1:0] cache_packed_weight_data;
    wire writer_busy,writer_done,writer_error,writer_mvalid,writer_mready,writer_mresp_ready,writer_source_ready;
    wire [ADDR_W-1:0] writer_maddr; wire signed[7:0] writer_mdata;
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
    function [31:0] tile_output_bytes;
        input [SHAPE_W-1:0] h,w,c;
        reg [13:0] a;
        begin
            a=small_extent_product(h,w);
            case(c)
                1:tile_output_bytes=a;
                2:tile_output_bytes={18'd0,a}<<1;
                4:tile_output_bytes={18'd0,a}<<2;
                8:tile_output_bytes={18'd0,a}<<3;
                16:tile_output_bytes={18'd0,a}<<4;
                32:tile_output_bytes={18'd0,a}<<5;
                64:tile_output_bytes={18'd0,a}<<6;
                default:tile_output_bytes=0;
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
    assign busy_o=(state_r!=ST_IDLE)&&(state_r!=ST_DONE)&&(state_r!=ST_FAIL);
    assign state_o=state_r;
    assign cycle_count_o=cycle_r;
    // Keep the original SHAPE_W extent/addition and ADDR_W byte semantics.
    // Split only the capacity-product cone; arbitrary input channels remain legal.
    wire command_geometry_base_valid_w=descriptor_valid_i && opcode_i==4'd1 &&
        tile_shape_valid_w &&
        input_c_i!=0 && input_c_i<=512 && local_h_w!=0 && local_w_w!=0 &&
        local_h_w<=15 && local_w_w<=15 &&
        tile_origin_y_i+tile_h_i<=output_h_i && tile_origin_x_i+tile_w_i<=output_w_i;
    assign tile_ready_o=state_r==ST_RUN && !last_seen_r && validation_phase_r==0 && load_phase_r==PH_IDLE &&
                        ifm_state_r[load_slot_r]==IF_FREE;
    assign stage_active_o={store_phase_r!=PH_IDLE,compute_phase_r!=PH_IDLE,
                           state_r==ST_PARAM_START || state_r==ST_PARAM_WAIT || load_phase_r!=PH_IDLE || validation_phase_r!=0};
    genvar g; generate for(g=0;g<NUM_PE;g=g+1) begin:G_WEIGHT_OFFSET
        assign cache_weight_offsets[g*14+:14]=exec_weight_addr[g*24+:14];
    end endgenerate
    assign exec_weight_data=cache_weight_data;
    assign exec_feature_data=$signed(feature_source_data);
    v5n_tile_geometry_shared_alu #(.SHAPE_W(SHAPE_W)) geometry_alu(
        .clk_i(clk_i),.rst_ni(rst_ni && state_r==ST_RUN),
        .start_i(tile_valid_i && tile_ready_o),.local_h_i(local_h_w),.local_w_i(local_w_w),
        .input_c_i(input_c_i),.tile_h_i(tile_h_i),.tile_w_i(tile_w_i),.output_c_i(output_c_i),
        .busy_o(validation_alu_busy_w),.done_o(validation_alu_done_w),
        .area_o(validation_area_r),.capacity_o(validation_bytes_r),.output_bytes_o(validation_output_bytes_w));

    v5n_conv_tile_parameter_loader #(.ADDR_W(ADDR_W),.NUM_PE(NUM_PE),.LINE_PREFETCH(LINE_PREFETCH)) parameters(
        .memory_line_valid_i(memory_line_valid_i),.memory_line_address_i(memory_line_address_i),
        .memory_line_data_i(memory_line_data_i),.memory_line_invalidate_i(memory_line_invalidate_i),
        .clk_i(clk_i),.rst_ni(child_rst_ni),.start_i(state_r==ST_PARAM_START),.weight_address_i(weight_address_i),.weight_bytes_i(weight_bytes_i),.bias_address_i(bias_address_i),.bias_bytes_i(bias_bytes_i),.requant_address_i(requant_address_i),.requant_bytes_i(requant_bytes_i),.output_channels_i(output_c_i),
        .busy_o(param_busy),.done_o(param_done),.error_o(param_error),.memory_valid_o(param_mvalid),.memory_ready_i(param_mready),.memory_raw_byte_address_o(param_maddr),.memory_response_valid_i(param_response_valid_w),.memory_response_ready_o(param_mresp_ready),.memory_response_error_i(memory_response_error_i),.memory_read_data_i(memory_read_data_i),.weight_load_valid_o(param_wvalid),.weight_load_ready_i(param_wready),.weight_load_lane_o(param_wlane),.weight_load_offset_o(param_woffset),.weight_load_data_o(param_wdata),.weight_load_last_o(param_wlast),.parameter_index_i(executor_pindex),.parameter_multiplier_o(executor_pmult),.parameter_bias_o(executor_pbias));
    v5n_hwc_halo_tile_reader #(.ADDR_W(ADDR_W),.SHAPE_W(SHAPE_W),.LINE_PREFETCH(LINE_PREFETCH)) halo(
        .memory_line_valid_i(memory_line_valid_i),.memory_line_address_i(memory_line_address_i),
        .memory_line_data_i(memory_line_data_i),.memory_line_invalidate_i(memory_line_invalidate_i),
        .clk_i(clk_i),.rst_ni(child_rst_ni),.start_i(load_phase_r==PH_START),.tensor_base_i(source_tensor_base_i),.input_h_i(input_h_i),.input_w_i(input_w_i),.input_c_i(input_c_i),.output_origin_y_i(ifm_y_r[load_slot_r]),.output_origin_x_i(ifm_x_r[load_slot_r]),.output_tile_h_i(ifm_h_r[load_slot_r]),.output_tile_w_i(ifm_w_r[load_slot_r]),.kernel_h_i(kernel_h_i),.kernel_w_i(kernel_w_i),.stride_h_i(stride_h_i),.stride_w_i(stride_w_i),.pad_top_i(pad_top_i),.pad_left_i(pad_left_i),.busy_o(halo_busy),.done_o(halo_done),.error_o(halo_error),.cache_valid_o(halo_cache_valid),.cache_ready_i(halo_cache_ready),.cache_offset_o(halo_cache_offset),.cache_data_o(halo_cache_data),.memory_valid_o(halo_mvalid),.memory_ready_i(halo_mready),.memory_tensor_base_o(halo_tbase),.memory_tensor_h_o(halo_th),.memory_tensor_w_o(halo_tw),.memory_tensor_c_o(halo_tc),.memory_y_o(halo_y),.memory_x_o(halo_x),.memory_c_o(halo_c),.memory_response_valid_i(halo_response_valid_w),.memory_response_ready_o(halo_mresp_ready),.memory_response_error_i(memory_response_error_i),.memory_read_data_i(memory_read_data_i));
    v5n_paired_weight_cache #(.NUM_PE(NUM_PE),.TILE_BYTES(`V5N_WEIGHT_CACHE_BYTES),.ADDR_W(14),.CHANNEL_W(SHAPE_W)) parameter_cache(
        .read_packed_weight_o(cache_packed_weight_data),
        .clk_i(clk_i),.rst_ni(child_rst_ni),.compute_active_i(exec_busy),.compute_bank_i(1'b0),.read_offset_i(cache_weight_offsets),.read_weight_o(cache_weight_data),.active_channels_i(output_c_i),.load_begin_i(1'b0),.load_valid_i(param_wvalid),.load_ready_o(param_wready),.load_bank_i(1'b0),.load_lane_i(param_wlane),.load_offset_i(param_woffset),.load_data_i(param_wdata),.load_last_i(param_wlast),.bank_valid_o(cache_bank_valid));
    v5n_feature_tile_store_physical_friendly_eram #(.TILE_BYTES(FEATURE_TILE_BYTES),.ADDR_W(14)) feature_cache(
        .clk_i(clk_i),.compute_active_i(compute_phase_r!=PH_IDLE),
        .source_bank_i(compute_ifm_slot_r),.source_addr_i(exec_feature_addr[13:0]),
        .source_data_o(feature_source_data),
        .destination_write_enable_i(exec_out_valid),.destination_write_addr_i(exec_out_addr[13:0]),
        .destination_write_data_i(exec_out_data),
        .store_active_i(store_phase_r!=PH_IDLE),
        .store_read_addr_i(cache_dest_read_addr),.store_read_data_o(cache_dest_read_data),
        .dma_valid_i(halo_cache_valid),.dma_ready_o(halo_cache_ready),
        .dma_bank_i(load_slot_r),.dma_addr_i(halo_cache_offset[13:0]),
        .dma_data_i(halo_cache_data),.ownership_error_o(ownership_error_w));
    v5n_conv_silu_tile_executor #(.NUM_PE(NUM_PE),.ADDR_W(24)) executor(
        .packed_weight_data_i(cache_packed_weight_data),
        .clk_i(clk_i),.rst_ni(child_rst_ni),.start_i(compute_phase_r==PH_START),.cfg_output_origin_y_i(10'd0),.cfg_output_origin_x_i(10'd0),.cfg_tile_h_i(ifm_h_r[compute_ifm_slot_r]),.cfg_tile_w_i(ifm_w_r[compute_ifm_slot_r]),.cfg_input_h_i(compute_local_h_w),.cfg_input_w_i(compute_local_w_w),.cfg_input_c_i(input_c_i),.cfg_output_c_i(output_c_i),.cfg_kernel_h_i(kernel_h_i),.cfg_kernel_w_i(kernel_w_i),.cfg_stride_h_i(stride_h_i),.cfg_stride_w_i(stride_w_i),.cfg_pad_top_i(4'd0),.cfg_pad_left_i(4'd0),.cfg_requant_shift_i(requant_shift_i),.feature_read_offset_o(exec_feature_addr),.feature_read_data_i(exec_feature_data),.weight_read_offset_o(exec_weight_addr),.weight_read_data_i(exec_weight_data),.parameter_index_o(executor_pindex),.parameter_multiplier_i(executor_pmult),.parameter_bias_i(executor_pbias),.activation_enable_i(1'b0),.lut_cfg_write_enable_i(1'b0),.lut_cfg_address_i(8'd0),.lut_cfg_data_i(8'sd0),.output_write_valid_o(exec_out_valid),.output_write_offset_o(exec_out_addr),.output_write_data_o(exec_out_data),.busy_o(exec_busy),.done_o(exec_done),.error_o(exec_error),.cycle_count_o());
    wire writer_write_line_w;
    wire [127:0] writer_line_data_w;
    // Sideband belongs only to the selected write request, never a read.
    assign memory_write_line_o=memory_valid_o && memory_write_o && writer_write_line_w;
    assign memory_write_line_data_o=memory_write_o?writer_line_data_w:128'd0;
    v5n_runtime_hwc_tile_write_dma #(.ADDR_W(ADDR_W),.SHAPE_W(SHAPE_W),.WRITE_LINE_ENABLE(WRITE_LINE_ENABLE)) writer(
        .memory_write_line_o(writer_write_line_w),.memory_write_line_data_o(writer_line_data_w),
        .clk_i(clk_i),.rst_ni(child_rst_ni),.start_i(store_phase_r==PH_START),.destination_tensor_base_i(destination_tensor_base_i),.output_w_i(output_w_i),.destination_tensor_c_i(destination_tensor_c_i),.source_c_i(output_c_i),.destination_channel_offset_i(destination_channel_offset_i),.tile_origin_y_i(ifm_y_r[compute_ifm_slot_r]),.tile_origin_x_i(ifm_x_r[compute_ifm_slot_r]),.tile_h_i(ifm_h_r[compute_ifm_slot_r]),.tile_w_i(ifm_w_r[compute_ifm_slot_r]),.busy_o(writer_busy),.done_o(writer_done),.error_o(writer_error),.source_valid_i(store_phase_r==PH_WAIT && drain_offset_r<active_tile_bytes_r),.source_ready_o(writer_source_ready),.source_data_i($signed(cache_dest_read_data)),.source_last_i(drain_offset_r+1>=active_tile_bytes_r),.memory_valid_o(writer_mvalid),.memory_ready_i(writer_mready),.memory_write_o(),.memory_raw_byte_address_o(writer_maddr),.memory_write_data_o(writer_mdata),.memory_response_valid_i(writer_response_valid_w),.memory_response_ready_o(writer_mresp_ready),.memory_response_error_i(memory_response_error_i),.memory_response_is_write_i(memory_response_is_write_i));

    always @* begin
        choice_w=OWNER_NONE;
        if(state_r==ST_PARAM_WAIT && param_mvalid) choice_w=OWNER_PARAM;
        else if(state_r==ST_RUN) begin
            if(halo_mvalid && writer_mvalid) choice_w=prefer_store_r?OWNER_STORE:OWNER_HALO;
            else if(halo_mvalid) choice_w=OWNER_HALO;
            else if(writer_mvalid) choice_w=OWNER_STORE;
        end
    end
    wire selected_valid_w=grant_owner_r==OWNER_PARAM?param_mvalid:
                          grant_owner_r==OWNER_HALO?halo_mvalid:
                          grant_owner_r==OWNER_STORE?writer_mvalid:1'b0;
    assign memory_valid_o=grant_valid_r && !pending_r && selected_valid_w &&
                         (state_r==ST_PARAM_WAIT || state_r==ST_RUN);
    assign memory_write_o=grant_owner_r==OWNER_STORE;
    assign memory_use_hwc_o=grant_owner_r==OWNER_HALO;
    assign memory_raw_byte_address_o=grant_owner_r==OWNER_PARAM?param_maddr:
                                    grant_owner_r==OWNER_STORE?writer_maddr:0;
    assign memory_tensor_base_o=memory_use_hwc_o?halo_tbase:0;
    assign memory_tensor_h_o=memory_use_hwc_o?halo_th:0;
    assign memory_tensor_w_o=memory_use_hwc_o?halo_tw:0;
    assign memory_tensor_c_o=memory_use_hwc_o?halo_tc:0;
    assign memory_y_o=memory_use_hwc_o?halo_y:0;
    assign memory_x_o=memory_use_hwc_o?halo_x:0;
    assign memory_channel_o=memory_use_hwc_o?halo_c:0;
    assign memory_write_data_o=memory_write_o?writer_mdata:0;
    assign param_mready=memory_valid_o && grant_owner_r==OWNER_PARAM && memory_ready_i;
    assign halo_mready=memory_valid_o && grant_owner_r==OWNER_HALO && memory_ready_i;
    assign writer_mready=memory_valid_o && grant_owner_r==OWNER_STORE && memory_ready_i;
    assign memory_response_ready_o=pending_r &&
        (response_owner_r==OWNER_PARAM?param_mresp_ready:
         response_owner_r==OWNER_HALO?halo_mresp_ready:
         response_owner_r==OWNER_STORE?writer_mresp_ready:1'b0);
    always @(posedge clk_i or negedge rst_ni) begin
        if(!rst_ni)begin
            grant_valid_r<=0;pending_r<=0;prefer_store_r<=0;
            grant_owner_r<=OWNER_NONE;response_owner_r<=OWNER_NONE;
        end else begin
            if(!grant_valid_r && !pending_r && choice_w!=OWNER_NONE)begin
                grant_valid_r<=1;grant_owner_r<=choice_w;
            end
            if(memory_valid_o && memory_ready_i)begin
                grant_valid_r<=0;pending_r<=1;response_owner_r<=grant_owner_r;
                if(grant_owner_r==OWNER_HALO)prefer_store_r<=1;
                else if(grant_owner_r==OWNER_STORE)prefer_store_r<=0;
            end
            if(memory_response_valid_i && memory_response_ready_o)begin
                pending_r<=0;response_owner_r<=OWNER_NONE;
            end
            if(state_r==ST_FAIL && !pending_r)grant_valid_r<=0;
        end
    end

    integer k;
    always @(posedge clk_i or negedge rst_ni) begin
        if(!rst_ni)begin
            state_r<=ST_IDLE;done_o<=0;error_o<=0;cycle_r<=0;
            parameter_tag_valid_r<=0;parameter_key_r<=0;halo_job_key_r<=0;
            parameter_hits_r<=0;halo_hits_r<=0;
            validation_phase_r<=0;validation_slot_r<=0;validation_last_r<=0;
            validation_guard_r<=0;validation_halo_allowed_r<=0;validation_halo_hit_r<=0;
            validation_local_h_r<=0;validation_local_w_r<=0;validation_input_c_r<=0;
            validation_halo_key_r<=0;
            load_phase_r<=PH_IDLE;compute_phase_r<=PH_IDLE;store_phase_r<=PH_IDLE;
            load_slot_r<=0;next_ifm_r<=0;ofm_state_r<=OF_FREE;
            compute_ifm_slot_r<=0;
            drain_offset_r<=0;active_tile_bytes_r<=0;last_seen_r<=0;
            tile_done_o<=0;tile_done_id_o<=0;result_frame_id_o<=0;
            issued_tiles_o<=0;committed_tiles_o<=0;
            load_compute_overlap_o<=0;compute_store_overlap_o<=0;triple_overlap_o<=0;
            for(k=0;k<2;k=k+1)begin
                halo_tag_valid_r[k]<=0;halo_key_r[k]<=0;
                ifm_state_r[k]<=IF_FREE;
                ifm_output_bytes_r[k]<=0;
                ifm_y_r[k]<=0;ifm_x_r[k]<=0;ifm_h_r[k]<=0;ifm_w_r[k]<=0;ifm_id_r[k]<=0;
            end
        end else begin
            done_o<=0;tile_done_o<=0;
            if(busy_o)cycle_r<=cycle_r+1'b1;
            if(stage_active_o[0] && stage_active_o[1])load_compute_overlap_o<=load_compute_overlap_o+1'b1;
            if(stage_active_o[1] && stage_active_o[2])compute_store_overlap_o<=compute_store_overlap_o+1'b1;
            if(&stage_active_o)triple_overlap_o<=triple_overlap_o+1'b1;
            case(state_r)
                ST_IDLE,ST_FAIL:if(start_i && !pending_r && !grant_valid_r)begin
                    cycle_r<=0;error_o<=0;last_seen_r<=0;issued_tiles_o<=0;committed_tiles_o<=0;
                    validation_phase_r<=0;
                    load_compute_overlap_o<=0;compute_store_overlap_o<=0;triple_overlap_o<=0;
                    result_frame_id_o<=frame_id_i;
                    load_phase_r<=PH_IDLE;compute_phase_r<=PH_IDLE;store_phase_r<=PH_IDLE;
                    load_slot_r<=0;next_ifm_r<=0;ofm_state_r<=OF_FREE;
                    for(k=0;k<2;k=k+1)begin ifm_state_r[k]<=IF_FREE;end
                    halo_job_key_r<=start_halo_job_key_w;
                    if(destination_channel_offset_i==0 || halo_job_key_r!=start_halo_job_key_w)
                        for(k=0;k<2;k=k+1)halo_tag_valid_r[k]<=0;
                    if(state_r==ST_FAIL)begin
                        parameter_tag_valid_r<=0;
                        for(k=0;k<2;k=k+1)halo_tag_valid_r[k]<=0;
                        state_r<=ST_REARM;
                    end else if(parameter_cache_hit_w)begin
                        parameter_hits_r<=parameter_hits_r+1'b1;state_r<=ST_RUN;
                    end else begin parameter_tag_valid_r<=0;state_r<=ST_PARAM_START;end
                end
                ST_REARM:state_r<=ST_PARAM_START;
                ST_PARAM_START:begin parameter_tag_valid_r<=0;state_r<=ST_PARAM_WAIT;end
                ST_PARAM_WAIT:if(param_error)begin error_o<=1;state_r<=ST_FAIL;end
                    else if(param_done)begin
                        parameter_tag_valid_r<=1;parameter_key_r<=parameter_key_w;state_r<=ST_RUN;
                    end
                ST_RUN:begin
                    if(tile_valid_i && tile_ready_o)begin
                        // Capture moving tile payload and exact bank-local tile key
                        // once. The layer configuration contract remains stable.
                        validation_slot_r<=load_slot_r;validation_last_r<=tile_last_i;
                        ifm_id_r[load_slot_r]<=tile_id_i;
                        ifm_y_r[load_slot_r]<=tile_origin_y_i;ifm_x_r[load_slot_r]<=tile_origin_x_i;
                        ifm_h_r[load_slot_r]<=tile_h_i;ifm_w_r[load_slot_r]<=tile_w_i;
                        validation_local_h_r<=local_h_w;validation_local_w_r<=local_w_w;
                        validation_input_c_r<=input_c_i;
                        validation_guard_r<=command_geometry_base_valid_w;
                        validation_halo_key_r<=command_halo_key_w;
                        validation_halo_allowed_r<=SPATIAL_OUTER_HALO &&
                            ((SPATIAL_OUTER_HALO==1)||((kernel_h_i==3)&&(kernel_w_i==3))) &&
                            destination_channel_offset_i!=0;
                        validation_phase_r<=1;
                    end
                    if(validation_phase_r==1)begin
                        validation_halo_hit_r<=validation_halo_allowed_r &&
                            halo_tag_valid_r[validation_slot_r] &&
                            halo_key_r[validation_slot_r]==validation_halo_key_r;
                        // All four size products share one exact 32-bit ALU.
                        // No command commit or DMA before arithmetic finishes.
                        if(validation_alu_done_w)begin
                            validation_guard_r<=validation_guard_r &&
                                ADDR_W'(validation_output_bytes_w)!=0 &&
                                ADDR_W'(validation_output_bytes_w)<=FEATURE_TILE_BYTES;
                            validation_phase_r<=3;
                        end
                    end
                    if(validation_phase_r==3)begin
                        validation_phase_r<=0;
                        if(!validation_guard_r || validation_bytes_r>FEATURE_TILE_BYTES)begin
                            error_o<=1;state_r<=ST_FAIL;
                        end else begin
                            ifm_output_bytes_r[validation_slot_r]<=validation_output_bytes_w;
                            if(validation_halo_hit_r)begin
                                ifm_state_r[validation_slot_r]<=IF_READY;
                                load_slot_r<=~validation_slot_r;
                                halo_hits_r<=halo_hits_r+1'b1;
                            end else begin
                                // Exact validation precedes replacement and DMA.
                                halo_tag_valid_r[validation_slot_r]<=0;
                                ifm_state_r[validation_slot_r]<=IF_LOAD;
                                load_phase_r<=PH_START;
                            end
                            issued_tiles_o<=issued_tiles_o+1'b1;
                            if(validation_last_r)last_seen_r<=1;
                        end
                    end
                    if(load_phase_r==PH_START)load_phase_r<=PH_WAIT;
                    if(load_phase_r==PH_WAIT && halo_done)begin
                        halo_tag_valid_r[load_slot_r]<=1;halo_key_r[load_slot_r]<=loaded_halo_key_w;
                        ifm_state_r[load_slot_r]<=IF_READY;load_phase_r<=PH_IDLE;load_slot_r<=~load_slot_r;
                    end
                    // Single fixed OFM: no compute/store simultaneous ownership.
                    // Do not free the IFM descriptor on exec_done: writer needs
                    // its exact geometry/id until the last physical response.
                    if(compute_phase_r==PH_IDLE && store_phase_r==PH_IDLE &&
                       ofm_state_r==OF_FREE && ifm_state_r[next_ifm_r]==IF_READY)begin
                        compute_ifm_slot_r<=next_ifm_r;
                        ifm_state_r[next_ifm_r]<=IF_COMPUTE;ofm_state_r<=OF_COMPUTE;
                        compute_phase_r<=PH_START;next_ifm_r<=~next_ifm_r;
                    end
                    if(compute_phase_r==PH_START)compute_phase_r<=PH_WAIT;
                    if(compute_phase_r==PH_WAIT && exec_done)begin
                        ofm_state_r<=OF_READY;compute_phase_r<=PH_IDLE;
                    end
                    if(store_phase_r==PH_IDLE && ofm_state_r==OF_READY)begin
                        ofm_state_r<=OF_STORE;
                        active_tile_bytes_r<=ifm_output_bytes_r[compute_ifm_slot_r];drain_offset_r<=0;
                        store_phase_r<=PH_START;
                    end
                    if(store_phase_r==PH_START)store_phase_r<=PH_WAIT;
                    if(store_phase_r==PH_WAIT && writer_source_ready && drain_offset_r<active_tile_bytes_r)
                        drain_offset_r<=drain_offset_r+1'b1;
                    if(store_phase_r==PH_WAIT && writer_done)begin
                        ifm_state_r[compute_ifm_slot_r]<=IF_FREE;
                        ofm_state_r<=OF_FREE;store_phase_r<=PH_IDLE;
                        tile_done_o<=1;tile_done_id_o<=ifm_id_r[compute_ifm_slot_r];
                        committed_tiles_o<=committed_tiles_o+1'b1;
                    end
                    // Final completion is downstream of the writer's final real
                    // physical response, and all accepted tiles must retire.
                    if(last_seen_r && validation_phase_r==0 && issued_tiles_o==committed_tiles_o &&
                       load_phase_r==PH_IDLE && compute_phase_r==PH_IDLE && store_phase_r==PH_IDLE &&
                       !pending_r && !grant_valid_r)state_r<=ST_DONE;
                    if(halo_error || exec_error || writer_error || ownership_error_w)begin
                        validation_phase_r<=0;
                        parameter_tag_valid_r<=0;
                        for(k=0;k<2;k=k+1)halo_tag_valid_r[k]<=0;
                        error_o<=1;state_r<=ST_FAIL;
                    end
                end
                ST_DONE:begin done_o<=1;state_r<=ST_IDLE;end
                default:begin error_o<=1;state_r<=ST_FAIL;end
            endcase
        end
    end
endmodule
