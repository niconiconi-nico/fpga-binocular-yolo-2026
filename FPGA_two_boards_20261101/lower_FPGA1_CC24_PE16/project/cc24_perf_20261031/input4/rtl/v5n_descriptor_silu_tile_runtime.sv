// One descriptor-driven SiLU tile transaction using the package's real LUT.
//
// The CONV and SiLU records are intentionally separate. This runtime first
// loads the 256-entry signed INT8 LUT from the descriptor-addressed parameter
// image, then performs HWC-addressed feature reads and writes for one tile.
// No activation result or LUT value is embedded in RTL.
module v5n_descriptor_silu_tile_runtime #(
    parameter integer ADDR_W = 32,
    parameter integer SHAPE_W = 10
) (
    input wire clk_i, input wire rst_ni, input wire start_i,
    input wire descriptor_valid_i, input wire [7:0] descriptor_id_i,
    input wire [3:0] opcode_i,
    input wire [ADDR_W-1:0] source_tensor_base_i,
    input wire [ADDR_W-1:0] destination_tensor_base_i,
    input wire [SHAPE_W-1:0] tensor_h_i, input wire [SHAPE_W-1:0] tensor_w_i,
    input wire [SHAPE_W-1:0] tensor_c_i,
    input wire [ADDR_W-1:0] lut_address_i, input wire [ADDR_W-1:0] lut_bytes_i,
    input wire [SHAPE_W-1:0] tile_origin_y_i, input wire [SHAPE_W-1:0] tile_origin_x_i,
    input wire [SHAPE_W-1:0] tile_h_i, input wire [SHAPE_W-1:0] tile_w_i,
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
    localparam [3:0] ST_IDLE=4'd0, ST_LUT_REQ=4'd1, ST_LUT_WAIT=4'd2,
                     ST_READ_REQ=4'd3, ST_READ_WAIT=4'd4, ST_APPLY=4'd5,
                     ST_OUTPUT_WAIT=4'd6, ST_WRITE_REQ=4'd7, ST_WRITE_WAIT=4'd8,
                     ST_DONE=4'd9, ST_FAIL=4'd10;
    reg [3:0] state_r;
    reg [7:0] lut_index_r;
    reg [SHAPE_W-1:0] y_r, x_r, c_r;
    reg signed [7:0] input_code_r;
    reg [31:0] cycle_r;
    wire lut_valid_w;
    wire signed [7:0] lut_code_w;
    wire last_element_w = (y_r + 1 >= tile_h_i) && (x_r + 1 >= tile_w_i) && (c_r + 1 >= tensor_c_i);
    wire [SHAPE_W-1:0] absolute_y_w = tile_origin_y_i + y_r;
    wire [SHAPE_W-1:0] absolute_x_w = tile_origin_x_i + x_r;

    v5n_lut256_i8 #(.NUM_LANES(1)) lut (
        .clk_i(clk_i), .rst_ni(rst_ni),
        .cfg_write_enable_i((state_r == ST_LUT_WAIT) && memory_response_valid_i && !memory_response_error_i),
        .cfg_address_i(lut_index_r), .cfg_data_i(memory_read_data_i),
        .valid_i(state_r == ST_APPLY), .code_i(input_code_r),
        .valid_o(lut_valid_w), .code_o(lut_code_w)
    );

    assign busy_o = (state_r != ST_IDLE) && (state_r != ST_DONE) && (state_r != ST_FAIL);
    assign state_o = state_r;
    assign cycle_count_o = cycle_r;
    assign memory_valid_o = (state_r == ST_LUT_REQ) || (state_r == ST_READ_REQ) || (state_r == ST_WRITE_REQ);
    assign memory_write_o = (state_r == ST_WRITE_REQ);
    assign memory_use_hwc_o = (state_r == ST_READ_REQ) || (state_r == ST_WRITE_REQ);
    assign memory_raw_byte_address_o = lut_address_i + lut_index_r;
    assign memory_tensor_base_o = (state_r == ST_WRITE_REQ) ? destination_tensor_base_i : source_tensor_base_i;
    assign memory_tensor_h_o = tensor_h_i;
    assign memory_tensor_w_o = tensor_w_i;
    assign memory_tensor_c_o = tensor_c_i;
    assign memory_y_o = absolute_y_w;
    assign memory_x_o = absolute_x_w;
    assign memory_channel_o = c_r;
    assign memory_write_data_o = lut_code_w;
    assign memory_response_ready_o = (state_r == ST_LUT_WAIT) || (state_r == ST_READ_WAIT) || (state_r == ST_WRITE_WAIT);

    task advance_element;
        begin
            if (c_r + 1 >= tensor_c_i) begin
                c_r <= 0;
                if (x_r + 1 >= tile_w_i) begin
                    x_r <= 0;
                    y_r <= y_r + 1'b1;
                end else x_r <= x_r + 1'b1;
            end else c_r <= c_r + 1'b1;
        end
    endtask

    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            state_r <= ST_IDLE; lut_index_r <= 0; y_r <= 0; x_r <= 0; c_r <= 0;
            input_code_r <= 0; cycle_r <= 0; done_o <= 0; error_o <= 0;
        end else begin
            done_o <= 1'b0;
            if (busy_o) cycle_r <= cycle_r + 1'b1;
            case (state_r)
                ST_IDLE: if (start_i) begin
                    cycle_r <= 0; error_o <= 0; lut_index_r <= 0; y_r <= 0; x_r <= 0; c_r <= 0;
                    if (!descriptor_valid_i || opcode_i != 4'd2 || lut_bytes_i != 32'd256 ||
                        tile_h_i == 0 || tile_w_i == 0 || tensor_c_i == 0 ||
                        tile_origin_y_i + tile_h_i > tensor_h_i || tile_origin_x_i + tile_w_i > tensor_w_i) begin
                        error_o <= 1'b1; state_r <= ST_FAIL;
                    end else state_r <= ST_LUT_REQ;
                end
                ST_LUT_REQ: if (memory_ready_i) state_r <= ST_LUT_WAIT;
                ST_LUT_WAIT: if (memory_response_valid_i) begin
                    if (memory_response_error_i) begin error_o <= 1'b1; state_r <= ST_FAIL; end
                    else if (lut_index_r == 8'hff) state_r <= ST_READ_REQ;
                    else begin lut_index_r <= lut_index_r + 1'b1; state_r <= ST_LUT_REQ; end
                end
                ST_READ_REQ: if (memory_ready_i) state_r <= ST_READ_WAIT;
                ST_READ_WAIT: if (memory_response_valid_i) begin
                    if (memory_response_error_i || memory_response_is_write_i) begin error_o <= 1'b1; state_r <= ST_FAIL; end
                    else begin input_code_r <= memory_read_data_i; state_r <= ST_APPLY; end
                end
                ST_APPLY: state_r <= ST_OUTPUT_WAIT;
                ST_OUTPUT_WAIT: if (lut_valid_w) state_r <= ST_WRITE_REQ;
                ST_WRITE_REQ: if (memory_ready_i) state_r <= ST_WRITE_WAIT;
                ST_WRITE_WAIT: if (memory_response_valid_i) begin
                    if (memory_response_error_i || !memory_response_is_write_i) begin error_o <= 1'b1; state_r <= ST_FAIL; end
                    else if (last_element_w) state_r <= ST_DONE;
                    else begin advance_element; state_r <= ST_READ_REQ; end
                end
                ST_DONE: begin done_o <= 1'b1; state_r <= ST_IDLE; end
                default: state_r <= ST_FAIL;
            endcase
        end
    end
endmodule
