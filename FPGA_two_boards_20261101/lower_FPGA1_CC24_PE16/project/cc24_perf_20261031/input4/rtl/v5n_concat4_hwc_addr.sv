// Direct HWC channel-concat address resolver for one to four source tensors.
//
// All YOLO concat inputs share Y/X geometry.  Given a destination HWC channel,
// this primitive identifies the source tensor and its source channel.  A
// tensor-memory adapter then reads that source and applies the matching merge
// requant parameters.  This preserves the source order and avoids a full-map
// intermediate or a numerically-wrong cascade of binary Concats.
module v5n_concat4_hwc_addr #(
    parameter integer CHANNEL_W = 10
) (
    input  wire [2:0]                 source_count_i,
    input  wire [CHANNEL_W-1:0]       source0_channels_i,
    input  wire [CHANNEL_W-1:0]       source1_channels_i,
    input  wire [CHANNEL_W-1:0]       source2_channels_i,
    input  wire [CHANNEL_W-1:0]       source3_channels_i,
    input  wire [CHANNEL_W-1:0]       output_channel_i,
    output reg                        valid_o,
    output reg [1:0]                  source_index_o,
    output reg [CHANNEL_W-1:0]        source_channel_o
);
    reg [CHANNEL_W:0] limit0_r;
    reg [CHANNEL_W:0] limit1_r;
    reg [CHANNEL_W:0] limit2_r;
    reg [CHANNEL_W:0] limit3_r;
    reg [CHANNEL_W:0] channel_r;

    always @* begin
        channel_r = {1'b0, output_channel_i};
        limit0_r = {1'b0, source0_channels_i};
        limit1_r = limit0_r + {1'b0, source1_channels_i};
        limit2_r = limit1_r + {1'b0, source2_channels_i};
        limit3_r = limit2_r + {1'b0, source3_channels_i};
        valid_o = 1'b0;
        source_index_o = 2'd0;
        source_channel_o = 0;
        if (source_count_i >= 1 && channel_r < limit0_r) begin
            valid_o = 1'b1;
            source_index_o = 2'd0;
            source_channel_o = output_channel_i;
        end else if (source_count_i >= 2 && channel_r < limit1_r) begin
            valid_o = 1'b1;
            source_index_o = 2'd1;
            source_channel_o = channel_r - limit0_r;
        end else if (source_count_i >= 3 && channel_r < limit2_r) begin
            valid_o = 1'b1;
            source_index_o = 2'd2;
            source_channel_o = channel_r - limit1_r;
        end else if (source_count_i >= 4 && channel_r < limit3_r) begin
            valid_o = 1'b1;
            source_index_o = 2'd3;
            source_channel_o = channel_r - limit2_r;
        end
    end
endmodule
