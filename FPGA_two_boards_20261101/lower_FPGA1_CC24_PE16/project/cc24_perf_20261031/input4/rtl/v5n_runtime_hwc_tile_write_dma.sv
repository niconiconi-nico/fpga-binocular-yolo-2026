// Descriptor-configured HWC tile writer.
//
// Unlike a contiguous drain DMA, this unit maps compact tile-order bytes back
// into their row-strided HWC positions in the full destination tensor.  This
// is required before a later descriptor can consume a non-zero-origin tile
// from DDR.  It owns no tensor contents and never synthesizes result data.
(* multstyle = "logic" *) module v5n_runtime_hwc_tile_write_dma #(
    parameter integer ADDR_W = 32,
    parameter integer SHAPE_W = 10,
    parameter integer WRITE_LINE_ENABLE = 0
) (
    input wire clk_i, input wire rst_ni, input wire start_i,
    input wire [ADDR_W-1:0] destination_tensor_base_i,
    // destination_tensor_c_i controls the HWC row stride in external DDR;
    // source_c_i is the compact tile channel count.  They differ only when
    // a wide Conv is time-multiplexed by output-channel slices.
    input wire [SHAPE_W-1:0] output_w_i, input wire [SHAPE_W-1:0] destination_tensor_c_i,
    input wire [SHAPE_W-1:0] source_c_i, input wire [SHAPE_W-1:0] destination_channel_offset_i,
    input wire [SHAPE_W-1:0] tile_origin_y_i, input wire [SHAPE_W-1:0] tile_origin_x_i,
    input wire [SHAPE_W-1:0] tile_h_i, input wire [SHAPE_W-1:0] tile_w_i,
    output wire busy_o, output reg done_o, output reg error_o,
    input wire source_valid_i, output wire source_ready_o,
    input wire signed [7:0] source_data_i, input wire source_last_i,
    output wire memory_valid_o, input wire memory_ready_i,
    output wire memory_write_o, output wire [ADDR_W-1:0] memory_raw_byte_address_o,
    output wire signed [7:0] memory_write_data_o,
    output wire memory_write_line_o, output wire [127:0] memory_write_line_data_o,
    input wire memory_response_valid_i, output wire memory_response_ready_o,
    input wire memory_response_error_i, input wire memory_response_is_write_i
);
    localparam [2:0] ST_IDLE=3'd0, ST_INIT_ROW=3'd1,
                     ST_INIT_CHANNEL=3'd2, ST_INIT_GAP=3'd3,
                     ST_SOURCE=3'd4, ST_ISSUE=3'd5, ST_WAIT=3'd6, ST_SOURCE_GAP=3'd7;
    reg [2:0] state_r;
    reg [SHAPE_W-1:0] y_r, x_r, c_r;
    reg signed [7:0] data_r;
    reg last_r;
    reg wide_r;
    reg [3:0] gather_lane_r;
    reg [127:0] gather_data_r;
    wire last_pixel_w=(y_r+1>=tile_h_i)&&(x_r+1>=tile_w_i);
    wire last_transaction_w=last_pixel_w && (c_r+(wide_r?16:1)>=source_c_i);
    wire expected_source_last_w=last_pixel_w && (c_r+gather_lane_r+1>=source_c_i);
    wire last_element_w = (y_r + 1 >= tile_h_i) && (x_r + 1 >= tile_w_i) && (c_r + 1 >= source_c_i);
    reg [ADDR_W-1:0] address_r, initial_offset_r;
    reg [ADDR_W-1:0] pixel_advance_r, row_advance_r;
    reg [ADDR_W-1:0] multiply_accumulator_r, multiply_multiplicand_r;
    reg [SHAPE_W-1:0] multiply_multiplier_r;
    reg [3:0] multiply_bit_r;
    wire [ADDR_W-1:0] multiply_sum_w = multiply_accumulator_r +
        (multiply_multiplier_r[0] ? multiply_multiplicand_r : {ADDR_W{1'b0}});
    assign busy_o = (state_r != ST_IDLE);
    assign source_ready_o = (state_r == ST_SOURCE);
    assign memory_valid_o = (state_r == ST_ISSUE);
    assign memory_write_o = 1'b1;
    assign memory_raw_byte_address_o = address_r;
    assign memory_write_data_o = data_r;
    assign memory_write_line_o = wide_r;
    assign memory_write_line_data_o = gather_data_r;
    assign memory_response_ready_o = (state_r == ST_WAIT);

    task advance_element;
        begin
            if (c_r + 1 >= source_c_i) begin
                c_r <= 0;
                if (x_r + 1 >= tile_w_i) begin
                    x_r <= 0;
                    y_r <= y_r + 1'b1;
                end else begin
                    x_r <= x_r + 1'b1;
                end
            end else begin
                c_r <= c_r + 1'b1;
            end
        end
    endtask

    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            state_r <= ST_IDLE; y_r <= 0; x_r <= 0; c_r <= 0;
            data_r <= 0; last_r <= 0; done_o <= 0; error_o <= 0;
            wide_r<=0; gather_lane_r<=0; gather_data_r<=0;
            address_r <= 0; initial_offset_r <= 0;
            pixel_advance_r <= 0; row_advance_r <= 0;
            multiply_accumulator_r <= 0; multiply_multiplicand_r <= 0;
            multiply_multiplier_r <= 0; multiply_bit_r <= 0;
        end else begin
            done_o <= 1'b0;
            case (state_r)
                ST_IDLE: if (start_i) begin
                    y_r <= 0; x_r <= 0; c_r <= 0; error_o <= 1'b0;
                    gather_lane_r<=0;
                    wide_r <= WRITE_LINE_ENABLE!=0 && source_c_i[3:0]==0 &&
                        destination_tensor_c_i[3:0]==0 && destination_tensor_base_i[3:0]==0 &&
                        destination_channel_offset_i[3:0]==0;
                    if (tile_h_i == 0 || tile_w_i == 0 || source_c_i == 0 ||
                        destination_tensor_c_i == 0 ||
                        (destination_channel_offset_i + source_c_i > destination_tensor_c_i))
                        begin error_o <= 1'b1; state_r <= ST_IDLE; end
                    else begin
                        multiply_accumulator_r <= 0;
                        multiply_multiplicand_r <= tile_origin_y_i;
                        multiply_multiplier_r <= output_w_i;
                        multiply_bit_r <= 0;
                        state_r <= ST_INIT_ROW;
                    end
                end
                ST_INIT_ROW: begin
                    multiply_accumulator_r <= multiply_sum_w;
                    multiply_multiplicand_r <= multiply_multiplicand_r << 1;
                    multiply_multiplier_r <= multiply_multiplier_r >> 1;
                    if (multiply_bit_r == SHAPE_W-1) begin
                        multiply_accumulator_r <= 0;
                        multiply_multiplicand_r <= multiply_sum_w + tile_origin_x_i;
                        multiply_multiplier_r <= destination_tensor_c_i;
                        multiply_bit_r <= 0;
                        state_r <= ST_INIT_CHANNEL;
                    end else multiply_bit_r <= multiply_bit_r + 1'b1;
                end
                ST_INIT_CHANNEL: begin
                    multiply_accumulator_r <= multiply_sum_w;
                    multiply_multiplicand_r <= multiply_multiplicand_r << 1;
                    multiply_multiplier_r <= multiply_multiplier_r >> 1;
                    if (multiply_bit_r == SHAPE_W-1) begin
                        initial_offset_r <= multiply_sum_w;
                        multiply_accumulator_r <= 0;
                        multiply_multiplicand_r <= output_w_i - tile_w_i;
                        multiply_multiplier_r <= destination_tensor_c_i;
                        multiply_bit_r <= 0;
                        state_r <= ST_INIT_GAP;
                    end else multiply_bit_r <= multiply_bit_r + 1'b1;
                end
                ST_INIT_GAP: begin
                    multiply_accumulator_r <= multiply_sum_w;
                    multiply_multiplicand_r <= multiply_multiplicand_r << 1;
                    multiply_multiplier_r <= multiply_multiplier_r >> 1;
                    if (multiply_bit_r == SHAPE_W-1) begin
                        address_r <= destination_tensor_base_i + initial_offset_r +
                                     destination_channel_offset_i;
                        pixel_advance_r <= destination_tensor_c_i - source_c_i + 1'b1;
                        row_advance_r <= multiply_sum_w + destination_tensor_c_i -
                                         source_c_i + 1'b1;
                        state_r <= ST_SOURCE;
                    end else multiply_bit_r <= multiply_bit_r + 1'b1;
                end
                ST_SOURCE: if (source_valid_i) begin
                    data_r <= source_data_i; last_r <= source_last_i;
                    if(!wide_r) state_r <= ST_ISSUE;
                    else if(source_last_i != expected_source_last_w)begin
                        error_o<=1'b1;state_r<=ST_IDLE;
                    end else begin
                        gather_data_r[gather_lane_r*8+:8]<=source_data_i;
                        if(gather_lane_r==15)state_r<=ST_ISSUE;
                        else begin gather_lane_r<=gather_lane_r+1'b1;state_r<=ST_SOURCE_GAP;end
                    end
                end
                // ERAM NOREG still has a synchronous array read. The producer
                // increments its read address on source acceptance; leave one
                // clock for the next returned byte before accepting it.
                ST_SOURCE_GAP: state_r<=ST_SOURCE;
                ST_ISSUE: if (memory_ready_i) state_r <= ST_WAIT;
                ST_WAIT: if (memory_response_valid_i) begin
                    if (memory_response_error_i || !memory_response_is_write_i || (last_r != last_transaction_w)) begin
                        error_o <= 1'b1; state_r <= ST_IDLE;
                    end else if (last_transaction_w) begin
                        done_o <= 1'b1; state_r <= ST_IDLE;
                    end else if(wide_r)begin
                        gather_lane_r<=0;
                        if(c_r+16>=source_c_i)begin
                            c_r<=0;
                            if(x_r+1>=tile_w_i)begin
                                x_r<=0;y_r<=y_r+1'b1;
                                address_r<=address_r+row_advance_r+15;
                            end else begin
                                x_r<=x_r+1'b1;address_r<=address_r+pixel_advance_r+15;
                            end
                        end else begin c_r<=c_r+16;address_r<=address_r+16;end
                        state_r<=ST_SOURCE;
                    end else begin
                        if (c_r + 1 >= source_c_i) begin
                            if (x_r + 1 >= tile_w_i)
                                address_r <= address_r + row_advance_r;
                            else
                                address_r <= address_r + pixel_advance_r;
                        end else begin
                            address_r <= address_r + 1'b1;
                        end
                        advance_element; state_r <= ST_SOURCE;
                    end
                end
                default: state_r <= ST_IDLE;
            endcase
        end
    end
endmodule
