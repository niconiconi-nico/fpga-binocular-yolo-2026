// Runtime-programmable signed INT8 lookup table.
//
// The verified YOLOv8n package carries one 256-entry table for each SiLU
// node (and separate postprocess tables).  Unlike v5n_silu_pwl, this
// primitive does not bake a temporary scale or approximation into RTL: the
// loader writes code -128..127 at addresses 0..255 and the datapath performs
// exactly table[code + 128].
module v5n_lut256_i8 #(
    parameter integer NUM_LANES = 4
) (
    input  wire                            clk_i,
    input  wire                            rst_ni,
    input  wire                            cfg_write_enable_i,
    input  wire [7:0]                      cfg_address_i,
    input  wire signed [7:0]               cfg_data_i,
    input  wire                            valid_i,
    input  wire signed [NUM_LANES*8-1:0]   code_i,
    output reg                             valid_o,
    output wire signed [NUM_LANES*8-1:0]   code_o
);
    reg signed [7:0] table_r [0:255];
    reg signed [7:0] code_r [0:NUM_LANES-1];
    integer lane_i;

    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            valid_o <= 1'b0;
            for (lane_i = 0; lane_i < NUM_LANES; lane_i = lane_i + 1)
                code_r[lane_i] <= 8'sd0;
        end else begin
            if (cfg_write_enable_i)
                table_r[cfg_address_i] <= cfg_data_i;
            valid_o <= valid_i;
            if (valid_i) begin
                for (lane_i = 0; lane_i < NUM_LANES; lane_i = lane_i + 1)
                    code_r[lane_i] <= table_r[$unsigned(code_i[lane_i*8 +: 8]) + 8'd128];
            end
        end
    end

    genvar lane;
    generate
        for (lane = 0; lane < NUM_LANES; lane = lane + 1) begin : G_LUT_OUTPUT
            assign code_o[lane*8 +: 8] = code_r[lane];
        end
    endgenerate
endmodule
