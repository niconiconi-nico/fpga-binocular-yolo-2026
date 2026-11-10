// Stage18 fixed C2f channel views. Constants derived from the frozen tensor map.
// Read-only aliases; writers continue to target the real producer allocation.
// There are no chained views and no reusable feature allocations in this graph.
// Address arithmetic is registered by the byte adapter before cache lookup.
module v5n_split_view_map #(
    parameter integer ADDR_W=32
)(
    input wire [ADDR_W-1:0] logical_address_i,
    output reg hit_o,
    output reg [ADDR_W-1:0] logical_base_o, physical_base_o,
    output reg [7:0] channel_mask_o
);
    always @* begin
        hit_o=0; logical_base_o=0; physical_base_o=0; channel_mask_o=0;
        if (logical_address_i >= 32'd1945600 && logical_address_i < 32'd2048000) begin
            // tensor 7 = tensor 6 channel half 0
            hit_o=1; logical_base_o=32'd1945600;
            physical_base_o=32'd1740800; channel_mask_o=8'd15;
        end
        if (logical_address_i >= 32'd2048000 && logical_address_i < 32'd2150400) begin
            // tensor 8 = tensor 6 channel half 1
            hit_o=1; logical_base_o=32'd2048000;
            physical_base_o=32'd1740816; channel_mask_o=8'd15;
        end
        if (logical_address_i >= 32'd3788800 && logical_address_i < 32'd3840000) begin
            // tensor 21 = tensor 20 channel half 0
            hit_o=1; logical_base_o=32'd3788800;
            physical_base_o=32'd3686400; channel_mask_o=8'd31;
        end
        if (logical_address_i >= 32'd3840000 && logical_address_i < 32'd3891200) begin
            // tensor 22 = tensor 20 channel half 1
            hit_o=1; logical_base_o=32'd3840000;
            physical_base_o=32'd3686432; channel_mask_o=8'd31;
        end
        if (logical_address_i >= 32'd5017600 && logical_address_i < 32'd5043200) begin
            // tensor 40 = tensor 39 channel half 0
            hit_o=1; logical_base_o=32'd5017600;
            physical_base_o=32'd4966400; channel_mask_o=8'd63;
        end
        if (logical_address_i >= 32'd5043200 && logical_address_i < 32'd5068800) begin
            // tensor 41 = tensor 39 channel half 1
            hit_o=1; logical_base_o=32'd5043200;
            physical_base_o=32'd4966464; channel_mask_o=8'd63;
        end
        if (logical_address_i >= 32'd5632000 && logical_address_i < 32'd5644800) begin
            // tensor 59 = tensor 58 channel half 0
            hit_o=1; logical_base_o=32'd5632000;
            physical_base_o=32'd5606400; channel_mask_o=8'd127;
        end
        if (logical_address_i >= 32'd5644800 && logical_address_i < 32'd5657600) begin
            // tensor 60 = tensor 58 channel half 1
            hit_o=1; logical_base_o=32'd5644800;
            physical_base_o=32'd5606528; channel_mask_o=8'd127;
        end
        if (logical_address_i >= 32'd6336000 && logical_address_i < 32'd6361600) begin
            // tensor 81 = tensor 80 channel half 0
            hit_o=1; logical_base_o=32'd6336000;
            physical_base_o=32'd6284800; channel_mask_o=8'd63;
        end
        if (logical_address_i >= 32'd6361600 && logical_address_i < 32'd6387200) begin
            // tensor 82 = tensor 80 channel half 1
            hit_o=1; logical_base_o=32'd6361600;
            physical_base_o=32'd6284864; channel_mask_o=8'd63;
        end
        if (logical_address_i >= 32'd7385600 && logical_address_i < 32'd7436800) begin
            // tensor 94 = tensor 93 channel half 0
            hit_o=1; logical_base_o=32'd7385600;
            physical_base_o=32'd7283200; channel_mask_o=8'd31;
        end
        if (logical_address_i >= 32'd7436800 && logical_address_i < 32'd7488000) begin
            // tensor 95 = tensor 93 channel half 1
            hit_o=1; logical_base_o=32'd7436800;
            physical_base_o=32'd7283232; channel_mask_o=8'd31;
        end
        if (logical_address_i >= 32'd8281600 && logical_address_i < 32'd8307200) begin
            // tensor 108 = tensor 107 channel half 0
            hit_o=1; logical_base_o=32'd8281600;
            physical_base_o=32'd8230400; channel_mask_o=8'd63;
        end
        if (logical_address_i >= 32'd8307200 && logical_address_i < 32'd8332800) begin
            // tensor 109 = tensor 107 channel half 1
            hit_o=1; logical_base_o=32'd8307200;
            physical_base_o=32'd8230464; channel_mask_o=8'd63;
        end
        if (logical_address_i >= 32'd8729600 && logical_address_i < 32'd8742400) begin
            // tensor 122 = tensor 121 channel half 0
            hit_o=1; logical_base_o=32'd8729600;
            physical_base_o=32'd8704000; channel_mask_o=8'd127;
        end
        if (logical_address_i >= 32'd8742400 && logical_address_i < 32'd8755200) begin
            // tensor 123 = tensor 121 channel half 1
            hit_o=1; logical_base_o=32'd8742400;
            physical_base_o=32'd8704128; channel_mask_o=8'd127;
        end
    end
endmodule
