// Isolated cycle-equivalent FWFT ingress FIFO. Internal RAM has synchronous
// read; a write-to-empty / simultaneous last-pop+push bypass preserves the
// original head/valid/empty timing. No packet/model change or private DDR.
module v5n_ingress_fifo_eram #(parameter integer ADDR_W=32,DEPTH=512,PTR_W=9)(
 input wire clk_i,rst_ni,push_i,output wire push_ready_o,
 input wire [ADDR_W-1:0] push_address_i,input wire signed [7:0] push_data_i,
 output wire pop_valid_o,input wire pop_ready_i,
 output wire [ADDR_W-1:0] pop_address_o,output wire signed [7:0] pop_data_o,
 output wire empty_o
);
 reg [ADDR_W+7:0] mem[0:DEPTH-1];
 reg [PTR_W-1:0] wr_r,rd_r;
 reg [PTR_W:0] count_r;
 reg [ADDR_W+7:0] ram_head_r,bypass_data_r;
 reg bypass_r;
 wire pop_w=pop_valid_o&&pop_ready_i,push_w=push_i&&push_ready_o;
 wire [PTR_W-1:0] next_head_w=rd_r+pop_w;
 wire bypass_w=push_w && (count_r==0 || (pop_w && count_r==1));
 assign push_ready_o=count_r<DEPTH;
 assign pop_valid_o=count_r!=0;
 assign empty_o=count_r==0;
 assign {pop_address_o,pop_data_o}=bypass_r?bypass_data_r:ram_head_r;
 // No RAM/data reset. Every exposed valid word was accepted after reset.
 // Independent synchronous read/write enables physical ERAM inference.
 always @(posedge clk_i)begin
  if(push_w)mem[wr_r]<={push_address_i,push_data_i};
  ram_head_r<=mem[next_head_w];
  if(bypass_w)bypass_data_r<={push_address_i,push_data_i};
 end
 always @(posedge clk_i or negedge rst_ni)begin
  if(!rst_ni)begin wr_r<=0;rd_r<=0;count_r<=0;bypass_r<=0;end
  else begin
   bypass_r<=bypass_w;
   if(push_w)wr_r<=wr_r+1'b1;
   if(pop_w)rd_r<=rd_r+1'b1;
   case({push_w,pop_w})
    2'b10:count_r<=count_r+1'b1;
    2'b01:count_r<=count_r-1'b1;
    default:count_r<=count_r;
   endcase
  end
 end
endmodule
