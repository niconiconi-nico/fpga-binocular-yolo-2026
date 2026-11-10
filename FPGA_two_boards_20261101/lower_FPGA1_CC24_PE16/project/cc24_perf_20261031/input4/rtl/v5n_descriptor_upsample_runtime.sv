// Handshaked shared-memory wrapper for nearest-neighbour HWC x2 upsample.
// The coordinate transform is the existing v5n_upsample_addr primitive;
// one source byte is read and acknowledged before its destination write.
module v5n_descriptor_upsample_runtime #(
    parameter integer ADDR_W=32, parameter integer SHAPE_W=10
) (
    input wire clk_i,input wire rst_ni,input wire start_i,input wire descriptor_valid_i,input wire [3:0] opcode_i,
    input wire [ADDR_W-1:0] source_base_i,input wire [ADDR_W-1:0] destination_base_i,
    input wire [SHAPE_W-1:0] input_h_i,input wire [SHAPE_W-1:0] input_w_i,input wire [SHAPE_W-1:0] channels_i,
    input wire [SHAPE_W-1:0] output_h_i,input wire [SHAPE_W-1:0] output_w_i,
    input wire [SHAPE_W-1:0] tile_origin_y_i,input wire [SHAPE_W-1:0] tile_origin_x_i,
    input wire [SHAPE_W-1:0] tile_h_i,input wire [SHAPE_W-1:0] tile_w_i,
    output wire busy_o,output reg done_o,output reg error_o,
    output wire memory_valid_o,input wire memory_ready_i,output wire memory_write_o,output wire memory_use_hwc_o,
    output wire [ADDR_W-1:0] memory_raw_byte_address_o,output wire [ADDR_W-1:0] memory_tensor_base_o,
    output wire [SHAPE_W-1:0] memory_tensor_h_o,memory_tensor_w_o,memory_tensor_c_o,memory_y_o,memory_x_o,memory_channel_o,
    output wire signed [7:0] memory_write_data_o,input wire memory_response_valid_i,output wire memory_response_ready_o,
    input wire memory_response_error_i,input wire memory_response_is_write_i,input wire signed [7:0] memory_read_data_i
);
    localparam [3:0] ST_IDLE=0,ST_READ_REQ=1,ST_READ_WAIT=2,ST_WRITE_REQ=3,ST_WRITE_WAIT=4,ST_DONE=5,ST_FAIL=6;
    reg [3:0] state_r; reg [SHAPE_W-1:0] ly_r,lx_r,c_r; reg signed [7:0] data_r;
    wire [SHAPE_W-1:0] oy_w=tile_origin_y_i+ly_r, ox_w=tile_origin_x_i+lx_r;
    wire [SHAPE_W-1:0] sy_w,sx_w,sc_w;
    wire last_w=(ly_r+1>=tile_h_i)&&(lx_r+1>=tile_w_i)&&(c_r+1>=channels_i);
    v5n_upsample_addr #(.COORD_W(SHAPE_W),.CHANNEL_W(SHAPE_W)) address_map(
      .output_y_i(oy_w),.output_x_i(ox_w),.output_channel_i(c_r),.input_y_o(sy_w),.input_x_o(sx_w),.input_channel_o(sc_w));
    assign busy_o=(state_r!=ST_IDLE)&&(state_r!=ST_DONE)&&(state_r!=ST_FAIL);
    assign memory_valid_o=(state_r==ST_READ_REQ)||(state_r==ST_WRITE_REQ); assign memory_write_o=(state_r==ST_WRITE_REQ); assign memory_use_hwc_o=1'b1;
    assign memory_raw_byte_address_o=0; assign memory_tensor_base_o=(state_r==ST_WRITE_REQ)?destination_base_i:source_base_i;
    assign memory_tensor_h_o=(state_r==ST_WRITE_REQ)?output_h_i:input_h_i; assign memory_tensor_w_o=(state_r==ST_WRITE_REQ)?output_w_i:input_w_i;
    assign memory_tensor_c_o=channels_i; assign memory_y_o=(state_r==ST_WRITE_REQ)?oy_w:sy_w; assign memory_x_o=(state_r==ST_WRITE_REQ)?ox_w:sx_w;
    assign memory_channel_o=(state_r==ST_WRITE_REQ)?c_r:sc_w; assign memory_write_data_o=data_r;
    assign memory_response_ready_o=(state_r==ST_READ_WAIT)||(state_r==ST_WRITE_WAIT);
    task advance; begin
      if(c_r+1>=channels_i) begin c_r<=0;if(lx_r+1>=tile_w_i) begin lx_r<=0;ly_r<=ly_r+1'b1;end else lx_r<=lx_r+1'b1;end else c_r<=c_r+1'b1;
    end endtask
    always @(posedge clk_i or negedge rst_ni) begin
      if(!rst_ni) begin state_r<=ST_IDLE;ly_r<=0;lx_r<=0;c_r<=0;data_r<=0;done_o<=0;error_o<=0;end
      else begin done_o<=0; case(state_r)
        ST_IDLE:if(start_i) begin ly_r<=0;lx_r<=0;c_r<=0;error_o<=0;
          if(!descriptor_valid_i||opcode_i!=4'd7||input_h_i*2!=output_h_i||input_w_i*2!=output_w_i||channels_i==0||tile_h_i==0||tile_w_i==0||tile_origin_y_i+tile_h_i>output_h_i||tile_origin_x_i+tile_w_i>output_w_i) begin error_o<=1;state_r<=ST_FAIL;end else state_r<=ST_READ_REQ;end
        ST_READ_REQ:if(memory_ready_i)state_r<=ST_READ_WAIT;
        ST_READ_WAIT:if(memory_response_valid_i)begin if(memory_response_error_i||memory_response_is_write_i)begin error_o<=1;state_r<=ST_FAIL;end else begin data_r<=memory_read_data_i;state_r<=ST_WRITE_REQ;end end
        ST_WRITE_REQ:if(memory_ready_i)state_r<=ST_WRITE_WAIT;
        ST_WRITE_WAIT:if(memory_response_valid_i)begin if(memory_response_error_i||!memory_response_is_write_i)begin error_o<=1;state_r<=ST_FAIL;end else if(last_w)state_r<=ST_DONE;else begin advance;state_r<=ST_READ_REQ;end end
        ST_DONE:begin done_o<=1;state_r<=ST_IDLE;end default:state_r<=ST_FAIL;
      endcase end
    end
endmodule
