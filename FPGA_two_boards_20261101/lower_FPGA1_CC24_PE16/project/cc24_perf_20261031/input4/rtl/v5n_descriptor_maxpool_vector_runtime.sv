// Frozen graph SPPF: same signed INT8 5x5/s1/p2 reduction, same memory interface and descriptor checks.
// CC17 (speed): column-maxima reuse. For each output pixel the 5x5 window is the max of 5 window COLUMNS, each the
// max over its 5 rows. Column maxima (per channel) are kept in a small RAM (8 slots x MAX_CHANNELS); moving one pixel
// to the right only the new column is read from memory (5 rows x C), the other 4 columns are reused. The first pixel
// of every tile row computes all 5 columns. Out-of-tensor positions are skipped and every column starts at -128,
// exactly like the original per-window scan (max over the inside positions only), so results are identical.
module v5n_descriptor_maxpool_vector_runtime #(
    parameter integer ADDR_W=32, SHAPE_W=10, MAX_CHANNELS=128
) (
    input wire clk_i,input wire rst_ni,input wire start_i,input wire descriptor_valid_i,input wire [3:0] opcode_i,
    input wire [ADDR_W-1:0] source_base_i,input wire [ADDR_W-1:0] destination_base_i,
    input wire [SHAPE_W-1:0] tensor_h_i,input wire [SHAPE_W-1:0] tensor_w_i,input wire [SHAPE_W-1:0] channels_i,
    input wire [SHAPE_W-1:0] tile_origin_y_i,input wire [SHAPE_W-1:0] tile_origin_x_i,
    input wire [SHAPE_W-1:0] tile_h_i,input wire [SHAPE_W-1:0] tile_w_i,
    output wire busy_o,output reg done_o,output reg error_o,
    output wire memory_valid_o,input wire memory_ready_i,output wire memory_write_o,output wire memory_use_hwc_o,
    output wire [ADDR_W-1:0] memory_raw_byte_address_o,output wire [ADDR_W-1:0] memory_tensor_base_o,
    output wire [SHAPE_W-1:0] memory_tensor_h_o,memory_tensor_w_o,memory_tensor_c_o,memory_y_o,memory_x_o,memory_channel_o,
    output wire signed [7:0] memory_write_data_o,input wire memory_response_valid_i,output wire memory_response_ready_o,
    input wire memory_response_error_i,input wire memory_response_is_write_i,input wire signed [7:0] memory_read_data_i
);
    localparam [3:0] IDLE=0, COL_CLEAR=1, COL_SCAN=2, READ_REQ=3, READ_WAIT=4, OUT_A=5, OUT_B=6,
        WRITE_REQ=7, WRITE_WAIT=8, DONE=9, FAIL=10, PIXEL=11;
    localparam integer CW=$clog2(MAX_CHANNELS);
    reg [3:0] state_r;
    reg [SHAPE_W-1:0] ly_r,lx_r,c_r;
    reg [2:0] ky_r,col_r,k_r;          // ky: window row of the column being read; col: window column 0..4; k: output scan
    reg signed [7:0] colmax_q, out_r;
    (* ram_style="bram" *) reg signed [7:0] colmax [0:8*MAX_CHANNELS-1];
    wire [SHAPE_W-1:0] oy_w=tile_origin_y_i+ly_r, ox_w=tile_origin_x_i+lx_r;
    wire signed [SHAPE_W+1:0] sy_w=$signed({2'b0,oy_w})+$signed({1'b0,ky_r})-2;
    wire signed [SHAPE_W+1:0] sx_w=$signed({2'b0,ox_w})+$signed({1'b0,col_r})-2;
    wire inside_w=sy_w>=0 && sx_w>=0 && sy_w<$signed({2'b0,tensor_h_i}) && sx_w<$signed({2'b0,tensor_w_i});
    wire last_c_w=(c_r+1>=channels_i);
    wire last_pixel_w=(ly_r+1>=tile_h_i && lx_r+1>=tile_w_i);
    // slot of window column j at the current pixel: (lx + j) mod 8 (5 consecutive values are distinct mod 8)
    wire [2:0] col_slot_w=lx_r[2:0]+col_r;
    wire [2:0] out_slot_w=lx_r[2:0]+k_r;
    wire good_read_w=state_r==READ_WAIT && memory_response_valid_i && !memory_response_error_i && !memory_response_is_write_i;
    wire [CW+2:0] col_addr_w={col_slot_w,c_r[CW-1:0]};
    wire [CW+2:0] out_addr_w={out_slot_w,c_r[CW-1:0]};

    // CC18: one muxed read address (single read port) so the 1 KB colmax maps to ERAM like the original maxima RAM
    // (CC17's two indexed reads were mapped to distributed LUT-RAM: +128 LUT-RAM, +48 F7/F8).
    wire [CW+2:0] rd_addr_w=(state_r==OUT_A)?out_addr_w:col_addr_w;
    always @(posedge clk_i) begin
        if (state_r==READ_REQ || state_r==OUT_A) colmax_q <= colmax[rd_addr_w];
        if (state_r==COL_CLEAR) colmax[col_addr_w] <= -8'sd128;
        else if (good_read_w)
            colmax[col_addr_w] <= ($signed(memory_read_data_i)>$signed(colmax_q)) ? memory_read_data_i : colmax_q;
    end

    assign busy_o=state_r!=IDLE && state_r!=DONE && state_r!=FAIL;
    assign memory_valid_o=state_r==READ_REQ || state_r==WRITE_REQ;
    assign memory_write_o=state_r==WRITE_REQ;
    assign memory_use_hwc_o=1'b1;
    assign memory_raw_byte_address_o=0;
    assign memory_tensor_base_o=state_r==WRITE_REQ ? destination_base_i : source_base_i;
    assign memory_tensor_h_o=tensor_h_i;
    assign memory_tensor_w_o=tensor_w_i;
    assign memory_tensor_c_o=channels_i;
    assign memory_y_o=state_r==WRITE_REQ ? oy_w : sy_w[SHAPE_W-1:0];
    assign memory_x_o=state_r==WRITE_REQ ? ox_w : sx_w[SHAPE_W-1:0];
    assign memory_channel_o=c_r;
    assign memory_write_data_o=out_r;
    assign memory_response_ready_o=state_r==READ_WAIT || state_r==WRITE_WAIT;

    // finished reading one window row (ky) of the current column for all channels
    task next_row;
        begin
            c_r<=0;
            if(ky_r==4)begin
                if(col_r==4)begin k_r<=0;state_r<=OUT_A; end      // all needed columns ready -> output
                else begin col_r<=col_r+1'b1;ky_r<=0;state_r<=COL_CLEAR; end
            end else begin ky_r<=ky_r+1'b1;state_r<=COL_SCAN; end
        end
    endtask

    always @(posedge clk_i or negedge rst_ni) begin
        if(!rst_ni)begin
            state_r<=IDLE;ly_r<=0;lx_r<=0;c_r<=0;ky_r<=0;col_r<=0;k_r<=0;out_r<=0;done_o<=0;error_o<=0;
        end else begin
            done_o<=0;
            case(state_r)
                IDLE: if(start_i)begin
                    ly_r<=0;lx_r<=0;c_r<=0;ky_r<=0;col_r<=0;k_r<=0;error_o<=0;
                    if(!descriptor_valid_i || opcode_i!=6 || tensor_h_i==0 || tensor_w_i==0 ||
                       channels_i==0 || channels_i>MAX_CHANNELS || tile_h_i==0 || tile_w_i==0 ||
                       {1'b0,tile_origin_y_i}+tile_h_i>{1'b0,tensor_h_i} ||
                       {1'b0,tile_origin_x_i}+tile_w_i>{1'b0,tensor_w_i})begin
                        error_o<=1;state_r<=FAIL;
                    end else state_r<=PIXEL;
                end
                // first pixel of a tile row: build columns 0..4; otherwise only the new column 4
                PIXEL: begin c_r<=0;ky_r<=0;col_r<=(lx_r==0)?3'd0:3'd4;state_r<=COL_CLEAR; end
                COL_CLEAR: if(last_c_w)begin c_r<=0;state_r<=COL_SCAN;end else c_r<=c_r+1'b1;
                COL_SCAN: if(inside_w)state_r<=READ_REQ;else next_row;
                READ_REQ: if(memory_ready_i)state_r<=READ_WAIT;
                READ_WAIT: if(memory_response_valid_i)begin
                    if(memory_response_error_i || memory_response_is_write_i)begin error_o<=1;state_r<=FAIL;end
                    else if(last_c_w)next_row;
                    else begin c_r<=c_r+1'b1;state_r<=READ_REQ;end
                end
                OUT_A: state_r<=OUT_B;                               // colmax_q <= column k of channel c
                OUT_B: begin
                    out_r<=(k_r==0 || $signed(colmax_q)>$signed(out_r)) ? colmax_q : out_r;
                    if(k_r==4) state_r<=WRITE_REQ; else begin k_r<=k_r+1'b1;state_r<=OUT_A; end
                end
                WRITE_REQ: if(memory_ready_i)state_r<=WRITE_WAIT;
                WRITE_WAIT: if(memory_response_valid_i)begin
                    if(memory_response_error_i || !memory_response_is_write_i)begin error_o<=1;state_r<=FAIL;end
                    else if(!last_c_w)begin c_r<=c_r+1'b1;k_r<=0;state_r<=OUT_A;end
                    else if(last_pixel_w)state_r<=DONE;
                    else begin
                        if(lx_r+1>=tile_w_i)begin lx_r<=0;ly_r<=ly_r+1'b1;end
                        else lx_r<=lx_r+1'b1;
                        state_r<=PIXEL;
                    end
                end
                DONE:begin done_o<=1;state_r<=IDLE;end
                default:state_r<=FAIL;
            endcase
        end
    end
endmodule
