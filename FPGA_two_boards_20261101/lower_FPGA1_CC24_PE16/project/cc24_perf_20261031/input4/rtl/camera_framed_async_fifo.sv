// Camera -> DDR framed line CDC. Gray pointers + synchronous true-dual-port
// ERAM. No cross-domain multi-bit control sampling; frame ID rides each word.
// No asynchronous reset per-frame. A lost line marks/discards the whole frame.
module camera_framed_async_fifo #(
 parameter integer ADDR_BITS=9
)(
 input wire write_clk,write_rst_n,write_valid_i,output wire write_ready_o,
 input wire [162:0] write_data_i,
 input wire read_clk,read_rst_n,output wire read_valid_o,input wire read_ready_i,
 output wire [162:0] read_data_o
);
 localparam integer DEPTH=1<<ADDR_BITS;
 reg [ADDR_BITS:0] wp,wg,rp,rg;
 (* async_reg="true" *) reg [ADDR_BITS:0] rgs1,rgs2,wgs1,wgs2;
 wire [ADDR_BITS:0] next_wp=wp+1'b1;
 wire [ADDR_BITS:0] next_wg=(next_wp>>1)^next_wp;
 // Reserve one slot; conservative combinational full check cannot overwrite.
 wire full=next_wg=={~rgs2[ADDR_BITS:ADDR_BITS-1],rgs2[ADDR_BITS-2:0]};
 wire empty=rg==wgs2;
 assign write_ready_o=!full;
 reg valid,fetch_pending;reg [162:0] held;
 wire [162:0] ram_data;
 wire fetch=!valid&&!fetch_pending&&!empty;
 assign read_valid_o=valid;assign read_data_o=held;
 PH1P_LOGIC_ERAM #(.DATA_WIDTH_A(163),.DATA_WIDTH_B(163),.ADDR_WIDTH_A(ADDR_BITS),.ADDR_WIDTH_B(ADDR_BITS),
   .DATA_DEPTH_A(DEPTH),.DATA_DEPTH_B(DEPTH),.MODE("DP"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),
   .WRITEMODE_A("READBEFOREWRITE"),.WRITEMODE_B("READBEFOREWRITE"),.CLKMODE("ASYNC"),.SSROVERCE("DISABLE"),
   .OREGSET_A("RESET"),.OREGSET_B("RESET"),.RESETMODE_A("ASYNC"),.RESETMODE_B("ASYNC"),
   .ASYNC_RESET_RELEASE_A("ASYNC"),.ASYNC_RESET_RELEASE_B("ASYNC"),.ECC_ENCODE("DISABLE"),.ECC_DECODE("DISABLE"),
   .IMPLEMENT("20K(FAST)"),.INIT_FILE("NONE"),.FILL_ALL("NONE")) storage(
   .dia(write_data_i),.addra(wp[ADDR_BITS-1:0]),.cea(1'b1),.ocea(1'b0),.clka(write_clk),
   .wea(write_valid_i&&write_ready_o),.rsta(1'b0),.bea(1'b0),.dib(163'd0),.addrb(rp[ADDR_BITS-1:0]),
   .ceb(fetch),.oceb(1'b0),.clkb(read_clk),.web(1'b0),.rstb(1'b0),.beb(1'b0),
   .ecc_sbiterrinj(1'b0),.ecc_dbiterrinj(1'b0),.doa(),.dob(ram_data),.ecc_sbiterr(),.ecc_dbiterr());
 always @(posedge write_clk or negedge write_rst_n)begin
   if(!write_rst_n)begin wp<=0;wg<=0;rgs1<=0;rgs2<=0;end
   else begin rgs1<=rg;rgs2<=rgs1;if(write_valid_i&&write_ready_o)begin wp<=next_wp;wg<=next_wg;end end
 end
 always @(posedge read_clk or negedge read_rst_n)begin
   if(!read_rst_n)begin rp<=0;rg<=0;wgs1<=0;wgs2<=0;valid<=0;fetch_pending<=0;held<=0;end
   else begin
     wgs1<=wg;wgs2<=wgs1;
     if(fetch)fetch_pending<=1;
     if(fetch_pending)begin held<=ram_data;valid<=1;fetch_pending<=0;end
     if(valid&&read_ready_i)begin valid<=0;rp<=rp+1'b1;rg<=((rp+1'b1)>>1)^(rp+1'b1);end
   end
 end
endmodule
