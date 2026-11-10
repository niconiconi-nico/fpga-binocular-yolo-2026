// L3 is HDIO. Same FPGA clock and polarity as the reference direct assignment,
// but sent to the output through the dedicated DDR output element.
module camera_clock_forward(input wire clk, output wire q);
    PH1P_LOGIC_HD_ODDR u_oddr(.q(q),.clk(clk),.d0(1'b1),.d1(1'b0),.rst(1'b0));
endmodule
