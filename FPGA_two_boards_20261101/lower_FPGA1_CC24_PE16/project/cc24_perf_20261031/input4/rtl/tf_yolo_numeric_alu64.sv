// Local operator arithmetic only: never TF/FAT/DDR address arbitration.
// Exact modulo64 products use ONE reused unsigned16x16 DSP product.
// Comba columns0..3 retain every low64 bit, including signed MIN64 wrap.
// ONE32bit carry adder serves add/sub/compare AND product accumulation.
module tf_yolo_numeric_alu64 #(parameter integer TAG_W=4)(
 input wire clk,rst_n,input wire req_valid,output wire req_ready,
 input wire[3:0]req_op,input wire[63:0]req_a,req_b,
 input wire[5:0]req_shift,input wire[TAG_W-1:0]req_tag,
 output wire rsp_valid,input wire rsp_ready,output wire[63:0]rsp_value,
 output wire rsp_carry,rsp_unsigned_lt,rsp_signed_lt,rsp_error,
 output wire[TAG_W-1:0]rsp_tag
);
 localparam[3:0] ADD=0,SUB=1,LSL=2,LSR=3,ASR=4,CMP=5,MUL=6;
 localparam[2:0] IDLE=0,EXEC=1,LOW=2,HIGH=3,SHIFT=4,MCAP=5,MACC=6,RESP=7;
 reg[2:0]state_r;reg[3:0]op_r;
 reg[63:0]a_r,b_r,value_r;reg[5:0]shift_r;reg[TAG_W-1:0]tag_r;
 reg lowcarry_r,carry_r,ult_r,slt_r,error_r;
 reg[1:0]column_r,term_r;reg[33:0]acc_r;reg[31:0]product_r;
 reg[15:0]aword_w,bword_w;
 wire[1:0]bindex_w=column_r-term_r;
 always @*begin
  case(term_r)
   0:aword_w=a_r[15:0];1:aword_w=a_r[31:16];
   2:aword_w=a_r[47:32];default:aword_w=a_r[63:48];
  endcase
  case(bindex_w)
   0:bword_w=b_r[15:0];1:bword_w=b_r[31:16];
   2:bword_w=b_r[47:32];default:bword_w=b_r[63:48];
  endcase
 end
 (* multstyle="dsp" *) wire[31:0]product_w=aword_w*bword_w;
 wire subtract_w=op_r==SUB||op_r==CMP;
 wire[31:0]add_a_w=state_r==MACC?acc_r[31:0]:state_r==HIGH?a_r[63:32]:a_r[31:0];
 wire[31:0]word_b_w=state_r==HIGH?b_r[63:32]:b_r[31:0];
 wire[31:0]add_b_w=state_r==MACC?product_r:(word_b_w^{32{subtract_w}});
 wire cin_w=state_r==MACC?1'b0:state_r==HIGH?lowcarry_r:subtract_w;
 wire[32:0]sum_w={1'b0,add_a_w}+{1'b0,add_b_w}+cin_w;
 wire[1:0]acc_high_w=acc_r[33:32]+{1'b0,sum_w[32]};
 wire[33:0]acc_sum_w={acc_high_w,sum_w[31:0]};
 assign req_ready=state_r==IDLE;assign rsp_valid=state_r==RESP;
 assign rsp_value=value_r;assign rsp_tag=tag_r;assign rsp_carry=carry_r;
 assign rsp_unsigned_lt=ult_r;assign rsp_signed_lt=slt_r;assign rsp_error=error_r;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   state_r<=IDLE;op_r<=0;a_r<=0;b_r<=0;value_r<=0;shift_r<=0;tag_r<=0;
   lowcarry_r<=0;carry_r<=0;ult_r<=0;slt_r<=0;error_r<=0;
   column_r<=0;term_r<=0;acc_r<=0;product_r<=0;
  end else case(state_r)
   IDLE:if(req_valid)begin
    op_r<=req_op;a_r<=req_a;b_r<=req_b;shift_r<=req_shift;tag_r<=req_tag;
    carry_r<=0;ult_r<=0;slt_r<=0;error_r<=0;state_r<=EXEC;
   end
   EXEC:case(op_r)
    ADD,SUB,CMP:state_r<=LOW;
    MUL:begin value_r<=0;column_r<=0;term_r<=0;acc_r<=0;state_r<=MCAP;end
    LSL,LSR,ASR:begin value_r<=a_r;state_r<=shift_r==0?RESP:SHIFT;end
    default:begin value_r<=0;error_r<=1;state_r<=RESP;end
   endcase
   LOW:begin value_r[31:0]<=sum_w[31:0];lowcarry_r<=sum_w[32];state_r<=HIGH;end
   HIGH:begin
    value_r[63:32]<=sum_w[31:0];carry_r<=sum_w[32];
    if(subtract_w)begin ult_r<=!sum_w[32];slt_r<=a_r[63]!=b_r[63]?a_r[63]:sum_w[31];end
    state_r<=RESP;
   end
   SHIFT:begin
    case(op_r)
     LSL:value_r<={value_r[62:0],1'b0};LSR:value_r<={1'b0,value_r[63:1]};
     ASR:value_r<={value_r[63],value_r[63:1]};default:value_r<=0;
    endcase
    shift_r<=shift_r-1'b1;if(shift_r==1)state_r<=RESP;
   end
   MCAP:begin product_r<=product_w;state_r<=MACC;end
   MACC:begin
    if(term_r==column_r)begin
     case(column_r)
      0:value_r[15:0]<=acc_sum_w[15:0];1:value_r[31:16]<=acc_sum_w[15:0];
      2:value_r[47:32]<=acc_sum_w[15:0];3:value_r[63:48]<=acc_sum_w[15:0];
     endcase
     acc_r<={16'd0,acc_sum_w[33:16]};term_r<=0;
     if(column_r==3)state_r<=RESP;else begin column_r<=column_r+1'b1;state_r<=MCAP;end
    end else begin acc_r<=acc_sum_w;term_r<=term_r+1'b1;state_r<=MCAP;end
   end
   RESP:if(rsp_ready)state_r<=IDLE;
   default:begin state_r<=IDLE;error_r<=1;end
  endcase
 end
endmodule
