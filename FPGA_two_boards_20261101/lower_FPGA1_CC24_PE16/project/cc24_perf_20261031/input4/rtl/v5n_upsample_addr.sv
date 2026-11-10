// Nearest-neighbor x2 address transform. Input/output tensors remain HWC;
// the surrounding tile scheduler supplies the channel coordinate unchanged.
module v5n_upsample_addr #(
    parameter integer COORD_W = 10,
    parameter integer CHANNEL_W = 10
) (
    input  wire [COORD_W-1:0]    output_y_i,
    input  wire [COORD_W-1:0]    output_x_i,
    input  wire [CHANNEL_W-1:0]  output_channel_i,
    output wire [COORD_W-1:0]    input_y_o,
    output wire [COORD_W-1:0]    input_x_o,
    output wire [CHANNEL_W-1:0]  input_channel_o
);
    assign input_y_o = output_y_i >> 1;
    assign input_x_o = output_x_i >> 1;
    assign input_channel_o = output_channel_i;
endmodule
