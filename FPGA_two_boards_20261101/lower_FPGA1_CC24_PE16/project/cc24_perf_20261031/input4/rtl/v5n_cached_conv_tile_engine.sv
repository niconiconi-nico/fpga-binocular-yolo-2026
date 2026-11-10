// Scalar-IC / four-output-channel INT8 convolution tile engine.
//
// Independent physical_friendly_v2 primitive for the fixed A2 YOLOv5 graph.
// It deliberately uses external byte-addressed tensor
// storage and parameter storage: a later Flash->DDR->tile-cache adapter owns
// residency, while this engine owns only loop ordering and integer arithmetic.
// Weights are consumed in the verified package layout O,KY,KX,IC and feature
// tensors in HWC layout.  One signed INT8 activation is broadcast to NUM_PE
// output-channel lanes per cycle.  The final INT32 accumulators are passed to
// the existing affine v5n_cached_requantize primitive, preserving the frozen
// nearest-ties-away-from-zero contract.
module v5n_cached_conv_tile_engine #(
    parameter integer PACKED_INT8 = 1,
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
    input  wire [((NUM_PE/2)>0 ? (NUM_PE/2)*27 : 1)-1:0]          packed_weight_data_i,
    output reg  [CHANNEL_W-1:0]              parameter_index_o,
    input  wire signed [31:0]                parameter_multiplier_i,
    input  wire signed [31:0]                parameter_bias_numerator_i,

    output reg                               output_valid_o,
    output reg  [COORD_W-1:0]                output_y_o,
    output reg  [COORD_W-1:0]                output_x_o,
    output reg  [CHANNEL_W-1:0]              output_channel_base_o,
    output wire signed [NUM_PE*8-1:0]        output_data_o,
    output reg  [NUM_PE-1:0]                 output_lane_valid_o,
output wire rq_req_valid,
input wire rq_req_ready,
output wire signed[31:0] rq_source0,
output wire signed[31:0] rq_source1,
output wire signed[31:0] rq_mult0,
output wire signed[31:0] rq_mult1,
output wire signed[31:0] rq_bias,
output wire[5:0] rq_shift0,
output wire[5:0] rq_shift1,
input wire rq_rsp_valid,
input wire signed[7:0] rq_rsp_code,
input wire rq_rsp_error,
output reg requant_error_o
);
    localparam [3:0] ST_IDLE = 4'd0;
    localparam [3:0] ST_MAC = 4'd1;
    localparam [3:0] ST_WRITE = 4'd3;
    localparam [3:0] ST_MAC_DRAIN = 4'd4;
    localparam [3:0] ST_MAC_PRIME = 4'd5;
    localparam [3:0] ST_MAC_DRAIN_FINAL = 4'd6;
    localparam [3:0] ST_PARAM_LOAD = 4'd7;
    localparam [3:0] ST_MAC_PIPE = 4'd8;

    reg [3:0] state_r;
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
    // The registered bank crossbar makes the weight and feature read paths
    // two clocks deep. Keep an independent issue cursor two terms ahead of
    // the loop/accumulator cursor; otherwise ST_MAC_PIPE repeats term one and
    // drops the final kernel term.
    reg [ADDR_W-1:0] weight_issue_offset_r;
    // Bytes occupied by one output channel's KxKxCin weight plane.  Keeping
    // this stride registered lets every PE derive its lane address from the
    // same rolling term offset without the former O*KH*KW*IC multiplier tree.
    reg [ADDR_W-1:0] weight_channel_stride_r;
    // The descriptor runtime presents a zero-padded local HWC halo with origin
    // (0,0).  Track its byte address incrementally so tile_x/tile_y never feed
    // the feature ERAM through two dynamic multipliers.
    reg [ADDR_W-1:0] scalar_input_offset_r;
    reg [ADDR_W-1:0] input_issue_offset_r;
    reg [3:0] issue_kernel_y_r;
    reg [3:0] issue_kernel_x_r;
    reg [CHANNEL_W-1:0] issue_input_channel_r;
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
    reg signed [7:0] input_data_pipeline_r;
    // One-clock alignment with the synchronous scalar parameter ERAM port.
    // No all-lane multiplier/bias staging and no second accumulator bank.
    reg signed [31:0] parameter_accumulator_pipe_r;
    reg [NUM_PE-1:0] requant_lane_valid_r;
    localparam integer REQUANT_COUNT_W = $clog2(NUM_PE + 1);
    reg [REQUANT_COUNT_W-1:0] parameter_issue_count_r;
    reg parameter_issue_valid_r;

    // The 32x32 affine multiplier is much larger than an INT8 MAC on PH1P.
    // Share one pipelined requantizer across the output lanes; convolution
    // takes hundreds of MAC cycles per result, so these NUM_PE issue cycles do
    // not reduce sustained MAC throughput and avoid replicating wide DSPs.
    reg [REQUANT_COUNT_W-1:0] requant_collect_count_r;
    reg signed [NUM_PE*8-1:0] requant_code_r;
    wire shared_requant_valid_i = (state_r == ST_PARAM_LOAD) &&
                                  parameter_issue_valid_r;
    wire shared_requant_valid_o;
    wire signed [7:0] shared_requant_code_w;

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

    // Paired Cout lanes receive the SAME registered activation and different
    // synchronous weight-bank results. Unpack before the existing independent
    // INT32 accumulators. Keep the existing product register/prime/drain stages
    // exactly: using the registered product-only microbenchmark here would add
    // an unaccounted cycle and drop/mislabel the final kernel term.
    wire signed [7:0] shared_activation_w =
        input_in_bounds_r ? input_data_pipeline_r : 8'sd0;
    wire signed [31:0] lane_product_w [0:NUM_PE-1];
    wire [NUM_PE-1:0] lane_carry_w;
    reg [NUM_PE-1:0] mac_carry_r;
    wire [NUM_PE-1:0] lane_enabled_w;
    generate for(genvar en=0;en<NUM_PE;en=en+1) begin:G_LANE_ENABLED
        if(NUM_PE==16) begin:G_GROUP16
            // output_channel_r starts at zero and advances by 16, so these
            // comparisons are exactly output_channel_r+en < cfg_output_c_i.
            assign lane_enabled_w[en] =
                output_channel_r[CHANNEL_W-1:4]<cfg_output_c_i[CHANNEL_W-1:4] ||
                (output_channel_r[CHANNEL_W-1:4]==cfg_output_c_i[CHANNEL_W-1:4] && en<cfg_output_c_i[3:0]);
        end else assign lane_enabled_w[en] = output_channel_r+en<cfg_output_c_i;
    end endgenerate
    always @(posedge clk_i or negedge rst_ni) begin
        if(!rst_ni) mac_carry_r<=0;
        else if(state_r==ST_MAC || state_r==ST_MAC_DRAIN) mac_carry_r<=lane_carry_w;
    end
    generate
        genvar pair_g;
        for(pair_g=0;pair_g<NUM_PE/2;pair_g=pair_g+1)begin:G_PACKED_PAIR
            if(PACKED_INT8)begin:G_PACK
                wire signed [7:0] w0=weight_data_i[(2*pair_g)*8+:8];
                wire signed [7:0] w1=weight_data_i[(2*pair_g+1)*8+:8];
                wire signed [26:0] extended_w0={{19{w0[7]}},w0};
                wire signed [26:0] shifted_w1={{1{w1[7]}},w1,18'd0};
                wire signed [26:0] packed_w=packed_weight_data_i[pair_g*27+:27];
                (* multstyle="dsp" *) wire signed [34:0] packed_product=
                    packed_w*shared_activation_w;
                wire signed [15:0] p0=packed_product[15:0];
                // Defer the exact high-lane sign correction to the accumulator
                // carry input, eliminating eight standalone 16-bit adders.
                wire signed [15:0] p1=$signed(packed_product[33:18]);
                assign lane_carry_w[2*pair_g]=1'b0;
                assign lane_carry_w[2*pair_g+1]=packed_product[17];
                assign lane_product_w[2*pair_g]={{16{p0[15]}},p0};
                assign lane_product_w[2*pair_g+1]={{16{p1[15]}},p1};
            end else begin:G_SCALAR
                assign lane_carry_w[2*pair_g+:2]=2'b00;
                assign lane_product_w[2*pair_g]=mac_product(shared_activation_w,
                    $signed(weight_data_i[(2*pair_g)*8+:8]));
                assign lane_product_w[2*pair_g+1]=mac_product(shared_activation_w,
                    $signed(weight_data_i[(2*pair_g+1)*8+:8]));
            end
        end
        if(NUM_PE%2)begin:G_ODD_LANE
            assign lane_carry_w[NUM_PE-1]=1'b0;
            assign lane_product_w[NUM_PE-1]=mac_product(shared_activation_w,
                $signed(weight_data_i[(NUM_PE-1)*8+:8]));
        end
    endgenerate

    // Decode every input-channel count used by the frozen graph into shifts
    // and adds so width*channels is exact without a general multiplier.  The
    // 48/96/192/384 cases are produced by concat nodes and must not fall into
    // a DSP-backed default path.
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
                48:  width_channel_product = (w << 5) + (w << 4);
                64:  width_channel_product = w << 6;
                96:  width_channel_product = (w << 6) + (w << 5);
                128: width_channel_product = w << 7;
                192: width_channel_product = (w << 7) + (w << 6);
                256: width_channel_product = w << 8;
                384: width_channel_product = (w << 8) + (w << 7);
                512: width_channel_product = w << 9;
                default: width_channel_product = {ADDR_W{1'b0}};
            endcase
        end
    endfunction

    function [ADDR_W-1:0] kernel_channel_product;
        input [3:0] kernel_h_value;
        input [3:0] kernel_w_value;
        input [CHANNEL_W-1:0] channel_value;
        reg [ADDR_W-1:0] c;
        reg [7:0] kernel_area;
        begin
            c = {{(ADDR_W-CHANNEL_W){1'b0}}, channel_value};
            kernel_area = kernel_h_value * kernel_w_value;
            case (kernel_area)
                1:  kernel_channel_product = c;
                3:  kernel_channel_product = (c << 1) + c;
                5:  kernel_channel_product = (c << 2) + c;
                9:  kernel_channel_product = (c << 3) + c;
                36: kernel_channel_product = (c << 5) + (c << 2);
                25: kernel_channel_product = (c << 4) + (c << 3) + c;
                default: kernel_channel_product = kernel_area * c;
            endcase
        end
    endfunction

    function [ADDR_W-1:0] lane_stride_offset;
        input [ADDR_W-1:0] stride_value;
        input integer lane_value;
        begin
            case (lane_value)
                0:  lane_stride_offset = {ADDR_W{1'b0}};
                1:  lane_stride_offset = stride_value;
                2:  lane_stride_offset = stride_value << 1;
                3:  lane_stride_offset = (stride_value << 1) + stride_value;
                4:  lane_stride_offset = stride_value << 2;
                5:  lane_stride_offset = (stride_value << 2) + stride_value;
                6:  lane_stride_offset = (stride_value << 2) + (stride_value << 1);
                7:  lane_stride_offset = (stride_value << 3) - stride_value;
                8:  lane_stride_offset = stride_value << 3;
                9:  lane_stride_offset = (stride_value << 3) + stride_value;
                10: lane_stride_offset = (stride_value << 3) + (stride_value << 1);
                11: lane_stride_offset = (stride_value << 3) + (stride_value << 1) + stride_value;
                12: lane_stride_offset = (stride_value << 3) + (stride_value << 2);
                13: lane_stride_offset = (stride_value << 3) + (stride_value << 2) + stride_value;
                14: lane_stride_offset = (stride_value << 4) - (stride_value << 1);
                15: lane_stride_offset = (stride_value << 4) - stride_value;
                default: lane_stride_offset = lane_value * stride_value;
            endcase
        end
    endfunction

    // Addresses are byte addresses.  Invalid padding reads are mapped to zero
    // but their MAC term is explicitly forced to zero below.
    always @* begin
        absolute_input_y_r = 0;
        absolute_input_x_r = 0;
        input_in_bounds_r = 1'b1;
        input_address_o = cfg_input_base_i + input_issue_offset_r;
        for (lane_i = 0; lane_i < NUM_PE; lane_i = lane_i + 1) begin
            weight_address_o[lane_i*ADDR_W +: ADDR_W] = cfg_weight_base_i +
                weight_issue_offset_r;
        end
        parameter_index_o = output_channel_r + parameter_issue_count_r;
    end

 assign rq_req_valid=shared_requant_valid_i;
 assign rq_source0=parameter_accumulator_pipe_r;
 assign rq_source1=32'sd0;
 assign rq_mult0=parameter_multiplier_i;
 assign rq_mult1=32'sd0;
 assign rq_bias=parameter_bias_numerator_i;
 assign rq_shift0=cfg_requant_shift_i;
 assign rq_shift1=6'd0;
    assign shared_requant_valid_o=rq_rsp_valid&&!rq_rsp_error;
    assign shared_requant_code_w=rq_rsp_code;
    assign output_data_o = requant_code_r;
`ifndef SYNTHESIS
    always @(posedge clk_i) if(rst_ni && NUM_PE==16 && output_channel_r[3:0]!=0)
        $fatal(1,"PE16 output channel group invariant");
`endif

    // One full INT32 adder per lane, shared by MAC and the two drain states.
    // Inactive lanes previously added zero in drain; CE hold is bit-identical.
    // No extra pipeline stage or arithmetic-width change.
    wire accumulator_clear_w = (state_r==ST_IDLE && start_i) ||
        (state_r==ST_WRITE && requant_collect_count_r>=NUM_PE);
    wire accumulator_step_w = (state_r==ST_MAC && mac_product_valid_r) ||
        state_r==ST_MAC_DRAIN || state_r==ST_MAC_DRAIN_FINAL;
    generate for(genvar acc_lane=0;acc_lane<NUM_PE;acc_lane=acc_lane+1) begin:G_ACC
        // floor(({A,1}+{B,C})/2) = A+B+C modulo 2^32. The extra
        // low bit supplies carry-in to a single adder, retaining all INT32 bits.
        wire [32:0] corrected_sum_w = {accumulator_r[acc_lane],1'b1} +
                                     {mac_product_r[acc_lane],mac_carry_r[acc_lane]};
        always @(posedge clk_i or negedge rst_ni) begin
            if(!rst_ni) accumulator_r[acc_lane]<=32'sd0;
            else if(accumulator_clear_w) accumulator_r[acc_lane]<=32'sd0;
            else if(accumulator_step_w && lane_enabled_w[acc_lane])
                accumulator_r[acc_lane]<=corrected_sum_w[32:1];
        end
    end endgenerate

    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            requant_error_o<=0;
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
            weight_issue_offset_r <= 0;
            weight_channel_stride_r <= 0;
            scalar_input_offset_r <= 0;
            input_issue_offset_r <= 0;
            issue_kernel_y_r <= 0;
            issue_kernel_x_r <= 0;
            issue_input_channel_r <= 0;
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
            requant_collect_count_r <= 0;
            requant_code_r <= 0;
            mac_product_valid_r <= 1'b0;
            input_data_pipeline_r <= 0;
            parameter_issue_count_r <= 0;
            parameter_accumulator_pipe_r <= 0;
            parameter_issue_valid_r <= 0;
            for (lane_i = 0; lane_i < NUM_PE; lane_i = lane_i + 1) begin
                mac_product_r[lane_i] <= 0;
            end
        end else begin
            done_o <= 1'b0;
            output_valid_o <= 1'b0;
            input_data_pipeline_r <= input_data_i;
            if (shared_requant_valid_o) begin
                requant_code_r[requant_collect_count_r*8 +: 8] <= shared_requant_code_w;
                requant_collect_count_r <= requant_collect_count_r + 1'b1;
            end
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
                        weight_issue_offset_r <= 0;
                        weight_channel_stride_r <=
                            kernel_channel_product(cfg_kernel_h_i,cfg_kernel_w_i,cfg_input_c_i);
                        scalar_input_offset_r <= 0;
                        input_issue_offset_r <= 0;
                        issue_kernel_y_r <= 0;
                        issue_kernel_x_r <= 0;
                        issue_input_channel_r <= 0;
                        scalar_feature_anchor_r <= 0;
                        scalar_tile_row_anchor_r <= 0;
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
                        mac_product_valid_r <= 1'b0;
                                    requant_collect_count_r <= 0;
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
                    scalar_weight_offset_r <= scalar_weight_offset_r + 1'b1;
                    weight_issue_offset_r <= weight_issue_offset_r + 1'b1;
                    if (input_channel_r + 1 < cfg_input_c_i) begin
                        input_channel_r <= input_channel_r + 1'b1;
                        scalar_input_offset_r <= scalar_input_offset_r + 1'b1;
                        issue_input_channel_r <= issue_input_channel_r + 1'b1;
                        input_issue_offset_r <= input_issue_offset_r + 1'b1;
                    end else begin
                        input_channel_r <= 0;
                        issue_input_channel_r <= 0;
                        if (kernel_x_r + 1 < cfg_kernel_w_i) begin
                            kernel_x_r <= kernel_x_r + 1'b1;
                            scalar_input_offset_r <= scalar_input_offset_r + 1'b1;
                            issue_kernel_x_r <= issue_kernel_x_r + 1'b1;
                            input_issue_offset_r <= input_issue_offset_r + 1'b1;
                        end else begin
                            kernel_x_r <= 0;
                            issue_kernel_x_r <= 0;
                            if (kernel_y_r + 1 < cfg_kernel_h_i) begin
                                kernel_y_r <= kernel_y_r + 1'b1;
                                scalar_input_offset_r <= scalar_input_offset_r + 1'b1 +
                                                         scalar_kernel_row_gap_r;
                                issue_kernel_y_r <= issue_kernel_y_r + 1'b1;
                                input_issue_offset_r <= input_issue_offset_r + 1'b1 +
                                                        scalar_kernel_row_gap_r;
                            end
                        end
                    end
                    state_r <= ST_MAC_PIPE;
                end
                // Issue term two while the two-stage feature/weight paths
                // deliver term zero. The semantic loop cursor intentionally
                // remains on term one until ST_MAC starts consuming results.
                ST_MAC_PIPE: begin
                    mac_product_valid_r <= 1'b0;
                    weight_issue_offset_r <= weight_issue_offset_r + 1'b1;
                    if (issue_input_channel_r + 1 < cfg_input_c_i) begin
                        issue_input_channel_r <= issue_input_channel_r + 1'b1;
                        input_issue_offset_r <= input_issue_offset_r + 1'b1;
                    end else begin
                        issue_input_channel_r <= 0;
                        if (issue_kernel_x_r + 1 < cfg_kernel_w_i) begin
                            issue_kernel_x_r <= issue_kernel_x_r + 1'b1;
                            input_issue_offset_r <= input_issue_offset_r + 1'b1;
                        end else begin
                            issue_kernel_x_r <= 0;
                            if (issue_kernel_y_r + 1 < cfg_kernel_h_i) begin
                                issue_kernel_y_r <= issue_kernel_y_r + 1'b1;
                                input_issue_offset_r <= input_issue_offset_r + 1'b1 +
                                                        scalar_kernel_row_gap_r;
                            end else begin
                                issue_kernel_y_r <= 0;
                                input_issue_offset_r <= scalar_feature_anchor_r;
                            end
                        end
                    end
                    state_r <= ST_MAC;
                end
                ST_MAC: begin
                    scalar_weight_offset_r <= scalar_weight_offset_r + 1'b1;
                    weight_issue_offset_r <= weight_issue_offset_r + 1'b1;
                    if (input_channel_r + 1 < cfg_input_c_i)
                        scalar_input_offset_r <= scalar_input_offset_r + 1'b1;
                    else if (kernel_x_r + 1 < cfg_kernel_w_i)
                        scalar_input_offset_r <= scalar_input_offset_r + 1'b1;
                    else if (kernel_y_r + 1 < cfg_kernel_h_i)
                        scalar_input_offset_r <= scalar_input_offset_r + 1'b1 +
                                                 scalar_kernel_row_gap_r;
                    else
                        scalar_input_offset_r <= scalar_feature_anchor_r;
                    if (issue_input_channel_r + 1 < cfg_input_c_i) begin
                        issue_input_channel_r <= issue_input_channel_r + 1'b1;
                        input_issue_offset_r <= input_issue_offset_r + 1'b1;
                    end else begin
                        issue_input_channel_r <= 0;
                        if (issue_kernel_x_r + 1 < cfg_kernel_w_i) begin
                            issue_kernel_x_r <= issue_kernel_x_r + 1'b1;
                            input_issue_offset_r <= input_issue_offset_r + 1'b1;
                        end else begin
                            issue_kernel_x_r <= 0;
                            if (issue_kernel_y_r + 1 < cfg_kernel_h_i) begin
                                issue_kernel_y_r <= issue_kernel_y_r + 1'b1;
                                input_issue_offset_r <= input_issue_offset_r + 1'b1 +
                                                        scalar_kernel_row_gap_r;
                            end else begin
                                issue_kernel_y_r <= 0;
                                input_issue_offset_r <= scalar_feature_anchor_r;
                            end
                        end
                    end
                    for (lane_i = 0; lane_i < NUM_PE; lane_i = lane_i + 1) begin
                        mac_product_r[lane_i] <=
                            lane_product_w[lane_i];
                    end
                    mac_product_valid_r <= 1'b1;
                    if (input_channel_r + 1 >= cfg_input_c_i) begin
                        input_channel_r <= 0;
                        if (kernel_x_r + 1 >= cfg_kernel_w_i) begin
                            kernel_x_r <= 0;
                            if (kernel_y_r + 1 >= cfg_kernel_h_i) begin
                                kernel_y_r <= 0;
                                for (lane_i = 0; lane_i < NUM_PE; lane_i = lane_i + 1) begin
                                    requant_lane_valid_r[lane_i] <=
                                        lane_enabled_w[lane_i];
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
                        // The final issued ERAM word becomes visible only on
                        // this edge.  Capture it before forming the requant
                        // accumulator in ST_MAC_DRAIN_FINAL.
                        mac_product_r[lane_i] <=
                            lane_product_w[lane_i];
                    end
                    mac_product_valid_r <= 1'b0;
                    state_r <= ST_MAC_DRAIN_FINAL;
                end
                ST_MAC_DRAIN_FINAL: begin
                            requant_collect_count_r <= 0;
                    parameter_issue_count_r <= 0;
                    parameter_issue_valid_r <= 0;
                    state_r <= ST_PARAM_LOAD;
                end
                ST_PARAM_LOAD: begin
                    // Read current ERAM index and matching finalized accumulator.
                    // Never advance the index while this word is backpressured.
                    if(parameter_issue_valid_r)begin
                        if(rq_req_ready)begin
                            parameter_issue_count_r<=parameter_issue_count_r+1'b1;
                            parameter_issue_valid_r<=0;
                        end
                    end else if(parameter_issue_count_r<NUM_PE)begin
                        parameter_accumulator_pipe_r<=accumulator_r[parameter_issue_count_r];
                        parameter_issue_valid_r<=1;
                    end else state_r<=ST_WRITE;
                end
                ST_WRITE: begin
                    if(requant_collect_count_r >= NUM_PE) begin
                        output_valid_o <= 1'b1;
                        output_y_o <= cfg_output_origin_y_i + tile_y_r;
                        output_x_o <= cfg_output_origin_x_i + tile_x_r;
                        output_channel_base_o <= output_channel_r;
                        output_lane_valid_o <= requant_lane_valid_r;
                        input_channel_r <= 0;
                        kernel_x_r <= 0;
                        kernel_y_r <= 0;
                        if (output_channel_r + NUM_PE < cfg_output_c_i) begin
                            output_channel_r <= output_channel_r + NUM_PE;
                            // Each lane owns a bank of output-channel planes.
                            // At group boundaries the rolling offset already
                            // points at the next plane in every lane bank.
                            scalar_weight_offset_r <= scalar_weight_offset_r;
                            weight_issue_offset_r <= scalar_weight_offset_r;
                            scalar_input_offset_r <= scalar_feature_anchor_r;
                            input_issue_offset_r <= scalar_feature_anchor_r;
                            issue_input_channel_r <= 0;
                            issue_kernel_x_r <= 0;
                            issue_kernel_y_r <= 0;
                            state_r <= ST_MAC_PRIME;
                        end else begin
                            output_channel_r <= 0;
                            if (tile_x_r + 1 < cfg_tile_w_i) begin
                                tile_x_r <= tile_x_r + 1'b1;
                                scalar_weight_offset_r <= 0;
                                weight_issue_offset_r <= 0;
                                scalar_feature_anchor_r <= scalar_feature_anchor_r +
                                                           scalar_horizontal_step_r;
                                scalar_input_offset_r <= scalar_feature_anchor_r +
                                                         scalar_horizontal_step_r;
                                input_issue_offset_r <= scalar_feature_anchor_r +
                                                        scalar_horizontal_step_r;
                                issue_input_channel_r <= 0;
                                issue_kernel_x_r <= 0;
                                issue_kernel_y_r <= 0;
                                state_r <= ST_MAC_PRIME;
                            end else if (tile_y_r + 1 < cfg_tile_h_i) begin
                                tile_x_r <= 0;
                                tile_y_r <= tile_y_r + 1'b1;
                                scalar_weight_offset_r <= 0;
                                weight_issue_offset_r <= 0;
                                scalar_tile_row_anchor_r <= scalar_tile_row_anchor_r +
                                                            scalar_vertical_step_r;
                                scalar_feature_anchor_r <= scalar_tile_row_anchor_r +
                                                           scalar_vertical_step_r;
                                scalar_input_offset_r <= scalar_tile_row_anchor_r +
                                                         scalar_vertical_step_r;
                                input_issue_offset_r <= scalar_tile_row_anchor_r +
                                                        scalar_vertical_step_r;
                                issue_input_channel_r <= 0;
                                issue_kernel_x_r <= 0;
                                issue_kernel_y_r <= 0;
                                state_r <= ST_MAC_PRIME;
                            end else begin
                                scalar_weight_offset_r <= 0;
                                weight_issue_offset_r <= 0;
                                busy_o <= 1'b0;
                                done_o <= 1'b1;
                                state_r <= ST_IDLE;
                            end
                        end
                    end
                end
                default: state_r <= ST_IDLE;
            endcase
            if(rq_rsp_valid&&rq_rsp_error)begin
                requant_error_o<=1;busy_o<=0;state_r<=ST_IDLE;
            end

        end
    end
endmodule


