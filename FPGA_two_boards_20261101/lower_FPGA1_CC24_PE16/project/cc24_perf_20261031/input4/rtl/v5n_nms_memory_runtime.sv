// A2 v5 candidate buffer:6300 positions x8int32, candidates=position*4+class.
// Shared-memory wrapper for the verified class-aware integer NMS engine.
// Stage 8 compacts threshold-passing candidates into local ERAM before NMS.
// Stable input order is preserved. If MAX_FILTERED overflows, the runtime
// falls back to the original direct-DDR path instead of truncating results.
(* multstyle = "logic" *) module v5n_nms_memory_runtime #(
 parameter integer ADDR_W=32,parameter integer SHAPE_W=10,parameter integer MAX_FILTERED=1024
)(
 input wire clk_i,input wire rst_ni,input wire start_i,input wire descriptor_valid_i,input wire [3:0] opcode_i,
 input wire [ADDR_W-1:0] feature_base_i,input wire [ADDR_W-1:0] destination_base_i,
 output reg [8:0] detection_count_o,output wire busy_o,output reg done_o,output reg error_o,
 output wire memory_valid_o,input wire memory_ready_i,output wire memory_write_o,output wire memory_use_hwc_o,
 output wire [ADDR_W-1:0] memory_raw_byte_address_o,output wire [ADDR_W-1:0] memory_tensor_base_o,
 output wire [SHAPE_W-1:0] memory_tensor_h_o,memory_tensor_w_o,memory_tensor_c_o,memory_y_o,memory_x_o,memory_channel_o,
 output wire signed [7:0] memory_write_data_o,input wire memory_response_valid_i,output wire memory_response_ready_o,
 input wire memory_response_error_i,input wire memory_response_is_write_i,input wire signed [7:0] memory_read_data_i,
output wire context_req_valid,input wire context_req_ready,
output wire[2:0]context_mode,output wire[511:0]context_words,
input wire context_rsp_valid,output wire context_rsp_ready,
input wire[31:0]context_rsp_data,input wire[2:0]context_rsp_index,
input wire context_rsp_last,context_rsp_error

);
 wire numeric_arithmetic_error_o;
 localparam [3:0] ST_IDLE=0,ST_PREFETCH_REQ=1,ST_PREFETCH_WAIT=2,ST_PREFETCH_EVAL=3,
  ST_ENGINE_START=4,ST_WAIT_ENGINE=5,ST_CACHE_PRIME=6,ST_CACHE_VALID=7,
  ST_DIRECT_REQ=8,ST_DIRECT_WAIT=9,ST_DIRECT_VALID=10,ST_WRITE_REQ=11,
  ST_WRITE_WAIT=12,ST_DONE=13,ST_FAIL=14;
 localparam integer FILTER_ADDR_W=$clog2(MAX_FILTERED);
 reg [3:0] state_r;reg [14:0] fetch_index_r,filtered_count_r;reg [2:0] field_r;reg [1:0] byte_r;
 reg [31:0] word_r;reg signed [127:0] candidate_box_r,selected_box_r;
 reg [15:0] candidate_score_r,selected_score_r;reg [1:0] candidate_class_r,selected_class_r;
 reg [127:0] cache_box_write_r;reg [31:0] cache_meta_write_r;
 reg [8:0] record_index_r;reg engine_complete_r,filtered_overflow_r,direct_mode_r;

 wire engine_ready_w,engine_busy_w,engine_complete_w,engine_candidate_request_w,engine_selected_valid_w;
 wire [14:0] engine_candidate_index_w,engine_selected_index_w;wire signed [127:0] engine_selected_box_w;
 wire [15:0] engine_selected_score_w;wire [1:0] engine_selected_class_w;wire [8:0] engine_selected_count_w;
 wire prefetch_eligible_w=(candidate_score_r>=16'd33);
 wire prefetch_cache_write_w=(state_r==ST_PREFETCH_EVAL)&&prefetch_eligible_w&&
  !filtered_overflow_r&&(filtered_count_r<MAX_FILTERED);
 wire prefetch_overflow_now_w=(state_r==ST_PREFETCH_EVAL)&&prefetch_eligible_w&&(filtered_count_r>=MAX_FILTERED);

 wire [127:0] cache_box_read_w;wire [31:0] cache_meta_read_w;
 wire [FILTER_ADDR_W-1:0] cache_write_addr_w=filtered_count_r[FILTER_ADDR_W-1:0];
 wire [FILTER_ADDR_W-1:0] cache_read_addr_w=engine_candidate_index_w[FILTER_ADDR_W-1:0];
 wire [31:0] cache_port_a_unused_w[0:4];
 genvar cache_field;
 generate for(cache_field=0;cache_field<4;cache_field=cache_field+1)begin:G_CANDIDATE_BOX_CACHE
  PH1P_LOGIC_ERAM #(.DATA_WIDTH_A(32),.DATA_WIDTH_B(32),.ADDR_WIDTH_A(FILTER_ADDR_W),.ADDR_WIDTH_B(FILTER_ADDR_W),
   .DATA_DEPTH_A(MAX_FILTERED),.DATA_DEPTH_B(MAX_FILTERED),.MODE("DP"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),
   .WRITEMODE_A("READBEFOREWRITE"),.WRITEMODE_B("READBEFOREWRITE"),.CLKMODE("ASYNC"),.SSROVERCE("DISABLE"),
   .OREGSET_A("RESET"),.OREGSET_B("RESET"),.RESETMODE_A("ASYNC"),.RESETMODE_B("ASYNC"),
   .ASYNC_RESET_RELEASE_A("ASYNC"),.ASYNC_RESET_RELEASE_B("ASYNC"),.ECC_ENCODE("DISABLE"),.ECC_DECODE("DISABLE"),
   .IMPLEMENT("20K(FAST)"),.INIT_FILE("NONE"),.FILL_ALL("NONE")) candidate_box_cache(
   .dia(cache_box_write_r[cache_field*32+:32]),.addra(cache_write_addr_w),.cea(1'b1),.ocea(1'b0),.clka(clk_i),
   .wea(prefetch_cache_write_w),.rsta(1'b0),.bea(1'b0),.dib(32'd0),.addrb(cache_read_addr_w),.ceb(1'b1),
   .oceb(1'b0),.clkb(clk_i),.web(1'b0),.rstb(1'b0),.beb(1'b0),.ecc_sbiterrinj(1'b0),.ecc_dbiterrinj(1'b0),
   .doa(cache_port_a_unused_w[cache_field]),.dob(cache_box_read_w[cache_field*32+:32]),.ecc_sbiterr(),.ecc_dbiterr());
 end endgenerate
 PH1P_LOGIC_ERAM #(.DATA_WIDTH_A(32),.DATA_WIDTH_B(32),.ADDR_WIDTH_A(FILTER_ADDR_W),.ADDR_WIDTH_B(FILTER_ADDR_W),
  .DATA_DEPTH_A(MAX_FILTERED),.DATA_DEPTH_B(MAX_FILTERED),.MODE("DP"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),
  .WRITEMODE_A("READBEFOREWRITE"),.WRITEMODE_B("READBEFOREWRITE"),.CLKMODE("ASYNC"),.SSROVERCE("DISABLE"),
  .OREGSET_A("RESET"),.OREGSET_B("RESET"),.RESETMODE_A("ASYNC"),.RESETMODE_B("ASYNC"),
  .ASYNC_RESET_RELEASE_A("ASYNC"),.ASYNC_RESET_RELEASE_B("ASYNC"),.ECC_ENCODE("DISABLE"),.ECC_DECODE("DISABLE"),
  .IMPLEMENT("20K(FAST)"),.INIT_FILE("NONE"),.FILL_ALL("NONE")) candidate_meta_cache(
  .dia(cache_meta_write_r),.addra(cache_write_addr_w),.cea(1'b1),.ocea(1'b0),.clka(clk_i),
  .wea(prefetch_cache_write_w),.rsta(1'b0),.bea(1'b0),.dib(32'd0),.addrb(cache_read_addr_w),.ceb(1'b1),
  .oceb(1'b0),.clkb(clk_i),.web(1'b0),.rstb(1'b0),.beb(1'b0),.ecc_sbiterrinj(1'b0),.ecc_dbiterrinj(1'b0),
  .doa(cache_port_a_unused_w[4]),.dob(cache_meta_read_w),.ecc_sbiterr(),.ecc_dbiterr());

 wire engine_candidate_valid_w=(state_r==ST_CACHE_VALID)||(state_r==ST_DIRECT_VALID);
 wire [15:0] engine_candidate_score_w=(state_r==ST_CACHE_VALID)?cache_meta_read_w[15:0]:candidate_score_r;
 wire [1:0] engine_candidate_class_w=(state_r==ST_CACHE_VALID)?cache_meta_read_w[17:16]:candidate_class_r;
 wire signed [127:0] engine_candidate_box_w=(state_r==ST_CACHE_VALID)?$signed(cache_box_read_w):candidate_box_r;
 wire [14:0] engine_candidate_count_w=direct_mode_r?15'd25200:filtered_count_r;
 v5n_integer_nms_context engine(.arithmetic_error_o(numeric_arithmetic_error_o),
.context_req_valid(context_req_valid),.context_req_ready(context_req_ready),.context_mode(context_mode),.context_words(context_words),.context_rsp_valid(context_rsp_valid),.context_rsp_ready(context_rsp_ready),.context_rsp_data(context_rsp_data),.context_rsp_index(context_rsp_index),.context_rsp_last(context_rsp_last),.context_rsp_error(context_rsp_error),
.clk_i(clk_i),.rst_ni(rst_ni),.start_i(state_r==ST_ENGINE_START),
  .ready_o(engine_ready_w),.busy_o(engine_busy_w),.complete_o(engine_complete_w),
  .candidate_count_i(engine_candidate_count_w),.score_threshold_q15_i(16'd33),.max_detections_i(9'd300),
  .candidate_index_o(engine_candidate_index_w),.candidate_request_o(engine_candidate_request_w),
  .candidate_valid_i(engine_candidate_valid_w),.candidate_score_q15_i(engine_candidate_score_w),
  .candidate_class_i(engine_candidate_class_w),.candidate_box_q16_i(engine_candidate_box_w),
  .selected_valid_o(engine_selected_valid_w),.selected_box_q16_o(engine_selected_box_w),
  .selected_score_q15_o(engine_selected_score_w),.selected_class_o(engine_selected_class_w),
  .selected_candidate_index_o(engine_selected_index_w),.selected_count_o(engine_selected_count_w));

    wire [1:0] fetch_class_r = fetch_index_r[1:0];
    wire [12:0] local_position_r = fetch_index_r >> 2;
    wire [ADDR_W-1:0] scale_base_r = feature_base_i;
    wire [3:0] read_lane_r = (field_r<4) ? field_r : (4+fetch_class_r);
 reg signed [31:0] write_word_r;
 always @* begin case(field_r)
  0:write_word_r={{30{1'b0}},selected_class_r};1:write_word_r={16'd0,selected_score_r};
  2:write_word_r=selected_box_r[31:0];3:write_word_r=selected_box_r[63:32];
  4:write_word_r=selected_box_r[95:64];default:write_word_r=selected_box_r[127:96];endcase end
 wire read_phase_w=(state_r==ST_PREFETCH_REQ)||(state_r==ST_DIRECT_REQ);
 assign memory_valid_o=read_phase_w||(state_r==ST_WRITE_REQ);assign memory_write_o=(state_r==ST_WRITE_REQ);
 assign memory_use_hwc_o=1'b0;
 assign memory_raw_byte_address_o=read_phase_w?(scale_base_r+(local_position_r*32)+(read_lane_r*4)+byte_r):
  (destination_base_i+(record_index_r*24)+(field_r*4)+byte_r);
 assign memory_tensor_base_o=0;assign memory_tensor_h_o=0;assign memory_tensor_w_o=0;assign memory_tensor_c_o=0;
 assign memory_y_o=0;assign memory_x_o=0;assign memory_channel_o=0;
 assign memory_write_data_o=write_word_r[byte_r*8+:8];
 assign memory_response_ready_o=(state_r==ST_PREFETCH_WAIT)||(state_r==ST_DIRECT_WAIT)||(state_r==ST_WRITE_WAIT);
 assign busy_o=(state_r!=ST_IDLE)&&(state_r!=ST_DONE)&&(state_r!=ST_FAIL);

 always @(posedge clk_i or negedge rst_ni)begin
  if(!rst_ni)begin
   state_r<=ST_IDLE;fetch_index_r<=0;filtered_count_r<=0;field_r<=0;byte_r<=0;word_r<=0;
   candidate_box_r<=0;candidate_score_r<=0;candidate_class_r<=0;selected_box_r<=0;selected_score_r<=0;
   cache_box_write_r<=0;cache_meta_write_r<=0;
   selected_class_r<=0;record_index_r<=0;detection_count_o<=0;engine_complete_r<=0;
   filtered_overflow_r<=0;direct_mode_r<=0;done_o<=0;error_o<=0;
  end else begin
   done_o<=0;if(engine_complete_w)engine_complete_r<=1;
   if(numeric_arithmetic_error_o)begin error_o<=1;state_r<=ST_FAIL;end else case(state_r)
    ST_IDLE:if(start_i)begin
     fetch_index_r<=0;filtered_count_r<=0;field_r<=0;byte_r<=0;word_r<=0;record_index_r<=0;
     detection_count_o<=0;engine_complete_r<=0;filtered_overflow_r<=0;direct_mode_r<=0;error_o<=0;
     if(!descriptor_valid_i||opcode_i!=4'd9)begin error_o<=1;state_r<=ST_FAIL;end
     else begin candidate_class_r<=0;state_r<=ST_PREFETCH_REQ;end
    end
    ST_PREFETCH_REQ:if(memory_ready_i)state_r<=ST_PREFETCH_WAIT;
    ST_PREFETCH_WAIT:if(memory_response_valid_i)begin
     if(memory_response_error_i||memory_response_is_write_i)begin error_o<=1;state_r<=ST_FAIL;end
     else begin
      word_r[byte_r*8+:8]<=memory_read_data_i;
      if(byte_r!=3)begin byte_r<=byte_r+1'b1;state_r<=ST_PREFETCH_REQ;end
      else if(field_r<4)begin candidate_box_r[field_r*32+:32]<={memory_read_data_i,word_r[23:0]};
       field_r<=field_r+1'b1;byte_r<=0;word_r<=0;state_r<=ST_PREFETCH_REQ;end
      else begin
       candidate_score_r<={memory_read_data_i,word_r[23:0]};
       cache_box_write_r<=candidate_box_r;
       // Pack only the Q15 score's low 16 bits with the two class bits.
       // The previous expression appended the full assembled 32-bit DDR
       // word, producing a 48-bit concatenation assigned to this 32-bit
       // register.  Verilog truncated its upper 16 bits, including the class,
       // so every cached candidate was presented to NMS as class zero.
       cache_meta_write_r<={14'd0,candidate_class_r,word_r[15:0]};
       state_r<=ST_PREFETCH_EVAL;
      end
     end
    end
    ST_PREFETCH_EVAL:begin
     if(prefetch_cache_write_w)filtered_count_r<=filtered_count_r+1'b1;
     if(prefetch_overflow_now_w)filtered_overflow_r<=1'b1;
     if(fetch_index_r+1'b1>=15'd25200)begin direct_mode_r<=filtered_overflow_r||prefetch_overflow_now_w;state_r<=ST_ENGINE_START;end
     else begin fetch_index_r<=fetch_index_r+1'b1;candidate_class_r<=(fetch_index_r+1'b1)%4;
      field_r<=0;byte_r<=0;word_r<=0;state_r<=ST_PREFETCH_REQ;end
    end
    ST_ENGINE_START:state_r<=ST_WAIT_ENGINE;
    ST_WAIT_ENGINE:begin
     if(engine_selected_valid_w)begin selected_box_r<=engine_selected_box_w;selected_score_r<=engine_selected_score_w;
      selected_class_r<=engine_selected_class_w;field_r<=0;byte_r<=0;state_r<=ST_WRITE_REQ;end
     else if(engine_complete_r||engine_complete_w)state_r<=ST_DONE;
     else if(engine_candidate_request_w)begin
      if(direct_mode_r)begin fetch_index_r<=engine_candidate_index_w;candidate_class_r<=engine_candidate_index_w%4;
       field_r<=0;byte_r<=0;word_r<=0;state_r<=ST_DIRECT_REQ;end
      else state_r<=ST_CACHE_PRIME;
     end
    end
    ST_CACHE_PRIME:state_r<=ST_CACHE_VALID;
    ST_CACHE_VALID:state_r<=ST_WAIT_ENGINE;
    ST_DIRECT_REQ:if(memory_ready_i)state_r<=ST_DIRECT_WAIT;
    ST_DIRECT_WAIT:if(memory_response_valid_i)begin
     if(memory_response_error_i||memory_response_is_write_i)begin error_o<=1;state_r<=ST_FAIL;end
     else begin word_r[byte_r*8+:8]<=memory_read_data_i;
      if(byte_r!=3)begin byte_r<=byte_r+1'b1;state_r<=ST_DIRECT_REQ;end
      else if(field_r<4)begin candidate_box_r[field_r*32+:32]<={memory_read_data_i,word_r[23:0]};
       field_r<=field_r+1'b1;byte_r<=0;word_r<=0;state_r<=ST_DIRECT_REQ;end
      else begin candidate_score_r<={memory_read_data_i,word_r[23:0]};state_r<=ST_DIRECT_VALID;end
     end
    end
    ST_DIRECT_VALID:state_r<=ST_WAIT_ENGINE;
    ST_WRITE_REQ:if(memory_ready_i)state_r<=ST_WRITE_WAIT;
    ST_WRITE_WAIT:if(memory_response_valid_i)begin
     if(memory_response_error_i||!memory_response_is_write_i)begin error_o<=1;state_r<=ST_FAIL;end
     else if(byte_r!=3)begin byte_r<=byte_r+1'b1;state_r<=ST_WRITE_REQ;end
     else if(field_r!=5)begin field_r<=field_r+1'b1;byte_r<=0;state_r<=ST_WRITE_REQ;end
     else begin detection_count_o<=record_index_r+1'b1;record_index_r<=record_index_r+1'b1;byte_r<=0;field_r<=0;
      if(engine_complete_r||engine_complete_w)state_r<=ST_DONE;else state_r<=ST_WAIT_ENGINE;end
    end
    ST_DONE,ST_FAIL:begin done_o<=1;state_r<=ST_IDLE;end
    default:state_r<=ST_FAIL;
   endcase
  end
 end
endmodule
