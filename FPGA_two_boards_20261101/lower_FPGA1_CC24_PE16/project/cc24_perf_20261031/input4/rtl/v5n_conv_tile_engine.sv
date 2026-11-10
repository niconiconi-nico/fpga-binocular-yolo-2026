// Independent v5 copy: generalized 6x6 two-lane parameter addressing.
// Scalar-IC / four-output-channel INT8 convolution tile engine.
//
// This is the first real-parameter execution primitive for the separate
// YOLOv8n graph path.  It deliberately uses external byte-addressed tensor
// storage and parameter storage: a later Flash->DDR->tile-cache adapter owns
// residency, while this engine owns only loop ordering and integer arithmetic.
// Weights are consumed in the verified package layout O,KY,KX,IC and feature
// tensors in HWC layout.  One signed INT8 activation is broadcast to NUM_PE
// output-channel lanes per cycle.  The final INT32 accumulators are passed to
// the existing affine v5n_requantize primitive, preserving the frozen
// nearest-ties-away-from-zero contract.
module v5n_conv_tile_engine #(
    parameter integer NUM_PE = 4,
    parameter integer COORD_W = 10,
    parameter integer CHANNEL_W = 10,
    parameter integer ADDR_W = 24
) (
    input  wire                              clk_i,
    input  wire                              rst_ni,
    input  wire                              start_i,
    output reg                               busy_o,
    output reg                               done_o,

    input  wire [COORD_W-1:0]                cfg_output_origin_y_i,
    input  wire [COORD_W-1:0]                cfg_output_origin_x_i,
    input  wire [COORD_W-1:0]                cfg_tile_h_i,
    input  wire [COORD_W-1:0]                cfg_tile_w_i,
    input  wire [COORD_W-1:0]                cfg_input_h_i,
    input  wire [COORD_W-1:0]                cfg_input_w_i,
    input  wire [CHANNEL_W-1:0]              cfg_input_c_i,
    input  wire [CHANNEL_W-1:0]              cfg_output_c_i,
    input  wire [3:0]                        cfg_kernel_h_i,
    input  wire [3:0]                        cfg_kernel_w_i,
    input  wire [3:0]                        cfg_stride_h_i,
    input  wire [3:0]                        cfg_stride_w_i,
    input  wire [3:0]                        cfg_pad_top_i,
    input  wire [3:0]                        cfg_pad_left_i,
    input  wire [5:0]                        cfg_requant_shift_i,
    input  wire [ADDR_W-1:0]                 cfg_input_base_i,
    input  wire [ADDR_W-1:0]                 cfg_weight_base_i,

    // Combinational read ports supplied by the memory/cache adapter.
    (* multstyle = "logic" *) output reg [ADDR_W-1:0] input_address_o,
    input  wire signed [7:0]                 input_data_i,
    (* multstyle = "logic" *) output reg [NUM_PE*ADDR_W-1:0] weight_address_o,
    input  wire signed [NUM_PE*8-1:0]        weight_data_i,
    output reg  [NUM_PE*CHANNEL_W-1:0]       parameter_index_o,
    input  wire signed [NUM_PE*32-1:0]       parameter_multiplier_i,
    input  wire signed [NUM_PE*32-1:0]       parameter_bias_numerator_i,

    output reg                               output_valid_o,
    output reg  [COORD_W-1:0]                output_y_o,
    output reg  [COORD_W-1:0]                output_x_o,
    output reg  [CHANNEL_W-1:0]              output_channel_base_o,
    output wire signed [NUM_PE*8-1:0]        output_data_o,
    output reg  [NUM_PE-1:0]                 output_lane_valid_o
);
    localparam [2:0] ST_IDLE = 3'd0;
    localparam [2:0] ST_MAC = 3'd1;
    localparam [2:0] ST_REQUANT = 3'd2;
    localparam [2:0] ST_WRITE = 3'd3;
    localparam [2:0] ST_MAC_DRAIN = 3'd4;
    localparam [2:0] ST_MAC_PRIME = 3'd5;
    localparam [2:0] ST_MAC_DRAIN_FINAL = 3'd6;

    reg [2:0] state_r;
    reg [COORD_W-1:0] tile_y_r;
    reg [COORD_W-1:0] tile_x_r;
    reg [CHANNEL_W-1:0] output_channel_r;
    reg [3:0] kernel_y_r;
    reg [3:0] kernel_x_r;
    reg [CHANNEL_W-1:0] input_channel_r;
    // With the deployed scalar PE the O,KY,KX,IC parameter layout is exactly
    // the MAC loop order.  A rolling byte offset therefore replaces the
    // former O*KH*KW*IC combinational address chain without changing a read.
    reg [ADDR_W-1:0] scalar_weight_offset_r;
    // Two-PE fixed graph: both lanes traverse the same K,Y,X,IC term.
    // Hold the per-output filter span and advance the output-channel group
    // base only between output groups, avoiding a three-DSP address chain.
    reg [ADDR_W-1:0] pe2_row_span_r, pe2_filter_span_r, pe2_group_base_r;
    reg [ADDR_W-1:0] pe2_kernel_row_offset_r, pe2_kernel_col_offset_r;
    // The descriptor runtime presents a zero-padded local HWC halo with origin
    // (0,0).  Track its byte address incrementally so tile_x/tile_y never feed
    // the feature ERAM through two dynamic multipliers.
    reg [ADDR_W-1:0] scalar_input_offset_r;
    reg [ADDR_W-1:0] scalar_feature_anchor_r;
    reg [ADDR_W-1:0] scalar_tile_row_anchor_r;
    reg [ADDR_W-1:0] scalar_horizontal_step_r;
    reg [ADDR_W-1:0] scalar_vertical_step_r;
    reg [ADDR_W-1:0] scalar_kernel_row_gap_r;
    reg signed [31:0] accumulator_r [0:NUM_PE-1];
    // Break the physical ERAM -> DSP multiply -> accumulator path.  ST_MAC
    // captures one product per cycle and accumulates the product captured on
    // the preceding cycle.  ST_MAC_DRAIN consumes the final captured term.
    // This preserves the exact integer term order while giving the multiplier
    // output a full registered boundary for reliable board operation.
    reg signed [31:0] mac_product_r [0:NUM_PE-1];
    reg mac_product_valid_r;
    reg signed [31:0] requant_accumulator_r [0:NUM_PE-1];
    reg signed [31:0] requant_multiplier_r [0:NUM_PE-1];
    reg signed [31:0] requant_bias_r [0:NUM_PE-1];
    reg [NUM_PE-1:0] requant_lane_valid_r;

    wire signed [NUM_PE*32-1:0] requant_accumulator_bus;
    wire signed [NUM_PE*32-1:0] requant_multiplier_bus;
    wire signed [NUM_PE*32-1:0] requant_bias_bus;
    wire [NUM_PE*6-1:0] requant_shift_bus;
    wire signed [NUM_PE*32-1:0] requant_zero_point_bus;
    wire signed [NUM_PE*32-1:0] requant_qmin_bus;
    wire signed [NUM_PE*32-1:0] requant_qmax_bus;
    wire requant_valid;
    wire signed [NUM_PE*8-1:0] requant_code;

    (* multstyle = "logic" *) reg signed [31:0] absolute_input_y_r;
    (* multstyle = "logic" *) reg signed [31:0] absolute_input_x_r;
    reg input_in_bounds_r;
    integer lane_i;

    (* multstyle = "dsp" *) function signed [31:0] mac_product;
        input signed [7:0] activation_value;
        input signed [7:0] weight_value;
        begin
            mac_product = activation_value * weight_value;
        end
    endfunction

    // Frozen graph channel counts are 3 or powers of two.  Decode that fixed
    // set into shifts so width*channels is exact without a general multiplier.
    function [ADDR_W-1:0] width_channel_product;
        input [COORD_W-1:0] width_value;
        input [CHANNEL_W-1:0] channel_value;
        reg [ADDR_W-1:0] w;
        begin
            w = {{(ADDR_W-COORD_W){1'b0}}, width_value};
            case (channel_value)
                3:   width_channel_product = (w << 1) + w;
                16:  width_channel_product = w << 4;
                32:  width_channel_product = w << 5;
                64:  width_channel_product = w << 6;
                128: width_channel_product = w << 7;
                256: width_channel_product = w << 8;
                512: width_channel_product = w << 9;
                default: width_channel_product = width_value * channel_value;
            endcase
        end
    endfunction

    // Addresses are byte addresses.  Invalid padding reads are mapped to zero
    // but their MAC term is explicitly forced to zero below.
    always @* begin
        pe2_kernel_row_offset_r = kernel_y_r * pe2_row_span_r;
        pe2_kernel_col_offset_r = kernel_x_r * cfg_input_c_i;
        if (NUM_PE <= 2) begin
            absolute_input_y_r = 0;
            absolute_input_x_r = 0;
            input_in_bounds_r = 1'b1;
            input_address_o = cfg_input_base_i + scalar_input_offset_r;
        end else begin
            absolute_input_y_r = ($signed({1'b0, cfg_output_origin_y_i}) + $signed({1'b0, tile_y_r})) *
                                 $signed({1'b0, cfg_stride_h_i}) - $signed({1'b0, cfg_pad_top_i}) +
                                 $signed({1'b0, kernel_y_r});
            absolute_input_x_r = ($signed({1'b0, cfg_output_origin_x_i}) + $signed({1'b0, tile_x_r})) *
                                 $signed({1'b0, cfg_stride_w_i}) - $signed({1'b0, cfg_pad_left_i}) +
                                 $signed({1'b0, kernel_x_r});
            input_in_bounds_r = (absolute_input_y_r >= 0) && (absolute_input_x_r >= 0) &&
                                (absolute_input_y_r < $signed({1'b0, cfg_input_h_i})) &&
                                (absolute_input_x_r < $signed({1'b0, cfg_input_w_i}));
            if (input_in_bounds_r)
                input_address_o = cfg_input_base_i +
                    ((absolute_input_y_r * $signed({1'b0, cfg_input_w_i}) + absolute_input_x_r) *
                     $signed({1'b0, cfg_input_c_i}) + $signed({1'b0, input_channel_r}));
            else
                input_address_o = cfg_input_base_i;
        end
        for (lane_i = 0; lane_i < NUM_PE; lane_i = lane_i + 1) begin
            if (NUM_PE == 1)
                weight_address_o[lane_i*ADDR_W +: ADDR_W] =
                    cfg_weight_base_i + scalar_weight_offset_r;
            else if (NUM_PE == 2)
                weight_address_o[lane_i*ADDR_W +: ADDR_W] =
                    cfg_weight_base_i + pe2_group_base_r +
                    pe2_kernel_row_offset_r + pe2_kernel_col_offset_r +
                    input_channel_r + ((lane_i == 0) ? 0 : pe2_filter_span_r);
            else
                weight_address_o[lane_i*ADDR_W +: ADDR_W] = cfg_weight_base_i +
                    (((output_channel_r + lane_i) * cfg_kernel_h_i * cfg_kernel_w_i * cfg_input_c_i) +
                     (kernel_y_r * cfg_kernel_w_i * cfg_input_c_i) +
                     (kernel_x_r * cfg_input_c_i) + input_channel_r);
            parameter_index_o[lane_i*CHANNEL_W +: CHANNEL_W] = output_channel_r + lane_i;
        end
    end

    generate
        genvar lane_g;
        for (lane_g = 0; lane_g < NUM_PE; lane_g = lane_g + 1) begin : G_REQUANT_PACK
            assign requant_accumulator_bus[lane_g*32 +: 32] = requant_accumulator_r[lane_g];
            assign requant_multiplier_bus[lane_g*32 +: 32] = requant_multiplier_r[lane_g];
            assign requant_bias_bus[lane_g*32 +: 32] = requant_bias_r[lane_g];
            assign requant_shift_bus[lane_g*6 +: 6] = cfg_requant_shift_i;
            assign requant_zero_point_bus[lane_g*32 +: 32] = 32'sd0;
            assign requant_qmin_bus[lane_g*32 +: 32] = -32'sd128;
            assign requant_qmax_bus[lane_g*32 +: 32] = 32'sd127;
        end
    endgenerate

    v5n_requantize #(.NUM_PE(NUM_PE),.PIPELINED(1)) requantizer (
        .clk_i(clk_i), .rst_ni(rst_ni), .valid_i(state_r == ST_REQUANT),
        .accumulator_i(requant_accumulator_bus), .multiplier_i(requant_multiplier_bus),
        .bias_i(requant_bias_bus), .shift_i(requant_shift_bus),
        .output_zero_point_i(requant_zero_point_bus), .qmin_i(requant_qmin_bus),
        .qmax_i(requant_qmax_bus), .valid_o(requant_valid), .code_o(requant_code)
    );

    assign output_data_o = requant_code;

    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            state_r <= ST_IDLE;
            busy_o <= 1'b0;
            done_o <= 1'b0;
            output_valid_o <= 1'b0;
            tile_y_r <= 0;
            tile_x_r <= 0;
            output_channel_r <= 0;
            kernel_y_r <= 0;
            kernel_x_r <= 0;
            input_channel_r <= 0;
            scalar_weight_offset_r <= 0;
            pe2_row_span_r <= 0;
            pe2_filter_span_r <= 0;
            pe2_group_base_r <= 0;
            scalar_input_offset_r <= 0;
            scalar_feature_anchor_r <= 0;
            scalar_tile_row_anchor_r <= 0;
            scalar_horizontal_step_r <= 0;
            scalar_vertical_step_r <= 0;
            scalar_kernel_row_gap_r <= 0;
            output_y_o <= 0;
            output_x_o <= 0;
            output_channel_base_o <= 0;
            output_lane_valid_o <= 0;
            requant_lane_valid_r <= 0;
            mac_product_valid_r <= 1'b0;
            for (lane_i = 0; lane_i < NUM_PE; lane_i = lane_i + 1) begin
                accumulator_r[lane_i] <= 0;
                mac_product_r[lane_i] <= 0;
                requant_accumulator_r[lane_i] <= 0;
                requant_multiplier_r[lane_i] <= 0;
                requant_bias_r[lane_i] <= 0;
            end
        end else begin
            done_o <= 1'b0;
            output_valid_o <= 1'b0;
            case (state_r)
                ST_IDLE: begin
                    busy_o <= 1'b0;
                    if (start_i) begin
                        busy_o <= 1'b1;
                        tile_y_r <= 0;
                        tile_x_r <= 0;
                        output_channel_r <= 0;
                        kernel_y_r <= 0;
                        kernel_x_r <= 0;
                        input_channel_r <= 0;
                        scalar_weight_offset_r <= 0;
                        pe2_group_base_r <= 0;
                        pe2_row_span_r <= width_channel_product(cfg_kernel_w_i,cfg_input_c_i);
                        pe2_filter_span_r <= cfg_kernel_h_i * width_channel_product(cfg_kernel_w_i,cfg_input_c_i);
                        scalar_horizontal_step_r <=
                            (cfg_stride_w_i == 2) ?
                                ({{(ADDR_W-CHANNEL_W){1'b0}},cfg_input_c_i} << 1) :
                                {{(ADDR_W-CHANNEL_W){1'b0}},cfg_input_c_i};
                        scalar_vertical_step_r <=
                            (cfg_stride_h_i == 2) ?
                                (width_channel_product(cfg_input_w_i,cfg_input_c_i) << 1) :
                                width_channel_product(cfg_input_w_i,cfg_input_c_i);
                        scalar_kernel_row_gap_r <=
                            width_channel_product(cfg_input_w_i,cfg_input_c_i) -
                            width_channel_product(cfg_kernel_w_i,cfg_input_c_i);
                        for (lane_i = 0; lane_i < NUM_PE; lane_i = lane_i + 1)
                            accumulator_r[lane_i] <= 0;
                        mac_product_valid_r <= 1'b0;
                        state_r <= ST_MAC_PRIME;
                    end
                end
                // PH1P ERAM is a synchronous-read macro even in NOREG mode.
                // Present term zero for one clock, while advancing the issue
                // address to term one.  ST_MAC then consumes term zero on its
                // first edge and the subsequent terms without duplicating the
                // first word.  The fixed graph always has at least three input
                // channels, but retain the complete nested-loop advance here
                // so this primitive's contract remains self-contained.
                ST_MAC_PRIME: begin
                    mac_product_valid_r <= 1'b0;
                    if (NUM_PE == 1)
                        scalar_weight_offset_r <= scalar_weight_offset_r + 1'b1;
                    if (input_channel_r + 1 < cfg_input_c_i) begin
                        input_channel_r <= input_channel_r + 1'b1;
                        if (NUM_PE <= 2)
                            scalar_input_offset_r <= scalar_input_offset_r + 1'b1;
                    end else begin
                        input_channel_r <= 0;
                        if (kernel_x_r + 1 < cfg_kernel_w_i) begin
                            kernel_x_r <= kernel_x_r + 1'b1;
                            if (NUM_PE <= 2)
                                scalar_input_offset_r <= scalar_input_offset_r + 1'b1;
                        end else begin
                            kernel_x_r <= 0;
                            if (kernel_y_r + 1 < cfg_kernel_h_i) begin
                                kernel_y_r <= kernel_y_r + 1'b1;
                                if (NUM_PE <= 2)
                                    scalar_input_offset_r <= scalar_input_offset_r + 1'b1 +
                                                             scalar_kernel_row_gap_r;
                            end
                        end
                    end
                    state_r <= ST_MAC;
                end
                ST_MAC: begin
                    if (NUM_PE == 1)
                        scalar_weight_offset_r <= scalar_weight_offset_r + 1'b1;
                    if (NUM_PE <= 2) begin
                        if (input_channel_r + 1 < cfg_input_c_i)
                            scalar_input_offset_r <= scalar_input_offset_r + 1'b1;
                        else if (kernel_x_r + 1 < cfg_kernel_w_i)
                            scalar_input_offset_r <= scalar_input_offset_r + 1'b1;
                        else if (kernel_y_r + 1 < cfg_kernel_h_i)
                            scalar_input_offset_r <= scalar_input_offset_r + 1'b1 +
                                                     scalar_kernel_row_gap_r;
                        else
                            scalar_input_offset_r <= scalar_feature_anchor_r;
                    end
                    for (lane_i = 0; lane_i < NUM_PE; lane_i = lane_i + 1) begin
                        mac_product_r[lane_i] <=
                            mac_product(input_in_bounds_r ? input_data_i : 8'sd0,
                                        $signed(weight_data_i[lane_i*8 +: 8]));
                        if (mac_product_valid_r &&
                            ((output_channel_r + lane_i) < cfg_output_c_i))
                            accumulator_r[lane_i] <= accumulator_r[lane_i] +
                                mac_product_r[lane_i];
                    end
                    mac_product_valid_r <= 1'b1;
                    if (input_channel_r + 1 >= cfg_input_c_i) begin
                        input_channel_r <= 0;
                        if (kernel_x_r + 1 >= cfg_kernel_w_i) begin
                            kernel_x_r <= 0;
                            if (kernel_y_r + 1 >= cfg_kernel_h_i) begin
                                kernel_y_r <= 0;
                                for (lane_i = 0; lane_i < NUM_PE; lane_i = lane_i + 1) begin
                                    requant_multiplier_r[lane_i] <=
                                        $signed(parameter_multiplier_i[lane_i*32 +: 32]);
                                    requant_bias_r[lane_i] <=
                                        $signed(parameter_bias_numerator_i[lane_i*32 +: 32]);
                                    requant_lane_valid_r[lane_i] <=
                                        ((output_channel_r + lane_i) < cfg_output_c_i);
                                end
                                state_r <= ST_MAC_DRAIN;
                            end else begin
                                kernel_y_r <= kernel_y_r + 1'b1;
                            end
                        end else begin
                            kernel_x_r <= kernel_x_r + 1'b1;
                        end
                    end else begin
                        input_channel_r <= input_channel_r + 1'b1;
                    end
                end
                ST_MAC_DRAIN: begin
                    for (lane_i = 0; lane_i < NUM_PE; lane_i = lane_i + 1) begin
                        accumulator_r[lane_i] <= accumulator_r[lane_i] +
                            (((output_channel_r + lane_i) < cfg_output_c_i) ?
                             mac_product_r[lane_i] : 0);
                        // The final issued ERAM word becomes visible only on
                        // this edge.  Capture it before forming the requant
                        // accumulator in ST_MAC_DRAIN_FINAL.
                        mac_product_r[lane_i] <=
                            mac_product(input_in_bounds_r ? input_data_i : 8'sd0,
                                        $signed(weight_data_i[lane_i*8 +: 8]));
                    end
                    mac_product_valid_r <= 1'b0;
                    state_r <= ST_MAC_DRAIN_FINAL;
                end
                ST_MAC_DRAIN_FINAL: begin
                    for (lane_i = 0; lane_i < NUM_PE; lane_i = lane_i + 1)
                        requant_accumulator_r[lane_i] <= accumulator_r[lane_i] +
                            (((output_channel_r + lane_i) < cfg_output_c_i) ?
                             mac_product_r[lane_i] : 0);
                    state_r <= ST_REQUANT;
                end
                ST_REQUANT: begin
                    state_r <= ST_WRITE;
                end
                ST_WRITE: begin
                    if(requant_valid) begin
                        output_valid_o <= 1'b1;
                        output_y_o <= cfg_output_origin_y_i + tile_y_r;
                        output_x_o <= cfg_output_origin_x_i + tile_x_r;
                        output_channel_base_o <= output_channel_r;
                        output_lane_valid_o <= requant_lane_valid_r;
                        for (lane_i = 0; lane_i < NUM_PE; lane_i = lane_i + 1)
                            accumulator_r[lane_i] <= 0;
                        input_channel_r <= 0;
                        kernel_x_r <= 0;
                        kernel_y_r <= 0;
                        if (output_channel_r + NUM_PE < cfg_output_c_i) begin
                            output_channel_r <= output_channel_r + NUM_PE;
                            if (NUM_PE == 2)
                                pe2_group_base_r <= pe2_group_base_r + (pe2_filter_span_r << 1);
                            if (NUM_PE <= 2)
                                scalar_input_offset_r <= scalar_feature_anchor_r;
                            state_r <= ST_MAC_PRIME;
                        end else begin
                            output_channel_r <= 0;
                            if (tile_x_r + 1 < cfg_tile_w_i) begin
                                tile_x_r <= tile_x_r + 1'b1;
                                if (NUM_PE == 2) pe2_group_base_r <= 0;
                                if (NUM_PE == 1)
                                    scalar_weight_offset_r <= 0;
                                if (NUM_PE <= 2) begin
                                    scalar_feature_anchor_r <= scalar_feature_anchor_r +
                                                               scalar_horizontal_step_r;
                                    scalar_input_offset_r <= scalar_feature_anchor_r +
                                                             scalar_horizontal_step_r;
                                end
                                state_r <= ST_MAC_PRIME;
                            end else if (tile_y_r + 1 < cfg_tile_h_i) begin
                                tile_x_r <= 0;
                                tile_y_r <= tile_y_r + 1'b1;
                                if (NUM_PE == 2) pe2_group_base_r <= 0;
                                if (NUM_PE == 1)
                                    scalar_weight_offset_r <= 0;
                                if (NUM_PE <= 2) begin
                                    scalar_tile_row_anchor_r <= scalar_tile_row_anchor_r +
                                                                scalar_vertical_step_r;
                                    scalar_feature_anchor_r <= scalar_tile_row_anchor_r +
                                                               scalar_vertical_step_r;
                                    scalar_input_offset_r <= scalar_tile_row_anchor_r +
                                                             scalar_vertical_step_r;
                                end
                                state_r <= ST_MAC_PRIME;
                            end else begin
                                if (NUM_PE == 1)
                                    scalar_weight_offset_r <= 0;
                                busy_o <= 1'b0;
                                done_o <= 1'b1;
                                state_r <= ST_IDLE;
                            end
                        end
                    end
                end
                default: state_r <= ST_IDLE;
            endcase
        end
    end
endmodule
