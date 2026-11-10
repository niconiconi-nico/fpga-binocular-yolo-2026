// Descriptor-driven HWC Concat transaction for one to four INT8 sources.
// A destination channel is resolved to exactly one source channel, then that
// source is affine-requantized once into the destination domain.  It never
// cascades saturated binary Concats and keeps all feature-map traffic on the
// common DDR adapter contract.
module v5n_descriptor_concat_runtime #(
    parameter integer ADDR_W = 32,
    parameter integer SHAPE_W = 10,
    parameter integer WRITE_LINE_ENABLE = 0,
    parameter integer READ_LINE_ENABLE = 0
) (
    input wire clk_i, input wire rst_ni, input wire start_i,
    input wire descriptor_valid_i, input wire [3:0] opcode_i,
    input wire [2:0] source_count_i,
    input wire [ADDR_W-1:0] source0_base_i, input wire [ADDR_W-1:0] source1_base_i,
    input wire [ADDR_W-1:0] source2_base_i, input wire [ADDR_W-1:0] source3_base_i,
    input wire [ADDR_W-1:0] destination_base_i,
    input wire [SHAPE_W-1:0] tensor_h_i, input wire [SHAPE_W-1:0] tensor_w_i,
    input wire [SHAPE_W-1:0] source0_channels_i, input wire [SHAPE_W-1:0] source1_channels_i,
    input wire [SHAPE_W-1:0] source2_channels_i, input wire [SHAPE_W-1:0] source3_channels_i,
    input wire [SHAPE_W-1:0] destination_channels_i,
    input wire signed [31:0] source0_multiplier_i, input wire [5:0] source0_shift_i,
    input wire signed [31:0] source1_multiplier_i, input wire [5:0] source1_shift_i,
    input wire signed [31:0] source2_multiplier_i, input wire [5:0] source2_shift_i,
    input wire signed [31:0] source3_multiplier_i, input wire [5:0] source3_shift_i,
    output wire busy_o, output reg done_o, output reg error_o,
    output wire [3:0] state_o, output wire [31:0] cycle_count_o,
    output wire memory_valid_o, input wire memory_ready_i, output wire memory_write_o,
    output wire memory_use_hwc_o, output wire [ADDR_W-1:0] memory_raw_byte_address_o,
    output wire [ADDR_W-1:0] memory_tensor_base_o,
    output wire [SHAPE_W-1:0] memory_tensor_h_o, output wire [SHAPE_W-1:0] memory_tensor_w_o,
    output wire [SHAPE_W-1:0] memory_tensor_c_o, output wire [SHAPE_W-1:0] memory_y_o,
    output wire [SHAPE_W-1:0] memory_x_o, output wire [SHAPE_W-1:0] memory_channel_o,
    output wire signed [7:0] memory_write_data_o,
    output wire memory_write_line_o,
    output wire [127:0] memory_write_line_data_o,
    input wire memory_response_valid_i, output wire memory_response_ready_o,
    input wire memory_response_error_i, input wire memory_response_is_write_i,
    input wire signed [7:0] memory_read_data_i,
    // Line valid/address comes from the owned response bridge. No bare
    // unsolicited DDR payload is accepted as a completed operand group.
    input wire memory_read_line_valid_i,
    input wire [ADDR_W-1:0] memory_read_line_address_i,
    input wire [127:0] memory_read_line_data_i,
    input wire line_alias_safe_i,
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
    localparam [3:0] ST_IDLE=4'd0, ST_READ_REQ=4'd1, ST_READ_WAIT=4'd2,
                     ST_APPLY=4'd3, ST_OUTPUT_WAIT=4'd4, ST_WRITE_REQ=4'd5,
                     ST_WRITE_WAIT=4'd6, ST_DONE=4'd7, ST_FAIL=4'd8, ST_STREAM=4'd9;
    reg [3:0] state_r;
    reg [SHAPE_W-1:0] y_r,x_r,c_r;
    reg signed [7:0] source_r;
    reg [31:0] cycle_r;
    reg line_mode_r;
    reg [3:0] line_lane_r;
    reg [SHAPE_W-1:0] line_channel_r;
    reg [127:0] line_data_r;
    reg [127:0] input_line_r;
    reg [4:0] stream_issue_r,stream_collect_r;
    wire [3:0] stream_lane_w=(stream_issue_r<16)?stream_issue_r[3:0]:4'd0;
    wire stream_input_valid_w=(state_r==ST_STREAM)&&(stream_issue_r<16);
    wire resolver_valid_w; wire [1:0] resolver_source_index_w; wire [SHAPE_W-1:0] resolver_source_channel_w;
    reg [ADDR_W-1:0] selected_base_r;
    reg [SHAPE_W-1:0] selected_channels_r;
    reg signed [31:0] selected_multiplier_r;
    reg [5:0] selected_shift_r;
    wire merge_valid_w; wire signed [7:0] merge_data_w;
    wire [SHAPE_W:0] source_channel_sum_w={1'b0,source0_channels_i}+{1'b0,source1_channels_i}+{1'b0,source2_channels_i}+{1'b0,source3_channels_i};
    wire last_element_w=(y_r+1>=tensor_h_i)&&(x_r+1>=tensor_w_i)&&(c_r+1>=destination_channels_i);
    v5n_concat4_hwc_addr #(.CHANNEL_W(SHAPE_W)) resolver(
        .source_count_i(source_count_i),.source0_channels_i(source0_channels_i),.source1_channels_i(source1_channels_i),.source2_channels_i(source2_channels_i),.source3_channels_i(source3_channels_i),.output_channel_i(c_r),
        .valid_o(resolver_valid_w),.source_index_o(resolver_source_index_w),.source_channel_o(resolver_source_channel_w));
    wire signed[7:0]rq_source_byte_w=(state_r==ST_STREAM)?input_line_r[7:0]:source_r;
 assign rq_req_valid=(state_r==ST_APPLY)||stream_input_valid_w;
 assign rq_source0={{24{rq_source_byte_w[7]}},rq_source_byte_w};
 assign rq_source1=32'sd0;
 assign rq_mult0=selected_multiplier_r;
 assign rq_mult1=32'sd0;
 assign rq_bias=32'sd0;
 assign rq_shift0=selected_shift_r;
 assign rq_shift1=6'd0;
    assign merge_valid_w=rq_rsp_valid&&!rq_rsp_error;assign merge_data_w=rq_rsp_code;
    always @* begin
        selected_base_r=source0_base_i;selected_channels_r=source0_channels_i;selected_multiplier_r=source0_multiplier_i;selected_shift_r=source0_shift_i;
        case(resolver_source_index_w)
          2'd1:begin selected_base_r=source1_base_i;selected_channels_r=source1_channels_i;selected_multiplier_r=source1_multiplier_i;selected_shift_r=source1_shift_i;end
          2'd2:begin selected_base_r=source2_base_i;selected_channels_r=source2_channels_i;selected_multiplier_r=source2_multiplier_i;selected_shift_r=source2_shift_i;end
          2'd3:begin selected_base_r=source3_base_i;selected_channels_r=source3_channels_i;selected_multiplier_r=source3_multiplier_i;selected_shift_r=source3_shift_i;end
        endcase
    end
    // Conservative specialization: never cross a source/pixel/domain boundary,
    // never consume an unsolicited line or pre-read overlapping destination data.
    // Any missing qualification, head/tail, unaligned source or alias falls back
    // to the original scalar gather (with its original optional write16).
    reg stream_geometry_ok_r;
    wire stream_geometry_ok_w=(READ_LINE_ENABLE!=0)&&line_mode_r&&
        (line_lane_r==0)&&(c_r[3:0]==0)&&
        (selected_base_r[3:0]==0)&&(selected_channels_r[3:0]==0)&&
        (resolver_source_channel_w[3:0]==0)&&
        ({1'b0,resolver_source_channel_w}+16<={1'b0,selected_channels_r})&&
        ({1'b0,c_r}+16<={1'b0,destination_channels_i});
    // Only request-owned descriptor/coordinate geometry is registered.
    // Response identity, validity, alignment and live alias safety stay at ACK.
    wire stream_line_hit_w=stream_geometry_ok_r && line_alias_safe_i &&
        memory_read_line_valid_i && (memory_read_line_address_i[3:0]==0);
    assign busy_o=(state_r!=ST_IDLE)&&(state_r!=ST_DONE)&&(state_r!=ST_FAIL);
    assign state_o=state_r;assign cycle_count_o=cycle_r;
    assign memory_valid_o=(state_r==ST_READ_REQ)||(state_r==ST_WRITE_REQ);
    assign memory_write_o=(state_r==ST_WRITE_REQ);assign memory_use_hwc_o=1'b1;assign memory_raw_byte_address_o={ADDR_W{1'b0}};
    assign memory_tensor_base_o=(state_r==ST_READ_REQ)?selected_base_r:destination_base_i;
    assign memory_tensor_h_o=tensor_h_i;assign memory_tensor_w_o=tensor_w_i;
    assign memory_tensor_c_o=(state_r==ST_READ_REQ)?selected_channels_r:destination_channels_i;
    assign memory_y_o=y_r;assign memory_x_o=x_r;
    assign memory_channel_o=(state_r==ST_READ_REQ)?resolver_source_channel_w:
                           (line_mode_r?line_channel_r:c_r);
    assign memory_write_data_o=merge_data_w;
    // Retained payload/flag must never turn a subsequent source read into a write.
    assign memory_write_line_o=line_mode_r&&
                              ((state_r==ST_WRITE_REQ)||(state_r==ST_WRITE_WAIT));
    assign memory_write_line_data_o=line_data_r;
    assign memory_response_ready_o=(state_r==ST_READ_WAIT)||(state_r==ST_WRITE_WAIT);
    task advance_element;begin
      if(c_r+1>=destination_channels_i)begin c_r<=0;if(x_r+1>=tensor_w_i)begin x_r<=0;y_r<=y_r+1'b1;end else x_r<=x_r+1'b1;end else c_r<=c_r+1'b1;
    end endtask
    always@(posedge clk_i or negedge rst_ni)begin
      if(!rst_ni)begin state_r<=ST_IDLE;y_r<=0;x_r<=0;c_r<=0;source_r<=0;cycle_r<=0;done_o<=0;error_o<=0;
        line_mode_r<=0;line_lane_r<=0;line_channel_r<=0;line_data_r<=0;
        input_line_r<=0;stream_issue_r<=0;stream_collect_r<=0;stream_geometry_ok_r<=0;end
      else begin
        done_o<=0;if(busy_o)cycle_r<=cycle_r+1'b1;
        if(rq_rsp_valid&&rq_rsp_error)begin error_o<=1;state_r<=ST_FAIL;end else case(state_r)
          ST_IDLE:if(start_i)begin
            cycle_r<=0;y_r<=0;x_r<=0;c_r<=0;error_o<=0;
            line_lane_r<=0;line_channel_r<=0;line_data_r<=0;
            stream_issue_r<=0;stream_collect_r<=0;stream_geometry_ok_r<=0;
            line_mode_r<=WRITE_LINE_ENABLE&&(destination_base_i[3:0]==0)&&
                         (destination_channels_i[3:0]==0);
            if(!descriptor_valid_i||opcode_i!=4'd5||source_count_i==0||source_count_i>4||tensor_h_i==0||tensor_w_i==0||destination_channels_i==0||source_channel_sum_w!=destination_channels_i)begin error_o<=1;state_r<=ST_FAIL;end else state_r<=ST_READ_REQ;
          end
          ST_READ_REQ:if(!resolver_valid_w)begin error_o<=1;state_r<=ST_FAIL;end else if(memory_ready_i)begin stream_geometry_ok_r<=stream_geometry_ok_w;state_r<=ST_READ_WAIT;end
          ST_READ_WAIT:if(memory_response_valid_i)begin if(memory_response_error_i||memory_response_is_write_i)begin error_o<=1;state_r<=ST_FAIL;end else if(stream_line_hit_w)begin
              input_line_r<=memory_read_line_data_i;line_channel_r<=c_r;
              stream_issue_r<=0;stream_collect_r<=0;state_r<=ST_STREAM;
            end else begin source_r<=memory_read_data_i;state_r<=ST_APPLY;end end
          ST_APPLY:if(rq_req_ready)state_r<=ST_OUTPUT_WAIT;
          ST_OUTPUT_WAIT:if(merge_valid_w)begin
            if(line_mode_r)begin
              // Only actual outputs of the unchanged one-lane requant enter this register.
              line_data_r<={merge_data_w,line_data_r[127:8]};
              if(line_lane_r==0)line_channel_r<=c_r;
              if(line_lane_r==15)state_r<=ST_WRITE_REQ;
              else begin line_lane_r<=line_lane_r+1'b1;advance_element;state_r<=ST_READ_REQ;end
            end else state_r<=ST_WRITE_REQ;
          end
          ST_STREAM:begin
            // c/source selection stays fixed throughout the affine pipeline;
            // issue exactly16 real bytes, collect exactly16 actual valid outputs.
            if(rq_req_valid&&rq_req_ready)begin
              stream_issue_r<=stream_issue_r+1'b1;
              input_line_r<={8'd0,input_line_r[127:8]};
            end
            if(merge_valid_w)begin
              line_data_r<={merge_data_w,line_data_r[127:8]};
              stream_collect_r<=stream_collect_r+1'b1;
            end
            if(stream_collect_r>=16)begin
              // Match scalar gather's last-byte coordinate, but do not advance
              // to a subsequent group until its genuine physical writer ACK.
              c_r<=c_r+15;state_r<=ST_WRITE_REQ;
            end
          end
          ST_WRITE_REQ:if(memory_ready_i)state_r<=ST_WRITE_WAIT;
          ST_WRITE_WAIT:if(memory_response_valid_i)begin
            if(memory_response_error_i||!memory_response_is_write_i)begin error_o<=1;state_r<=ST_FAIL;end
            else begin
              // Advance/finish only on the common service's genuine physical commit response.
              line_lane_r<=0;
              if(last_element_w)state_r<=ST_DONE;
              else begin advance_element;state_r<=ST_READ_REQ;end
            end
          end
          ST_DONE:begin done_o<=1;state_r<=ST_IDLE;end
          default:state_r<=ST_FAIL;
        endcase
      end
    end
`ifndef SYNTHESIS
    always @(posedge clk_i)if(rst_ni && state_r==ST_READ_WAIT && memory_response_valid_i)
      if(stream_geometry_ok_r!==stream_geometry_ok_w)
        $fatal(1,"CONCAT_REQUEST_GEOMETRY_CHANGED_BEFORE_OWNED_RESPONSE");
`endif
endmodule
