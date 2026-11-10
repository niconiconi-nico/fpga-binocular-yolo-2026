// Reliable UDP payload to signed-INT8 HWC image-memory ingress.
// The elastic output byte remains valid until the ingress FIFO accepts it.
// Completion and checksum are based only on accepted bytes.
module v5n_udp_image_frame_rx #(
 parameter integer ADDR_W=32,parameter integer IMAGE_BYTES=320*320*3
)(
 input wire clk_i,input wire rst_ni,input wire udp_rx_valid_i,input wire[7:0]udp_rx_data_i,input wire[15:0]udp_rx_length_i,
 output reg image_write_valid_o,input wire image_write_ready_i,output reg[ADDR_W-1:0]image_write_address_o,output reg signed[7:0]image_write_data_o,
 output reg image_frame_start_o,output reg image_frame_complete_o,output reg[31:0]image_frame_id_o,
 output wire[31:0]image_bytes_received_o,output wire[31:0]image_checksum_o,
 output reg overflow_error_o,output reg sequence_error_o,output reg error_o
);
 localparam integer HEADER_BYTES=20;
 reg in_packet_r,header_error_r,header_good_r,frame_valid_r;
 reg[15:0]byte_index_r,packet_length_r,packet_id_r,packet_count_r,expected_packet_r;
 reg[7:0]type_r;reg[31:0]frame_id_header_r,offset_r,next_offset_r,accepted_bytes_r,checksum_r;
 reg pending_packet_end_r,pending_frame_end_r;reg[31:0]pending_next_offset_r;
 wire pending_accept_w=image_write_valid_o&&image_write_ready_i;
 wire slot_available_w=!image_write_valid_o||image_write_ready_i;
 wire[31:0]payload_index_w=byte_index_r-HEADER_BYTES;
 wire[31:0]current_offset_w={udp_rx_data_i,offset_r[23:0]};
 wire last_udp_byte_w=(byte_index_r+1'b1>=packet_length_r);
 assign image_bytes_received_o=accepted_bytes_r;assign image_checksum_o=checksum_r;
 always @(posedge clk_i or negedge rst_ni)begin
  if(!rst_ni)begin
   in_packet_r<=0;header_error_r<=0;header_good_r<=0;frame_valid_r<=0;byte_index_r<=0;packet_length_r<=0;
   packet_id_r<=0;packet_count_r<=0;expected_packet_r<=0;type_r<=0;frame_id_header_r<=0;offset_r<=0;next_offset_r<=0;
   accepted_bytes_r<=0;checksum_r<=0;image_write_valid_o<=0;image_write_address_o<=0;image_write_data_o<=0;
   pending_packet_end_r<=0;pending_frame_end_r<=0;pending_next_offset_r<=0;
   image_frame_start_o<=0;image_frame_complete_o<=0;image_frame_id_o<=0;overflow_error_o<=0;sequence_error_o<=0;error_o<=0;
  end else begin
   image_frame_start_o<=0;image_frame_complete_o<=0;
   if(pending_accept_w)begin
    image_write_valid_o<=0;
    if(frame_valid_r)begin
     accepted_bytes_r<=accepted_bytes_r+1'b1;checksum_r<=checksum_r+{{24{1'b0}},image_write_data_o};
     if(pending_packet_end_r)begin
      next_offset_r<=pending_next_offset_r;expected_packet_r<=expected_packet_r+1'b1;
      if(pending_frame_end_r)begin
       if((accepted_bytes_r+1'b1==IMAGE_BYTES)&&(pending_next_offset_r==IMAGE_BYTES))image_frame_complete_o<=1;
       else begin sequence_error_o<=1;error_o<=1;frame_valid_r<=0;end
      end
     end
    end
   end
   if(udp_rx_valid_i)begin
    if(!in_packet_r)begin
     in_packet_r<=1;byte_index_r<=1;packet_length_r<=udp_rx_length_i;header_good_r<=0;
     header_error_r<=(udp_rx_data_i!=8'h59);
     type_r<=0;frame_id_header_r<=0;packet_id_r<=0;packet_count_r<=0;offset_r<=0;
     if(udp_rx_data_i!=8'h59)begin sequence_error_o<=1;error_o<=1;end
    end else begin
     case(byte_index_r)
      1:if(udp_rx_data_i!=8'h38)header_error_r<=1;2:if(udp_rx_data_i!=8'h4e)header_error_r<=1;
      3:if(udp_rx_data_i!=8'h33)header_error_r<=1;4:if(udp_rx_data_i!=8'd1)header_error_r<=1;
      5:begin type_r<=udp_rx_data_i;if((udp_rx_data_i==8'd1)&&(packet_length_r<=HEADER_BYTES))begin header_error_r<=1;sequence_error_o<=1;error_o<=1;end end
      8:frame_id_header_r[7:0]<=udp_rx_data_i;9:frame_id_header_r[15:8]<=udp_rx_data_i;
      10:frame_id_header_r[23:16]<=udp_rx_data_i;11:frame_id_header_r[31:24]<=udp_rx_data_i;
      12:packet_id_r[7:0]<=udp_rx_data_i;13:packet_id_r[15:8]<=udp_rx_data_i;
      14:packet_count_r[7:0]<=udp_rx_data_i;15:packet_count_r[15:8]<=udp_rx_data_i;
      16:offset_r[7:0]<=udp_rx_data_i;17:offset_r[15:8]<=udp_rx_data_i;18:offset_r[23:16]<=udp_rx_data_i;
      19:begin
       offset_r[31:24]<=udp_rx_data_i;
       if(type_r!=8'd1)header_good_r<=0;
       else if(header_error_r||packet_count_r==0||packet_id_r>=packet_count_r||current_offset_w>=IMAGE_BYTES||
               ((packet_id_r==0)&&(current_offset_w!=0))||
               ((packet_id_r!=0)&&((packet_id_r!=expected_packet_r)||(current_offset_w!=next_offset_r)||(frame_id_header_r!=image_frame_id_o))))begin
        header_good_r<=0;frame_valid_r<=0;sequence_error_o<=1;error_o<=1;
       end else begin
        header_good_r<=1;
        if(packet_id_r==0)begin frame_valid_r<=1;expected_packet_r<=0;next_offset_r<=0;accepted_bytes_r<=0;checksum_r<=0;
         image_frame_id_o<=frame_id_header_r;image_frame_start_o<=1;end
       end
      end
      default:if(header_good_r&&frame_valid_r)begin
       if(offset_r+payload_index_w>=IMAGE_BYTES)begin frame_valid_r<=0;sequence_error_o<=1;error_o<=1;end
       else if(slot_available_w)begin
        image_write_valid_o<=1;image_write_address_o<=offset_r+payload_index_w;image_write_data_o<=udp_rx_data_i;
        pending_packet_end_r<=last_udp_byte_w;pending_frame_end_r<=last_udp_byte_w&&(packet_id_r+1'b1==packet_count_r);
        pending_next_offset_r<=offset_r+payload_index_w+1'b1;
       end else begin frame_valid_r<=0;overflow_error_o<=1;error_o<=1;end
      end
     endcase
     if(last_udp_byte_w)in_packet_r<=0;else byte_index_r<=byte_index_r+1'b1;
    end
   end
  end
 end
endmodule
