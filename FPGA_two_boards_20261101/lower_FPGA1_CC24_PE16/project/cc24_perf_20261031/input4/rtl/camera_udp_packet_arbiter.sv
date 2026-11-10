// One existing vendor UDP stack, two applications (video0 / inference1).
// O_W_udp_busy is a grant. It is exposed only to the latched packet owner,
// never as free/busy readiness to an unselected application.
module camera_udp_packet_arbiter(
 input wire clk,rst_n,input wire [1:0] request_i,valid_i,
 input wire [15:0] data_i,input wire [31:0] length_i,output wire [1:0] grant_o,
 output wire request_o,valid_o,output wire [7:0] data_o,output wire [15:0] length_o,
 input wire vendor_busy_i,output wire active_o
);
 reg active,owner,prefer;reg [15:0] length;reg [15:0] sent;reg granted;
 assign active_o=active;
 assign request_o=active&&!granted;
 assign valid_o=active&&granted&&valid_i[owner];
 assign data_o=owner?data_i[15:8]:data_i[7:0];assign length_o=length;
 assign grant_o=active?(owner?{vendor_busy_i,1'b0}:{1'b0,vendor_busy_i}):2'b0;
 always @(posedge clk or negedge rst_n)begin
   if(!rst_n)begin active<=0;owner<=0;prefer<=1;length<=0;sent<=0;granted<=0;end
   else begin
     if(!active&&!vendor_busy_i&&|request_i)begin
       active<=1;owner<=request_i[prefer]?prefer:!prefer;
       length<=request_i[prefer]?length_i[prefer*16+:16]:length_i[(!prefer)*16+:16];
       sent<=0;granted<=0;
     end
     if(active&&!granted&&vendor_busy_i)granted<=1;
     if(valid_o)sent<=sent+1'b1;
     if(active&&granted&&sent==length&&!vendor_busy_i)begin active<=0;prefer<=!owner;end
   end
 end
endmodule
