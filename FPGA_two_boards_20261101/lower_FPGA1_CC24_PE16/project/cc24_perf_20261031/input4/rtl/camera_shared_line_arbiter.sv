// Isolated implementation-equivalence experiment; no resource/physical claim.
// Four-client in-order transport prototype. Eight read-owner credits; capture
// writes retain priority and do not wait for a slow read consumer. No write
// buffering/early acknowledgement is introduced. Backend must preserve order.
module camera_shared_line_arbiter(
 input wire clk,rst_n,input wire [3:0] req_valid_i,output reg [3:0] req_ready_o,
 input wire [3:0] req_write_i,input wire [111:0] req_address_i,
 input wire [511:0] req_data_i,input wire [63:0] req_strobe_i,
 output reg [3:0] read_valid_o,input wire [3:0] read_ready_i,output wire [511:0] read_data_o,
 output wire memory_req_valid_o,input wire memory_req_ready_i,output wire memory_req_write_o,
 output wire [27:0] memory_req_address_o,output wire [127:0] memory_req_data_o,output wire [15:0] memory_req_strobe_o,
 input wire memory_read_valid_i,output wire memory_read_ready_o,input wire [127:0] memory_read_data_i,
 output wire [1:0] selected_client_o,output wire read_pending_o
);
 reg [1:0] round_robin,owners[0:7];
 reg [3:0] count;
 genvar slot;
 reg selected_valid;reg [1:0] selected;
 wire [3:0] eligible=req_valid_i & (req_write_i | {4{count<8}});
 wire [3:0] lane_select={selected==3,selected==2,selected==1,selected==0};
 wire [3:0] owner_select={owners[0]==3,owners[0]==2,owners[0]==1,owners[0]==0};
 wire accept=memory_req_valid_o&&memory_req_ready_i;
 wire push=accept&&!memory_req_write_o;
 wire pop=memory_read_valid_i&&memory_read_ready_o;
 always @*begin
   selected_valid=0;selected=0;
   if(eligible[0])begin selected_valid=1;selected=0;end
   else case(round_robin)
     2'd1:begin
       if(eligible[1])begin selected_valid=1;selected=1;end
       else if(eligible[2])begin selected_valid=1;selected=2;end
       else if(eligible[3])begin selected_valid=1;selected=3;end
     end
     2'd2:begin
       if(eligible[2])begin selected_valid=1;selected=2;end
       else if(eligible[3])begin selected_valid=1;selected=3;end
       else if(eligible[1])begin selected_valid=1;selected=1;end
     end
     2'd3:begin
       if(eligible[3])begin selected_valid=1;selected=3;end
       else if(eligible[1])begin selected_valid=1;selected=1;end
       else if(eligible[2])begin selected_valid=1;selected=2;end
     end
     default:begin // Unreachable after reset; preserve old loop's 0,1,2 order.
       if(eligible[1])begin selected_valid=1;selected=1;end
       else if(eligible[2])begin selected_valid=1;selected=2;end
     end
   endcase
   req_ready_o=lane_select & {4{selected_valid&&memory_req_ready_i}};
   read_valid_o=owner_select & {4{(count!=0)&&memory_read_valid_i}};
 end
 assign memory_req_valid_o=selected_valid;
 assign memory_req_write_o=|(req_write_i & lane_select);
 assign memory_req_address_o=({28{lane_select[0]}}&req_address_i[27:0]) |
                            ({28{lane_select[1]}}&req_address_i[55:28]) |
                            ({28{lane_select[2]}}&req_address_i[83:56]) |
                            ({28{lane_select[3]}}&req_address_i[111:84]);
 assign memory_req_data_o=({128{lane_select[0]}}&req_data_i[127:0]) |
                         ({128{lane_select[1]}}&req_data_i[255:128]) |
                         ({128{lane_select[2]}}&req_data_i[383:256]) |
                         ({128{lane_select[3]}}&req_data_i[511:384]);
 assign memory_req_strobe_o=({16{lane_select[0]}}&req_strobe_i[15:0]) |
                           ({16{lane_select[1]}}&req_strobe_i[31:16]) |
                           ({16{lane_select[2]}}&req_strobe_i[47:32]) |
                           ({16{lane_select[3]}}&req_strobe_i[63:48]);
 assign memory_read_ready_o=(count!=0)&&(|(read_ready_i & owner_select));
 assign read_data_o={4{memory_read_data_i}};
 assign selected_client_o=selected;
 assign read_pending_o=(count!=0);
 always @(posedge clk or negedge rst_n)begin
   if(!rst_n)begin round_robin<=1;count<=0;end
   else begin
     case({push,pop})2'b10:count<=count+1'b1;2'b01:count<=count-1'b1;endcase
     if(accept&&selected!=0)round_robin<=(selected==3)?1:selected+1'b1;
   end
 end
 // Same eight-entry ordered queue, explicit shift on consumption.
 // No dynamic memory read index and no circular pointer control.
 // Queue storage is intentionally not reset; count masks unused entries.
 generate for(slot=0;slot<8;slot=slot+1)begin: owner_shift
   always @(posedge clk) if(rst_n)begin
     if(push&&((!pop&&count==slot)||(pop&&count==slot+1)))
       owners[slot]<=selected;
     else if(pop)begin
       if(slot<7)owners[slot]<=owners[(slot+1)%8];
     end
   end
 end endgenerate
`ifndef SYNTHESIS
 always @(posedge clk)if(rst_n)begin
   if(count>8)$fatal(1,"owner credit overflow");
   if(memory_read_valid_i&&count==0)$fatal(1,"response has no owner");
 end
`endif
endmodule
