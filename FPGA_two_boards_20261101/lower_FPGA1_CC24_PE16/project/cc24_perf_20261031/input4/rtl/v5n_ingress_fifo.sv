// Private drop-in; original depth/capacity/ready/valid/head cycle contract.
module v5n_ingress_fifo #(parameter integer ADDR_W=32,DEPTH=512,PTR_W=9)(
 input wire clk_i,rst_ni,push_i,output wire push_ready_o,
 input wire [ADDR_W-1:0] push_address_i,input wire signed [7:0] push_data_i,
 output wire pop_valid_o,input wire pop_ready_i,
 output wire [ADDR_W-1:0] pop_address_o,output wire signed [7:0] pop_data_o,
 output wire empty_o
);
 v5n_ingress_fifo_eram #(.ADDR_W(ADDR_W),.DEPTH(DEPTH),.PTR_W(PTR_W)) fifo_i(.*);
endmodule
