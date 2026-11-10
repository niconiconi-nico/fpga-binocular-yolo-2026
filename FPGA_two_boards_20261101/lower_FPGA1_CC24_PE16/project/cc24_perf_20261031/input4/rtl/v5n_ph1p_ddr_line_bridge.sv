// Diagnostic equivalent storage alternative. Same eight total read credits.
// Synchronous BRAM read adds a valid staging slot; credit is freed only when
// the final consumer accepts it, not when RAM fetches into that slot.
module v5n_ph1p_ddr_line_bridge(
 input wire clk_i,input wire rst_ni,input wire req_valid_i,output wire req_ready_o,input wire req_write_i,input wire[27:0]req_line_address_i,
 input wire[127:0]req_write_data_i,input wire[15:0]req_write_strobe_i,output wire read_valid_o,input wire read_ready_i,output wire[127:0]read_data_o,
 output wire[24:0]mc_app_addr_o,output wire[2:0]mc_app_cmd_o,output wire mc_app_en_o,input wire mc_app_rdy_i,
 output wire[127:0]mc_wdf_data_o,output wire mc_wdf_end_o,output wire[15:0]mc_wdf_mask_o,output wire mc_wdf_wren_o,input wire mc_wdf_rdy_i,
 input wire[127:0]mc_read_data_i,input wire mc_read_valid_i
);
 (* ram_style="bram" *) reg [127:0] response[0:7];
 reg [127:0] front_data;
 reg front_valid;
 reg [2:0] wrptr,rdptr;
 reg [3:0] reserved,available;
 wire accept=req_valid_i&&req_ready_o;
 wire issue=accept&&!req_write_i;
 wire consume=read_valid_o&&read_ready_i;
 wire fetch=(available!=0)&&(!front_valid||consume);
 assign req_ready_o=req_write_i?(mc_app_rdy_i&&mc_wdf_rdy_i):(mc_app_rdy_i&&(reserved<8));
 assign mc_app_en_o=accept;
 assign mc_app_cmd_o=req_write_i?3'd0:3'd1;
 assign mc_app_addr_o={req_line_address_i[21:0],3'b000};
 assign mc_wdf_wren_o=accept&&req_write_i;
 assign mc_wdf_end_o=mc_wdf_wren_o;
 assign mc_wdf_data_o=req_write_data_i;
 assign mc_wdf_mask_o=~req_write_strobe_i;
 assign read_valid_o=front_valid;
 assign read_data_o=front_data;
 always @(posedge clk_i)begin
   if(mc_read_valid_i&&rst_ni)response[wrptr]<=mc_read_data_i;
   if(fetch&&rst_ni)front_data<=response[rdptr];
 end
 always @(posedge clk_i or negedge rst_ni)begin
   if(!rst_ni)begin wrptr<=0;rdptr<=0;reserved<=0;available<=0;front_valid<=0;end
   else begin
     case({issue,consume})
       2'b10:reserved<=reserved+1'b1;
       2'b01:reserved<=reserved-1'b1;
     endcase
     case({mc_read_valid_i,fetch})
       2'b10:available<=available+1'b1;
       2'b01:available<=available-1'b1;
     endcase
     if(mc_read_valid_i)wrptr<=wrptr+1'b1;
     if(fetch)begin rdptr<=rdptr+1'b1;front_valid<=1;end
     else if(consume)front_valid<=0;
   end
 end
`ifndef SYNTHESIS
 always @(posedge clk_i)if(rst_ni)begin
   if(({1'b0,available}+front_valid)>reserved||reserved>8)$fatal(1,"MC response credit invariant");
   if(mc_read_valid_i&&(({1'b0,available}+front_valid)==reserved)&&!issue)$fatal(1,"unsolicited MC response");
   if(mc_wdf_wren_o&&(!mc_app_rdy_i||!mc_wdf_rdy_i))$fatal(1,"premature write commit");
   if(fetch&&mc_read_valid_i&&rdptr==wrptr)$fatal(1,"RAM same-address collision");
 end
`endif
endmodule
