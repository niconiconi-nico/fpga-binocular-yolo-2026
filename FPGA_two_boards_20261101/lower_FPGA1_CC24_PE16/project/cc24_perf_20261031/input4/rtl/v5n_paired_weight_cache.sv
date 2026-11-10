// A2 isolated observed-critical-path experiment. NOT promoted.
// Lossless internal coefficient representation. External frozen weight bytes
// remain O,KY,KX,IC. A pair stores {signed9(w1-sign(w0)), w0[7:0]} in17 bits.
// Reconstruct27-bit DSP input as {high9,{10{w0[7]}},w0}; no compute-time add.
// Sixteen old byte banks map to eight paired17-bit banks. Both weights of a
// pair have matching old bank-local offsets. Load odd Cout planes by a guarded
// one-cycle synchronous read/modify/write; never duplicate the full tile.
`include "v5n_weight_capacity.vh"
module v5n_paired_weight_cache #(
 parameter integer NUM_PE=16, parameter integer TILE_BYTES=`V5N_WEIGHT_CACHE_BYTES,
 parameter integer ADDR_W=14, parameter integer CHANNEL_W=10
)(
 input wire clk_i,rst_ni,compute_active_i,compute_bank_i,
 input wire [NUM_PE*ADDR_W-1:0] read_offset_i,
 output wire [NUM_PE*8-1:0] read_weight_o,
 output wire [(NUM_PE/2)*27-1:0] read_packed_weight_o,
 input wire [CHANNEL_W-1:0] active_channels_i,
 input wire load_begin_i,load_valid_i,output wire load_ready_o,
 input wire load_bank_i,input wire [3:0] load_lane_i,
 input wire [ADDR_W-1:0] load_offset_i,input wire [7:0] load_data_i,
 input wire load_last_i,output reg [1:0] bank_valid_o
);
 localparam integer PAIRS=NUM_PE/2, BANK_BYTES=TILE_BYTES/NUM_PE;
 localparam integer BW=$clog2(BANK_BYTES);
 wire [PAIRS*17-1:0] bank_read_w;
 reg [PAIRS*17-1:0] logical_read_r,coefficient_r;
 reg [3:0] phase_r;
 wire [ADDR_W-1:0] scalar_offset_w=read_offset_i[ADDR_W-1:0];
 reg [2:0] load_pair_bank_r;
 reg load_high_r;
 reg pending_r,pending_last_r;
 reg [2:0] pending_bank_r;
 reg [BW-1:0] pending_offset_r;
 reg signed [7:0] pending_weight_r;
 wire accept_w=load_valid_i&&load_ready_o;
 assign load_ready_o=!compute_active_i&&!pending_r;
 always @*begin
  // Fixed16-lane contract, legal even slices2/4/8 or multiples16.
  load_pair_bank_r=load_lane_i[3:1];load_high_r=load_lane_i[0];
  case(active_channels_i)
   8:begin load_pair_bank_r={load_lane_i[3:2],load_lane_i[0]};load_high_r=load_lane_i[1];end
   4:begin load_pair_bank_r={load_lane_i[3],load_lane_i[1:0]};load_high_r=load_lane_i[2];end
   2:begin load_pair_bank_r=load_lane_i[2:0];load_high_r=load_lane_i[3];end
  endcase
 end

 reg [CHANNEL_W-1:0] read_channels_r;
 always @(posedge clk_i or negedge rst_ni) begin
  if(!rst_ni) read_channels_r<=0;
  else if(!compute_active_i) read_channels_r<=active_channels_i;
 end
 integer pair_i,bank_i;
 // Cout1 stores consecutive scalar terms in the existing paired banks:
 // term[3:1] selects a bank, term>>4 its address, term[0] low/high.
 // Recover the selected signed8 coefficient and normalize the unused Cout1
 // partner to zero. External O,KY,KX,IC bytes and the2-cycle read stay exact.
 function [16:0] scalar_coefficient;
  input [16:0] pair_value;input use_high;
  reg signed [8:0] recovered_high;
  reg [7:0] selected_weight;
  reg signed [8:0] normalized_high;
  begin
   recovered_high=$signed(pair_value[16:8])+$signed({8'd0,pair_value[7]});
   selected_weight=use_high?recovered_high[7:0]:pair_value[7:0];
   normalized_high=selected_weight[7]?-9'sd1:9'sd0;
   scalar_coefficient={normalized_high,selected_weight};
  end
 endfunction
 always @*begin
  logical_read_r=0;
  for(pair_i=0;pair_i<PAIRS;pair_i=pair_i+1)begin
   bank_i=pair_i;
   case(read_channels_r)
    1:bank_i=phase_r[3:1];
    8:bank_i=pair_i*2+phase_r[0];
    4:bank_i=pair_i*4+phase_r[1:0];
    2:bank_i=phase_r[2:0];
   endcase
   if(2*pair_i<read_channels_r&&bank_i<PAIRS)begin
    // Avoid a dynamic bank_i*17 part-select address. Native TD mapped six
    // such crossbar indexes into DSPs. Constant cases are the same exact
    // bank data mux, not a numerical or latency change.
    case(bank_i)
     0:logical_read_r[pair_i*17+:17]=bank_read_w[0+:17];
     1:logical_read_r[pair_i*17+:17]=bank_read_w[17+:17];
     2:logical_read_r[pair_i*17+:17]=bank_read_w[34+:17];
     3:logical_read_r[pair_i*17+:17]=bank_read_w[51+:17];
     4:logical_read_r[pair_i*17+:17]=bank_read_w[68+:17];
     5:logical_read_r[pair_i*17+:17]=bank_read_w[85+:17];
     6:logical_read_r[pair_i*17+:17]=bank_read_w[102+:17];
     7:logical_read_r[pair_i*17+:17]=bank_read_w[119+:17];
     default:logical_read_r[pair_i*17+:17]=0;
    endcase
    if(read_channels_r==1)
      logical_read_r[pair_i*17+:17]=scalar_coefficient(logical_read_r[pair_i*17+:17],phase_r[0]);
   end
  end
 end
 always @(posedge clk_i or negedge rst_ni)begin
  if(!rst_ni)begin
   phase_r<=0;coefficient_r<=0;pending_r<=0;pending_last_r<=0;
   pending_bank_r<=0;pending_offset_r<=0;pending_weight_r<=0;bank_valid_o<=0;
  end else begin
   if(compute_active_i)begin
    coefficient_r<=logical_read_r;
    case(read_channels_r)
     1:phase_r<=scalar_offset_w[3:0];
     8:phase_r<={3'd0,scalar_offset_w[0]};
     4:phase_r<={2'd0,scalar_offset_w[1:0]};
     2:phase_r<={1'd0,scalar_offset_w[2:0]};
     default:phase_r<=0;
    endcase
   end
   if(load_begin_i)bank_valid_o<=0;
   if(pending_r)begin
    pending_r<=0;
    if(pending_last_r)bank_valid_o<=1;
   end
   if(accept_w)begin
    if(load_high_r)begin
     pending_r<=1;pending_bank_r<=load_pair_bank_r;
     pending_offset_r<=load_offset_i[BW-1:0];
     pending_weight_r<=load_data_i;pending_last_r<=load_last_i;
    end else if(load_last_i)bank_valid_o<=1;
   end
  end
 end
 generate
  genvar p;
  for(p=0;p<PAIRS;p=p+1)begin:G_PAIR
   wire [16:0] coeff_w=coefficient_r[p*17+:17];
   wire signed [7:0] w0_w=coeff_w[7:0];
   wire signed [8:0] w1_w=$signed(coeff_w[16:8])+$signed({8'd0,w0_w[7]});
   assign read_weight_o[2*p*8+:8]=w0_w;
   assign read_weight_o[(2*p+1)*8+:8]=w1_w[7:0];
   assign read_packed_weight_o[p*27+:27]={coeff_w[16:8],{10{coeff_w[7]}},coeff_w[7:0]};
   reg [BW-1:0] offset_r;
   always @*begin
    case(read_channels_r)
     1:offset_r=scalar_offset_w>>4;
     8:offset_r=scalar_offset_w>>1;
     4:offset_r=scalar_offset_w>>2;
     2:offset_r=scalar_offset_w>>3;
     default:offset_r=read_offset_i[2*p*ADDR_W+:BW];
    endcase
    if(accept_w&&load_high_r&&load_pair_bank_r==p)
     offset_r=load_offset_i[BW-1:0];
   end
   wire [16:0] old_w=bank_read_w[p*17+:17];
   wire signed [8:0] new_high_w=$signed({pending_weight_r[7],pending_weight_r})-
                                      $signed({8'd0,old_w[7]});
   wire signed [8:0] zero_high_w=load_data_i[7] ? -9'sd1:9'sd0;
   wire [16:0] write_word_w=pending_r ? {new_high_w,old_w[7:0]}:
                                      {zero_high_w,load_data_i};
   wire write_w=(pending_r&&pending_bank_r==p)||
                (accept_w&&!load_high_r&&load_pair_bank_r==p);
   wire [BW-1:0] write_address_w=pending_r?pending_offset_r:load_offset_i[BW-1:0];
   wire [16:0] unused_w;
   PH1P_LOGIC_ERAM #(
    .DATA_WIDTH_A(17),.DATA_WIDTH_B(17),.ADDR_WIDTH_A(BW),.ADDR_WIDTH_B(BW),
    .DATA_DEPTH_A(BANK_BYTES),.DATA_DEPTH_B(BANK_BYTES),.MODE("DP"),
    .REGMODE_A("NOREG"),.REGMODE_B("NOREG"),.WRITEMODE_A("READBEFOREWRITE"),
    .WRITEMODE_B("READBEFOREWRITE"),.CLKMODE("ASYNC"),.SSROVERCE("DISABLE"),
    .OREGSET_A("RESET"),.OREGSET_B("RESET"),.RESETMODE_A("ASYNC"),.RESETMODE_B("ASYNC"),
    .ASYNC_RESET_RELEASE_A("ASYNC"),.ASYNC_RESET_RELEASE_B("ASYNC"),
    .ECC_ENCODE("DISABLE"),.ECC_DECODE("DISABLE"),.IMPLEMENT("20K(FAST)"),
    .INIT_FILE("NONE"),.FILL_ALL("NONE")
   ) memory(
    .dia(write_word_w),.addra(write_address_w),.cea(1'b1),.ocea(1'b0),.clka(clk_i),.wea(write_w),.rsta(1'b0),.bea(1'b0),
    .dib(17'd0),.addrb(offset_r),.ceb(1'b1),.oceb(1'b0),.clkb(clk_i),.web(1'b0),.rstb(1'b0),.beb(1'b0),
    .ecc_sbiterrinj(1'b0),.ecc_dbiterrinj(1'b0),.doa(unused_w),.dob(bank_read_w[p*17+:17]),.ecc_sbiterr(),.ecc_dbiterr());
  end
 endgenerate
`ifndef SYNTHESIS
 initial if(NUM_PE!=16||(TILE_BYTES!=16384&&TILE_BYTES!=65536))$fatal(1,"Paired cache prototype fixed16/16-or64KiB contract");
`endif
endmodule
