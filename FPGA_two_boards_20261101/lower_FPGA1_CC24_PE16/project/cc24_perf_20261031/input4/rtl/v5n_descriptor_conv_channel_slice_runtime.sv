// Output-channel time-multiplexing wrapper for a descriptor-driven Conv.
//
// The frozen Round3 parameter cache is 16 KiB per bank.  Wide layers such as
// descriptor 17 contain more than 16 KiB of immutable weight bytes, so this
// runtime schedules bounded output-channel slices through the same single
// Conv engine/cache.  A channel slice is the outer loop and all adaptive
// spatial tiles are the inner loop, so the parameter cache loaded by the first
// tile is reused by every later tile in that slice.  It does not alter weights,
// quantization, descriptor ABI or parallel operator resources.
`include "v5n_weight_capacity.vh"
(* multstyle = "logic" *) module v5n_descriptor_conv_channel_slice_runtime #(
    parameter integer ADDR_W=32, parameter integer SHAPE_W=10,
    parameter integer NUM_PE=1,
    parameter integer LINE_PREFETCH=0,
    parameter integer WRITE_LINE_ENABLE=0,
    parameter integer SPATIAL_OUTER_HALO=2,
    parameter integer MAX_WEIGHT_SLICE_BYTES=`V5N_WEIGHT_CACHE_BYTES
) (
    input wire clk_i,input wire rst_ni,input wire start_i,
    input wire memory_line_valid_i,input wire [ADDR_W-1:0] memory_line_address_i,
    input wire [127:0] memory_line_data_i,input wire memory_line_invalidate_i,
    input wire descriptor_valid_i,input wire [7:0] descriptor_id_i,input wire [3:0] opcode_i,
    input wire [ADDR_W-1:0] source_tensor_base_i,input wire [SHAPE_W-1:0] input_h_i,input wire [SHAPE_W-1:0] input_w_i,input wire [SHAPE_W-1:0] input_c_i,
    input wire [ADDR_W-1:0] destination_tensor_base_i,input wire [SHAPE_W-1:0] output_h_i,input wire [SHAPE_W-1:0] output_w_i,input wire [SHAPE_W-1:0] output_c_i,
    input wire [3:0] kernel_h_i,input wire [3:0] kernel_w_i,input wire [3:0] stride_h_i,input wire [3:0] stride_w_i,input wire [3:0] pad_top_i,input wire [3:0] pad_left_i,input wire [5:0] requant_shift_i,
    input wire [ADDR_W-1:0] weight_address_i,input wire [ADDR_W-1:0] weight_bytes_per_output_i,
    input wire [ADDR_W-1:0] bias_address_i,input wire [ADDR_W-1:0] requant_address_i,
    input wire [SHAPE_W-1:0] max_slice_channels_i,
    input wire [SHAPE_W-1:0] tile_origin_y_i,input wire [SHAPE_W-1:0] tile_origin_x_i,input wire [SHAPE_W-1:0] tile_h_i,input wire [SHAPE_W-1:0] tile_w_i,
    output wire busy_o,output reg done_o,output reg error_o,output wire [3:0] state_o,output wire [31:0] cycle_count_o,
    output wire [SHAPE_W-1:0] channel_slice_o,
    output wire memory_valid_o,input wire memory_ready_i,output wire memory_write_o,output wire memory_use_hwc_o,output wire [ADDR_W-1:0] memory_raw_byte_address_o,output wire [ADDR_W-1:0] memory_tensor_base_o,
    output wire [SHAPE_W-1:0] memory_tensor_h_o,output wire [SHAPE_W-1:0] memory_tensor_w_o,output wire [SHAPE_W-1:0] memory_tensor_c_o,output wire [SHAPE_W-1:0] memory_y_o,output wire [SHAPE_W-1:0] memory_x_o,output wire [SHAPE_W-1:0] memory_channel_o,
    output wire signed [7:0] memory_write_data_o,input wire memory_response_valid_i,output wire memory_response_ready_o,input wire memory_response_error_i,input wire memory_response_is_write_i,input wire signed [7:0] memory_read_data_i
    ,output wire memory_write_line_o,output wire [127:0] memory_write_line_data_o,
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
    localparam [3:0] ST_IDLE=4'd0,ST_SLICE_START=4'd1,ST_SLICE_WAIT=4'd2,ST_DONE=4'd3,ST_FAIL=4'd4;
    reg [3:0] state_r;reg [SHAPE_W-1:0] slice_base_r;
    wire use_spatial_outer_w=SPATIAL_OUTER_HALO &&
      ((SPATIAL_OUTER_HALO==1)||((kernel_h_i==3)&&(kernel_w_i==3)));
    reg [SHAPE_W-1:0] spatial_y_r,spatial_x_r;
    reg [ADDR_W-1:0] slice_weight_offset_r;reg [31:0] cycle_r;
    wire [SHAPE_W:0] remaining_w={1'b0,output_c_i}-{1'b0,slice_base_r};
    wire [SHAPE_W-1:0] limited_channels_w=(remaining_w>{1'b0,max_slice_channels_i})?max_slice_channels_i:remaining_w[SHAPE_W-1:0];
    reg [SHAPE_W-1:0] slice_channels_r;
    always @* begin
      if(limited_channels_w>=64)slice_channels_r=64;
      else if(limited_channels_w>=32)slice_channels_r=32;
      else if(limited_channels_w>=16)slice_channels_r=16;
      else if(limited_channels_w>=8)slice_channels_r=8;
      else if(limited_channels_w>=4)slice_channels_r=4;
      else if(limited_channels_w>=2)slice_channels_r=2;
      else slice_channels_r=limited_channels_w;
    end
    wire [SHAPE_W-1:0] slice_channels_w=slice_channels_r;
    // Fixed graph channel slices are powers of two.  Decode the scale into a
    // shift and accumulate the byte offset between slices, avoiding two wide
    // address multipliers on the parameter/cache timing path.
    reg [ADDR_W-1:0] slice_weight_bytes_r;
    always @* begin
      case(slice_channels_w)
        10'd1:  slice_weight_bytes_r=weight_bytes_per_output_i;
        10'd2:  slice_weight_bytes_r=weight_bytes_per_output_i<<1;
        10'd4:  slice_weight_bytes_r=weight_bytes_per_output_i<<2;
        10'd8:  slice_weight_bytes_r=weight_bytes_per_output_i<<3;
        10'd16: slice_weight_bytes_r=weight_bytes_per_output_i<<4;
        10'd32: slice_weight_bytes_r=weight_bytes_per_output_i<<5;
        10'd64: slice_weight_bytes_r=weight_bytes_per_output_i<<6;
        default:slice_weight_bytes_r={ADDR_W{1'b0}};
      endcase
    end
    wire [ADDR_W-1:0] slice_weight_bytes_w=slice_weight_bytes_r;
    wire [ADDR_W-1:0] slice_bias_bytes_w=slice_channels_w<<2;
    wire [ADDR_W-1:0] slice_parameter_offset_w=slice_base_r<<2;
    wire [SHAPE_W-1:0] spatial_remaining_h_w=output_h_i-spatial_y_r;
    wire [SHAPE_W-1:0] spatial_remaining_w_w=output_w_i-spatial_x_r;
    wire [SHAPE_W-1:0] spatial_tile_h_w=(spatial_remaining_h_w>tile_h_i)?tile_h_i:spatial_remaining_h_w;
    wire [SHAPE_W-1:0] spatial_tile_w_w=(spatial_remaining_w_w>tile_w_i)?tile_w_i:spatial_remaining_w_w;
    wire spatial_last_w=(spatial_y_r+spatial_tile_h_w>=output_h_i)&&
                        (spatial_x_r+spatial_tile_w_w>=output_w_i);
    wire slice_busy_w,slice_done_w,slice_error_w;wire [3:0]slice_state_w;wire[31:0]slice_cycles_w;
    assign busy_o=(state_r!=ST_IDLE)&&(state_r!=ST_DONE)&&(state_r!=ST_FAIL);assign state_o=state_r;assign cycle_count_o=cycle_r;
    assign channel_slice_o=slice_base_r;
    v5n_descriptor_conv_tile_runtime #(.ADDR_W(ADDR_W),.SHAPE_W(SHAPE_W),.NUM_PE(NUM_PE),.SPATIAL_OUTER_HALO(SPATIAL_OUTER_HALO),.LINE_PREFETCH(LINE_PREFETCH),.WRITE_LINE_ENABLE(WRITE_LINE_ENABLE)) base_runtime(.rq_req_valid(rq_req_valid),.rq_req_ready(rq_req_ready),.rq_source0(rq_source0),.rq_source1(rq_source1),.rq_mult0(rq_mult0),.rq_mult1(rq_mult1),.rq_bias(rq_bias),.rq_shift0(rq_shift0),.rq_shift1(rq_shift1),.rq_rsp_valid(rq_rsp_valid),.rq_rsp_code(rq_rsp_code),.rq_rsp_error(rq_rsp_error),


      .memory_write_line_o(memory_write_line_o),.memory_write_line_data_o(memory_write_line_data_o),
      .memory_line_valid_i(memory_line_valid_i),.memory_line_address_i(memory_line_address_i),
      .memory_line_data_i(memory_line_data_i),.memory_line_invalidate_i(memory_line_invalidate_i),
      .clk_i(clk_i),.rst_ni(rst_ni),.start_i(state_r==ST_SLICE_START),.descriptor_valid_i(descriptor_valid_i),.descriptor_id_i(descriptor_id_i),.opcode_i(opcode_i),
      .source_tensor_base_i(source_tensor_base_i),.input_h_i(input_h_i),.input_w_i(input_w_i),.input_c_i(input_c_i),.destination_tensor_base_i(destination_tensor_base_i),.output_h_i(output_h_i),.output_w_i(output_w_i),.output_c_i(slice_channels_w),.destination_tensor_c_i(output_c_i),.destination_channel_offset_i(slice_base_r),
      .kernel_h_i(kernel_h_i),.kernel_w_i(kernel_w_i),.stride_h_i(stride_h_i),.stride_w_i(stride_w_i),.pad_top_i(pad_top_i),.pad_left_i(pad_left_i),.requant_shift_i(requant_shift_i),
      .weight_address_i(weight_address_i+slice_weight_offset_r),.weight_bytes_i(slice_weight_bytes_w),.bias_address_i(bias_address_i+slice_parameter_offset_w),.bias_bytes_i(slice_bias_bytes_w),.requant_address_i(requant_address_i+slice_parameter_offset_w),.requant_bytes_i(slice_bias_bytes_w),
      .tile_origin_y_i(spatial_y_r),.tile_origin_x_i(spatial_x_r),.tile_h_i(spatial_tile_h_w),.tile_w_i(spatial_tile_w_w),.busy_o(slice_busy_w),.done_o(slice_done_w),.error_o(slice_error_w),.state_o(slice_state_w),.cycle_count_o(slice_cycles_w),
      .memory_valid_o(memory_valid_o),.memory_ready_i(memory_ready_i),.memory_write_o(memory_write_o),.memory_use_hwc_o(memory_use_hwc_o),.memory_raw_byte_address_o(memory_raw_byte_address_o),.memory_tensor_base_o(memory_tensor_base_o),.memory_tensor_h_o(memory_tensor_h_o),.memory_tensor_w_o(memory_tensor_w_o),.memory_tensor_c_o(memory_tensor_c_o),.memory_y_o(memory_y_o),.memory_x_o(memory_x_o),.memory_channel_o(memory_channel_o),.memory_write_data_o(memory_write_data_o),.memory_response_valid_i(memory_response_valid_i),.memory_response_ready_o(memory_response_ready_o),.memory_response_error_i(memory_response_error_i),.memory_response_is_write_i(memory_response_is_write_i),.memory_read_data_i(memory_read_data_i));
    always@(posedge clk_i or negedge rst_ni)begin
      if(!rst_ni)begin state_r<=ST_IDLE;slice_base_r<=0;spatial_y_r<=0;spatial_x_r<=0;slice_weight_offset_r<=0;cycle_r<=0;done_o<=0;error_o<=0;end
      else begin
        done_o<=0;if(busy_o)cycle_r<=cycle_r+1'b1;
        case(state_r)
          ST_IDLE:if(start_i)begin cycle_r<=0;slice_base_r<=0;spatial_y_r<=tile_origin_y_i;spatial_x_r<=tile_origin_x_i;slice_weight_offset_r<=0;error_o<=0;
            // Do not validate slice_weight_bytes_w here: it is derived from
            // slice_base_r, which still contains the final slice of the
            // previous Conv until this clock edge.  A multi-slice layer
            // followed later by a narrower Conv could therefore see a zero
            // stale remainder and fail before the reset-to-zero took effect.
            // Validate the invariant that even a one-channel slice fits;
            // ST_SLICE_START then observes slice_base_r==0 and the parameter
            // loader checks the actual first and subsequent slice sizes.
            if(!descriptor_valid_i||opcode_i!=4'd1||output_h_i==0||output_w_i==0||output_c_i==0||tile_h_i==0||tile_w_i==0||max_slice_channels_i==0||max_slice_channels_i>64||weight_bytes_per_output_i==0||(weight_bytes_per_output_i>MAX_WEIGHT_SLICE_BYTES))begin error_o<=1;state_r<=ST_FAIL;end else state_r<=ST_SLICE_START;
          end
          ST_SLICE_START:state_r<=ST_SLICE_WAIT;
          ST_SLICE_WAIT:if(slice_error_w)begin error_o<=1;state_r<=ST_FAIL;end else if(slice_done_w)begin
            // Spatial outer loop keeps the exact source halo in bank0 while
            // all Cout slices compute into independent bank1. We explicitly
            // trade repeated weight loading for avoided scalar halo DMA.
            if(use_spatial_outer_w)begin
              if(slice_base_r+slice_channels_w>=output_c_i)begin
                if(spatial_last_w)state_r<=ST_DONE;
                else begin
                  slice_base_r<=0;slice_weight_offset_r<=0;
                  if(spatial_x_r+spatial_tile_w_w>=output_w_i)begin
                    spatial_x_r<=tile_origin_x_i;spatial_y_r<=spatial_y_r+spatial_tile_h_w;
                  end else spatial_x_r<=spatial_x_r+spatial_tile_w_w;
                  state_r<=ST_SLICE_START;
                end
              end else begin
                slice_base_r<=slice_base_r+slice_channels_w;
                slice_weight_offset_r<=slice_weight_offset_r+slice_weight_bytes_w;
                state_r<=ST_SLICE_START;
              end
            end else if(spatial_last_w)begin
              if(slice_base_r+slice_channels_w>=output_c_i)state_r<=ST_DONE;
              else begin
                slice_base_r<=slice_base_r+slice_channels_w;
                slice_weight_offset_r<=slice_weight_offset_r+slice_weight_bytes_w;
                spatial_y_r<=tile_origin_y_i;spatial_x_r<=tile_origin_x_i;
                state_r<=ST_SLICE_START;
              end
            end else begin
              if(spatial_x_r+spatial_tile_w_w>=output_w_i)begin
                spatial_x_r<=tile_origin_x_i;spatial_y_r<=spatial_y_r+spatial_tile_h_w;
              end else spatial_x_r<=spatial_x_r+spatial_tile_w_w;
              state_r<=ST_SLICE_START;
            end
          end
          ST_DONE:begin done_o<=1;state_r<=ST_IDLE;end
          default:state_r<=ST_FAIL;
        endcase
      end
    end
endmodule
