// Behavioural PH1P_LOGIC_ERAM for the unit test: true dual port, NOREG outputs (data one clock after ce), ports A and B write.
module PH1P_LOGIC_ERAM #(parameter integer DATA_WIDTH_A=8, DATA_WIDTH_B=8, ADDR_WIDTH_A=9, ADDR_WIDTH_B=9,
  DATA_DEPTH_A=512, DATA_DEPTH_B=512, parameter MODE="DP", REGMODE_A="NOREG", REGMODE_B="NOREG",
  WRITEMODE_A="NORMAL", WRITEMODE_B="NORMAL", CLKMODE="SYNC", SSROVERCE="DISABLE", OREGSET_A="RESET", OREGSET_B="RESET",
  RESETMODE_A="SYNC", RESETMODE_B="SYNC", ASYNC_RESET_RELEASE_A="SYNC", ASYNC_RESET_RELEASE_B="SYNC",
  ECC_ENCODE="DISABLE", ECC_DECODE="DISABLE", IMPLEMENT="20K", INIT_FILE="NONE", FILL_ALL="NONE")(
  input [DATA_WIDTH_A-1:0] dia, input [ADDR_WIDTH_A-1:0] addra, input cea, ocea, clka, wea, rsta, bea,
  input [DATA_WIDTH_B-1:0] dib, input [ADDR_WIDTH_B-1:0] addrb, input ceb, oceb, clkb, web, rstb, beb,
  input ecc_sbiterrinj, ecc_dbiterrinj, output reg [DATA_WIDTH_A-1:0] doa, output reg [DATA_WIDTH_B-1:0] dob,
  output ecc_sbiterr, ecc_dbiterr);
  reg [DATA_WIDTH_A-1:0] m [0:DATA_DEPTH_A-1];
  integer ii; initial for(ii=0; ii<DATA_DEPTH_A; ii=ii+1) m[ii] = 0;   // ERAM powers up as 0
  always @(posedge clka) begin if(cea && wea) m[addra] <= dia; if(cea) doa <= m[addra]; end   // port A read (depth RMW)
  always @(posedge clkb) begin if(ceb) dob <= m[addrb]; if(ceb && web) m[addrb] <= dib; end   // port B write (MOTION history)
  assign ecc_sbiterr=1'b0; assign ecc_dbiterr=1'b0;
endmodule
