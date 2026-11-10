// Runtime-parameterized INT32 -> INT8 affine requantizer.
//
// total = accumulator * multiplier + bias
// code  = round_ties_away(total / 2^shift) + output_zero_point
// code is saturated to [qmin, qmax]. Every affine field is runtime-loaded.
module v5n_requantize #(
    parameter integer NUM_PE = 4,
    parameter integer PIPELINED = 0
) (
    input  wire                          clk_i,
    input  wire                          rst_ni,
    input  wire                          valid_i,
    input  wire signed [NUM_PE*32-1:0]  accumulator_i,
    input  wire signed [NUM_PE*32-1:0]  multiplier_i,
    input  wire signed [NUM_PE*32-1:0]  bias_i,
    input  wire [NUM_PE*6-1:0]          shift_i,
    input  wire signed [NUM_PE*32-1:0]  output_zero_point_i,
    input  wire signed [NUM_PE*32-1:0]  qmin_i,
    input  wire signed [NUM_PE*32-1:0]  qmax_i,
    output reg                           valid_o,
    output wire signed [NUM_PE*8-1:0]   code_o
);
    reg signed [7:0] code_r [0:NUM_PE-1];
    (* multstyle = "dsp" *) reg signed [63:0] product_r [0:NUM_PE-1];
    reg signed [63:0] total_r [0:NUM_PE-1], rounded_r [0:NUM_PE-1];
    reg signed [31:0] bias_product_r [0:NUM_PE-1], zero_product_r [0:NUM_PE-1];
    reg signed [31:0] qmin_product_r [0:NUM_PE-1], qmax_product_r [0:NUM_PE-1];
    reg signed [31:0] zero_total_r [0:NUM_PE-1], qmin_total_r [0:NUM_PE-1], qmax_total_r [0:NUM_PE-1];
    reg signed [31:0] zero_rounded_r [0:NUM_PE-1], qmin_rounded_r [0:NUM_PE-1], qmax_rounded_r [0:NUM_PE-1];
    reg [5:0] shift_product_r [0:NUM_PE-1], shift_total_r [0:NUM_PE-1];
    reg product_valid_r, total_valid_r, rounded_valid_r;

    function signed [7:0] affine_round_sat;
        input signed [31:0] accumulator_value;
        input signed [31:0] multiplier_value;
        input signed [31:0] bias_value;
        input [5:0] shift_value;
        input signed [31:0] output_zero_point_value;
        input signed [31:0] qmin_value;
        input signed [31:0] qmax_value;
        (* multstyle = "dsp" *) reg signed [63:0] product_value;
        reg signed [63:0] total_value;
        reg signed [63:0] rounding_value;
        reg signed [63:0] rounded_value;
        begin
            product_value = accumulator_value * multiplier_value;
            total_value = product_value + bias_value;
            if (shift_value == 0) begin
                rounded_value = total_value;
            end else begin
                rounding_value = (64'sd1 <<< (shift_value - 1));
                if (total_value >= 0)
                    rounded_value = (total_value + rounding_value) >>> shift_value;
                else
                    rounded_value = -(((-total_value) + rounding_value) >>> shift_value);
            end
            rounded_value = rounded_value + output_zero_point_value;
            if (rounded_value > qmax_value)
                affine_round_sat = qmax_value[7:0];
            else if (rounded_value < qmin_value)
                affine_round_sat = qmin_value[7:0];
            else
                affine_round_sat = rounded_value[7:0];
        end
    endfunction

    function signed [63:0] round_total;
        input signed [63:0] total_value;
        input [5:0] shift_value;
        reg signed [63:0] rounding_value;
        begin
            if (shift_value == 0) round_total = total_value;
            else begin
                rounding_value = (64'sd1 <<< (shift_value - 1));
                if (total_value >= 0) round_total = (total_value + rounding_value) >>> shift_value;
                else round_total = -(((-total_value) + rounding_value) >>> shift_value);
            end
        end
    endfunction

    generate if (PIPELINED != 0) begin : G_PIPELINED
        integer lane_i;
        always @(posedge clk_i or negedge rst_ni) begin
            if (!rst_ni) begin
                valid_o<=0;product_valid_r<=0;total_valid_r<=0;rounded_valid_r<=0;
                for(lane_i=0;lane_i<NUM_PE;lane_i=lane_i+1) begin
                    code_r[lane_i]<=0;product_r[lane_i]<=0;total_r[lane_i]<=0;rounded_r[lane_i]<=0;
                    bias_product_r[lane_i]<=0;zero_product_r[lane_i]<=0;qmin_product_r[lane_i]<=0;qmax_product_r[lane_i]<=0;shift_product_r[lane_i]<=0;
                    zero_total_r[lane_i]<=0;qmin_total_r[lane_i]<=0;qmax_total_r[lane_i]<=0;shift_total_r[lane_i]<=0;
                    zero_rounded_r[lane_i]<=0;qmin_rounded_r[lane_i]<=0;qmax_rounded_r[lane_i]<=0;
                end
            end else begin
                product_valid_r<=valid_i;total_valid_r<=product_valid_r;rounded_valid_r<=total_valid_r;valid_o<=rounded_valid_r;
                if(valid_i) for(lane_i=0;lane_i<NUM_PE;lane_i=lane_i+1) begin
                    product_r[lane_i]<=$signed(accumulator_i[lane_i*32 +: 32])*$signed(multiplier_i[lane_i*32 +: 32]);
                    bias_product_r[lane_i]<=$signed(bias_i[lane_i*32 +: 32]);shift_product_r[lane_i]<=shift_i[lane_i*6 +: 6];
                    zero_product_r[lane_i]<=$signed(output_zero_point_i[lane_i*32 +: 32]);qmin_product_r[lane_i]<=$signed(qmin_i[lane_i*32 +: 32]);qmax_product_r[lane_i]<=$signed(qmax_i[lane_i*32 +: 32]);
                end
                if(product_valid_r) for(lane_i=0;lane_i<NUM_PE;lane_i=lane_i+1) begin
                    total_r[lane_i]<=product_r[lane_i]+bias_product_r[lane_i];shift_total_r[lane_i]<=shift_product_r[lane_i];
                    zero_total_r[lane_i]<=zero_product_r[lane_i];qmin_total_r[lane_i]<=qmin_product_r[lane_i];qmax_total_r[lane_i]<=qmax_product_r[lane_i];
                end
                if(total_valid_r) for(lane_i=0;lane_i<NUM_PE;lane_i=lane_i+1) begin
                    rounded_r[lane_i]<=round_total(total_r[lane_i],shift_total_r[lane_i]);
                    zero_rounded_r[lane_i]<=zero_total_r[lane_i];qmin_rounded_r[lane_i]<=qmin_total_r[lane_i];qmax_rounded_r[lane_i]<=qmax_total_r[lane_i];
                end
                if(rounded_valid_r) for(lane_i=0;lane_i<NUM_PE;lane_i=lane_i+1) begin
                    if(rounded_r[lane_i]+zero_rounded_r[lane_i]>qmax_rounded_r[lane_i]) code_r[lane_i]<=qmax_rounded_r[lane_i][7:0];
                    else if(rounded_r[lane_i]+zero_rounded_r[lane_i]<qmin_rounded_r[lane_i]) code_r[lane_i]<=qmin_rounded_r[lane_i][7:0];
                    else code_r[lane_i]<=rounded_r[lane_i]+zero_rounded_r[lane_i];
                end
            end
        end
    end else begin : G_SINGLE_CYCLE
        integer lane_i;
        always @(posedge clk_i or negedge rst_ni) begin
            if (!rst_ni) begin
                valid_o <= 1'b0;
                for (lane_i = 0; lane_i < NUM_PE; lane_i = lane_i + 1) code_r[lane_i] <= 0;
            end else begin
                valid_o <= valid_i;
                if (valid_i) for (lane_i = 0; lane_i < NUM_PE; lane_i = lane_i + 1)
                    code_r[lane_i] <= affine_round_sat($signed(accumulator_i[lane_i*32 +: 32]),
                        $signed(multiplier_i[lane_i*32 +: 32]),$signed(bias_i[lane_i*32 +: 32]),shift_i[lane_i*6 +: 6],
                        $signed(output_zero_point_i[lane_i*32 +: 32]),$signed(qmin_i[lane_i*32 +: 32]),$signed(qmax_i[lane_i*32 +: 32]));
            end
        end
    end endgenerate

    genvar lane;
    generate
        for (lane = 0; lane < NUM_PE; lane = lane + 1) begin : G_CODE
            assign code_o[lane*8 +: 8] = code_r[lane];
        end
    endgenerate
endmodule
