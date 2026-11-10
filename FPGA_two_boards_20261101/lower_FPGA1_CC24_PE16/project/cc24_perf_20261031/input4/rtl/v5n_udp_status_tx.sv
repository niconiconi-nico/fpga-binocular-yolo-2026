// Compact, read-only status response for board bring-up (UDP protocol type 4).
module v5n_udp_status_tx(
 input wire clk_i,input wire rst_ni,input wire start_i,input wire udp_busy_i,
 input wire[3:0]parameter_mask_i,input wire[7:0]flags_i,input wire[15:0]last_error_i,
 input wire[31:0]frame_id_i,image_bytes_i,weight_bytes_i,bias_bytes_i,requant_bytes_i,lut_bytes_i,
 input wire[31:0]image_checksum_i,weight_checksum_i,bias_checksum_i,requant_checksum_i,lut_checksum_i,
 input wire[7:0]active_layer_i,input wire[3:0]active_opcode_i,input wire[1:0]scheduler_state_i,
 input wire[2:0]service_state_i,input wire[3:0]selected_runtime_i,input wire[2:0]bridge_state_i,
 input wire[3:0]memory_state_i,input wire[9:0]tile_x_i,tile_y_i,channel_slice_i,
 input wire[47:0]layer_cycles_i,total_cycles_i,input wire[8:0]detection_count_i,
 output reg udp_request_o,output reg udp_valid_o,output reg[7:0]udp_data_o,output wire[15:0]udp_length_o,
 output reg busy_o,output reg done_o
);
 localparam[1:0]ST_IDLE=0,ST_REQUEST=1,ST_SEND=2,ST_DONE=3;
 localparam[15:0]STATUS_BYTES=16'd84;
 reg[1:0]state_r;reg[6:0]byte_r,data_index_r;
 assign udp_length_o=STATUS_BYTES;
 always @* begin
  case(data_index_r)
   0:udp_data_o=8'h59;1:udp_data_o=8'h38;2:udp_data_o=8'h4e;3:udp_data_o=8'h33;
   4:udp_data_o=8'd1;5:udp_data_o=8'd4;6:udp_data_o=8'd0;7:udp_data_o={4'd0,parameter_mask_i};
   8:udp_data_o=flags_i;9:udp_data_o={4'd0,active_opcode_i};10:udp_data_o=active_layer_i;
   11:udp_data_o={5'd0,service_state_i};12:udp_data_o={4'd0,selected_runtime_i};
   13:udp_data_o={5'd0,bridge_state_i};14:udp_data_o={6'd0,scheduler_state_i};15:udp_data_o={4'd0,memory_state_i};
   16:udp_data_o=last_error_i[7:0];17:udp_data_o=last_error_i[15:8];
   18:udp_data_o=detection_count_i[7:0];19:udp_data_o={7'd0,detection_count_i[8]};
   20:udp_data_o=frame_id_i[7:0];21:udp_data_o=frame_id_i[15:8];22:udp_data_o=frame_id_i[23:16];23:udp_data_o=frame_id_i[31:24];
   24:udp_data_o=image_bytes_i[7:0];25:udp_data_o=image_bytes_i[15:8];26:udp_data_o=image_bytes_i[23:16];27:udp_data_o=image_bytes_i[31:24];
   28:udp_data_o=weight_bytes_i[7:0];29:udp_data_o=weight_bytes_i[15:8];30:udp_data_o=weight_bytes_i[23:16];31:udp_data_o=weight_bytes_i[31:24];
   32:udp_data_o=bias_bytes_i[7:0];33:udp_data_o=bias_bytes_i[15:8];34:udp_data_o=bias_bytes_i[23:16];35:udp_data_o=bias_bytes_i[31:24];
   36:udp_data_o=requant_bytes_i[7:0];37:udp_data_o=requant_bytes_i[15:8];38:udp_data_o=requant_bytes_i[23:16];39:udp_data_o=requant_bytes_i[31:24];
   40:udp_data_o=lut_bytes_i[7:0];41:udp_data_o=lut_bytes_i[15:8];42:udp_data_o=lut_bytes_i[23:16];43:udp_data_o=lut_bytes_i[31:24];
   44:udp_data_o=image_checksum_i[7:0];45:udp_data_o=image_checksum_i[15:8];46:udp_data_o=image_checksum_i[23:16];47:udp_data_o=image_checksum_i[31:24];
   48:udp_data_o=weight_checksum_i[7:0];49:udp_data_o=weight_checksum_i[15:8];50:udp_data_o=weight_checksum_i[23:16];51:udp_data_o=weight_checksum_i[31:24];
   52:udp_data_o=bias_checksum_i[7:0];53:udp_data_o=bias_checksum_i[15:8];54:udp_data_o=bias_checksum_i[23:16];55:udp_data_o=bias_checksum_i[31:24];
   56:udp_data_o=requant_checksum_i[7:0];57:udp_data_o=requant_checksum_i[15:8];58:udp_data_o=requant_checksum_i[23:16];59:udp_data_o=requant_checksum_i[31:24];
   60:udp_data_o=lut_checksum_i[7:0];61:udp_data_o=lut_checksum_i[15:8];62:udp_data_o=lut_checksum_i[23:16];63:udp_data_o=lut_checksum_i[31:24];
   64:udp_data_o=tile_x_i[7:0];65:udp_data_o={6'd0,tile_x_i[9:8]};66:udp_data_o=tile_y_i[7:0];67:udp_data_o={6'd0,tile_y_i[9:8]};
   68:udp_data_o=channel_slice_i[7:0];69:udp_data_o={6'd0,channel_slice_i[9:8]};
   70:udp_data_o=layer_cycles_i[7:0];71:udp_data_o=layer_cycles_i[15:8];72:udp_data_o=layer_cycles_i[23:16];
   73:udp_data_o=layer_cycles_i[31:24];74:udp_data_o=layer_cycles_i[39:32];75:udp_data_o=layer_cycles_i[47:40];
   76:udp_data_o=total_cycles_i[7:0];77:udp_data_o=total_cycles_i[15:8];78:udp_data_o=total_cycles_i[23:16];
   79:udp_data_o=total_cycles_i[31:24];80:udp_data_o=total_cycles_i[39:32];81:udp_data_o=total_cycles_i[47:40];
   82:udp_data_o=8'h43;default:udp_data_o=8'h4b; // "CK" terminator
  endcase
 end
 always @(posedge clk_i or negedge rst_ni)begin
  if(!rst_ni)begin state_r<=ST_IDLE;byte_r<=0;data_index_r<=0;udp_request_o<=0;udp_valid_o<=0;busy_o<=0;done_o<=0;end
  else begin
   udp_request_o<=0;udp_valid_o<=0;done_o<=0;
   case(state_r)
    ST_IDLE:if(start_i)begin busy_o<=1;state_r<=ST_REQUEST;end
    ST_REQUEST:if(!udp_busy_i)begin udp_request_o<=1;byte_r<=0;data_index_r<=0;state_r<=ST_SEND;end
    ST_SEND:if(udp_busy_i)begin udp_valid_o<=1;data_index_r<=byte_r;if(byte_r+1>=STATUS_BYTES)state_r<=ST_DONE;else byte_r<=byte_r+1'b1;end
    ST_DONE:begin busy_o<=0;done_o<=1;state_r<=ST_IDLE;end
    default:state_r<=ST_IDLE;
   endcase
  end
 end
endmodule
