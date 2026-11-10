// Independent ISP-only experiment. Identical full20 gain, floor and saturation.
// Preserve the original 256 BLANK cycles and SOF atomic-commit protocol.
// No model, YOLO arithmetic, frame buffer, AE, AWB statistics or clock changes.
module camera_awb_gain_lut(
 input wire clk,rst_n,sof_i,valid_i,input wire[95:0] rgb_i,
 input wire prepare_valid_i,output wire prepare_ready_o,
 input wire[19:0] gain_r_i,gain_b_i,
 output reg prepared_o,output reg applied_o,
 output reg valid_o,output wire[95:0] rgb_o
);
 reg building; reg[7:0] index;
 reg[19:0] pending_r,pending_b,active_r,active_b;
 wire commit=sof_i && prepared_o;
 wire[19:0] use_r=commit ? pending_r : active_r;
 wire[19:0] use_b=commit ? pending_b : active_b;
 assign prepare_ready_o=!building && !prepared_o && !sof_i;
 always @(posedge clk or negedge rst_n)begin
   if(!rst_n)begin
     building<=0;index<=0;pending_r<=20'h10000;pending_b<=20'h10000;
     active_r<=20'h10000;active_b<=20'h10000;prepared_o<=0;applied_o<=0;valid_o<=0;
   end else begin
     valid_o<=valid_i;applied_o<=0;
     if(commit)begin active_r<=pending_r;active_b<=pending_b;prepared_o<=0;applied_o<=1;end
     if(prepare_valid_i && prepare_ready_o)begin
       pending_r<=gain_r_i;pending_b<=gain_b_i;index<=0;building<=1;
     end else if(building && !valid_i)begin
       if(index==255)begin building<=0;prepared_o<=1;end
       else index<=index+1'b1;
     end
   end
 end
 genvar lane;
 generate for(lane=0;lane<4;lane=lane+1)begin:G_LANE
   wire[27:0] red,blue;
   reg[7:0] green;
   always @(posedge clk or negedge rst_n)begin
     if(!rst_n)green<=0;else if(valid_i)green<=rgb_i[lane*24+8+:8];
   end
   camera_awb_native_y0 red_mul(clk,rst_n,valid_i,use_r,rgb_i[lane*24+16+:8],red);
   camera_awb_native_y0 blue_mul(clk,rst_n,valid_i,use_b,rgb_i[lane*24+:8],blue);
   assign rgb_o[lane*24+:24]=!valid_o ? 24'd0 :
     {((|red[27:24]) ? 8'hff : red[23:16]),green,((|blue[27:24]) ? 8'hff : blue[23:16])};
 end endgenerate
endmodule

module camera_awb_native_y0(input wire clk,rst_n,valid,input wire[19:0]gain,input wire[7:0]pixel,output reg[27:0]p);
wire[53:0]product;wire[44:0]mp;wire[26:0]mx;wire[17:0]my;wire mode,sgn,op;
// All DSP state blocks are disabled. Vendor CLKMUX="0" is documented;
// the real external pixel/product FFs below retain their original clock/reset.

PH1P_PHY_DSPSIOU_V2 #(.CCOREG("0"),.CE0("SIG"),.CE1("1"),.CE2("1"),.CE3("1"),.CECINCTRL("CE0"),.CECOUT("CE0"),.CEINCTRL("CE0"),.CEM("CE0"),.CEMUXCTRL("CE0"),.CEOPCTRL("CE0"),.CEPOU("CE0"),.CEW("CE0"),.CEXA1("CE0"),.CEXA2("CE0"),.CEXAB("CE0"),.CEXB1("CE0"),.CEXB2("CE0"),.CEY1("CE1"),.CEY2("CE1"),.CEZ("CE0"),.CINCTRLREG("0"),.CLKMUX("0"),.CXAREG("0"),.CXBREG("0"),.CYREG("0"),.INCTRLREG("0"),.MREG("0"),.MULT_MODE("NORMAL"),.MUXCTRLREG("0"),.OPCTRLREG("0"),.POUWREG("0"),.RST0("INV"),.RST1("INV"),.RST2("INV"),.RST3("INV"),.RSTCINCTRL("RST0"),.RSTCOUT("RST0"),.RSTINCTRL("RST0"),.RSTM("RST0"),.RSTMUXCTRL("RST0"),.RSTOPCTRL("RST0"),.RSTPOU("RST0"),.RSTW("RST0"),.RSTXA1("RST0"),.RSTXA2("RST0"),.RSTXAB("RST0"),.RSTXB1("RST0"),.RSTXB2("RST0"),.RSTY1("RST0"),.RSTY2("RST0"),.RSTZ("RST0"),.SR0MODE("ASYNC"),.SR1MODE("ASYNC"),.SR2MODE("ASYNC"),.SR3MODE("ASYNC"),.USER_GSRN("DISABLE"),.USE_OVERFLOW("P47"),.XABREG("0"),.XAREG("0"),.XA_INPUT("XA"),.XBREG("0"),.XB_INPUT("XB"),.YREG("0"),.Y_INPUT("Y"),.ZREG("0")) siou (.ce({1'b1,1'b1,1'b1,valid}),.clk(1'b0),.inctrl({1'b1,1'b0,5'b11111}),.mult_p(mp),.muxctrl({1'b0,1'b0,1'b0,1'b0,1'b0,2'b10}),.opctrl({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,3'b010,1'b0}),.rst({1'b1,1'b1,1'b1,rst_n}),.xa({7'b0000000,gain}),.y({10'b0000000000,pixel}),.mul9_mode(mode),.mul9_signed(sgn),.mult_opctrl(op),.mult_x(mx),.mult_y(my),.p(product),.xb(27'b0));
PH1P_PHY_DSPMULT_V2 mult (.mul9_mode(mode),.mul9_signed(sgn),.opctrl(op),.x(mx),.y(my),.p(mp));
always @(posedge clk or negedge rst_n) begin if(!rst_n)p<=0;else if(valid)p<=product[27:0];end
endmodule
