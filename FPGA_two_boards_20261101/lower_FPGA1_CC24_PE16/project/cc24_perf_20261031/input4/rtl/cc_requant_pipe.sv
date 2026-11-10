// cc_requant_pipe (v2, area-reduced) — Claude Code candidate CC1, 2026-10-20
// Dedicated Conv/Add/Concat requant engine; drop-in for the req/rsp side of
// tf_yolo_requant_context. Bit-exact to numeric_context1.hex (SHA 6b5eccde…)
// PC_CONV/PC_ADD/PC_CONCAT as executed by r10_numeric_context_vm:
//   CONV  : clamp( rs(s0*m0 + bias, sh0) + zero , qmin, qmax )
//   ADD   : clamp( rs(s0*m0, sh0) + rs(s1*m1, sh1), -128, 127 )
//   CONCAT: clamp( rs(s0*m0, sh0), -128, 127 )
//   rs(v,0)=v ; rs(v,s)= v<0 ? -ASR(-v + 2^(s-1), s) : ASR(v + 2^(s-1), s)   (all mod 2^64)
//   code = low 8 bits of the selected 64-bit value; mode 3 -> error response.
// Exactness argument (inputs are int32): |s*m + bias| <= 2^62 + 2^31 < 2^63, so the
// product/bias stage never wraps. For 1<=s<=62 |v|+2^(s-1) < 2^63, hence
//   ASR(|v| + 2^(s-1), s) == ((|v| >> (s-1)) + 1) >> 1           (no wrap, floor identity)
// For s==63 the VM sum |v|+2^62 wraps to bit63 exactly when |v|>=2^62, giving ASR=-1
// where the floor identity gives +1 (and 0 vs 0 otherwise) => result is negated.
// Clamp: q are sign-extended int32, so a 64-bit compare reduces to a fits-in-int32
// test plus a 32-bit signed compare.
// One signed 17x17 DSP product, 4 partials per source; one shared 64-bit adder.
// CC16 (speed, same arithmetic): skip states that are no-ops for the operands at hand:
//  - v>=0 in RNEG: no negation, so the shift is done in RNEG itself (RSHF skipped);
//  - RRES only when the result must be negated ((sh==63)^rneg);
//  - POST only for ADD (both passes) or CONV with a non-zero zero-point (CONV zero is 0 in this design).
module cc_requant_pipe(
 input wire clk_i,rst_ni,
 input wire req_valid,output wire req_ready,
 input wire[1:0]req_mode,
 input wire signed[31:0]req_source0,req_source1,req_mult0,req_mult1,
 input wire signed[31:0]req_bias,req_zero,req_qmin,req_qmax,
 input wire[5:0]req_shift0,req_shift1,
 output wire rsp_valid,input wire rsp_ready,
 output reg signed[7:0]rsp_code,output reg rsp_error
);
 localparam[3:0] IDLE=0,MUL=1,RNEG=2,RSHF=3,RINC=4,RRES=5,POST=6,CLAMP=7,RESP=8;
 reg[3:0]state_r;reg[1:0]mode_r;reg second_r;
 reg[31:0]ra_r,rb_r,rc_r,rd_r,re_r,rf_r; // s0,m0, (s1|bias),(m1|zero), qmin,qmax
 reg[5:0]sh0_r,sh1_r;
 reg[2:0]part_r;reg pvalid_r;reg[1:0]pidx_r;
 reg signed[33:0]product_r;
 reg[63:0]v_r,first_r;reg rneg_r;
 wire[31:0]src_w=second_r?rc_r:ra_r;
 wire[31:0]mul_w=second_r?rd_r:rb_r;
 wire[5:0]sh_w=second_r?sh1_r:sh0_r;
 // Exact signed17 x signed32 decomposition: two partials instead of four.
 // Includes -65536..65535, notably all signed8 Add/Concat samples.
 // Wide sources retain the original four-part signed32 multiplication.
 wire narrow_w=(src_w[31:16]=={16{src_w[16]}});
 wire issue_w=state_r==MUL && (narrow_w ? part_r<3'd2 : part_r<3'd4);
 wire last_w=narrow_w ? part_r==3'd2 : part_r==3'd4;
 // signed split: x = xh*2^16 + xl, xh signed 16b, xl unsigned 16b (as 17b signed)
 reg signed[16:0]x_w,y_w;
 always @*begin
  if(narrow_w)begin
   x_w=$signed(src_w[16:0]);
   y_w=part_r[0] ? $signed({mul_w[31],mul_w[31:16]}) : $signed({1'b0,mul_w[15:0]});
  end else case(part_r[1:0])
   2'd0:begin x_w={1'b0,src_w[15:0]};    y_w={1'b0,mul_w[15:0]};    end
   2'd1:begin x_w={1'b0,src_w[15:0]};    y_w={mul_w[31],mul_w[31:16]};end
   2'd2:begin x_w={src_w[31],src_w[31:16]};y_w={1'b0,mul_w[15:0]};    end
   default:begin x_w={src_w[31],src_w[31:16]};y_w={mul_w[31],mul_w[31:16]};end
  endcase
 end
 (* multstyle="dsp" *) wire signed[33:0]product_w=x_w*y_w;
 reg[63:0]pshift_w;
 always @*begin
  case(pidx_r)
   2'd0:pshift_w={{30{product_r[33]}},product_r};
   2'd1,2'd2:pshift_w={{14{product_r[33]}},product_r,16'd0};
   default:pshift_w={product_r[31:0],32'd0};
  endcase
 end
 // ---- one shared 64-bit adder ----
 reg[63:0]add_a_w,add_b_w;reg add_c_w;
 always @*begin
  add_a_w=v_r;add_b_w=64'd0;add_c_w=1'b0;
  case(state_r)
   MUL:add_b_w=pshift_w;
   RNEG,RRES:begin add_a_w=64'd0;add_b_w=~v_r;add_c_w=1'b1;end
   RINC:add_c_w=1'b1;
   POST:add_b_w=(mode_r==2'd0)?{{32{rd_r[31]}},rd_r}:first_r;
   default:begin end
  endcase
 end
 wire[64:0]sum_w={1'b0,add_a_w}+{1'b0,add_b_w}+{64'd0,add_c_w};
 wire[5:0]shm1_w=sh_w-1'b1;
 wire[63:0]lsr_w=v_r>>shm1_w;
 // clamp compare: v vs sign-extended int32 q
 wire fits_w=(&v_r[63:31])|~(|v_r[63:31]);
 wire gt_qmax_w=fits_w?($signed(v_r[31:0])>$signed(rf_r)):~v_r[63];
 wire lt_qmin_w=fits_w?($signed(v_r[31:0])<$signed(re_r)):v_r[63];
 // POST is required for ADD (store first pass / add first pass) and for CONV with a non-zero zero-point.
 wire need_post_w=(mode_r==2'd1)||(mode_r==2'd0&&rd_r!=32'd0);
 assign req_ready=state_r==IDLE;
 assign rsp_valid=state_r==RESP;
 always @(posedge clk_i or negedge rst_ni)begin
  if(!rst_ni)begin
   state_r<=IDLE;mode_r<=0;second_r<=0;
   ra_r<=0;rb_r<=0;rc_r<=0;rd_r<=0;re_r<=0;rf_r<=0;sh0_r<=0;sh1_r<=0;
   part_r<=0;pvalid_r<=0;pidx_r<=0;product_r<=0;v_r<=0;first_r<=0;rneg_r<=0;
   rsp_code<=0;rsp_error<=0;
  end else begin
   pvalid_r<=issue_w;
   pidx_r<=part_r[1:0];
   if(issue_w)product_r<=product_w;
   case(state_r)
    IDLE:if(req_valid)begin
     mode_r<=req_mode;second_r<=0;rsp_error<=0;part_r<=0;
     ra_r<=req_source0;rb_r<=req_mult0;
     rc_r<=(req_mode==2'd0)?req_bias:req_source1;
     rd_r<=(req_mode==2'd0)?req_zero:req_mult1;
     re_r<=(req_mode==2'd0)?req_qmin:-32'sd128;
     rf_r<=(req_mode==2'd0)?req_qmax:32'sd127;
     sh0_r<=req_shift0;sh1_r<=req_shift1;
     // CONV: accumulator starts at sign-extended bias (v = s0*m0 + bias)
     v_r<=(req_mode==2'd0)?{{32{req_bias[31]}},req_bias}:64'd0;
     if(req_mode==2'd3)begin rsp_error<=1;rsp_code<=0;state_r<=RESP;end
     else state_r<=MUL;
    end
    MUL:begin
     if(pvalid_r)v_r<=sum_w[63:0];
     part_r<=part_r+1'b1;
     if(last_w)begin
      // last partial is being accumulated this cycle
      state_r<=(sh_w==6'd0)?(need_post_w?POST:CLAMP):RNEG;
     end
    end
    RNEG:begin rneg_r<=v_r[63];
     if(v_r[63])begin v_r<=sum_w[63:0];state_r<=RSHF;end   // negate first, shift next cycle
     else begin v_r<=lsr_w;state_r<=RINC;end                // v>=0: shift now
    end
    RSHF:begin v_r<=lsr_w;state_r<=RINC;end
    RINC:begin v_r<=sum_w[64:1];state_r<=((sh_w==6'd63)^rneg_r)?RRES:(need_post_w?POST:CLAMP);end
    RRES:begin v_r<=sum_w[63:0];state_r<=need_post_w?POST:CLAMP;end
    POST:begin
     if(mode_r==2'd1&&!second_r)begin
      first_r<=v_r;second_r<=1;v_r<=0;part_r<=0;state_r<=MUL;
     end else begin
      if(mode_r!=2'd2)v_r<=sum_w[63:0];
      state_r<=CLAMP;
     end
    end
    CLAMP:begin
     if(gt_qmax_w)rsp_code<=rf_r[7:0];
     else if(lt_qmin_w)rsp_code<=re_r[7:0];
     else rsp_code<=v_r[7:0];
     state_r<=RESP;
    end
    RESP:if(rsp_ready)state_r<=IDLE;
    default:begin rsp_error<=1;state_r<=RESP;end
   endcase
  end
 end
endmodule
