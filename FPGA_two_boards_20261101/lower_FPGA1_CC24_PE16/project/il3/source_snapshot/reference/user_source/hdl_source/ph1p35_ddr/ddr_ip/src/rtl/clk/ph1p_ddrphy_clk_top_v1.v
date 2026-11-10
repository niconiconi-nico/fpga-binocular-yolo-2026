
`timescale 1ps / 1ps

module ph1p_ddrphy_clk_top #(
    parameter  BK_NUM      =  2   ,
    parameter  REFCLK_FREQ = "100",
    parameter  REFCLK_DIV  =  1   ,
    parameter  FBKCLK_DIV  =  1   ,
    parameter  CLK2_DIV    =  4   ,
    parameter  CLK3_DIV    =  32
)(
    input                sys_rst  , 
    input                ref_clk  , 

    output               cfg_clk  ,
    output               dhi_clk  ,
    output  [BK_NUM-1:0] ctl_clk  ,
    output  [BK_NUM-1:0] ddr_clk  ,
    output               pll_lock
);

///////////////////////////////////////////////////////////////////////////////////////////////////
// Local Parameter
///////////////////////////////////////////////////////////////////////////////////////////////////

///////////////////////////////////////////////////////////////////////////////////////////////////
// Internal Signals
///////////////////////////////////////////////////////////////////////////////////////////////////
wire  pll_clk_0;
wire  pll_clk_1;
wire  pll_clk_2;
wire  pll_clk_3;

wire  pll_mlclk_1;
wire  pll_mlclk_2;

///////////////////////////////////////////////////////////////////////////////////////////////////
// Instance : GPLL
///////////////////////////////////////////////////////////////////////////////////////////////////
ph1p_ddrphy_pll  #(
    .REFCLK_FREQ  ( REFCLK_FREQ ),
    .REFCLK_DIV   ( REFCLK_DIV  ),
    .FBKCLK_DIV   ( FBKCLK_DIV  ),
    .CLK2_DIV     ( CLK2_DIV    ),
    .CLK3_DIV     ( CLK3_DIV    )
) u_pll (
    .refclk       ( ref_clk     ),
    .reset        ( sys_rst     ),
    .clk0_out     ( pll_clk_0   ),
    .clk1_out     ( pll_clk_1   ),
    .clk2_out     ( pll_clk_2   ),
    .clk3_out     ( pll_clk_3   ),
    .lock         ( pll_lock    )
);

///////////////////////////////////////////////////////////////////////////////////////////////////
// Instance : Clock Buffer
///////////////////////////////////////////////////////////////////////////////////////////////////
PH1P_PHY_MLCLK u_mlclk_1 (
    .ce      ( 1'b1        ),
    .clkin   ( pll_clk_1   ),
    .clkout  ( pll_mlclk_1 )
);

PH1P_PHY_MLCLK u_mlclk_2 (
    .ce      ( 1'b1        ),
    .clkin   ( pll_clk_2   ),
    .clkout  ( pll_mlclk_2 )
);

genvar n;
generate
for (n = 0; n <= BK_NUM-1; n = n+1) begin : ioclk
    PH1P_PHY_IOCLK u_ioclk_0 (
        .clkin  ( pll_mlclk_1 ),
        .clkout ( ctl_clk[n]  )
    );

    PH1P_PHY_IOCLK u_ioclk_1 (
        .clkin  ( pll_mlclk_2 ),
        .clkout ( ddr_clk[n]  )
    );
end
endgenerate

///////////////////////////////////////////////////////////////////////////////////////////////////
// Output
///////////////////////////////////////////////////////////////////////////////////////////////////

assign cfg_clk  = pll_clk_3;
assign dhi_clk  = pll_clk_0;

endmodule

