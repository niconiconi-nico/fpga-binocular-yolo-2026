// Native PH1P35 DSP postadder/PREG, original moduloWIDTH result.
// Upper carry never feeds lower bits. Load has priority over step, CE holds.
// Actual callers WIDTH16/32/44 retain every original bit; no reduced precision.
module r10_parser_dsp_state #(parameter integer WIDTH=32)(
 input wire clk,input wire rst_n,input wire load_i,input wire[WIDTH-1:0]load_value_i,
 input wire step_i,input wire[WIDTH-1:0]increment_i,output wire[WIDTH-1:0]value_o);
 wire[53:0]p,ta,tb,tc,ts;wire ci,co,ov,un;wire[6:0]op;wire[5:0]os;
 PH1P_PHY_DSPSIOU_V2 #(
  .XAREG("0"),.XBREG("0"),.YREG("0"),.ZREG("0"),.XABREG("0"),.MREG("0"),
  .CXAREG("0"),.CXBREG("0"),.CYREG("0"),.POUWREG("1"),.CCOREG("0"),
  .INCTRLREG("0"),.MUXCTRLREG("0"),.OPCTRLREG("0"),.CINCTRLREG("0"),
  .CLKMUX("SIG"),.CE0("SIG"),.CE1("1"),.CE2("1"),.CE3("1"),.CEPOU("CE0"),
  .RST0("INV"),.RST1("INV"),.RST2("INV"),.RST3("INV"),.RSTPOU("RST0"),
  .SR0MODE("ASYNC"),.SR1MODE("ASYNC"),.SR2MODE("ASYNC"),.SR3MODE("ASYNC"),
  .USER_GSRN("DISABLE"),.USE_OVERFLOW("P53")) siou(
  .clk(clk),.ce({3'b111,(load_i|step_i)}),.rst({3'b111,rst_n}),
  .xa(27'd0),.xb(27'd0),.y(18'd0),.z({{(54-WIDTH){1'b0}},(load_i?load_value_i:increment_i)}),
  .cpi(54'd0),.cci(1'b0),.cxai(27'd0),.cxbi(27'd0),.cxabi(27'd0),.cyi(18'd0),
  .inctrl(7'b1011111),.cinctrl(3'd0),.opctrl(11'd1034),
  .muxctrl(load_i?7'd16:7'd44),.p(p),.mult_p(),.add_sum(),
  .logic_p(),.logic_wxor(),.tadd_a(ta),.tadd_b(tb),.tadd_c(tc),
  .tadd_ci(ci),.tadd_opctrl(op),.tadd_oversel(os),.tadd_sum(ts),
  .tadd_co(co),.tadd_overflow(ov),.tadd_underflow(un));
 PH1P_PHY_DSPTADD postadder(.a(ta),.b(tb),.c(tc),.ci(ci),.opctrl(op),.oversel(os),
  .sum(ts),.co(co),.overflow(ov),.underflow(un));
 assign value_o=p[WIDTH-1:0];
endmodule
