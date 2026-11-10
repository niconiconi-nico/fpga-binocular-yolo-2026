// Exact for the documented NCC domain: A<=72bits,B<=36bits,product<=108.
// Interface zero-extends the exact product.36serial clocks,108bit adder.
// Caller operands: sums18,square/dot covariance36,variance36 or variance
// product72 and trial-square16; normalized ranking72x36. No lost precision.
module match_mul72x36_2(input wire clk,rst_n,start_i,input wire[127:0] a_i,b_i,
 output reg busy_o,done_o,output reg[255:0] result_o);
 reg[107:0] shifted,acc;reg[35:0] bits;reg[5:0] count;
 wire[107:0] next_acc=acc+(bits[0]?shifted:108'd0);
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin busy_o<=0;done_o<=0;result_o<=0;shifted<=0;acc<=0;bits<=0;count<=0;end
  else begin
   done_o<=0;
   if(start_i&&!busy_o)begin busy_o<=1;shifted<={36'd0,a_i[71:0]};bits<=b_i[35:0];acc<=0;count<=0;end
   else if(busy_o)begin
    acc<=next_acc;shifted<=shifted<<1;bits<=bits>>1;
    if(count==35)begin result_o<={148'd0,next_acc};busy_o<=0;done_o<=1;end else count<=count+1'b1;
   end
  end
 end
endmodule
