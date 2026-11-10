// Real32x32 NCC or independent thresholded Hamming. Stream1024 actual pairs.
// C=1024*sum(TI)-sumT*sumI; V=1024*sum(P^2)-sumP^2.
// NCC accepts C>0,25*C^2>=16*VT*VI (rho>=0.8), minvariance explicitly.
// q8 score=max q: q^2*VT*VI<=65025*C^2, exact floor(255*rho).
// Widths: sums18, square/dot26, cov signed37,variance36,C^2/VT*VI72.
module template_score_core2 #(
 parameter integer BINARY_THRESHOLD=128,MAX_MISMATCH=128,MIN_TEMPLATE_ONES=64,
 parameter [35:0] MIN_VARIANCE=36'd16777216
)(input wire clk,rst_n,start_i,binary_i,pair_valid_i,input wire [7:0] template_i,image_i,
 output wire ready_o,output reg done_o,valid_o,hit_o,output reg [10:0] score_o,mismatch_o,
 output reg [71:0] covariance_squared_o,variance_product_o,output reg [35:0] image_variance_o);
 localparam IDLE=0,STREAM=1,STATS=2,TI_WAIT=3,TT_WAIT=4,II_WAIT=5,CSQ_WAIT=6,VP_WAIT=7,SCORE_WAIT=8;
 reg [3:0] state;reg binary_mode;reg [9:0] index;
 reg [17:0] sum_t,sum_i;reg [25:0] sum_tt,sum_ii,sum_ti;reg [10:0] mismatches,ones;
 reg signed [36:0] covariance;reg [35:0] vt,vi;reg [71:0] csq,vprod;
 reg [7:0] score,score_bit;
 reg mul_start;reg [127:0] mul_a,mul_b;wire mul_busy,mul_done;wire [255:0] mul_result;
 match_mul72x36_2 mul(clk,rst_n,mul_start,mul_a,mul_b,mul_busy,mul_done,mul_result);
 wire [15:0] tt=template_i*template_i,ii=image_i*image_i,ti=template_i*image_i;
 wire tb=template_i>=BINARY_THRESHOLD,ib=image_i>=BINARY_THRESHOLD;
 wire [7:0] trial=score|score_bit;wire [15:0] trial_squared=trial*trial;
 wire [35:0] vi_next={sum_ii,10'd0}-mul_result[35:0];
 wire [127:0] numerator=({56'd0,csq}<<16)-({56'd0,csq}<<9)+{56'd0,csq};
 wire [127:0] threshold_left=({56'd0,csq}<<4)+({56'd0,csq}<<3)+{56'd0,csq};
 assign ready_o=state==STREAM;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   state<=IDLE;binary_mode<=0;index<=0;sum_t<=0;sum_i<=0;sum_tt<=0;sum_ii<=0;sum_ti<=0;mismatches<=0;ones<=0;
   covariance<=0;vt<=0;vi<=0;csq<=0;vprod<=0;score<=0;score_bit<=0;mul_start<=0;mul_a<=0;mul_b<=0;
   done_o<=0;valid_o<=0;hit_o<=0;score_o<=0;mismatch_o<=0;covariance_squared_o<=0;variance_product_o<=0;image_variance_o<=0;
  end else begin
   done_o<=0;mul_start<=0;
   case(state)
    IDLE:if(start_i)begin
     binary_mode<=binary_i;index<=0;sum_t<=0;sum_i<=0;sum_tt<=0;sum_ii<=0;sum_ti<=0;mismatches<=0;ones<=0;
     valid_o<=0;hit_o<=0;score_o<=0;mismatch_o<=0;covariance_squared_o<=0;variance_product_o<=0;image_variance_o<=0;state<=STREAM;
    end
    STREAM:if(pair_valid_i)begin
     sum_t<=sum_t+template_i;sum_i<=sum_i+image_i;sum_tt<=sum_tt+tt;sum_ii<=sum_ii+ii;sum_ti<=sum_ti+ti;
     mismatches<=mismatches+(tb^ib);ones<=ones+tb;
     if(index==1023)state<=STATS;else index<=index+1'b1;
    end
    STATS:begin
     mismatch_o<=mismatches;
     if(binary_mode)begin
      valid_o<=ones>=MIN_TEMPLATE_ONES&&ones<=1024-MIN_TEMPLATE_ONES;
      hit_o<=ones>=MIN_TEMPLATE_ONES&&ones<=1024-MIN_TEMPLATE_ONES&&mismatches<=MAX_MISMATCH;
      score_o<=1024-mismatches;done_o<=1;state<=IDLE;
     end else begin mul_a<={110'd0,sum_t};mul_b<={110'd0,sum_i};mul_start<=1;state<=TI_WAIT;end
    end
    TI_WAIT:if(mul_done)begin
     covariance<=$signed({1'b0,sum_ti,10'd0})-$signed({1'b0,mul_result[35:0]});
     mul_a<={110'd0,sum_t};mul_b<={110'd0,sum_t};mul_start<=1;state<=TT_WAIT;
    end
    TT_WAIT:if(mul_done)begin
     vt<={sum_tt,10'd0}-mul_result[35:0];
     mul_a<={110'd0,sum_i};mul_b<={110'd0,sum_i};mul_start<=1;state<=II_WAIT;
    end
    II_WAIT:if(mul_done)begin
     vi<=vi_next;image_variance_o<=vi_next;
     if(covariance<=0||vt<MIN_VARIANCE||vi_next<MIN_VARIANCE)begin done_o<=1;valid_o<=0;hit_o<=0;score_o<=0;state<=IDLE;end
     else begin mul_a<={92'd0,covariance[35:0]};mul_b<={92'd0,covariance[35:0]};mul_start<=1;state<=CSQ_WAIT;end
    end
    CSQ_WAIT:if(mul_done)begin
     csq<=mul_result[71:0];covariance_squared_o<=mul_result[71:0];
     mul_a<={92'd0,vt};mul_b<={92'd0,vi};mul_start<=1;state<=VP_WAIT;
    end
    VP_WAIT:if(mul_done)begin
     vprod<=mul_result[71:0];variance_product_o<=mul_result[71:0];
     valid_o<=1;hit_o<=threshold_left>=({56'd0,mul_result[71:0]}<<4);
     score<=0;score_bit<=8'h80;mul_a<={56'd0,mul_result[71:0]};mul_b<=128'd16384;mul_start<=1;state<=SCORE_WAIT;
    end
    SCORE_WAIT:if(mul_done)begin
     if(mul_result<={128'd0,numerator})score<=trial;
     if(score_bit==1)begin score_o<={3'd0,(mul_result<={128'd0,numerator}?trial:score)};done_o<=1;state<=IDLE;end
     else begin
      score_bit<=score_bit>>1;
      mul_a<={56'd0,vprod};
      // Next binary-search trial depends on the completed comparison.
      if(mul_result<={128'd0,numerator})mul_b<=((trial|(score_bit>>1))*(trial|(score_bit>>1)));
      else mul_b<=((score|(score_bit>>1))*(score|(score_bit>>1)));
      mul_start<=1;
     end
    end
    default:state<=IDLE;
   endcase
  end
 end
endmodule
