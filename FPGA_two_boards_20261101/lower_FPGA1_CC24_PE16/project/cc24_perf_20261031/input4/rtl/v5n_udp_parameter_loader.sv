// Own private section lengths; packet parser/commit protocol unchanged.
// Reliable type-3 loader for weights, bias, requant and LUT images.
// Completion/checksum advance only when the ingress FIFO accepts a byte.
module v5n_udp_parameter_loader #(
 parameter integer ADDR_W=32,parameter[ADDR_W-1:0]WEIGHT_BASE=32'h01000000,BIAS_BASE=32'h01400000,
 parameter[ADDR_W-1:0]REQUANT_BASE=32'h01500000,LUT_BASE=32'h01600000
)(
 input wire clk_i,input wire rst_ni,input wire udp_rx_valid_i,input wire[7:0]udp_rx_data_i,input wire[15:0]udp_rx_length_i,
 output reg memory_write_valid_o,input wire memory_write_ready_i,output wire[ADDR_W-1:0]memory_write_address_o,output wire signed[7:0]memory_write_data_o,
 output reg parameters_complete_o,output wire[3:0]section_complete_o,
 output wire[31:0]weight_bytes_received_o,bias_bytes_received_o,requant_bytes_received_o,lut_bytes_received_o,
 output wire[31:0]weight_checksum_o,bias_checksum_o,requant_checksum_o,lut_checksum_o,
 output reg overflow_error_o,output reg sequence_error_o,output reg error_o
);
 localparam integer HEADER_BYTES=20;
 reg in_packet_r,header_good_r,header_error_r;wire[15:0]byte_index_r;reg[15:0]packet_length_r,packet_id_r,packet_count_r;
 reg[7:0]type_r,region_r;reg[31:0]offset_r;wire[15:0]expected_packet_r[0:3];
 wire[31:0]next_offset_r[0:3],accepted_r[0:3],checksum_r[0:3];reg[3:0]complete_mask_r,section_valid_r;integer k;
 wire pending_packet_end_r,pending_section_end_r;wire[1:0]pending_region_r;wire[31:0]pending_next_offset_r;
 reg[ADDR_W-1:0]region_base_r;reg[31:0]region_size_r;
 wire[31:0]payload_index_w=byte_index_r-HEADER_BYTES;wire[31:0]current_offset_w={udp_rx_data_i,offset_r[23:0]};
 wire last_udp_byte_w=(byte_index_r+1'b1>=packet_length_r);wire pending_accept_w=memory_write_valid_o&&memory_write_ready_i;
 wire slot_available_w=!memory_write_valid_o||memory_write_ready_i;
 assign section_complete_o=complete_mask_r;
 assign weight_bytes_received_o=accepted_r[0];assign bias_bytes_received_o=accepted_r[1];
 assign requant_bytes_received_o=accepted_r[2];assign lut_bytes_received_o=accepted_r[3];
 assign weight_checksum_o=checksum_r[0];assign bias_checksum_o=checksum_r[1];
 assign requant_checksum_o=checksum_r[2];assign lut_checksum_o=checksum_r[3];
 always @* begin case(region_r)
  0:begin region_base_r=WEIGHT_BASE;region_size_r=32'd1759744;end
  1:begin region_base_r=BIAS_BASE;region_size_r=32'd19344;end
  2:begin region_base_r=REQUANT_BASE;region_size_r=32'd19344;end
  default:begin region_base_r=LUT_BASE;region_size_r=32'd17760;end endcase end
 // EXACT successful header branch, including all original malformed/order guards.
 // This event has priority over an old pending accept in the SAME bank, as
 // the original later nonblocking assignment. Different banks update together.
 wire restart_bank_w=udp_rx_valid_i&&in_packet_r&&(byte_index_r==19)&&(type_r==3)&&
   (region_r<4)&&!header_error_r&&(packet_count_r!=0)&&(packet_id_r==0)&&
   (packet_id_r<packet_count_r)&&(current_offset_w==0)&&(current_offset_w<region_size_r);
 // Exact original case-default and payload offer condition. UDP has no
 // ready; no new serialization, queue or assumed boot/video exclusion.
 reg payload_case_w;
 always @* begin case(byte_index_r)
  1,2,3,4,5,6,12,13,14,15,16,17,18,19:payload_case_w=0;
  default:payload_case_w=1;
 endcase end
 wire offer_w=udp_rx_valid_i&&in_packet_r&&payload_case_w&&header_good_r&&
   section_valid_r[region_r]&&(offset_r+payload_index_w<region_size_r)&&slot_available_w;
 wire[31:0]offer_next_offset_w=offset_r+payload_index_w+1'b1;
 r10_parser_dsp_state #(.WIDTH(16)) byte_index_state(
  .clk(clk_i),.rst_n(rst_ni),.load_i(udp_rx_valid_i&&!in_packet_r),.load_value_i(16'd1),
  .step_i(udp_rx_valid_i&&in_packet_r&&!last_udp_byte_w),.increment_i(16'd1),.value_o(byte_index_r));
 // CC24 PERF PE16: load-only fields use ordinary registers; two DSPs
 // are reassigned to inference. The exact same offer event owns every field.
 reg [ADDR_W-1:0] address_hold_r;
 reg [43:0] pending_hold_r;
 assign memory_write_address_o=address_hold_r;
 assign {pending_packet_end_r,pending_section_end_r,pending_region_r,pending_next_offset_r,memory_write_data_o}=pending_hold_r;
 always @(posedge clk_i or negedge rst_ni) begin
  if(!rst_ni) begin address_hold_r<=0;pending_hold_r<=0;end
  else if(offer_w) begin
   address_hold_r<=region_base_r+offset_r+payload_index_w;
   pending_hold_r<={last_udp_byte_w,last_udp_byte_w&&(packet_id_r+1'b1==packet_count_r),region_r[1:0],offer_next_offset_w,udp_rx_data_i};
  end
 end
 for(genvar bank=0;bank<4;bank=bank+1)begin:BANK_DSP
  wire clear_bank=restart_bank_w&&(region_r==bank);
  wire step_bank=pending_accept_w&&section_valid_r[pending_region_r]&&(pending_region_r==bank);
  wire end_bank=step_bank&&pending_packet_end_r;
  r10_parser_dsp_state #(.WIDTH(16)) expected_packet_state(
   .clk(clk_i),.rst_n(rst_ni),.load_i(clear_bank),.load_value_i(16'd0),
   .step_i(end_bank),.increment_i(16'd1),.value_o(expected_packet_r[bank]));
  r10_parser_dsp_state #(.WIDTH(32)) next_offset_state(
   .clk(clk_i),.rst_n(rst_ni),.load_i(clear_bank||end_bank),
   .load_value_i(clear_bank?32'd0:pending_next_offset_r),.step_i(1'b0),
   .increment_i(32'd0),.value_o(next_offset_r[bank]));
  r10_parser_dsp_acc32 bytes_acc(.clk(clk_i),.rst_n(rst_ni),.clear_i(clear_bank),
   .step_i(step_bank),.increment_i(32'd1),.value_o(accepted_r[bank]));
  r10_parser_dsp_acc32 checksum_acc(.clk(clk_i),.rst_n(rst_ni),.clear_i(clear_bank),
   .step_i(step_bank),.increment_i({24'd0,memory_write_data_o}),.value_o(checksum_r[bank]));
 end
 always @(posedge clk_i or negedge rst_ni)begin
  if(!rst_ni)begin
   in_packet_r<=0;header_good_r<=0;header_error_r<=0;packet_length_r<=0;packet_id_r<=0;packet_count_r<=0;type_r<=0;region_r<=0;offset_r<=0;
   complete_mask_r<=0;section_valid_r<=0;parameters_complete_o<=0;memory_write_valid_o<=0;
   
   overflow_error_o<=0;sequence_error_o<=0;error_o<=0;
  end else begin
   if(pending_accept_w)begin
    memory_write_valid_o<=0;
    if(section_valid_r[pending_region_r])begin
     if(pending_packet_end_r)begin
      if(pending_section_end_r)begin
       case(pending_region_r)
        0:if((accepted_r[0]+1'b1==32'd1759744)&&(pending_next_offset_r==32'd1759744))complete_mask_r[0]<=1;else begin section_valid_r[0]<=0;sequence_error_o<=1;error_o<=1;end
        1:if((accepted_r[1]+1'b1==32'd19344)&&(pending_next_offset_r==32'd19344))complete_mask_r[1]<=1;else begin section_valid_r[1]<=0;sequence_error_o<=1;error_o<=1;end
        2:if((accepted_r[2]+1'b1==32'd19344)&&(pending_next_offset_r==32'd19344))complete_mask_r[2]<=1;else begin section_valid_r[2]<=0;sequence_error_o<=1;error_o<=1;end
        3:if((accepted_r[3]+1'b1==32'd17760)&&(pending_next_offset_r==32'd17760))complete_mask_r[3]<=1;else begin section_valid_r[3]<=0;sequence_error_o<=1;error_o<=1;end
       endcase
       if(&(complete_mask_r|(4'b0001<<pending_region_r)))parameters_complete_o<=1;
      end
     end
    end
   end
   if(udp_rx_valid_i)begin
    if(!in_packet_r)begin
     in_packet_r<=1;packet_length_r<=udp_rx_length_i;header_good_r<=0;
     header_error_r<=(udp_rx_data_i!=8'h59);type_r<=0;region_r<=0;packet_id_r<=0;packet_count_r<=0;offset_r<=0;
     if(udp_rx_data_i!=8'h59)begin sequence_error_o<=1;error_o<=1;end
    end else begin
     case(byte_index_r)
      1:if(udp_rx_data_i!=8'h38)header_error_r<=1;2:if(udp_rx_data_i!=8'h4e)header_error_r<=1;
      3:if(udp_rx_data_i!=8'h33)header_error_r<=1;4:if(udp_rx_data_i!=1)header_error_r<=1;
      5:begin type_r<=udp_rx_data_i;if((udp_rx_data_i==8'd3)&&(packet_length_r<=HEADER_BYTES))begin header_error_r<=1;sequence_error_o<=1;error_o<=1;end end
      6:region_r<=udp_rx_data_i;
      12:packet_id_r[7:0]<=udp_rx_data_i;13:packet_id_r[15:8]<=udp_rx_data_i;14:packet_count_r[7:0]<=udp_rx_data_i;15:packet_count_r[15:8]<=udp_rx_data_i;
      16:offset_r[7:0]<=udp_rx_data_i;17:offset_r[15:8]<=udp_rx_data_i;18:offset_r[23:16]<=udp_rx_data_i;
      19:begin
       offset_r[31:24]<=udp_rx_data_i;
       if(type_r!=3)header_good_r<=0;
       else if(region_r>3)begin header_good_r<=0;sequence_error_o<=1;error_o<=1;end
       else if(header_error_r||packet_count_r==0||packet_id_r>=packet_count_r||current_offset_w>=region_size_r||
               ((packet_id_r==0)&&(current_offset_w!=0))||
               ((packet_id_r!=0)&&((packet_id_r!=expected_packet_r[region_r])||(current_offset_w!=next_offset_r[region_r]))))begin
        header_good_r<=0;section_valid_r[region_r]<=0;sequence_error_o<=1;error_o<=1;
       end else begin
        header_good_r<=1;
        if(packet_id_r==0)begin section_valid_r[region_r]<=1;
         complete_mask_r[region_r]<=0;parameters_complete_o<=0;end
       end
      end
      default:if(header_good_r&&section_valid_r[region_r])begin
       if(offset_r+payload_index_w>=region_size_r)begin section_valid_r[region_r]<=0;sequence_error_o<=1;error_o<=1;end
       else if(slot_available_w)begin
        memory_write_valid_o<=1;
       end else begin section_valid_r[region_r]<=0;overflow_error_o<=1;error_o<=1;end
      end
     endcase
     if(last_udp_byte_w)in_packet_r<=0;
    end
   end
  end
 end
endmodule
