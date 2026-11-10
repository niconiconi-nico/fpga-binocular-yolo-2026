// Descriptor-addressed Conv parameter loader for the runtime tile path.
//
// The loader moves bytes only through the tensor-memory adapter client ABI.
// Weight bytes are committed to the frozen parameter ERAM cache. Requant
// multipliers and bias numerators are assembled little-endian into the live
// four-PE parameter lookup bank. This block contains no model constants.
`include "v5n_weight_capacity.vh"
module v5n_conv_tile_parameter_loader #(
    parameter integer ADDR_W = 32,
    parameter integer CHANNEL_W = 10,
    parameter integer NUM_PE = 4,
    parameter integer WEIGHT_ADDR_W = (NUM_PE==1 ? 15 : 14),
    parameter integer LINE_PREFETCH = 0,
    parameter integer MAX_CHANNELS = 64
) (
    input wire clk_i, input wire rst_ni, input wire start_i,
    input wire memory_line_valid_i,input wire [ADDR_W-1:0] memory_line_address_i,
    input wire [127:0] memory_line_data_i,input wire memory_line_invalidate_i,
    input wire [ADDR_W-1:0] weight_address_i, input wire [ADDR_W-1:0] weight_bytes_i,
    input wire [ADDR_W-1:0] bias_address_i, input wire [ADDR_W-1:0] bias_bytes_i,
    input wire [ADDR_W-1:0] requant_address_i, input wire [ADDR_W-1:0] requant_bytes_i,
    input wire [CHANNEL_W-1:0] output_channels_i,
    output wire busy_o, output reg done_o, output reg error_o,
    output wire memory_valid_o, input wire memory_ready_i,
    output wire [ADDR_W-1:0] memory_raw_byte_address_o,
    input wire memory_response_valid_i, output wire memory_response_ready_o,
    input wire memory_response_error_i, input wire signed [7:0] memory_read_data_i,
    output wire weight_load_valid_o, input wire weight_load_ready_i,
    output wire [3:0] weight_load_lane_o,
    output wire [WEIGHT_ADDR_W-1:0] weight_load_offset_o, output wire [7:0] weight_load_data_o,
    output wire weight_load_last_o,
    input wire [CHANNEL_W-1:0] parameter_index_i,
    output wire signed [31:0] parameter_multiplier_o,
    output wire signed [31:0] parameter_bias_o
);
    localparam [2:0] ST_IDLE = 3'd0, ST_WEIGHT = 3'd1, ST_BIAS = 3'd2,
                     ST_REQUANT = 3'd3, ST_DONE = 3'd4, ST_FAIL = 3'd5;
    reg [2:0] state_r;
    reg [ADDR_W-1:0] offset_r;
    reg [ADDR_W-1:0] weight_address_r, bias_address_r, requant_address_r;
    reg [ADDR_W-1:0] weight_bytes_r, bias_bytes_r, requant_bytes_r;
    reg waiting_response_r;
    // Consume all remaining bytes of a real shared-service read line locally.
    // Data is never invented, DDR writes remain acknowledged, and start/snoop
    // invalidate the line. The original scalar fallback remains available.
    reg line_valid_r;
    reg [ADDR_W-5:0] line_tag_r;
    reg [127:0] line_data_r;
    wire line_hit_w = LINE_PREFETCH && line_valid_r && !waiting_response_r &&
        !memory_line_invalidate_i &&
        line_tag_r == memory_raw_byte_address_o[ADDR_W-1:4];
    wire read_available_w = (waiting_response_r && memory_response_valid_i) || line_hit_w;
    wire read_error_w = waiting_response_r && memory_response_error_i;
    wire read_accept_w = read_available_w &&
        ((state_r != ST_WEIGHT) || weight_load_ready_i);
    wire signed [7:0] read_value_w = line_hit_w ?
        $signed(line_data_r[memory_raw_byte_address_o[3:0]*8 +: 8]) : memory_read_data_i;
    localparam integer PARAM_ADDR_W = $clog2(MAX_CHANNELS);
    reg [31:0] parameter_word_r;
    reg [13:0] weight_channel_stride_r, weight_plane_offset_r;
    reg [CHANNEL_W-1:0] weight_channel_r;
    reg [CHANNEL_W-1:0] output_channels_r;
    reg [WEIGHT_ADDR_W-1:0] weight_bank_offset_r [0:NUM_PE-1];
    reg [3:0] weight_bank_select_r;
    reg [WEIGHT_ADDR_W-1:0] weight_group_offset_r;
    wire parameter_word_write_w = read_accept_w && !read_error_w &&
                                  ((state_r == ST_BIAS) || (state_r == ST_REQUANT)) &&
                                  (offset_r[1:0] == 2'b11);
    wire bias_write_w = parameter_word_write_w && (state_r == ST_BIAS);
    wire multiplier_write_w = parameter_word_write_w && (state_r == ST_REQUANT);
    wire [PARAM_ADDR_W-1:0] parameter_write_address_w =
        offset_r[PARAM_ADDR_W+1:2];
    wire [31:0] parameter_write_data_w =
        {read_value_w, parameter_word_r[23:0]};

    assign busy_o = (state_r != ST_IDLE) && (state_r != ST_DONE) && (state_r != ST_FAIL);
    assign memory_valid_o = busy_o && !waiting_response_r && !line_hit_w &&
                            !((state_r == ST_WEIGHT) && !weight_load_ready_i);
    assign memory_response_ready_o = busy_o && waiting_response_r &&
                                     !((state_r == ST_WEIGHT) && !weight_load_ready_i);
    assign memory_raw_byte_address_o = (state_r == ST_WEIGHT) ? weight_address_r + offset_r :
                                             (state_r == ST_BIAS) ? bias_address_r + offset_r :
                                             requant_address_r + offset_r;
    assign weight_load_valid_o = (state_r == ST_WEIGHT) && read_available_w && !read_error_w;
    // A PE16 cache has sixteen 1-KiB physical banks.  When a channel slice has
    // fewer than sixteen output channels, stripe every weight plane across the
    // otherwise-idle banks.  This is required by real 3x3 layers: for example
    // Cin=128 occupies 1152 bytes per output channel, so a Cout=8 slice needs
    // two banks per channel.  Byte-interleaving keeps the bank-local address a
    // simple right shift and matches the read crossbar in param_tile_cache.
    always @* begin
        if (NUM_PE == 1) begin
            weight_bank_select_r = 0;
        end else if (NUM_PE == 2) begin
            if (output_channels_r >= 2) weight_bank_select_r = {3'd0,weight_channel_r[0]};
            else weight_bank_select_r = {3'd0,weight_plane_offset_r[0]};
        end else if (NUM_PE == 4) begin
            // CC2 PE4 cache: lane bank = channel[1:0] for every slice width, no
            // plane striping. 1/2-channel slices leave the other lanes idle (the
            // engine masks lanes >= cfg_output_c_i). Each bank holds 4 KiB.
            weight_bank_select_r = {2'd0,weight_channel_r[1:0]};
        end else if (NUM_PE == 8) begin
            // CC7 PE8 cache: lane bank = channel[2:0] for every slice width, no plane
            // striping; narrower slices leave lanes idle (engine masks them). 2 KiB/bank.
            weight_bank_select_r = {1'd0,weight_channel_r[2:0]};
        end else if (NUM_PE == 16 || output_channels_r >= 16)
            weight_bank_select_r = weight_channel_r[3:0];
        else begin
            case (output_channels_r)
                10'd8: weight_bank_select_r = {weight_channel_r[2:0],weight_plane_offset_r[0]};
                10'd4: weight_bank_select_r = {weight_channel_r[1:0],weight_plane_offset_r[1:0]};
                10'd2: weight_bank_select_r = {weight_channel_r[0],weight_plane_offset_r[2:0]};
                default: weight_bank_select_r = weight_plane_offset_r[3:0];
            endcase
        end
    end
    assign weight_load_lane_o = weight_bank_select_r;
    assign weight_load_offset_o = NUM_PE==16 ? weight_group_offset_r + weight_plane_offset_r : weight_bank_offset_r[weight_bank_select_r];
    assign weight_load_data_o = read_value_w;
    assign weight_load_last_o = (state_r == ST_WEIGHT) && (offset_r + 1 >= weight_bytes_r);

    // Requantization is already serialized across lanes. One multiplier ERAM
    // and one bias ERAM therefore serve the same scalar issue stream, avoiding
    // 16 replicated parameter read ports in the PE16 configuration.
    wire [31:0] multiplier_read_w, bias_read_w;
    wire [31:0] multiplier_write_port_unused_w, bias_write_port_unused_w;
    // The ERAM read is synchronous.  During collection of the final local
    // channel (address 63), parameter_index_i has already advanced to 64,
    // while multiplier_read_w/bias_read_w still contain the valid address-63
    // result from the preceding clock.  Gating the output with the live index
    // therefore zeroed exactly channel 63.  The executor qualifies collected
    // lanes, so expose the registered ERAM result without a live-index gate.
    assign parameter_multiplier_o = multiplier_read_w;
    assign parameter_bias_o = bias_read_w;

            PH1P_LOGIC_ERAM #(
                .DATA_WIDTH_A(32), .DATA_WIDTH_B(32),
                .ADDR_WIDTH_A(PARAM_ADDR_W), .ADDR_WIDTH_B(PARAM_ADDR_W),
                .DATA_DEPTH_A(MAX_CHANNELS), .DATA_DEPTH_B(MAX_CHANNELS),
                .MODE("DP"), .REGMODE_A("NOREG"), .REGMODE_B("NOREG"),
                .WRITEMODE_A("READBEFOREWRITE"), .WRITEMODE_B("READBEFOREWRITE"),
                .CLKMODE("ASYNC"), .SSROVERCE("DISABLE"),
                .OREGSET_A("RESET"), .OREGSET_B("RESET"),
                .RESETMODE_A("ASYNC"), .RESETMODE_B("ASYNC"),
                .ASYNC_RESET_RELEASE_A("ASYNC"), .ASYNC_RESET_RELEASE_B("ASYNC"),
                .ECC_ENCODE("DISABLE"), .ECC_DECODE("DISABLE"),
                .IMPLEMENT("20K(FAST)"), .INIT_FILE("NONE"), .FILL_ALL("NONE")
            ) multiplier_eram (
                .dia(parameter_write_data_w), .addra(parameter_write_address_w),
                .cea(1'b1), .ocea(1'b0), .clka(clk_i), .wea(multiplier_write_w),
                .rsta(1'b0), .bea(1'b0),
                .dib(32'd0), .addrb(parameter_index_i[PARAM_ADDR_W-1:0]),
                .ceb(1'b1), .oceb(1'b0), .clkb(clk_i), .web(1'b0),
                .rstb(1'b0), .beb(1'b0),
                .ecc_sbiterrinj(1'b0), .ecc_dbiterrinj(1'b0),
                .doa(multiplier_write_port_unused_w), .dob(multiplier_read_w),
                .ecc_sbiterr(), .ecc_dbiterr());

            PH1P_LOGIC_ERAM #(
                .DATA_WIDTH_A(32), .DATA_WIDTH_B(32),
                .ADDR_WIDTH_A(PARAM_ADDR_W), .ADDR_WIDTH_B(PARAM_ADDR_W),
                .DATA_DEPTH_A(MAX_CHANNELS), .DATA_DEPTH_B(MAX_CHANNELS),
                .MODE("DP"), .REGMODE_A("NOREG"), .REGMODE_B("NOREG"),
                .WRITEMODE_A("READBEFOREWRITE"), .WRITEMODE_B("READBEFOREWRITE"),
                .CLKMODE("ASYNC"), .SSROVERCE("DISABLE"),
                .OREGSET_A("RESET"), .OREGSET_B("RESET"),
                .RESETMODE_A("ASYNC"), .RESETMODE_B("ASYNC"),
                .ASYNC_RESET_RELEASE_A("ASYNC"), .ASYNC_RESET_RELEASE_B("ASYNC"),
                .ECC_ENCODE("DISABLE"), .ECC_DECODE("DISABLE"),
                .IMPLEMENT("20K(FAST)"), .INIT_FILE("NONE"), .FILL_ALL("NONE")
            ) bias_eram (
                .dia(parameter_write_data_w), .addra(parameter_write_address_w),
                .cea(1'b1), .ocea(1'b0), .clka(clk_i), .wea(bias_write_w),
                .rsta(1'b0), .bea(1'b0),
                .dib(32'd0), .addrb(parameter_index_i[PARAM_ADDR_W-1:0]),
                .ceb(1'b1), .oceb(1'b0), .clkb(clk_i), .web(1'b0),
                .rstb(1'b0), .beb(1'b0),
                .ecc_sbiterrinj(1'b0), .ecc_dbiterrinj(1'b0),
                .doa(bias_write_port_unused_w), .dob(bias_read_w),
                .ecc_sbiterr(), .ecc_dbiterr());

    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            state_r <= ST_IDLE; offset_r <= 0; waiting_response_r <= 0; weight_group_offset_r <= 0;
            weight_address_r <= 0; bias_address_r <= 0; requant_address_r <= 0;
            weight_bytes_r <= 0; bias_bytes_r <= 0; requant_bytes_r <= 0;
            parameter_word_r <= 0; weight_channel_stride_r <= 0;
            weight_plane_offset_r <= 0; weight_channel_r <= 0; output_channels_r <= 0;
            for (integer bank_i = 0; bank_i < NUM_PE; bank_i = bank_i + 1)
                weight_bank_offset_r[bank_i] <= 0;
            done_o <= 0; error_o <= 0;
        end else begin
            done_o <= 0;
            case (state_r)
                ST_IDLE: if (start_i) begin
                    error_o <= 0; offset_r <= 0; waiting_response_r <= 0; weight_group_offset_r <= 0;
                    weight_address_r <= weight_address_i;
                    bias_address_r <= bias_address_i;
                    requant_address_r <= requant_address_i;
                    weight_bytes_r <= weight_bytes_i;
                    bias_bytes_r <= bias_bytes_i;
                    requant_bytes_r <= requant_bytes_i;
                    output_channels_r <= output_channels_i;
                    weight_plane_offset_r <= 0; weight_channel_r <= 0;
                    case (output_channels_i)
                        1:  weight_channel_stride_r <= weight_bytes_i;
                        2:  weight_channel_stride_r <= weight_bytes_i >> 1;
                        4:  weight_channel_stride_r <= weight_bytes_i >> 2;
                        8:  weight_channel_stride_r <= weight_bytes_i >> 3;
                        16: weight_channel_stride_r <= weight_bytes_i >> 4;
                        32: weight_channel_stride_r <= weight_bytes_i >> 5;
                        64: weight_channel_stride_r <= weight_bytes_i >> 6;
                        default: weight_channel_stride_r <= 0;
                    endcase
                    for (integer bank_i = 0; bank_i < NUM_PE; bank_i = bank_i + 1)
                        weight_bank_offset_r[bank_i] <= 0;
                    if ((output_channels_i == 0) || (output_channels_i > MAX_CHANNELS) ||
                        (weight_bytes_i == 0) || (weight_bytes_i > `V5N_WEIGHT_CACHE_BYTES) ||
                        (bias_bytes_i != (output_channels_i << 2)) ||
                        (requant_bytes_i != (output_channels_i << 2))) begin
                        error_o <= 1'b1; state_r <= ST_FAIL;
                    end else begin
                        state_r <= ST_WEIGHT;
                    end
                end
                ST_WEIGHT, ST_BIAS, ST_REQUANT: begin
                    if (!waiting_response_r && memory_valid_o && memory_ready_i)
                        waiting_response_r <= 1'b1;
                    if (read_accept_w) begin
                        waiting_response_r <= 1'b0;
                        if (read_error_w) begin
                            error_o <= 1'b1; state_r <= ST_FAIL;
                        end else if (state_r == ST_WEIGHT) begin
                            weight_bank_offset_r[weight_bank_select_r] <=
                                weight_bank_offset_r[weight_bank_select_r] + 1'b1;
                            if (weight_plane_offset_r + 1 >= weight_channel_stride_r) begin
                                weight_plane_offset_r <= 0;
                                weight_channel_r <= weight_channel_r + 1'b1;
                                if (NUM_PE==16 && weight_channel_r[3:0]==15)
                                    weight_group_offset_r <= weight_group_offset_r + weight_channel_stride_r;
                            end else begin
                                weight_plane_offset_r <= weight_plane_offset_r + 1'b1;
                            end
                            if (offset_r + 1 >= weight_bytes_r) begin
                                offset_r <= 0; state_r <= ST_BIAS;
                            end else begin
                                offset_r <= offset_r + 1'b1;
                            end
                        end else if (state_r == ST_BIAS) begin
                            case (offset_r[1:0])
                                2'd0: parameter_word_r[7:0] <= read_value_w;
                                2'd1: parameter_word_r[15:8] <= read_value_w;
                                2'd2: parameter_word_r[23:16] <= read_value_w;
                                default: parameter_word_r <= 0;
                            endcase
                            if (offset_r + 1 >= bias_bytes_r) begin
                                offset_r <= 0; parameter_word_r <= 0; state_r <= ST_REQUANT;
                            end else begin
                                offset_r <= offset_r + 1'b1;
                            end
                        end else begin
                            case (offset_r[1:0])
                                2'd0: parameter_word_r[7:0] <= read_value_w;
                                2'd1: parameter_word_r[15:8] <= read_value_w;
                                2'd2: parameter_word_r[23:16] <= read_value_w;
                                default: parameter_word_r <= 0;
                            endcase
                            if (offset_r + 1 >= requant_bytes_r) begin
                                state_r <= ST_DONE;
                            end else begin
                                offset_r <= offset_r + 1'b1;
                            end
                        end
                    end
                end
                ST_DONE: begin done_o <= 1'b1; state_r <= ST_IDLE; end
                default: state_r <= ST_FAIL;
            endcase
        end
    end
    always @(posedge clk_i or negedge rst_ni) begin
      if(!rst_ni) begin line_valid_r<=0;line_tag_r<=0;line_data_r<=0;end
      else if(start_i || (LINE_PREFETCH && memory_line_invalidate_i)) line_valid_r<=0;
      else if(LINE_PREFETCH && waiting_response_r && memory_response_valid_i &&
              memory_response_ready_o) begin
        line_valid_r<=memory_line_valid_i && !memory_response_error_i &&
                      memory_line_address_i==memory_raw_byte_address_o;
        line_tag_r<=memory_line_address_i[ADDR_W-1:4];
        line_data_r<=memory_line_data_i;
      end
    end
endmodule
