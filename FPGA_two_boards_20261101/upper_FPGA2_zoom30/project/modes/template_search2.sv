// Single frozen ROI snapshot + one32x32 greyscale template. No full-frame
// buffer, host templates, fake coordinates, DDR accesses or derived clocks.
// Snapshot commits only after a complete WIDTH*HEIGHT raster frame and exact
// ROI pixel count. Epoch is display-raster epoch, NOT a sensor Frame ID.
module template_search2 #(
 parameter integer WIDTH=1280,HEIGHT=720,ROI_W=128,ROI_H=128,
 parameter integer ROI_X=(WIDTH-ROI_W)/2,ROI_Y=(HEIGHT-ROI_H)/2,STEP=4,
 parameter integer BINARY_THRESHOLD=128,MAX_MISMATCH=128,
 parameter integer TEMPLATE_X=(ROI_W-32)/2,TEMPLATE_Y=(ROI_H-32)/2
)(input wire clk,rst_n,vs_i,de_i,input wire[23:0] rgb_i,input wire[7:0] mode_i,
 input wire capture_i,output reg done_o,found_o,result_binary_o,
 output reg[11:0] x_o,y_o,output reg[10:0] score_o,output reg[31:0] result_epoch_o,cycles_o,
 output wire[2:0] status_o,output wire busy_o,output reg template_valid_o,
 output reg[31:0] template_epoch_o);
 localparam IDLE=0,CAPTURE=1,CP_ADDR=2,CP_READ=3,CP_WRITE=4,SETUP=5,
 CORE_START=6,PAIR_ADDR=7,PAIR_READ=8,PAIR_FEED=9,WAIT_CORE=10,RANK_A_WAIT=11,RANK_B_WAIT=12,NEXT=13,FINISH=14;
 reg[3:0] state;reg vs_d,de_d;reg[11:0] ix,iy;reg[31:0] epoch,snapshot_epoch,video_count,roi_count,cycles;
 reg want_capture,result_seen,binary_mode;reg[9:0] copy_index,pair_index;
 reg[11:0] candidate_x,candidate_y,best_x,best_y;reg best_valid,best_hit;
 reg[10:0] best_score,best_mismatch;reg[71:0] best_csq;reg[35:0] best_vi;
 wire enabled=mode_i==27||mode_i==28,boundary=vs_i&&!vs_d,fall=de_d&&!de_i;
 wire inside_roi=ix>=ROI_X&&ix<ROI_X+ROI_W&&iy>=ROI_Y&&iy<ROI_Y+ROI_H;
 reg[7:0] roi_mem[0:ROI_W*ROI_H-1];reg[7:0] template_mem[0:1023];reg[7:0] roi_q,template_q;
 localparam integer AW=$clog2(ROI_W*ROI_H);
 wire[AW-1:0] capture_address=(iy-ROI_Y)*ROI_W+(ix-ROI_X);
 reg[AW-1:0] read_address;
 always @*begin
  if(state==CP_ADDR||state==CP_READ||state==CP_WRITE)read_address=(TEMPLATE_Y+copy_index[9:5])*ROI_W+TEMPLATE_X+copy_index[4:0];
  else read_address=(candidate_y+pair_index[9:5])*ROI_W+candidate_x+pair_index[4:0];
 end
 function automatic[7:0] luma(input[23:0] p);
  reg[15:0] s;begin s=16'd77*p[23:16]+16'd150*p[15:8]+16'd29*p[7:0];luma=s[15:8];end
 endfunction
 always @(posedge clk)begin
  if(rst_n&&state==CAPTURE&&de_i&&inside_roi)roi_mem[capture_address]<=luma(rgb_i);
  if(rst_n&&state>=CP_ADDR)roi_q<=roi_mem[read_address];
  if(rst_n&&state==CP_WRITE)template_mem[copy_index]<=roi_q;
  if(rst_n&&state>=CORE_START)template_q<=template_mem[pair_index];
 end
 wire ready,core_done,core_valid,core_hit;wire[10:0] core_score,core_mm;wire[71:0] core_csq,core_vprod;wire[35:0] core_vi;
 template_score_core2 #(.BINARY_THRESHOLD(BINARY_THRESHOLD),.MAX_MISMATCH(MAX_MISMATCH)) core(
 clk,rst_n,state==CORE_START,binary_mode,state==PAIR_FEED&&ready,template_q,roi_q,
 ready,core_done,core_valid,core_hit,core_score,core_mm,core_csq,core_vprod,core_vi);
 reg rank_start;reg[127:0] rank_a,rank_b;wire rank_busy,rank_done;wire[255:0] rank_result;reg[107:0] left_rank;
 match_mul72x36_2 ranker(clk,rst_n,rank_start,rank_a,rank_b,rank_busy,rank_done,rank_result);
 // Positive NCC ranking uses C^2/VI. VT is identical for all candidates of
 // this frozen template; exact cross multiplication avoids q8 score ties.
 task automatic take_best;
 begin best_valid<=1;best_hit<=core_hit;best_x<=candidate_x;best_y<=candidate_y;best_score<=core_score;best_mismatch<=core_mm;best_csq<=core_csq;best_vi<=core_vi;end
 endtask
 assign busy_o=state!=IDLE;
 assign status_o=want_capture||!template_valid_o?3'd1:!result_seen?3'd3:found_o?3'd4:3'd5;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   state<=IDLE;vs_d<=0;de_d<=0;ix<=0;iy<=0;epoch<=0;snapshot_epoch<=0;video_count<=0;roi_count<=0;cycles<=0;
   want_capture<=1;result_seen<=0;binary_mode<=0;copy_index<=0;pair_index<=0;candidate_x<=0;candidate_y<=0;best_x<=0;best_y<=0;
   best_valid<=0;best_hit<=0;best_score<=0;best_mismatch<=1024;best_csq<=0;best_vi<=0;
   rank_start<=0;rank_a<=0;rank_b<=0;left_rank<=0;
   done_o<=0;found_o<=0;result_binary_o<=0;x_o<=0;y_o<=0;score_o<=0;result_epoch_o<=0;cycles_o<=0;template_valid_o<=0;template_epoch_o<=0;
  end else begin
   vs_d<=vs_i;de_d<=de_i;done_o<=0;rank_start<=0;
   if(boundary)begin ix<=0;iy<=0;epoch<=epoch+1'b1;end
   else begin if(de_i)ix<=ix+1'b1;if(fall)begin ix<=0;iy<=iy+1'b1;end end
   if(state>=CORE_START&&state<=FINISH)cycles<=cycles+1'b1;
   case(state)
    IDLE:if(boundary&&enabled)begin state<=CAPTURE;video_count<=0;roi_count<=0;end
    CAPTURE:begin
     if(de_i)begin video_count<=video_count+1'b1;if(inside_roi)roi_count<=roi_count+1'b1;end
     if(boundary)begin
      video_count<=0;roi_count<=0;
      if(!enabled)state<=IDLE;
      else if(video_count==WIDTH*HEIGHT&&roi_count==ROI_W*ROI_H)begin
       snapshot_epoch<=epoch;binary_mode<=mode_i==28;
       if(want_capture||!template_valid_o)begin copy_index<=0;template_valid_o<=0;state<=CP_ADDR;end
       else state<=SETUP;
      end
     end
    end
    CP_ADDR:state<=CP_READ;
    CP_READ:state<=CP_WRITE;
    CP_WRITE:begin
     if(copy_index==1023)begin template_valid_o<=1;template_epoch_o<=snapshot_epoch;want_capture<=0;state<=SETUP;end
     else begin copy_index<=copy_index+1'b1;state<=CP_ADDR;end
    end
    SETUP:begin
     candidate_x<=0;candidate_y<=0;best_valid<=0;best_hit<=0;best_score<=0;best_mismatch<=1024;best_csq<=0;best_vi<=0;cycles<=0;state<=CORE_START;
    end
    CORE_START:begin pair_index<=0;state<=PAIR_ADDR;end
    PAIR_ADDR:state<=PAIR_READ;
    PAIR_READ:state<=PAIR_FEED;
    PAIR_FEED:if(ready)begin
     if(pair_index==1023)state<=WAIT_CORE;else begin pair_index<=pair_index+1'b1;state<=PAIR_ADDR;end
    end
    WAIT_CORE:if(core_done)begin
     if(!core_valid)state<=NEXT;
     else if(!best_valid)begin take_best();state<=NEXT;end
     else if(binary_mode)begin if(core_mm<best_mismatch)take_best();state<=NEXT;end
     else begin rank_a<={56'd0,core_csq};rank_b<={92'd0,best_vi};rank_start<=1;state<=RANK_A_WAIT;end
    end
    RANK_A_WAIT:if(rank_done)begin
     left_rank<=rank_result[107:0];rank_a<={56'd0,best_csq};rank_b<={92'd0,core_vi};rank_start<=1;state<=RANK_B_WAIT;
    end
    RANK_B_WAIT:if(rank_done)begin if({148'd0,left_rank}>rank_result)take_best();state<=NEXT;end
    NEXT:begin
     if(candidate_x+STEP<=ROI_W-32)begin candidate_x<=candidate_x+STEP;state<=CORE_START;end
     else if(candidate_y+STEP<=ROI_H-32)begin candidate_x<=0;candidate_y<=candidate_y+STEP;state<=CORE_START;end
     else state<=FINISH;
    end
    FINISH:begin
     done_o<=1;found_o<=best_valid&&best_hit&&!want_capture;result_seen<=1;result_binary_o<=binary_mode;
     x_o<=ROI_X+best_x;y_o<=ROI_Y+best_y;score_o<=best_score;result_epoch_o<=snapshot_epoch;cycles_o<=cycles+1'b1;state<=IDLE;
    end
    default:state<=IDLE;
   endcase
   if(capture_i&&enabled)begin want_capture<=1;found_o<=0;result_seen<=0;end
  end
 end
endmodule
