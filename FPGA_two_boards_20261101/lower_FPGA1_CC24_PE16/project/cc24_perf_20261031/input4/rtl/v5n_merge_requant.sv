// Exact merge-domain requantization used by YOLOv8 C2f residuals and Concats.
//
// For an Add, each source is rounded in its own domain first, then the two
// mapped signed integers are added and saturated once.  For a Concat span,
// mode_add_i=0 copies source0 through its own mapping.  The concat address
// scheduler invokes this once for every source channel span; it must not build
// a four-input concat by cascading saturated two-input concats.
module v5n_merge_requant #(
    parameter integer NUM_LANES = 4,
    parameter integer PIPELINED = 0
) (
    input  wire                            clk_i,
    input  wire                            rst_ni,
    input  wire                            valid_i,
    input  wire                            mode_add_i,
    input  wire signed [NUM_LANES*8-1:0]   source0_i,
    input  wire signed [NUM_LANES*8-1:0]   source1_i,
    input  wire signed [31:0]              source0_multiplier_i,
    input  wire [5:0]                      source0_shift_i,
    input  wire signed [31:0]              source1_multiplier_i,
    input  wire [5:0]                      source1_shift_i,
    output reg                             valid_o,
    output wire signed [NUM_LANES*8-1:0]   data_o
);
    reg signed [7:0] data_r [0:NUM_LANES-1];
    (* multstyle = "dsp" *) reg signed [63:0] product0_r [0:NUM_LANES-1];
    (* multstyle = "dsp" *) reg signed [63:0] product1_r [0:NUM_LANES-1];
    reg signed [63:0] rounded0_r [0:NUM_LANES-1];
    reg signed [63:0] rounded1_r [0:NUM_LANES-1];
    reg product_valid_r, rounded_valid_r;
    reg mode_add_product_r, mode_add_rounded_r;
    reg [5:0] shift0_product_r, shift1_product_r;

    function signed [63:0] rta_shift;
        input signed [63:0] value_i;
        input [5:0] shift_i;
        reg signed [63:0] half;
        begin
            if (shift_i == 0)
                rta_shift = value_i;
            else begin
                half = 64'sd1 <<< (shift_i - 1'b1);
                if (value_i >= 0)
                    rta_shift = (value_i + half) >>> shift_i;
                else
                    rta_shift = -(((-value_i) + half) >>> shift_i);
            end
        end
    endfunction

    function signed [7:0] sat_i8;
        input signed [63:0] value_i;
        begin
            if (value_i > 64'sd127)
                sat_i8 = 8'sd127;
            else if (value_i < -64'sd128)
                sat_i8 = -8'sd128;
            else
                sat_i8 = value_i[7:0];
        end
    endfunction

    function signed [63:0] map_source;
        input signed [7:0] code_i;
        input signed [31:0] multiplier_i;
        input [5:0] shift_i;
        (* multstyle = "dsp" *) reg signed [63:0] numerator;
        begin
            numerator = code_i * multiplier_i;
            map_source = rta_shift(numerator, shift_i);
        end
    endfunction

    generate if (PIPELINED != 0) begin : G_PIPELINED
        integer lane_i;
        always @(posedge clk_i or negedge rst_ni) begin
            if (!rst_ni) begin
                valid_o <= 1'b0;
                product_valid_r <= 1'b0;
                rounded_valid_r <= 1'b0;
                mode_add_product_r <= 1'b0;
                mode_add_rounded_r <= 1'b0;
                shift0_product_r <= 6'd0;
                shift1_product_r <= 6'd0;
                for (lane_i = 0; lane_i < NUM_LANES; lane_i = lane_i + 1) begin
                    data_r[lane_i] <= 8'sd0;
                    product0_r[lane_i] <= 64'sd0;
                    product1_r[lane_i] <= 64'sd0;
                    rounded0_r[lane_i] <= 64'sd0;
                    rounded1_r[lane_i] <= 64'sd0;
                end
            end else begin
                product_valid_r <= valid_i;
                rounded_valid_r <= product_valid_r;
                valid_o <= rounded_valid_r;
                if (valid_i) begin
                    mode_add_product_r <= mode_add_i;
                    shift0_product_r <= source0_shift_i;
                    shift1_product_r <= source1_shift_i;
                    for (lane_i = 0; lane_i < NUM_LANES; lane_i = lane_i + 1) begin
                        product0_r[lane_i] <= $signed(source0_i[lane_i*8 +: 8]) * source0_multiplier_i;
                        product1_r[lane_i] <= $signed(source1_i[lane_i*8 +: 8]) * source1_multiplier_i;
                    end
                end
                if (product_valid_r) begin
                    mode_add_rounded_r <= mode_add_product_r;
                    for (lane_i = 0; lane_i < NUM_LANES; lane_i = lane_i + 1) begin
                        rounded0_r[lane_i] <= rta_shift(product0_r[lane_i], shift0_product_r);
                        rounded1_r[lane_i] <= rta_shift(product1_r[lane_i], shift1_product_r);
                    end
                end
                if (rounded_valid_r)
                    for (lane_i = 0; lane_i < NUM_LANES; lane_i = lane_i + 1)
                        data_r[lane_i] <= sat_i8(rounded0_r[lane_i] +
                                                 (mode_add_rounded_r ? rounded1_r[lane_i] : 64'sd0));
            end
        end
    end else begin : G_SINGLE_CYCLE
        integer lane_i;
        always @(posedge clk_i or negedge rst_ni) begin
            if (!rst_ni) begin
                valid_o <= 1'b0;
                for (lane_i = 0; lane_i < NUM_LANES; lane_i = lane_i + 1)
                    data_r[lane_i] <= 8'sd0;
            end else begin
                valid_o <= valid_i;
                if (valid_i) begin
                    for (lane_i = 0; lane_i < NUM_LANES; lane_i = lane_i + 1) begin
                        if (mode_add_i)
                            data_r[lane_i] <= sat_i8(
                                map_source($signed(source0_i[lane_i*8 +: 8]), source0_multiplier_i, source0_shift_i) +
                                map_source($signed(source1_i[lane_i*8 +: 8]), source1_multiplier_i, source1_shift_i)
                            );
                        else
                            data_r[lane_i] <= sat_i8(
                                map_source($signed(source0_i[lane_i*8 +: 8]), source0_multiplier_i, source0_shift_i)
                            );
                    end
                end
            end
        end
    end endgenerate

    genvar lane_g;
    generate
        for (lane_g = 0; lane_g < NUM_LANES; lane_g = lane_g + 1) begin : G_OUTPUT
            assign data_o[lane_g*8 +: 8] = data_r[lane_g];
        end
    endgenerate
endmodule
