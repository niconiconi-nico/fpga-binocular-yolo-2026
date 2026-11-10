// Application-side request persistence, with unchanged vendor/wire/payload semantics.
module v5n_udp_request_hold(
 input wire clk_i,input wire rst_ni,input wire request_i,input wire grant_i,
 output wire request_o
);
 reg pending_r;
 always @(posedge clk_i or negedge rst_ni)begin
  if(!rst_ni)pending_r<=1'b0;
  else if(grant_i)pending_r<=1'b0;
  else if(request_i)pending_r<=1'b1;
 end
 assign request_o=request_i|pending_r;
endmodule
