// Independent merge-stream candidate: real read16 operands, unchanged exact
// merge pipeline, retained real write16 payload/ACK (default0 scalar reference).
// Qualified PFv2/flat source remains untouched. No behavioral PASS claim yet.
module v5n_add_read16_runtime #(
 parameter integer ADDR_W=32,parameter integer SHAPE_W=10,
 parameter integer WRITE_LINE_ENABLE=0
)(
 input wire clk_i,rst_ni,start_i,descriptor_valid_i,input wire[3:0]opcode_i,
 input wire[ADDR_W-1:0]source0_base_i,source1_base_i,destination_base_i,
 input wire[SHAPE_W-1:0]tensor_h_i,tensor_w_i,tensor_c_i,
 input wire signed[31:0]source0_multiplier_i,source1_multiplier_i,input wire[5:0]source0_shift_i,source1_shift_i,
 output wire busy_o,output reg done_o,error_o,output wire[3:0]state_o,output wire[31:0]cycle_count_o,
 output wire memory_valid_o,input wire memory_ready_i,output wire memory_write_o,memory_use_hwc_o,
 output wire[ADDR_W-1:0]memory_raw_byte_address_o,memory_tensor_base_o,
 output wire[SHAPE_W-1:0]memory_tensor_h_o,memory_tensor_w_o,memory_tensor_c_o,memory_y_o,memory_x_o,memory_channel_o,
 output wire signed[7:0]memory_write_data_o,
 output wire memory_write_line_o,output wire[127:0]memory_write_line_data_o,
 input wire memory_response_valid_i,output wire memory_response_ready_o,
 input wire memory_response_error_i,memory_response_is_write_i,input wire signed[7:0]memory_read_data_i,
 input wire memory_read_line_valid_i,input wire[ADDR_W-1:0]memory_read_line_address_i,input wire[127:0]memory_read_line_data_i,
output wire rq_req_valid,
input wire rq_req_ready,
output wire signed[31:0] rq_source0,
output wire signed[31:0] rq_source1,
output wire signed[31:0] rq_mult0,
output wire signed[31:0] rq_mult1,
output wire signed[31:0] rq_bias,
output wire[5:0] rq_shift0,
output wire[5:0] rq_shift1,
input wire rq_rsp_valid,
input wire signed[7:0] rq_rsp_code,
input wire rq_rsp_error
);
 localparam[3:0]IDLE=0,READ0_REQ=1,READ0_WAIT=2,READ1_REQ=3,READ1_WAIT=4,
                    APPLY=5,WRITE_REQ=7,WRITE_WAIT=8,DONE=9,FAIL=10;
 reg[3:0]state_r,read_index_r,write_index_r;
 reg[SHAPE_W-1:0]y_r,x_r,c_r;reg[31:0]cycles_r;
 reg[127:0]source0_codes_r,source1_codes_r,output_codes_r;
 reg[4:0]issue_r,collect_r;
 wire[3:0]issue_index_w=issue_r<16?issue_r[3:0]:4'd0;
 wire merge_valid_w;wire signed[7:0]merge_code_w;
 assign rq_req_valid=state_r==APPLY&&issue_r<16;
 assign rq_source0={{24{source0_codes_r[7]}},source0_codes_r[7:0]};
 assign rq_source1={{24{source1_codes_r[7]}},source1_codes_r[7:0]};
 assign rq_mult0=source0_multiplier_i;
 assign rq_mult1=source1_multiplier_i;
 assign rq_bias=32'sd0;
 assign rq_shift0=source0_shift_i;
 assign rq_shift1=source1_shift_i;
 wire merge_valid_w_unused=1'b0;
 assign merge_valid_w=rq_rsp_valid&&!rq_rsp_error;assign merge_code_w=rq_rsp_code;
 assign busy_o=state_r!=IDLE&&state_r!=DONE&&state_r!=FAIL;
 assign state_o=state_r;assign cycle_count_o=cycles_r;
 assign memory_valid_o=state_r==READ0_REQ||state_r==READ1_REQ||state_r==WRITE_REQ;
 assign memory_write_o=state_r==WRITE_REQ;assign memory_use_hwc_o=1'b1;
 assign memory_raw_byte_address_o=0;
 assign memory_tensor_base_o=state_r==READ0_REQ?source0_base_i:state_r==READ1_REQ?source1_base_i:destination_base_i;
 assign memory_tensor_h_o=tensor_h_i;assign memory_tensor_w_o=tensor_w_i;assign memory_tensor_c_o=tensor_c_i;
 assign memory_y_o=y_r;assign memory_x_o=x_r;
 assign memory_channel_o=c_r+(state_r==WRITE_REQ?
  (WRITE_LINE_ENABLE!=0?4'd0:write_index_r):read_index_r);
 assign memory_write_data_o=output_codes_r[7:0];
 // Both descriptor acceptance and every issued group are aligned C%16==0.
 // Flag/payload stay owned through WRITE_WAIT and the final physical ACK;
 // never advertise a retained output buffer on operand reads.
 assign memory_write_line_o=(WRITE_LINE_ENABLE!=0)&&
  (state_r==WRITE_REQ||state_r==WRITE_WAIT);
 assign memory_write_line_data_o=output_codes_r;
 assign memory_response_ready_o=state_r==READ0_WAIT||state_r==READ1_WAIT||state_r==WRITE_WAIT;
 wire line_hit_w=read_index_r==0&&memory_read_line_valid_i&&memory_read_line_address_i[3:0]==0;
 wire final_group_w=y_r+1>=tensor_h_i&&x_r+1>=tensor_w_i&&c_r+16>=tensor_c_i;
 always@(posedge clk_i or negedge rst_ni)begin
  if(!rst_ni)begin
   state_r<=IDLE;read_index_r<=0;write_index_r<=0;y_r<=0;x_r<=0;c_r<=0;cycles_r<=0;
   source0_codes_r<=0;source1_codes_r<=0;output_codes_r<=0;issue_r<=0;collect_r<=0;done_o<=0;error_o<=0;
  end else begin
   done_o<=0;if(busy_o)cycles_r<=cycles_r+1'b1;
   if(rq_rsp_valid&&rq_rsp_error)begin error_o<=1;state_r<=FAIL;end else case(state_r)
    IDLE:if(start_i)begin
     cycles_r<=0;error_o<=0;y_r<=0;x_r<=0;c_r<=0;read_index_r<=0;write_index_r<=0;issue_r<=0;collect_r<=0;
     if(!descriptor_valid_i||opcode_i!=4||tensor_h_i==0||tensor_w_i==0||tensor_c_i<16||tensor_c_i[3:0]!=0||
        source0_base_i[3:0]!=0||source1_base_i[3:0]!=0||destination_base_i[3:0]!=0)begin error_o<=1;state_r<=FAIL;end
     else state_r<=READ0_REQ;
    end
    READ0_REQ:if(memory_ready_i)state_r<=READ0_WAIT;
    READ0_WAIT:if(memory_response_valid_i)begin
     if(memory_response_error_i||memory_response_is_write_i)begin error_o<=1;state_r<=FAIL;end
     else if(line_hit_w)begin source0_codes_r<=memory_read_line_data_i;read_index_r<=0;state_r<=READ1_REQ;end
     else begin
      source0_codes_r<={memory_read_data_i,source0_codes_r[127:8]};
      if(read_index_r==15)begin read_index_r<=0;state_r<=READ1_REQ;end
      else begin read_index_r<=read_index_r+1'b1;state_r<=READ0_REQ;end
     end
    end
    READ1_REQ:if(memory_ready_i)state_r<=READ1_WAIT;
    READ1_WAIT:if(memory_response_valid_i)begin
     if(memory_response_error_i||memory_response_is_write_i)begin error_o<=1;state_r<=FAIL;end
     else if(line_hit_w)begin source1_codes_r<=memory_read_line_data_i;issue_r<=0;collect_r<=0;state_r<=APPLY;end
     else begin
      source1_codes_r<={memory_read_data_i,source1_codes_r[127:8]};
      if(read_index_r==15)begin issue_r<=0;collect_r<=0;state_r<=APPLY;end
      else begin read_index_r<=read_index_r+1'b1;state_r<=READ1_REQ;end
     end
    end
    APPLY:begin
     // Consume exactly one low byte only on the actual requant ACCEPT.
     if(rq_req_valid&&rq_req_ready)begin
      issue_r<=issue_r+1'b1;
      source0_codes_r<={8'd0,source0_codes_r[127:8]};
      source1_codes_r<={8'd0,source1_codes_r[127:8]};
     end
     if(merge_valid_w)begin output_codes_r<={merge_code_w,output_codes_r[127:8]};collect_r<=collect_r+1'b1;end
     if(collect_r>=16)begin write_index_r<=0;state_r<=WRITE_REQ;end
    end
    WRITE_REQ:if(memory_ready_i)state_r<=WRITE_WAIT;
    WRITE_WAIT:if(memory_response_valid_i)begin
     if(memory_response_error_i||!memory_response_is_write_i)begin error_o<=1;state_r<=FAIL;end
     else if(WRITE_LINE_ENABLE==0&&write_index_r<15)begin output_codes_r<={8'd0,output_codes_r[127:8]};write_index_r<=write_index_r+1'b1;state_r<=WRITE_REQ;end
     else if(final_group_w)state_r<=DONE;
     else begin
      read_index_r<=0;
      if(c_r+16>=tensor_c_i)begin c_r<=0;if(x_r+1>=tensor_w_i)begin x_r<=0;y_r<=y_r+1'b1;end else x_r<=x_r+1'b1;end
      else c_r<=c_r+16;
      state_r<=READ0_REQ;
     end
    end
    DONE:begin done_o<=1;state_r<=IDLE;end
    default:state_r<=FAIL;
   endcase
  end
 end
endmodule
