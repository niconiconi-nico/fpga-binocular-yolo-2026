// Fixed classicv5 SiLU: genuine shared read16 -> real LUT -> scalar ACK writes.
// No precomputed output/LUT, no DDR master, no write acknowledgement shortcut.
module v5n_silu_read16_runtime #(
 parameter integer ADDR_W=32,parameter integer SHAPE_W=10,
 parameter integer WRITE_LINE_ENABLE=0
)(
 input wire clk_i,rst_ni,start_i,descriptor_valid_i,
 input wire [7:0] descriptor_id_i,input wire [3:0] opcode_i,
 input wire [ADDR_W-1:0] source_tensor_base_i,destination_tensor_base_i,
 input wire [SHAPE_W-1:0] tensor_h_i,tensor_w_i,tensor_c_i,
 input wire [ADDR_W-1:0] lut_address_i,lut_bytes_i,
 input wire [SHAPE_W-1:0] tile_origin_y_i,tile_origin_x_i,tile_h_i,tile_w_i,
 output wire busy_o,output reg done_o,error_o,
 output wire [3:0] state_o,output wire [31:0] cycle_count_o,
 output wire memory_valid_o,input wire memory_ready_i,output wire memory_write_o,memory_use_hwc_o,
 output wire [ADDR_W-1:0] memory_raw_byte_address_o,memory_tensor_base_o,
 output wire [SHAPE_W-1:0] memory_tensor_h_o,memory_tensor_w_o,memory_tensor_c_o,
 output wire [SHAPE_W-1:0] memory_y_o,memory_x_o,memory_channel_o,
 output wire signed [7:0] memory_write_data_o,
 output wire memory_write_line_o,output wire [127:0] memory_write_line_data_o,
 input wire memory_response_valid_i,output wire memory_response_ready_o,
 input wire memory_response_error_i,memory_response_is_write_i,input wire signed [7:0] memory_read_data_i,
 input wire memory_read_line_valid_i,input wire [ADDR_W-1:0] memory_read_line_address_i,
 input wire [127:0] memory_read_line_data_i
);
 localparam [3:0] IDLE=0,LUT_REQ=1,LUT_WAIT=2,READ_REQ=3,READ_WAIT=4,
                  APPLY=5,WRITE_REQ=7,WRITE_WAIT=8,DONE=9,FAIL=10;
 reg [3:0] state_r;reg [7:0] lut_index_r;
 reg [SHAPE_W-1:0] y_r,x_r,c_r;
 reg [3:0] read_index_r,write_index_r;
 reg [4:0] issue_r,collect_r;
 reg [127:0] input_codes_r,output_codes_r;
 reg [31:0] cycles_r;
 wire lut_valid_w;wire signed [7:0] lut_code_w;
 wire [3:0] issue_index_w=(issue_r<16)?issue_r[3:0]:4'd0;
 wire apply_valid_w=(state_r==APPLY)&&(issue_r<16);
 v5n_lut256_i8 #(.NUM_LANES(1)) actual_lut(
  .clk_i(clk_i),.rst_ni(rst_ni),
  .cfg_write_enable_i(state_r==LUT_WAIT&&memory_response_valid_i&&!memory_response_error_i&&!memory_response_is_write_i),
  .cfg_address_i(lut_index_r),.cfg_data_i(memory_read_data_i),
  .valid_i(apply_valid_w),.code_i(input_codes_r[issue_index_w*8+:8]),
  .valid_o(lut_valid_w),.code_o(lut_code_w));
 assign busy_o=state_r!=IDLE&&state_r!=DONE&&state_r!=FAIL;
 assign state_o=state_r;assign cycle_count_o=cycles_r;
 assign memory_valid_o=state_r==LUT_REQ||state_r==READ_REQ||state_r==WRITE_REQ;
 assign memory_write_o=state_r==WRITE_REQ;
 assign memory_use_hwc_o=state_r==READ_REQ||state_r==WRITE_REQ;
 assign memory_raw_byte_address_o=lut_address_i+lut_index_r;
 assign memory_tensor_base_o=state_r==WRITE_REQ?destination_tensor_base_i:source_tensor_base_i;
 assign memory_tensor_h_o=tensor_h_i;assign memory_tensor_w_o=tensor_w_i;assign memory_tensor_c_o=tensor_c_i;
 assign memory_y_o=tile_origin_y_i+y_r;assign memory_x_o=tile_origin_x_i+x_r;
 assign memory_channel_o=c_r+(state_r==WRITE_REQ?write_index_r:read_index_r);
 assign memory_write_data_o=output_codes_r[write_index_r*8+:8];
 // Only this fixed, aligned, C%16==0 runtime opts in. Both modes retain
 // the exact LUT pipeline; one ACK means one accepted physical transaction.
 assign memory_write_line_o=(WRITE_LINE_ENABLE!=0)&&(state_r==WRITE_REQ);
 assign memory_write_line_data_o=output_codes_r;
 assign memory_response_ready_o=state_r==LUT_WAIT||state_r==READ_WAIT||state_r==WRITE_WAIT;
 wire final_group_w=y_r+1>=tile_h_i&&x_r+1>=tile_w_i&&c_r+16>=tensor_c_i;
 always @(posedge clk_i or negedge rst_ni)begin
  if(!rst_ni)begin
   state_r<=IDLE;lut_index_r<=0;y_r<=0;x_r<=0;c_r<=0;read_index_r<=0;write_index_r<=0;
   issue_r<=0;collect_r<=0;input_codes_r<=0;output_codes_r<=0;cycles_r<=0;done_o<=0;error_o<=0;
  end else begin
   done_o<=0;if(busy_o)cycles_r<=cycles_r+1'b1;
   case(state_r)
    IDLE:if(start_i)begin
     cycles_r<=0;error_o<=0;lut_index_r<=0;y_r<=0;x_r<=0;c_r<=0;
     read_index_r<=0;write_index_r<=0;issue_r<=0;collect_r<=0;
     if(!descriptor_valid_i||opcode_i!=2||lut_bytes_i!=256||tile_h_i==0||tile_w_i==0||
        tensor_c_i<16||tensor_c_i[3:0]!=0||source_tensor_base_i[3:0]!=0||destination_tensor_base_i[3:0]!=0||
        tile_origin_y_i+tile_h_i>tensor_h_i||tile_origin_x_i+tile_w_i>tensor_w_i)begin error_o<=1;state_r<=FAIL;end
     else state_r<=LUT_REQ;
    end
    LUT_REQ:if(memory_ready_i)state_r<=LUT_WAIT;
    LUT_WAIT:if(memory_response_valid_i)begin
     if(memory_response_error_i||memory_response_is_write_i)begin error_o<=1;state_r<=FAIL;end
     else if(lut_index_r==255)state_r<=READ_REQ;
     else begin lut_index_r<=lut_index_r+1'b1;state_r<=LUT_REQ;end
    end
    READ_REQ:if(memory_ready_i)state_r<=READ_WAIT;
    READ_WAIT:if(memory_response_valid_i)begin
     if(memory_response_error_i||memory_response_is_write_i)begin error_o<=1;state_r<=FAIL;end
     else if(read_index_r==0&&memory_read_line_valid_i&&memory_read_line_address_i[3:0]==0)begin
      // Service+bridge qualify exactrequest/owner/tag. Current fixedgraph
      // Conv->SiLU has contiguousphysical16channelgroups, no Split aliases.
      input_codes_r<=memory_read_line_data_i;issue_r<=0;collect_r<=0;state_r<=APPLY;
     end else begin
      input_codes_r[read_index_r*8+:8]<=memory_read_data_i;
      if(read_index_r==15)begin issue_r<=0;collect_r<=0;state_r<=APPLY;end
      else begin read_index_r<=read_index_r+1'b1;state_r<=READ_REQ;end
     end
    end
    APPLY:begin
     if(issue_r<16)issue_r<=issue_r+1'b1;
     if(lut_valid_w)begin
      output_codes_r[collect_r[3:0]*8+:8]<=lut_code_w;collect_r<=collect_r+1'b1;
     end
     if(collect_r>=16)begin write_index_r<=0;state_r<=WRITE_REQ;end
    end
    WRITE_REQ:if(memory_ready_i)state_r<=WRITE_WAIT;
    WRITE_WAIT:if(memory_response_valid_i)begin
     if(memory_response_error_i||!memory_response_is_write_i)begin error_o<=1;state_r<=FAIL;end
     else if(WRITE_LINE_ENABLE==0&&write_index_r<15)begin write_index_r<=write_index_r+1'b1;state_r<=WRITE_REQ;end
     else if(final_group_w)state_r<=DONE;
     else begin
      read_index_r<=0;
      if(c_r+16>=tensor_c_i)begin
       c_r<=0;
       if(x_r+1>=tile_w_i)begin x_r<=0;y_r<=y_r+1'b1;end
       else x_r<=x_r+1'b1;
      end else c_r<=c_r+16;
      state_r<=READ_REQ;
     end
    end
    DONE:begin done_o<=1;state_r<=IDLE;end
    default:state_r<=FAIL;
   endcase
  end
 end
endmodule
