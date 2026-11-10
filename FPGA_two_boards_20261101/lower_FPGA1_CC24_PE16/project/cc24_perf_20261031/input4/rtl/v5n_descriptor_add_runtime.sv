// Descriptor-driven two-source INT8 Add transaction.
// Reads both HWC operands from their real DDR tensor addresses, applies the
// descriptor-provided merge-domain requantization, and writes the result back
// through the common tensor-memory adapter.  No source tensor is embedded.
module v5n_descriptor_add_runtime #(
    parameter integer ADDR_W = 32,
    parameter integer SHAPE_W = 10
) (
    input wire clk_i, input wire rst_ni, input wire start_i,
    input wire descriptor_valid_i, input wire [3:0] opcode_i,
    input wire [ADDR_W-1:0] source0_base_i, input wire [ADDR_W-1:0] source1_base_i,
    input wire [ADDR_W-1:0] destination_base_i,
    input wire [SHAPE_W-1:0] tensor_h_i, input wire [SHAPE_W-1:0] tensor_w_i,
    input wire [SHAPE_W-1:0] tensor_c_i,
    input wire signed [31:0] source0_multiplier_i, input wire [5:0] source0_shift_i,
    input wire signed [31:0] source1_multiplier_i, input wire [5:0] source1_shift_i,
    output wire busy_o, output reg done_o, output reg error_o,
    output wire [3:0] state_o, output wire [31:0] cycle_count_o,
    output wire memory_valid_o, input wire memory_ready_i, output wire memory_write_o,
    output wire memory_use_hwc_o, output wire [ADDR_W-1:0] memory_raw_byte_address_o,
    output wire [ADDR_W-1:0] memory_tensor_base_o,
    output wire [SHAPE_W-1:0] memory_tensor_h_o, output wire [SHAPE_W-1:0] memory_tensor_w_o,
    output wire [SHAPE_W-1:0] memory_tensor_c_o, output wire [SHAPE_W-1:0] memory_y_o,
    output wire [SHAPE_W-1:0] memory_x_o, output wire [SHAPE_W-1:0] memory_channel_o,
    output wire signed [7:0] memory_write_data_o,
    input wire memory_response_valid_i, output wire memory_response_ready_o,
    input wire memory_response_error_i, input wire memory_response_is_write_i,
    input wire signed [7:0] memory_read_data_i
);
    localparam [3:0] ST_IDLE=4'd0, ST_READ0_REQ=4'd1, ST_READ0_WAIT=4'd2,
                     ST_READ1_REQ=4'd3, ST_READ1_WAIT=4'd4, ST_APPLY=4'd5,
                     ST_OUTPUT_WAIT=4'd6, ST_WRITE_REQ=4'd7, ST_WRITE_WAIT=4'd8,
                     ST_DONE=4'd9, ST_FAIL=4'd10;
    reg [3:0] state_r; reg [SHAPE_W-1:0] y_r,x_r,c_r; reg signed [7:0] source0_r,source1_r;
    reg [31:0] cycle_r;
    wire merge_valid_w; wire signed [7:0] merge_data_w;
    wire last_element_w=(y_r+1>=tensor_h_i)&&(x_r+1>=tensor_w_i)&&(c_r+1>=tensor_c_i);
    v5n_merge_requant #(.NUM_LANES(1),.PIPELINED(1)) merge(
        .clk_i(clk_i),.rst_ni(rst_ni),.valid_i(state_r==ST_APPLY),.mode_add_i(1'b1),
        .source0_i(source0_r),.source1_i(source1_r),.source0_multiplier_i(source0_multiplier_i),
        .source0_shift_i(source0_shift_i),.source1_multiplier_i(source1_multiplier_i),
        .source1_shift_i(source1_shift_i),.valid_o(merge_valid_w),.data_o(merge_data_w));
    assign busy_o=(state_r!=ST_IDLE)&&(state_r!=ST_DONE)&&(state_r!=ST_FAIL);
    assign state_o=state_r;assign cycle_count_o=cycle_r;
    assign memory_valid_o=(state_r==ST_READ0_REQ)||(state_r==ST_READ1_REQ)||(state_r==ST_WRITE_REQ);
    assign memory_write_o=(state_r==ST_WRITE_REQ);assign memory_use_hwc_o=1'b1;
    assign memory_raw_byte_address_o={ADDR_W{1'b0}};
    assign memory_tensor_base_o=(state_r==ST_READ0_REQ)?source0_base_i:(state_r==ST_READ1_REQ)?source1_base_i:destination_base_i;
    assign memory_tensor_h_o=tensor_h_i;assign memory_tensor_w_o=tensor_w_i;assign memory_tensor_c_o=tensor_c_i;
    assign memory_y_o=y_r;assign memory_x_o=x_r;assign memory_channel_o=c_r;
    assign memory_write_data_o=merge_data_w;
    assign memory_response_ready_o=(state_r==ST_READ0_WAIT)||(state_r==ST_READ1_WAIT)||(state_r==ST_WRITE_WAIT);
    task advance_element;begin
        if(c_r+1>=tensor_c_i)begin c_r<=0;if(x_r+1>=tensor_w_i)begin x_r<=0;y_r<=y_r+1'b1;end else x_r<=x_r+1'b1;end else c_r<=c_r+1'b1;
    end endtask
    always@(posedge clk_i or negedge rst_ni)begin
      if(!rst_ni)begin state_r<=ST_IDLE;y_r<=0;x_r<=0;c_r<=0;source0_r<=0;source1_r<=0;cycle_r<=0;done_o<=0;error_o<=0;end
      else begin done_o<=0;if(busy_o)cycle_r<=cycle_r+1'b1;case(state_r)
        ST_IDLE:if(start_i)begin cycle_r<=0;y_r<=0;x_r<=0;c_r<=0;error_o<=0;if(!descriptor_valid_i||opcode_i!=4'd4||tensor_h_i==0||tensor_w_i==0||tensor_c_i==0)begin error_o<=1;state_r<=ST_FAIL;end else state_r<=ST_READ0_REQ;end
        ST_READ0_REQ:if(memory_ready_i)state_r<=ST_READ0_WAIT;
        ST_READ0_WAIT:if(memory_response_valid_i)begin if(memory_response_error_i||memory_response_is_write_i)begin error_o<=1;state_r<=ST_FAIL;end else begin source0_r<=memory_read_data_i;state_r<=ST_READ1_REQ;end end
        ST_READ1_REQ:if(memory_ready_i)state_r<=ST_READ1_WAIT;
        ST_READ1_WAIT:if(memory_response_valid_i)begin if(memory_response_error_i||memory_response_is_write_i)begin error_o<=1;state_r<=ST_FAIL;end else begin source1_r<=memory_read_data_i;state_r<=ST_APPLY;end end
        ST_APPLY:state_r<=ST_OUTPUT_WAIT;
        ST_OUTPUT_WAIT:if(merge_valid_w)state_r<=ST_WRITE_REQ;
        ST_WRITE_REQ:if(memory_ready_i)state_r<=ST_WRITE_WAIT;
        ST_WRITE_WAIT:if(memory_response_valid_i)begin if(memory_response_error_i||!memory_response_is_write_i)begin error_o<=1;state_r<=ST_FAIL;end else if(last_element_w)state_r<=ST_DONE;else begin advance_element;state_r<=ST_READ0_REQ;end end
        ST_DONE:begin done_o<=1;state_r<=ST_IDLE;end
        default:state_r<=ST_FAIL;
      endcase end
    end
endmodule
