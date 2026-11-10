// Serial, bounded local translation search. Grayscale bytes are actual pixels.
// One outstanding paired read; response occurs >=1 edge after acceptance.
// The local memory service must flush its pending response on reset.
// Candidate row address is staged before ISSUE; accepted pixels increment
// registered addresses. No frame buffer, synthetic detection or extrapolation.
module local_sad8_1 #(
 parameter integer WIDTH=160, HEIGHT=90, PATCH=8, RADIUS=4,
 parameter integer MIN_TEXTURE=24, MAX_MEAN_SAD=20, MIN_MARGIN=64,
 parameter integer MAX_WAIT=1024
)(
 input wire clk,rst,start,
 input wire[7:0]template_x,template_y,
 output wire busy,
 output wire read_valid,input wire read_ready,
 output wire[13:0]reference_addr,current_addr,
 input wire response_valid,input wire[7:0]reference_pixel,current_pixel,
 output reg done,match_valid,output reg[2:0]reason,
 output reg signed[4:0]motion_x,motion_y,
 output reg[15:0]best_cost,second_cost,
 output reg[7:0]texture,
 output reg[7:0]candidate_count
);
 localparam IDLE=0,CHECK=1,ISSUE=2,WAIT_PIXEL=3,SCORE=4,NEXT=5,FINISH=6,
  ROW_SCALE=7,ROW_BASE=8;
 reg[3:0]state;
 reg[7:0]tx,ty,px,py,lo,hi;
 reg signed[5:0]dx,dy;
 reg[15:0]sum;
 reg[15:0]wait_count;
 reg signed[4:0]best_dx,best_dy;
 reg[10:0]candidate_x,candidate_y;
 reg[31:0]reference_row,current_row;
 reg[13:0]reference_addr_r,current_addr_r;
 wire signed[10:0]cx=$signed({3'd0,tx})+$signed(dx);
 wire signed[10:0]cy=$signed({3'd0,ty})+$signed(dy);
 wire legal=cx>=0&&cy>=0&&cx<=WIDTH-PATCH&&cy<=HEIGHT-PATCH;
 wire[8:0]difference=reference_pixel>=current_pixel?
  {1'b0,reference_pixel}-{1'b0,current_pixel}:{1'b0,current_pixel}-{1'b0,reference_pixel};
 assign busy=state!=IDLE;
 assign read_valid=state==ISSUE;
 assign reference_addr=reference_addr_r;
 assign current_addr=current_addr_r;
 always @(posedge clk or posedge rst)begin
  if(rst)begin
   state<=IDLE;tx<=0;ty<=0;px<=0;py<=0;lo<=255;hi<=0;dx<=0;dy<=0;
   sum<=0;wait_count<=0;best_dx<=0;best_dy<=0;done<=0;match_valid<=0;
   reason<=0;motion_x<=0;motion_y<=0;best_cost<=65535;second_cost<=65535;
   texture<=0;candidate_count<=0;
   candidate_x<=0;candidate_y<=0;reference_row<=0;current_row<=0;
   reference_addr_r<=0;current_addr_r<=0;
  end else begin
   done<=0;
   case(state)
    IDLE:if(start)begin
     tx<=template_x;ty<=template_y;dx<=-RADIUS;dy<=-RADIUS;
     best_cost<=65535;second_cost<=65535;best_dx<=0;best_dy<=0;
     candidate_count<=0;lo<=255;hi<=0;texture<=0;match_valid<=0;reason<=0;
     motion_x<=0;motion_y<=0;wait_count<=0;
     if(template_x>WIDTH-PATCH||template_y>HEIGHT-PATCH)begin
      reason<=4;done<=1;
     end else state<=CHECK;
    end
    CHECK:begin
     px<=0;py<=0;sum<=0;wait_count<=0;
     candidate_x<=cx;candidate_y<=cy;
     state<=legal?ROW_SCALE:NEXT;
    end
    ROW_SCALE:begin
     reference_row<=ty*WIDTH;current_row<=candidate_y*WIDTH;
     state<=ROW_BASE;
    end
    ROW_BASE:begin
     reference_addr_r<=reference_row+tx;
     current_addr_r<=current_row+candidate_x;
     state<=ISSUE;
    end
    ISSUE:begin
     if(read_ready)begin wait_count<=0;state<=WAIT_PIXEL;end
     else if(wait_count==MAX_WAIT-1)begin reason<=5;done<=1;state<=IDLE;end
     else wait_count<=wait_count+1'b1;
    end
    WAIT_PIXEL:begin
     if(response_valid)begin
      sum<=sum+difference;wait_count<=0;
      if(reference_pixel<lo)lo<=reference_pixel;
      if(reference_pixel>hi)hi<=reference_pixel;
      if(px==PATCH-1&&py==PATCH-1)state<=SCORE;
      else begin
       if(px==PATCH-1)begin
        px<=0;py<=py+1'b1;
        reference_addr_r<=reference_addr_r+(WIDTH-PATCH+1);
        current_addr_r<=current_addr_r+(WIDTH-PATCH+1);
       end else begin
        px<=px+1'b1;
        reference_addr_r<=reference_addr_r+1'b1;
        current_addr_r<=current_addr_r+1'b1;
       end
       state<=ISSUE;
      end
     end else if(wait_count==MAX_WAIT-1)begin reason<=5;done<=1;state<=IDLE;end
     else wait_count<=wait_count+1'b1;
    end
    SCORE:begin
     candidate_count<=candidate_count+1'b1;
     if(sum<best_cost)begin
      second_cost<=best_cost;best_cost<=sum;best_dx<=dx;best_dy<=dy;
     end else if(sum<second_cost)second_cost<=sum;
     state<=NEXT;
    end
    NEXT:begin
     if(dx==RADIUS)begin
      dx<=-RADIUS;
      if(dy==RADIUS)state<=FINISH;
      else begin dy<=dy+1'b1;state<=CHECK;end
     end else begin dx<=dx+1'b1;state<=CHECK;end
    end
    FINISH:begin
     texture<=hi-lo;motion_x<=best_dx;motion_y<=best_dy;
     if(candidate_count<2)reason<=4;
     else if(hi-lo<MIN_TEXTURE)reason<=1;
     else if(best_cost>PATCH*PATCH*MAX_MEAN_SAD)reason<=2;
     else if(second_cost-best_cost<MIN_MARGIN)reason<=3;
     else begin reason<=0;match_valid<=1;end
     done<=1;state<=IDLE;
    end
    default:begin state<=IDLE;match_valid<=0;reason<=5;done<=1;end
   endcase
  end
 end
endmodule
