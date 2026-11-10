// Combinational converter for the HDMI/display RGB888 stream.
module rgb888_to_rgb565 (
    input  wire [23:0] I_rgb888,
    output wire [15:0] O_rgb565
);
    assign O_rgb565 = {I_rgb888[23:19], I_rgb888[15:10], I_rgb888[7:3]};
endmodule
