// Actual high-level affine/Decode/NMS context, NOT a programmable model engine.
// Fixed audited microprogram;147 graph, weights and integer contracts unchanged.
// One synchronous64x32 context RAM replaces per-customer full64 scratch banks.
// Input must remain VALID/stable until READY; READY is the LAST serial load.
module r10_numeric_context_vm #(
 parameter PROGRAM_FILE="numeric_context1.hex"
)(
 input wire clk,rst_n,input wire req_valid,output wire req_ready,
 input wire[2:0]req_mode,input wire[511:0]req_words,
 output wire rsp_valid,input wire rsp_ready,output wire[31:0]rsp_data,
 output wire[2:0]rsp_index,output wire rsp_last,rsp_error
);
 `include "numeric_context1.vh"
 localparam[4:0] CLEAR=0,IDLE=1,LOADLO=2,LOADHI=3,FETCH=4,DECODE=5,
  AREAD0=6,AREAD1=7,BREAD0=8,ISSUE=9,WAIT=10,WRITEHI=11,
  CREAD0=12,CREAD1=13,CWRITEHI=14,IMMFETCH=15,IMMLO=16,IMMHI=17,
  OREAD0=18,OREAD1=19,OUT=20,ERR=21;
 reg[4:0]state_r;reg[5:0]clear_r;reg[3:0]load_r;reg[2:0]mode_r;
 reg[8:0]pc_r;reg[4:0]imm_dest_r;reg[2:0]out_index_r;reg[3:0]out_count_r;
 reg[5:0]shift0_r,shift1_r;reg[31:0]out_data_r;
 reg[63:0]operand_a_r;reg last_negative_r,last_zero_r,last_lt_r,error_r;
 (* ram_style="bram" *)reg[31:0]context_ram[0:63];
 (* ram_style="bram" *)reg[31:0]program_rom[0:511];
 reg[31:0]qa_r,qb_r,instruction_r;
 initial $readmemh(PROGRAM_FILE,program_rom);
 wire[3:0]op_w=instruction_r[31:28];
 wire[4:0]dest_w=instruction_r[27:23],srca_w=instruction_r[22:18],srcb_w=instruction_r[17:13];
 wire[8:0]target_w=instruction_r[8:0];
 wire[2:0]shift_mode_w=instruction_r[6:4];
 wire[5:0]shift_w=shift_mode_w==1?shift0_r:shift_mode_w==2?shift1_r:
  shift_mode_w==3?shift0_r-1'b1:shift_mode_w==4?shift1_r-1'b1:instruction_r[12:7];
 reg[5:0]address_a_w,address_b_w;reg write_w;reg[31:0]write_data_w;
 wire[63:0]alu_value;wire alu_valid,alu_ready,alu_error,alu_lt;
 wire[31:0]load_word_w=req_words[load_r*32+:32];
 always @*begin
  address_a_w=0;address_b_w=0;write_w=0;write_data_w=0;
  case(state_r)
   CLEAR:begin address_a_w=clear_r;write_w=1;end
   LOADLO:begin address_a_w={load_r,1'b0};write_w=req_valid;write_data_w=load_word_w;end
   LOADHI:begin address_a_w={load_r,1'b1};write_w=req_valid;
    write_data_w=mode_r==3?32'd0:{32{load_word_w[31]}};end
   AREAD0,AREAD1,CREAD0:begin address_a_w={srca_w,1'b0};address_b_w={srca_w,1'b1};end
   BREAD0,ISSUE:begin address_a_w={srcb_w,1'b0};address_b_w={srcb_w,1'b1};end
   WAIT:begin address_a_w={dest_w,1'b0};write_w=alu_valid&&!alu_error;write_data_w=alu_value[31:0];end
   WRITEHI:begin address_a_w={dest_w,1'b1};write_w=1;write_data_w=alu_value[63:32];end
   CREAD1:begin address_a_w={dest_w,1'b0};write_w=1;write_data_w=qa_r;end
   CWRITEHI:begin address_a_w={dest_w,1'b1};write_w=1;end
   IMMLO:begin address_a_w={imm_dest_r,1'b0};write_w=1;write_data_w=instruction_r;end
   IMMHI:begin address_a_w={imm_dest_r,1'b1};write_w=1;write_data_w={32{instruction_r[31]}};end
   OREAD0:begin address_a_w={2'b11,out_index_r,1'b0};address_b_w={2'b11,out_index_r,1'b1};end
   default:begin end
  endcase
 end
 always @(posedge clk)begin
  if(write_w)context_ram[address_a_w]<=write_data_w;
  qa_r<=context_ram[address_a_w];qb_r<=context_ram[address_b_w];
  instruction_r<=program_rom[pc_r];
 end
 tf_yolo_numeric_alu64 arithmetic(.clk(clk),.rst_n(rst_n),
  .req_valid(state_r==ISSUE),.req_ready(alu_ready),.req_op(op_w),
  .req_a(operand_a_r),.req_b({qb_r,qa_r}),.req_shift(shift_w),.req_tag(4'd0),
  .rsp_valid(alu_valid),.rsp_ready(state_r==WRITEHI),.rsp_value(alu_value),
  .rsp_carry(),.rsp_unsigned_lt(),.rsp_signed_lt(alu_lt),.rsp_error(alu_error),.rsp_tag());
 assign req_ready=state_r==LOADHI&&load_r==15;
 assign rsp_valid=state_r==OUT||state_r==ERR;assign rsp_data=out_data_r;
 assign rsp_index=out_index_r;assign rsp_last=state_r==ERR||{1'b0,out_index_r}+1>=out_count_r;
 assign rsp_error=error_r;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   state_r<=CLEAR;clear_r<=0;load_r<=0;mode_r<=0;pc_r<=0;imm_dest_r<=0;
   out_index_r<=0;out_count_r<=0;out_data_r<=0;operand_a_r<=0;
   shift0_r<=0;shift1_r<=0;last_negative_r<=0;last_zero_r<=0;last_lt_r<=0;error_r<=0;
  end else case(state_r)
   CLEAR:if(clear_r==63)state_r<=IDLE;else clear_r<=clear_r+1'b1;
   IDLE:if(req_valid)begin mode_r<=req_mode;load_r<=0;error_r<=0;state_r<=LOADLO;end
   LOADLO:if(req_valid)begin
    if(load_r==8)shift0_r<=load_word_w[5:0];if(load_r==9)shift1_r<=load_word_w[5:0];state_r<=LOADHI;
   end
   LOADHI:if(req_valid)begin if(load_r==15)begin
    case(mode_r)0:pc_r<=PC_CONV;1:pc_r<=PC_ADD;2:pc_r<=PC_CONCAT;3:pc_r<=PC_DECODE;4:pc_r<=PC_NMS;default:pc_r<=PC_INVALID;endcase
    state_r<=FETCH;
   end else begin load_r<=load_r+1'b1;state_r<=LOADLO;end end
   FETCH:state_r<=DECODE;
   DECODE:case(op_w)
    0,1,2,3,4,5,6:state_r<=AREAD0;
    7:begin imm_dest_r<=dest_w;pc_r<=pc_r+1'b1;state_r<=IMMFETCH;end
    8:state_r<=CREAD0;
    9:begin pc_r<=target_w;state_r<=FETCH;end
    10:begin pc_r<=last_negative_r?target_w:pc_r+1'b1;state_r<=FETCH;end
    11:begin pc_r<=last_zero_r?target_w:pc_r+1'b1;state_r<=FETCH;end
    12:begin pc_r<=last_lt_r?target_w:pc_r+1'b1;state_r<=FETCH;end
    13:begin pc_r<=((srca_w==0?shift0_r:shift1_r)==0)?target_w:pc_r+1'b1;state_r<=FETCH;end
    14:begin out_index_r<=0;out_count_r<=instruction_r[3:0];state_r<=OREAD0;end
    default:begin error_r<=1;out_index_r<=0;out_data_r<=0;state_r<=ERR;end
   endcase
   AREAD0:state_r<=AREAD1;
   AREAD1:begin operand_a_r<={qb_r,qa_r};state_r<=BREAD0;end
   BREAD0:state_r<=ISSUE;
   ISSUE:if(alu_ready)state_r<=WAIT;
   WAIT:if(alu_valid)begin
    if(alu_error)begin error_r<=1;out_index_r<=0;out_data_r<=0;state_r<=ERR;end
    else begin last_negative_r<=alu_value[63];last_zero_r<=alu_value==0;last_lt_r<=alu_lt;state_r<=WRITEHI;end
   end
   WRITEHI,CWRITEHI:begin pc_r<=pc_r+1'b1;state_r<=FETCH;end
   CREAD0:state_r<=CREAD1;
   CREAD1:state_r<=CWRITEHI;
   IMMFETCH:state_r<=IMMLO;
   IMMLO:state_r<=IMMHI;
   IMMHI:begin pc_r<=pc_r+1'b1;state_r<=FETCH;end
   OREAD0:state_r<=OREAD1;
   OREAD1:begin out_data_r<=qa_r;state_r<=OUT;end
   OUT:if(rsp_ready)begin
    if(rsp_last)state_r<=IDLE;else begin out_index_r<=out_index_r+1'b1;state_r<=OREAD0;end
   end
   ERR:if(rsp_ready)state_r<=IDLE;
   default:begin error_r<=1;state_r<=ERR;end
  endcase
 end
endmodule
