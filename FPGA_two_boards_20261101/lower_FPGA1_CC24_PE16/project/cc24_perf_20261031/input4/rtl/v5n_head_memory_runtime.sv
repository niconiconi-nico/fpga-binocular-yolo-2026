// Classic anchor v5 head -> integer decode -> 8-word candidate buffer.
// Same byte/HWC service interface as copied operator bridge, no private DDR.
// PROTOTYPE: own candidate-specific exact arithmetic, not full graph acceptance.
module v5n_head_memory_runtime #(
    parameter integer ADDR_W=32, parameter integer SHAPE_W=10
) (
    input wire clk_i, rst_ni, start_i,
    input wire [ADDR_W-1:0] head_base_i, destination_base_i, sigmoid_base_i, anchor_base_i,
    input wire [SHAPE_W-1:0] tensor_h_i, tensor_w_i,
    input wire [5:0] stride_i,
    output wire busy_o, output reg done_o, error_o,
    output wire memory_valid_o, input wire memory_ready_i,
    output wire memory_write_o, memory_use_hwc_o,
    output wire [ADDR_W-1:0] memory_raw_byte_address_o, memory_tensor_base_o,
    output wire [SHAPE_W-1:0] memory_tensor_h_o, memory_tensor_w_o, memory_tensor_c_o,
    output wire [SHAPE_W-1:0] memory_y_o, memory_x_o, memory_channel_o,
    output wire signed [7:0] memory_write_data_o,
    input wire memory_response_valid_i,
    output wire memory_response_ready_o,
    input wire memory_response_error_i, memory_response_is_write_i,
    input wire signed [7:0] memory_read_data_i,
output wire context_req_valid,input wire context_req_ready,
output wire[2:0]context_mode,output wire[511:0]context_words,
input wire context_rsp_valid,output wire context_rsp_ready,
input wire[31:0]context_rsp_data,input wire[2:0]context_rsp_index,
input wire context_rsp_last,context_rsp_error

);
 wire numeric_error_o;
    localparam [4:0] IDLE=0, LUT_REQ=1, LUT_WAIT=2, LUT_STORE=3,
        ANCHOR_REQ=4, ANCHOR_WAIT=5, HEAD_REQ=6, HEAD_WAIT=7,
        CELL_START=8, CELL_WAIT=9, WRITE_REQ=10, WRITE_WAIT=11,
        DONE=12, FAIL=13;
    reg [4:0] state_r;
    reg [ADDR_W-1:0] head_base_r, destination_base_r, sigmoid_base_r, anchor_base_r;
    reg [SHAPE_W-1:0] h_r, w_r, x_r, y_r;
    reg [5:0] stride_r;
    reg [1:0] anchor_r, byte_r;
    reg [2:0] anchor_word_r, lane_r;
    reg [3:0] field_r;
    reg [7:0] lut_index_r;
    reg [31:0] word_r, anchor_q16_r [0:5];
    reg [15:0] sigmoid_r [0:255];
    reg [15:0] q_r [0:8];
    reg signed [127:0] box_r;
    reg [63:0] scores_r;
    reg [31:0] position_r;
    wire cell_valid_w;
    wire signed [31:0] x1_w, y1_w, x2_w, y2_w;
    wire [15:0] s0_w, s1_w, s2_w, s3_w;
    wire [7:0] sigmoid_index_w = $unsigned(memory_read_data_i) + 8'd128;
    wire [31:0] incoming_word_w = {memory_read_data_i, word_r[23:0]};

    v5n_anchor_decode_context cell_i(.error_o(numeric_error_o),
.context_req_valid(context_req_valid),.context_req_ready(context_req_ready),.context_mode(context_mode),.context_words(context_words),.context_rsp_valid(context_rsp_valid),.context_rsp_ready(context_rsp_ready),.context_rsp_data(context_rsp_data),.context_rsp_index(context_rsp_index),.context_rsp_last(context_rsp_last),.context_rsp_error(context_rsp_error),

        .clk_i(clk_i), .rst_ni(rst_ni), .valid_i(state_r==CELL_START),
        .sx_i(q_r[0]), .sy_i(q_r[1]), .sw_i(q_r[2]), .sh_i(q_r[3]), .obj_i(q_r[4]),
        .c0_i(q_r[5]), .c1_i(q_r[6]), .c2_i(q_r[7]), .c3_i(q_r[8]),
        .grid_x_i(x_r), .grid_y_i(y_r), .stride_i(stride_r),
        .anchor_w_q16_i(anchor_q16_r[anchor_r*2]),
        .anchor_h_q16_i(anchor_q16_r[anchor_r*2+1]),
        .valid_o(cell_valid_w), .x1_o(x1_w), .y1_o(y1_w), .x2_o(x2_w), .y2_o(y2_w),
        .score0_o(s0_w), .score1_o(s1_w), .score2_o(s2_w), .score3_o(s3_w));

    reg [31:0] lane_word_r;
    always @* begin
        case(lane_r)
            0:lane_word_r=box_r[31:0]; 1:lane_word_r=box_r[63:32];
            2:lane_word_r=box_r[95:64]; 3:lane_word_r=box_r[127:96];
            4:lane_word_r={16'd0,scores_r[15:0]}; 5:lane_word_r={16'd0,scores_r[31:16]};
            6:lane_word_r={16'd0,scores_r[47:32]}; default:lane_word_r={16'd0,scores_r[63:48]};
        endcase
    end
    assign busy_o = state_r!=IDLE && state_r!=DONE && state_r!=FAIL;
    assign memory_valid_o = state_r==LUT_REQ || state_r==ANCHOR_REQ || state_r==HEAD_REQ || state_r==WRITE_REQ;
    assign memory_write_o = state_r==WRITE_REQ;
    assign memory_use_hwc_o = state_r==HEAD_REQ;
    assign memory_raw_byte_address_o = state_r==LUT_REQ ? sigmoid_base_r+({24'd0,lut_index_r}<<2)+byte_r :
        state_r==ANCHOR_REQ ? anchor_base_r+({29'd0,anchor_word_r}<<2)+byte_r :
        destination_base_r+(position_r<<5)+({29'd0,lane_r}<<2)+byte_r;
    assign memory_tensor_base_o = head_base_r;
    assign memory_tensor_h_o=h_r; assign memory_tensor_w_o=w_r; assign memory_tensor_c_o=27;
    assign memory_y_o=y_r; assign memory_x_o=x_r;
    assign memory_channel_o=anchor_r*9+field_r;
    assign memory_write_data_o=lane_word_r[byte_r*8 +: 8];
    assign memory_response_ready_o=state_r==LUT_WAIT || state_r==ANCHOR_WAIT || state_r==HEAD_WAIT || state_r==WRITE_WAIT;
    integer i;
    always @(posedge clk_i or negedge rst_ni) begin
        if(!rst_ni) begin
            state_r<=IDLE; head_base_r<=0; destination_base_r<=0; sigmoid_base_r<=0; anchor_base_r<=0;
            h_r<=0;w_r<=0;stride_r<=0;x_r<=0;y_r<=0;anchor_r<=0;byte_r<=0;
            anchor_word_r<=0;lane_r<=0;field_r<=0;lut_index_r<=0;word_r<=0;
            box_r<=0;scores_r<=0;position_r<=0;done_o<=0;error_o<=0;
            for(i=0;i<9;i=i+1) q_r[i]<=0;
            for(i=0;i<6;i=i+1) anchor_q16_r[i]<=0;
            // LUT is not reset: every run replaces all256 entries before use.
        end else begin
            done_o<=0;
            if(numeric_error_o)begin error_o<=1;state_r<=FAIL;end else case(state_r)
                IDLE:if(start_i) begin
                    head_base_r<=head_base_i;destination_base_r<=destination_base_i;
                    sigmoid_base_r<=sigmoid_base_i;anchor_base_r<=anchor_base_i;
                    h_r<=tensor_h_i;w_r<=tensor_w_i;stride_r<=stride_i;
                    x_r<=0;y_r<=0;anchor_r<=0;byte_r<=0;anchor_word_r<=0;
                    field_r<=0;lut_index_r<=0;word_r<=0;position_r<=0;lane_r<=0;error_o<=0;
                    if(tensor_h_i==0 || tensor_w_i==0 || tensor_h_i>40 || tensor_w_i>40 ||
                       !(stride_i==8 || stride_i==16 || stride_i==32)) begin error_o<=1;state_r<=FAIL;end
                    else state_r<=LUT_REQ;
                end
                LUT_REQ:if(memory_ready_i) state_r<=LUT_WAIT;
                LUT_WAIT:if(memory_response_valid_i) begin
                    if(memory_response_error_i || memory_response_is_write_i) begin error_o<=1;state_r<=FAIL;end
                    else begin
                        word_r[byte_r*8 +: 8]<=memory_read_data_i;
                        if(byte_r==3) begin byte_r<=0;state_r<=LUT_STORE;end
                        else begin byte_r<=byte_r+1'b1;state_r<=LUT_REQ;end
                    end
                end
                LUT_STORE:begin
                    if(word_r>32768) begin error_o<=1;state_r<=FAIL;end
                    else begin
                        sigmoid_r[lut_index_r]<=word_r[15:0];
                        if(lut_index_r==255) begin word_r<=0;state_r<=ANCHOR_REQ;end
                        else begin lut_index_r<=lut_index_r+1'b1;state_r<=LUT_REQ;end
                    end
                end
                ANCHOR_REQ:if(memory_ready_i) state_r<=ANCHOR_WAIT;
                ANCHOR_WAIT:if(memory_response_valid_i) begin
                    if(memory_response_error_i || memory_response_is_write_i) begin error_o<=1;state_r<=FAIL;end
                    else begin
                        word_r[byte_r*8 +: 8]<=memory_read_data_i;
                        if(byte_r!=3) begin byte_r<=byte_r+1'b1;state_r<=ANCHOR_REQ;end
                        else if(incoming_word_w==0 || incoming_word_w>32'd33554432) begin error_o<=1;state_r<=FAIL;end
                        else begin
                            anchor_q16_r[anchor_word_r]<=incoming_word_w;byte_r<=0;word_r<=0;
                            if(anchor_word_r==5) state_r<=HEAD_REQ;
                            else begin anchor_word_r<=anchor_word_r+1'b1;state_r<=ANCHOR_REQ;end
                        end
                    end
                end
                HEAD_REQ:if(memory_ready_i) state_r<=HEAD_WAIT;
                HEAD_WAIT:if(memory_response_valid_i) begin
                    if(memory_response_error_i || memory_response_is_write_i) begin error_o<=1;state_r<=FAIL;end
                    else begin
                        q_r[field_r]<=sigmoid_r[sigmoid_index_w];
                        if(field_r==8) begin field_r<=0;state_r<=CELL_START;end
                        else begin field_r<=field_r+1'b1;state_r<=HEAD_REQ;end
                    end
                end
                CELL_START:state_r<=CELL_WAIT;
                CELL_WAIT:if(cell_valid_w) begin
                    box_r<={y2_w,x2_w,y1_w,x1_w};scores_r<={s3_w,s2_w,s1_w,s0_w};
                    byte_r<=0;lane_r<=0;state_r<=WRITE_REQ;
                end
                WRITE_REQ:if(memory_ready_i) state_r<=WRITE_WAIT;
                WRITE_WAIT:if(memory_response_valid_i) begin
                    if(memory_response_error_i || !memory_response_is_write_i) begin error_o<=1;state_r<=FAIL;end
                    else if(byte_r!=3) begin byte_r<=byte_r+1'b1;state_r<=WRITE_REQ;end
                    else if(lane_r!=7) begin byte_r<=0;lane_r<=lane_r+1'b1;state_r<=WRITE_REQ;end
                    else begin
                        byte_r<=0;lane_r<=0;position_r<=position_r+1'b1;
                        if(x_r+1<w_r) begin x_r<=x_r+1'b1;state_r<=HEAD_REQ;end
                        else if(y_r+1<h_r) begin x_r<=0;y_r<=y_r+1'b1;state_r<=HEAD_REQ;end
                        else if(anchor_r!=2) begin x_r<=0;y_r<=0;anchor_r<=anchor_r+1'b1;state_r<=HEAD_REQ;end
                        else state_r<=DONE;
                    end
                end
                DONE,FAIL:begin done_o<=1;state_r<=IDLE;end
                default:begin error_o<=1;state_r<=FAIL;end
            endcase
        end
    end
endmodule
