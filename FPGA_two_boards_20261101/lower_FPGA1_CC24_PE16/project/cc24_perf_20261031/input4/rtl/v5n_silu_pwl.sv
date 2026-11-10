// TEMPORARY TEST PARAMETERS: signed-code SiLU approximation for Stage A.
//
// The input/output code domain is zero point 0 and scale 1/32. This PWL
// function retains negative SiLU responses; it is explicitly not ReLU.
// Stage B must replace or re-verify it against the frozen QAT activation ABI.
module v5n_silu_pwl #(
    parameter integer NUM_PE = 4
) (
    input  wire                         clk_i,
    input  wire                         rst_ni,
    input  wire                         valid_i,
    input  wire signed [NUM_PE*8-1:0]  code_i,
    output reg                          valid_o,
    output wire signed [NUM_PE*8-1:0]  code_o
);
    reg signed [7:0] code_r [0:NUM_PE-1];
    integer lane_i;

    function signed [7:0] temporary_silu;
        input signed [7:0] x;
        reg signed [15:0] xs;
        reg signed [15:0] distance;
        reg signed [15:0] value;
        reg signed [15:0] product;
        begin
            xs = x;
            if (xs <= -96) begin
                distance = -xs - 96;
                value = -5 + (((distance * 3) + 16) >>> 5);
            end else if (xs <= -64) begin
                distance = xs + 96;
                value = -5 - (((distance * 3) + 16) >>> 5);
            end else if (xs <= -32) begin
                distance = xs + 64;
                value = -8 - ((distance + 16) >>> 5);
            end else if (xs < 0) begin
                distance = xs + 32;
                value = -9 + (((distance * 9) + 16) >>> 5);
            end else if (xs < 64) begin
                product = xs * (xs + 160);
                value = (product + 128) >>> 8;
            end else if (xs < 96) begin
                distance = xs - 64;
                value = 56 + (((distance * 36) + 16) >>> 5);
            end else begin
                distance = xs - 96;
                value = 92 + (((distance * 33) + 16) >>> 5);
            end
            if (value > 127)
                temporary_silu = 8'sd127;
            else if (value < -128)
                temporary_silu = 8'h80;
            else
                temporary_silu = value[7:0];
        end
    endfunction

    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            valid_o <= 1'b0;
            for (lane_i = 0; lane_i < NUM_PE; lane_i = lane_i + 1)
                code_r[lane_i] <= 0;
        end else begin
            valid_o <= valid_i;
            if (valid_i) begin
                for (lane_i = 0; lane_i < NUM_PE; lane_i = lane_i + 1)
                    code_r[lane_i] <= temporary_silu($signed(code_i[lane_i*8 +: 8]));
            end
        end
    end

    genvar lane;
    generate
        for (lane = 0; lane < NUM_PE; lane = lane + 1) begin : G_CODE
            assign code_o[lane*8 +: 8] = code_r[lane];
        end
    endgenerate
endmodule
