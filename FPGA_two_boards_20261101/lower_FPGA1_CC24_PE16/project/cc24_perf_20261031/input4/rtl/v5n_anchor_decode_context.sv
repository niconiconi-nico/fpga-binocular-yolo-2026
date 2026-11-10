// Real head caller holds metadata from CELL_START through CELL_WAIT.
// No duplicate full64 scratch registers or private ALU in this customer.
module v5n_anchor_decode_context(
 input wire clk_i,rst_ni,valid_i,
 input wire[15:0]sx_i,sy_i,sw_i,sh_i,obj_i,c0_i,c1_i,c2_i,c3_i,
 input wire[9:0]grid_x_i,grid_y_i,input wire[5:0]stride_i,
 input wire[31:0]anchor_w_q16_i,anchor_h_q16_i,
 output reg valid_o,output reg signed[31:0]x1_o,y1_o,x2_o,y2_o,
 output reg[15:0]score0_o,score1_o,score2_o,score3_o,
 output wire busy_o,output reg error_o,
 output wire context_req_valid,input wire context_req_ready,
 output wire[2:0]context_mode,output wire[511:0]context_words,
 input wire context_rsp_valid,output wire context_rsp_ready,
 input wire[31:0]context_rsp_data,input wire[2:0]context_rsp_index,
 input wire context_rsp_last,context_rsp_error
);
 reg pending_r,owned_r;
 assign busy_o=pending_r||owned_r;assign context_req_valid=pending_r;
 assign context_mode=3'd3;
 assign context_words={64'd0,anchor_h_q16_i,anchor_w_q16_i,26'd0,stride_i,
  22'd0,grid_y_i,22'd0,grid_x_i,16'd0,c3_i,16'd0,c2_i,16'd0,c1_i,16'd0,c0_i,
  16'd0,obj_i,16'd0,sh_i,16'd0,sw_i,16'd0,sy_i,16'd0,sx_i};
 assign context_rsp_ready=owned_r;
 always @(posedge clk_i or negedge rst_ni)begin
  if(!rst_ni)begin pending_r<=0;owned_r<=0;valid_o<=0;error_o<=0;
   x1_o<=0;y1_o<=0;x2_o<=0;y2_o<=0;score0_o<=0;score1_o<=0;score2_o<=0;score3_o<=0;end
  else begin
   valid_o<=0;
   if(valid_i&&!busy_o)begin pending_r<=1;error_o<=0;end
   if(context_req_valid&&context_req_ready)begin pending_r<=0;owned_r<=1;end
   if(context_rsp_valid&&context_rsp_ready)begin
    if(context_rsp_error)begin error_o<=1;owned_r<=0;end
    else begin
     case(context_rsp_index)
      0:x1_o<=context_rsp_data;1:y1_o<=context_rsp_data;2:x2_o<=context_rsp_data;3:y2_o<=context_rsp_data;
      4:score0_o<=context_rsp_data[15:0];5:score1_o<=context_rsp_data[15:0];
      6:score2_o<=context_rsp_data[15:0];7:score3_o<=context_rsp_data[15:0];
     endcase
     if(context_rsp_last)begin owned_r<=0;valid_o<=1;end
    end
   end
  end
 end
endmodule
