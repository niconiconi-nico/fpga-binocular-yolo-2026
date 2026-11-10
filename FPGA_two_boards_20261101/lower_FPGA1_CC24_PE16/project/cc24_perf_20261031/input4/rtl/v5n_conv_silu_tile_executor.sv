// Cache-facing wrapper for the frozen four-PE Conv and runtime-programmable
// SiLU. It serializes the four output lanes into the existing single-byte
// Feature ERAM write port; no result data is synthesized or preloaded here.
(* multstyle = "logic" *) module v5n_conv_silu_tile_executor #(
    parameter integer NUM_PE = 4, parameter integer COORD_W = 10,
    parameter integer CHANNEL_W = 10, parameter integer ADDR_W = 24
) (
    input wire clk_i,input wire rst_ni,input wire start_i,
    input wire [COORD_W-1:0] cfg_output_origin_y_i,cfg_output_origin_x_i,cfg_tile_h_i,cfg_tile_w_i,
    input wire [COORD_W-1:0] cfg_input_h_i,cfg_input_w_i,
    input wire [CHANNEL_W-1:0] cfg_input_c_i,cfg_output_c_i,
    input wire [3:0] cfg_kernel_h_i,cfg_kernel_w_i,cfg_stride_h_i,cfg_stride_w_i,cfg_pad_top_i,cfg_pad_left_i,
    input wire [5:0] cfg_requant_shift_i,
    output wire [ADDR_W-1:0] feature_read_offset_o,input wire signed [7:0] feature_read_data_i,
    output wire [NUM_PE*ADDR_W-1:0] weight_read_offset_o,input wire signed [NUM_PE*8-1:0] weight_read_data_i,
    input wire [((NUM_PE/2)>0 ? (NUM_PE/2)*27 : 1)-1:0] packed_weight_data_i,
    output wire [CHANNEL_W-1:0] parameter_index_o,input wire signed [31:0] parameter_multiplier_i,parameter_bias_i,
    // A CONV descriptor writes its requantized tensor unchanged; the following
    // SILU descriptor owns LUT activation. Set activation_enable_i only for a
    // deliberately fused transaction whose descriptor contract permits it.
    input wire activation_enable_i,
    input wire lut_cfg_write_enable_i,input wire [7:0] lut_cfg_address_i,input wire signed [7:0] lut_cfg_data_i,
    output wire output_write_valid_o,(* multstyle = "logic" *) output wire [ADDR_W-1:0] output_write_offset_o,output wire signed [7:0] output_write_data_o,
    output reg busy_o,output reg done_o,output reg error_o,output reg [31:0] cycle_count_o,
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
    wire requant_error_o;
    wire conv_busy_w,conv_done_w,conv_output_valid_w; wire [COORD_W-1:0] conv_y_w,conv_x_w; wire [CHANNEL_W-1:0] conv_channel_w;
    wire signed [NUM_PE*8-1:0] conv_data_w; wire [NUM_PE-1:0] conv_lane_valid_w;
    wire lut_valid_w; wire signed [NUM_PE*8-1:0] lut_data_w;
    wire vector_valid_w = activation_enable_i ? lut_valid_w : conv_output_valid_w;
    wire signed [NUM_PE*8-1:0] vector_data_w = activation_enable_i ? lut_data_w : conv_data_w;
    reg [COORD_W-1:0] meta_y_r,meta_x_r; reg [CHANNEL_W-1:0] meta_channel_r; reg [NUM_PE-1:0] meta_valid_r;
    localparam integer SERIAL_LANE_W = (NUM_PE>1 ? $clog2(NUM_PE) : 1);
    reg serial_active_r; reg [SERIAL_LANE_W-1:0] serial_lane_r; reg signed [NUM_PE*8-1:0] serial_data_r;
    reg [COORD_W-1:0] serial_y_r,serial_x_r; reg [CHANNEL_W-1:0] serial_channel_r; reg [NUM_PE-1:0] serial_valid_r;
    reg conv_finished_r; reg [31:0] written_r,total_r;
    // Conv emits tile_y, tile_x, output_channel in monotonically increasing
    // HWC order.  Count accepted bytes instead of rebuilding that offset with
    // two combinational multiplies on the ERAM write-address path.
    reg [ADDR_W-1:0] output_write_offset_r;
    integer i;
    function [13:0] small_extent_product;
      input [COORD_W-1:0] height_value;
      input [COORD_W-1:0] width_value;
      begin
        case(height_value)
          1:small_extent_product=width_value;
          2:small_extent_product=width_value<<1;
          3:small_extent_product=(width_value<<1)+width_value;
          4:small_extent_product=width_value<<2;
          5:small_extent_product=(width_value<<2)+width_value;
          6:small_extent_product=(width_value<<2)+(width_value<<1);
          7:small_extent_product=(width_value<<3)-width_value;
          8:small_extent_product=width_value<<3;
          9:small_extent_product=(width_value<<3)+width_value;
          10:small_extent_product=(width_value<<3)+(width_value<<1);
          11:small_extent_product=(width_value<<3)+(width_value<<1)+width_value;
          12:small_extent_product=(width_value<<3)+(width_value<<2);
          default:small_extent_product=14'd0;
        endcase
      end
    endfunction
    wire [13:0] configured_tile_area_w=small_extent_product(cfg_tile_h_i,cfg_tile_w_i);
    reg [31:0] configured_total_r;
    always @* begin
      case(cfg_output_c_i)
        1:configured_total_r=configured_tile_area_w;
        2:configured_total_r=configured_tile_area_w<<1;
        4:configured_total_r=configured_tile_area_w<<2;
        8:configured_total_r=configured_tile_area_w<<3;
        16:configured_total_r=configured_tile_area_w<<4;
        32:configured_total_r=configured_tile_area_w<<5;
        64:configured_total_r=configured_tile_area_w<<6;
        default:configured_total_r=32'd0;
      endcase
    end
    v5n_cached_conv_tile_engine #(.NUM_PE(NUM_PE),.COORD_W(COORD_W),.CHANNEL_W(CHANNEL_W),.ADDR_W(ADDR_W)) conv(.requant_error_o(requant_error_o),
.rq_req_valid(rq_req_valid),.rq_req_ready(rq_req_ready),.rq_source0(rq_source0),.rq_source1(rq_source1),.rq_mult0(rq_mult0),.rq_mult1(rq_mult1),.rq_bias(rq_bias),.rq_shift0(rq_shift0),.rq_shift1(rq_shift1),.rq_rsp_valid(rq_rsp_valid),.rq_rsp_code(rq_rsp_code),.rq_rsp_error(rq_rsp_error),

        .clk_i(clk_i),.rst_ni(rst_ni),.start_i(start_i),.busy_o(conv_busy_w),.done_o(conv_done_w),.packed_weight_data_i(packed_weight_data_i),
        .cfg_output_origin_y_i(cfg_output_origin_y_i),.cfg_output_origin_x_i(cfg_output_origin_x_i),.cfg_tile_h_i(cfg_tile_h_i),.cfg_tile_w_i(cfg_tile_w_i),.cfg_input_h_i(cfg_input_h_i),.cfg_input_w_i(cfg_input_w_i),.cfg_input_c_i(cfg_input_c_i),.cfg_output_c_i(cfg_output_c_i),.cfg_kernel_h_i(cfg_kernel_h_i),.cfg_kernel_w_i(cfg_kernel_w_i),.cfg_stride_h_i(cfg_stride_h_i),.cfg_stride_w_i(cfg_stride_w_i),.cfg_pad_top_i(cfg_pad_top_i),.cfg_pad_left_i(cfg_pad_left_i),.cfg_requant_shift_i(cfg_requant_shift_i),.cfg_input_base_i({ADDR_W{1'b0}}),.cfg_weight_base_i({ADDR_W{1'b0}}),.input_address_o(feature_read_offset_o),.input_data_i(feature_read_data_i),.weight_address_o(weight_read_offset_o),.weight_data_i(weight_read_data_i),.parameter_index_o(parameter_index_o),.parameter_multiplier_i(parameter_multiplier_i),.parameter_bias_numerator_i(parameter_bias_i),.output_valid_o(conv_output_valid_w),.output_y_o(conv_y_w),.output_x_o(conv_x_w),.output_channel_base_o(conv_channel_w),.output_data_o(conv_data_w),.output_lane_valid_o(conv_lane_valid_w));
    v5n_lut256_i8 #(.NUM_LANES(NUM_PE)) silu(.clk_i(clk_i),.rst_ni(rst_ni),.cfg_write_enable_i(lut_cfg_write_enable_i),.cfg_address_i(lut_cfg_address_i),.cfg_data_i(lut_cfg_data_i),.valid_i(conv_output_valid_w),.code_i(conv_data_w),.valid_o(lut_valid_w),.code_o(lut_data_w));
    assign output_write_valid_o=serial_active_r && serial_valid_r[serial_lane_r];
    assign output_write_offset_o=output_write_offset_r;
    assign output_write_data_o=serial_data_r[serial_lane_r*8 +: 8];
    always @(posedge clk_i or negedge rst_ni) begin
      if(!rst_ni) begin busy_o<=0;done_o<=0;error_o<=0;cycle_count_o<=0;meta_y_r<=0;meta_x_r<=0;meta_channel_r<=0;meta_valid_r<=0;serial_active_r<=0;serial_lane_r<=0;serial_data_r<=0;serial_y_r<=0;serial_x_r<=0;serial_channel_r<=0;serial_valid_r<=0;conv_finished_r<=0;written_r<=0;total_r<=0;output_write_offset_r<=0;end
      else begin
        done_o<=0;
        if(start_i && !busy_o) begin busy_o<=1;error_o<=0;cycle_count_o<=0;conv_finished_r<=0;written_r<=0;total_r<=configured_total_r;serial_active_r<=0;output_write_offset_r<=0;end
        if(busy_o) begin
          cycle_count_o<=cycle_count_o+1'b1;
          if(conv_output_valid_w) begin meta_y_r<=conv_y_w;meta_x_r<=conv_x_w;meta_channel_r<=conv_channel_w;meta_valid_r<=conv_lane_valid_w;end
          if(vector_valid_w) begin
            if(serial_active_r) error_o<=1'b1;
            else begin
              serial_active_r<=1'b1;serial_lane_r<=0;serial_data_r<=vector_data_w;
              if(activation_enable_i) begin serial_y_r<=meta_y_r;serial_x_r<=meta_x_r;serial_channel_r<=meta_channel_r;serial_valid_r<=meta_valid_r;end
              else begin serial_y_r<=conv_y_w;serial_x_r<=conv_x_w;serial_channel_r<=conv_channel_w;serial_valid_r<=conv_lane_valid_w;end
            end
          end
          if(serial_active_r) begin
            if(serial_valid_r[serial_lane_r]) begin
              written_r<=written_r+1'b1;
              output_write_offset_r<=output_write_offset_r+1'b1;
            end
            if(serial_lane_r+1>=NUM_PE) serial_active_r<=0; else serial_lane_r<=serial_lane_r+1'b1;
          end
          if(conv_done_w) conv_finished_r<=1'b1;
          if(requant_error_o)begin error_o<=1;busy_o<=0;end
          if(conv_finished_r && !serial_active_r && !vector_valid_w && (written_r>=total_r)) begin busy_o<=0;done_o<=1;end
        end
      end
    end
endmodule
