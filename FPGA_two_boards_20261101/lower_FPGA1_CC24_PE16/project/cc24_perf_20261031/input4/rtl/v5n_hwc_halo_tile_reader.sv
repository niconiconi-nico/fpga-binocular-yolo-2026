// Descriptor-configured HWC halo reader for convolution tiles. It traverses
// the exact local receptive field, uses the tensor-memory adapter for every
// in-bounds byte, and writes deterministic zero only for descriptor padding.
(* multstyle = "logic" *) module v5n_hwc_halo_tile_reader #(
    parameter integer ADDR_W = 32,
    parameter integer LINE_PREFETCH = 0,
    parameter integer SHAPE_W = 10
) (
    input wire clk_i, input wire rst_ni, input wire start_i,
    input wire memory_line_valid_i,input wire [ADDR_W-1:0] memory_line_address_i,
    input wire [127:0] memory_line_data_i,input wire memory_line_invalidate_i,
    input wire [ADDR_W-1:0] tensor_base_i,
    input wire [SHAPE_W-1:0] input_h_i, input wire [SHAPE_W-1:0] input_w_i, input wire [SHAPE_W-1:0] input_c_i,
    input wire [SHAPE_W-1:0] output_origin_y_i, input wire [SHAPE_W-1:0] output_origin_x_i,
    input wire [SHAPE_W-1:0] output_tile_h_i, input wire [SHAPE_W-1:0] output_tile_w_i,
    input wire [3:0] kernel_h_i, input wire [3:0] kernel_w_i, input wire [3:0] stride_h_i, input wire [3:0] stride_w_i,
    input wire [3:0] pad_top_i, input wire [3:0] pad_left_i,
    output wire busy_o, output reg done_o, output reg error_o,
    output wire cache_valid_o, input wire cache_ready_i, output wire [ADDR_W-1:0] cache_offset_o, output wire signed [7:0] cache_data_o,
    output wire memory_valid_o, input wire memory_ready_i,
    output wire [ADDR_W-1:0] memory_tensor_base_o, output wire [SHAPE_W-1:0] memory_tensor_h_o, output wire [SHAPE_W-1:0] memory_tensor_w_o, output wire [SHAPE_W-1:0] memory_tensor_c_o,
    output wire [SHAPE_W-1:0] memory_y_o, output wire [SHAPE_W-1:0] memory_x_o, output wire [SHAPE_W-1:0] memory_c_o,
    input wire memory_response_valid_i, output wire memory_response_ready_o, input wire memory_response_error_i, input wire signed [7:0] memory_read_data_i
);
    localparam [2:0] ST_IDLE=3'd0, ST_PREP=3'd1, ST_REQ=3'd2, ST_WAIT=3'd3, ST_WRITE=3'd4;
    reg [2:0] state_r; reg [SHAPE_W-1:0] ly_r,lx_r,lc_r, local_h_r,local_w_r;
    reg [ADDR_W-1:0] local_offset_r;
    (* multstyle = "logic" *) reg signed [31:0] gy_r,gx_r;
    reg in_bounds_r; reg signed [7:0] data_r;
    reg line_valid_r;
    reg [3:0] line_index_r;
    reg [127:0] line_data_r;
    wire line_hit_w=LINE_PREFETCH && line_valid_r && !memory_line_invalidate_i;
    wire last_w = (ly_r + 1 >= local_h_r) && (lx_r + 1 >= local_w_r) && (lc_r + 1 >= input_c_i);
    // Traversal order is strictly contiguous HWC, so a rolling cache offset
    // replaces the former (ly*width+lx)*channels+lc multiplier chain.
    assign busy_o=(state_r!=ST_IDLE); assign cache_valid_o=(state_r==ST_WRITE); assign cache_offset_o=local_offset_r; assign cache_data_o=data_r;
    assign memory_valid_o=(state_r==ST_REQ); assign memory_response_ready_o=(state_r==ST_WAIT);
    assign memory_tensor_base_o=tensor_base_i; assign memory_tensor_h_o=input_h_i; assign memory_tensor_w_o=input_w_i; assign memory_tensor_c_o=input_c_i;
    assign memory_y_o=gy_r[SHAPE_W-1:0]; assign memory_x_o=gx_r[SHAPE_W-1:0]; assign memory_c_o=lc_r;
    always @* begin
        gy_r = $signed({1'b0,(stride_h_i==2 ? (output_origin_y_i<<1) : output_origin_y_i)}) - $signed({1'b0,pad_top_i}) + $signed({1'b0,ly_r});
        gx_r = $signed({1'b0,(stride_w_i==2 ? (output_origin_x_i<<1) : output_origin_x_i)}) - $signed({1'b0,pad_left_i}) + $signed({1'b0,lx_r});
        in_bounds_r=(gy_r>=0)&&(gx_r>=0)&&(gy_r<$signed({1'b0,input_h_i}))&&(gx_r<$signed({1'b0,input_w_i}));
    end
    task advance_element;
        begin
            if (last_w) begin done_o<=1'b1; state_r<=ST_IDLE; end
            else if (lc_r + 1 >= input_c_i) begin lc_r<=0; if (lx_r+1>=local_w_r) begin lx_r<=0; ly_r<=ly_r+1'b1; end else lx_r<=lx_r+1'b1; end
            else lc_r<=lc_r+1'b1;
        end
    endtask
    always @(posedge clk_i or negedge rst_ni) begin
        if(!rst_ni) begin state_r<=ST_IDLE;ly_r<=0;lx_r<=0;lc_r<=0;local_h_r<=0;local_w_r<=0;local_offset_r<=0;data_r<=0;done_o<=0;error_o<=0;line_valid_r<=0;line_index_r<=0;line_data_r<=0;end
        else begin done_o<=0;
            case(state_r)
                ST_IDLE: if(start_i) begin error_o<=0; ly_r<=0;lx_r<=0;lc_r<=0;local_offset_r<=0;line_valid_r<=0;
                    local_h_r<=kernel_h_i+((stride_h_i==2)?((output_tile_h_i-1'b1)<<1):(output_tile_h_i-1'b1));
                    local_w_r<=kernel_w_i+((stride_w_i==2)?((output_tile_w_i-1'b1)<<1):(output_tile_w_i-1'b1));
                    state_r<=ST_PREP; end
                ST_PREP: if(!in_bounds_r) begin data_r<=0;line_valid_r<=0;state_r<=ST_WRITE;end
                  else if(line_hit_w) begin data_r<=line_data_r[line_index_r*8 +: 8];state_r<=ST_WRITE;end
                  else state_r<=ST_REQ;
                ST_REQ: if(memory_ready_i) state_r<=ST_WAIT;
                ST_WAIT: if(memory_response_valid_i) begin
                  if(memory_response_error_i) begin error_o<=1;line_valid_r<=0;state_r<=ST_IDLE;end
                  else begin
                    data_r<=memory_read_data_i;state_r<=ST_WRITE;
                    if(LINE_PREFETCH && memory_line_valid_i) begin
                      line_valid_r<=1;line_index_r<=memory_line_address_i[3:0];line_data_r<=memory_line_data_i;
                    end else line_valid_r<=0;
                  end
                end
                ST_WRITE: if(cache_ready_i) begin
                    // A halo row may skip bytes of the physical tensor row.
                    // Never carry a line across that discontinuity or padding.
                    if(line_index_r==15 || (lc_r+1>=input_c_i && lx_r+1>=local_w_r) || !in_bounds_r)
                      line_valid_r<=0;
                    else line_index_r<=line_index_r+1'b1;
                    if(!last_w) local_offset_r<=local_offset_r+1'b1;
                    advance_element; if(!last_w) state_r<=ST_PREP; end
                default: state_r<=ST_IDLE;
            endcase
            if(LINE_PREFETCH && memory_line_invalidate_i) line_valid_r<=0;
        end
    end
endmodule
