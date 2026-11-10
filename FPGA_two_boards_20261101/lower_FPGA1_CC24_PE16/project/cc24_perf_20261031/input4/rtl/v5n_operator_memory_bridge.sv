// Bridge existing operator byte requests onto the shared feature-memory service.
//
// No computation, parameter transformation or completion generation exists
// here.  A response is returned only when the shared memory service returns
// the corresponding physical-memory transaction response.
(* multstyle = "logic" *) module v5n_operator_memory_bridge #(
    parameter integer ADDR_W = 32,
    parameter integer SHAPE_W = 10,
    parameter integer OPERATOR_ID_W = 4,
    parameter integer WRITE_LINE_ENABLE = 0
) (
    input wire clk_i, input wire rst_ni,
    // Existing operator-side request ABI.
    input wire [OPERATOR_ID_W-1:0] operator_id_i,
    input wire operator_memory_valid_i, output wire operator_memory_ready_o,
    input wire operator_memory_write_i, input wire operator_memory_use_hwc_i,
    input wire operator_memory_byte_enable_i,
    input wire [ADDR_W-1:0] operator_memory_raw_byte_address_i,
    input wire [ADDR_W-1:0] operator_memory_tensor_base_i,
    input wire [SHAPE_W-1:0] operator_memory_tensor_h_i, operator_memory_tensor_w_i, operator_memory_tensor_c_i,
    input wire [SHAPE_W-1:0] operator_memory_y_i, operator_memory_x_i, operator_memory_channel_i,
    input wire signed [7:0] operator_memory_write_data_i,
    input wire operator_memory_write_line_i,
    input wire [127:0] operator_memory_write_line_data_i,
    output wire operator_memory_response_valid_o, input wire operator_memory_response_ready_i,
    output wire operator_memory_response_error_o, output wire operator_memory_response_is_write_o,
    output wire signed [7:0] operator_memory_read_data_o,
    output wire operator_read_line_valid_o,
    output wire [ADDR_W-1:0] operator_read_line_address_o,
    output wire [127:0] operator_read_line_data_o,
    output wire operator_line_invalidate_o,
    // Shared-service client ABI.
    output wire shared_memory_valid_o, input wire shared_memory_ready_i,
    output wire shared_memory_write_o, output wire [ADDR_W-1:0] shared_memory_address_o,
    output wire signed [7:0] shared_memory_write_data_o,
    output wire shared_memory_write_line_o,
    output wire [127:0] shared_memory_write_line_data_o,
    input wire shared_memory_response_valid_i, output wire shared_memory_response_ready_o,
    input wire shared_memory_response_error_i, input wire shared_memory_response_is_write_i,
    input wire signed [7:0] shared_memory_read_data_i,
    input wire shared_read_line_valid_i,
    input wire [ADDR_W-1:0] shared_read_line_address_i,
    input wire [127:0] shared_read_line_data_i,
    input wire shared_line_invalidate_i,
    output wire [OPERATOR_ID_W-1:0] active_operator_id_o, output wire busy_o,
    output wire [2:0] state_o
);
    localparam [2:0] ST_IDLE = 3'd0, ST_HWC_ROW = 3'd1, ST_HWC_CHANNEL = 3'd2,
                     ST_ISSUE = 3'd3, ST_RESPONSE = 3'd4, ST_HWC_CHECK = 3'd5;
    reg [2:0] state_r; reg [OPERATOR_ID_W-1:0] operator_id_r; reg write_r;
    reg write_line_r;
    reg [127:0] write_line_data_r;
    wire request_line_w=(WRITE_LINE_ENABLE!=0)&&operator_memory_write_line_i;
    wire line_span_error_w=request_line_w&&!operator_memory_write_i;
    reg [ADDR_W-1:0] address_r; reg signed [7:0] write_data_r; reg error_r, no_access_r;
    wire line_address_error_w=write_line_r&&(address_r[3:0]!=0);
    reg [ADDR_W-1:0] y_wide_r, x_wide_r, c_wide_r, height_wide_r, width_wide_r, channels_wide_r;
    reg [ADDR_W-1:0] tensor_base_r, row_offset_r;
    reg [ADDR_W-1:0] multiply_accumulator_r, multiply_multiplicand_r;
    reg [SHAPE_W-1:0] multiply_multiplier_r;
    reg [3:0] multiply_bit_r;
    // Low-concurrency candidate: no read/write address memoization banks.
    // Every HWC request uses the original full-width resolver in captured order.
    wire [ADDR_W-1:0] multiply_sum_w=multiply_accumulator_r+
      (multiply_multiplier_r[0]?multiply_multiplicand_r:{ADDR_W{1'b0}});
    // Check only captured coordinates. Otherwise Concat's source-channel
    // resolver feeds a second bounds comparator and the raw-address register
    // enable in the same cycle (14 levels in routed Camera attempt2).
    wire hwc_in_bounds_w = (y_wide_r < height_wide_r) &&
                           (x_wide_r < width_wide_r) &&
                           (c_wide_r < channels_wide_r);
    wire hwc_line_span_error_w=write_line_r&&(c_wide_r+16>channels_wide_r);
    // Captured bounds and original arithmetic/error order remain unchanged.
    assign operator_memory_ready_o = (state_r == ST_IDLE);
    assign shared_memory_valid_o = (state_r == ST_ISSUE) && !no_access_r && !line_address_error_w;
    assign shared_memory_write_o = write_r; assign shared_memory_address_o = address_r; assign shared_memory_write_data_o = write_data_r;
    assign shared_memory_write_line_o=write_line_r;
    assign shared_memory_write_line_data_o=write_line_data_r;
    assign shared_memory_response_ready_o = (state_r == ST_RESPONSE) && operator_memory_response_ready_i && !error_r && !no_access_r;
    assign operator_memory_response_valid_o = (state_r == ST_RESPONSE) && (error_r || no_access_r || shared_memory_response_valid_i);
    assign operator_memory_response_error_o = error_r || shared_memory_response_error_i;
    assign operator_memory_response_is_write_o = (error_r || no_access_r) ? write_r : shared_memory_response_is_write_i;
    assign operator_memory_read_data_o = error_r ? 8'sd0 : shared_memory_read_data_i;
    assign operator_read_line_valid_o = operator_memory_response_valid_o &&
        !operator_memory_response_error_o && !operator_memory_response_is_write_o &&
        !no_access_r && shared_read_line_valid_i &&
        // A real response owner alone does not qualify an unrelated line tag.
        // Wrong/stale line addresses use the original scalar response fallback.
        (shared_read_line_address_i=={address_r[ADDR_W-1:4],4'b0});
    assign operator_read_line_address_o = shared_read_line_address_i;
    assign operator_read_line_data_o = shared_read_line_data_i;
    assign operator_line_invalidate_o = shared_line_invalidate_i;
    assign active_operator_id_o = operator_id_r; assign busy_o = (state_r != ST_IDLE);
    assign state_o = state_r;
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin state_r <= ST_IDLE; operator_id_r <= 0; write_r <= 0; address_r <= 0; write_data_r <= 0; error_r <= 0; no_access_r <= 0;
            write_line_r<=0;write_line_data_r<=0;
            y_wide_r<=0;x_wide_r<=0;c_wide_r<=0;height_wide_r<=0;width_wide_r<=0;channels_wide_r<=0;tensor_base_r<=0;row_offset_r<=0;
            multiply_accumulator_r<=0;multiply_multiplicand_r<=0;multiply_multiplier_r<=0;multiply_bit_r<=0;

        end
        else case (state_r)
            ST_IDLE: if (operator_memory_valid_i) begin
                operator_id_r <= operator_id_i; write_r <= operator_memory_write_i; write_data_r <= operator_memory_write_data_i; error_r <= 1'b0; no_access_r <= !operator_memory_byte_enable_i;
                write_line_r<=request_line_w;
                write_line_data_r<=operator_memory_write_line_data_i;
                if (!operator_memory_byte_enable_i) begin address_r <= 0; state_r <= ST_RESPONSE; end
                else if(line_span_error_w)begin address_r<=0;error_r<=1;state_r<=ST_RESPONSE;end
                else if(operator_memory_use_hwc_i) begin
                    y_wide_r<=operator_memory_y_i;x_wide_r<=operator_memory_x_i;c_wide_r<=operator_memory_channel_i;
                    height_wide_r<=operator_memory_tensor_h_i;width_wide_r<=operator_memory_tensor_w_i;channels_wide_r<=operator_memory_tensor_c_i;
                    tensor_base_r<=operator_memory_tensor_base_i;
                    state_r<=ST_HWC_CHECK;
                end else begin address_r <= operator_memory_raw_byte_address_i; state_r <= ST_ISSUE; end
            end
            ST_HWC_CHECK: begin
                    if(!hwc_in_bounds_w||hwc_line_span_error_w)begin
                        address_r<=0;error_r<=1'b1;state_r<=ST_RESPONSE;
                    end else begin
                        multiply_accumulator_r<=0;multiply_multiplicand_r<=y_wide_r;
                        multiply_multiplier_r<=width_wide_r[SHAPE_W-1:0];multiply_bit_r<=0;state_r<=ST_HWC_ROW;
                    end
            end
            ST_HWC_ROW: begin
                multiply_accumulator_r<=multiply_sum_w;
                multiply_multiplicand_r<=multiply_multiplicand_r<<1;
                multiply_multiplier_r<=multiply_multiplier_r>>1;
                if(multiply_bit_r==SHAPE_W-1) begin
                    row_offset_r<=multiply_sum_w;multiply_accumulator_r<=0;
                    multiply_multiplicand_r<=multiply_sum_w+x_wide_r;
                    multiply_multiplier_r<=channels_wide_r;multiply_bit_r<=0;state_r<=ST_HWC_CHANNEL;
                end else multiply_bit_r<=multiply_bit_r+1'b1;
            end
            ST_HWC_CHANNEL: begin
                multiply_accumulator_r<=multiply_sum_w;
                multiply_multiplicand_r<=multiply_multiplicand_r<<1;
                multiply_multiplier_r<=multiply_multiplier_r>>1;
                if(multiply_bit_r==SHAPE_W-1) begin
                    address_r<=tensor_base_r+multiply_sum_w+c_wide_r;
                    state_r<=ST_ISSUE;
                end else multiply_bit_r<=multiply_bit_r+1'b1;
            end
            ST_ISSUE: begin
                if(line_address_error_w)begin error_r<=1;state_r<=ST_RESPONSE;end
                else if(shared_memory_ready_i)state_r<=ST_RESPONSE;
            end
            ST_RESPONSE: if (operator_memory_response_valid_o && operator_memory_response_ready_i) state_r <= ST_IDLE;
            default: state_r <= ST_IDLE;
        endcase
    end
endmodule
