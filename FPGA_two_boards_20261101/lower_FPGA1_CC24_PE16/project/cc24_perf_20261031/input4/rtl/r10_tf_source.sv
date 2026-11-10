// Only the board-proven SD/FAT/Header/CRC source leaves are imported.
// Original R10 packet parser, FIFO and DDR adapter remain the sole backend.
// CC13: controlled TF retry. CC12 boards intermittently showed "video OK, never MODEL_READY": any single SD/FAT/
// loader error (boot_state 9) moved the owner to HOST (PC Recovery) permanently, with no retry. Now a TF failure
// drains + clears the parser exactly as before, then holds ONLY the TF reader/FAT/loader/packet source in reset
// (card deselected, SCLK idle) for RETRY_HOLD_CYCLES and restarts the full TF boot (power wait, >=74 clocks, CMD0..),
// up to MAX_RETRIES times; only then the original HOST Recovery path is entered. The camera, Ethernet, DDR and YOLO
// are never reset by this; YOLO stays gated by MODEL_READY, which requires a fully verified TF model.
// status_o = {first_error[7:0], boot_state[4:0], retries[1:0], recovery} for telemetry (observation only).
module r10_tf_source #(
 parameter HEADER_FILE="flash_model_header.hex",
 parameter integer MAX_RETRIES=3,
 parameter integer RETRY_HOLD_CYCLES=20000000  // 200 ms at 100 MHz
)(
 input wire clk,rst_n,model_ready_i,ingress_idle_i,writer_error_i,
 input wire writer_slot_ready_i,writer_pending_i,
 input wire host_valid_i,input wire[7:0]host_data_i,input wire[15:0]host_length_i,
 output wire parameter_valid_o,output wire[7:0]parameter_data_o,output wire[15:0]parameter_length_o,
 output wire parser_reset_no,model_qualified_o,
 output wire[7:0]error_o,output wire[4:0]boot_state_o,output wire recovery_o,
 output wire[15:0]status_o,
 output wire sd_cs_n,sd_sclk,sd_mosi,input wire sd_miso
);
 localparam TF=0,DRAIN=1,CLEAR=2,HOST_WAIT=3,HOST=4,RETRY_HOLD=5;
 reg[2:0]owner_r;
 reg host_in_packet_r;reg[15:0]host_index_r,host_length_r;
 reg[1:0]retries_r;reg[7:0]first_error_r;reg[31:0]hold_r;
 // TF-only reset: global reset OR the retry hold. Synchronous assertion source, used as async reset like rst_n.
 reg tf_hold_r;
 wire tf_rst_n=rst_n&&!tf_hold_r;
 wire initialized,block_request_ready,block_request,block_valid,block_ready,block_done;
 wire[31:0]lba,ocr,file_bytes;wire[32:0]capacity;
 wire[7:0]block_data,sd_error,fat_error,file_data,loader_error;
 wire file_valid,file_ready,file_done,section_start,section_ready,section_last;
 wire[1:0]region;wire payload_valid,payload_ready,payload_verified,boot_done,unused_parameter_reset;
 wire[7:0]payload_data;wire[20:0]payload_bytes;
 wire synth_valid;wire[7:0]synth_data;wire[15:0]synth_length;
 tf_sd_wire_reader sd(.clk(clk),.rst_n(tf_rst_n),.enable_i(1'b1),
  .sd_cs_n(sd_cs_n),.sd_sclk(sd_sclk),.sd_mosi(sd_mosi),.sd_miso(sd_miso),
  .initialized_o(initialized),.request_ready_o(block_request_ready),.request_i(block_request),.lba_i(lba),
  .valid_o(block_valid),.ready_i(block_ready),.data_o(block_data),.done_o(block_done),.error_o(sd_error),
  .ocr_o(ocr),.device_sectors_o(capacity),.diagnostic_trace_o(),.wire_trace_o());
 tf_fat32_file_context fs(.clk(clk),.rst_n(tf_rst_n),.start_i(initialized),.device_sectors_i(capacity),
  .block_request_o(block_request),.block_request_ready_i(block_request_ready),.block_lba_o(lba),
  .block_valid_i(block_valid),.block_ready_o(block_ready),.block_data_i(block_data),.block_done_i(block_done),.block_error_i(sd_error),
  .file_valid_o(file_valid),.file_ready_i(file_ready),.file_data_o(file_data),.file_done_o(file_done),.error_o(fat_error),.file_bytes_o(file_bytes));
 tf_model_stream_loader #(.HEADER_FILE(HEADER_FILE)) loader(
  .clk(clk),.rst_n(tf_rst_n),.ddr_ready_i(initialized),
  .file_valid_i(file_valid),.file_ready_o(file_ready),.file_data_i(file_data),.file_done_i(file_done),
  .file_error_i(sd_error!=0?sd_error:fat_error),
  .section_start_o(section_start),.section_region_o(region),.section_ready_i(section_ready),
  .payload_valid_o(payload_valid),.payload_ready_i(payload_ready),.payload_data_o(payload_data),.section_last_i(section_last),
  .writer_error_i(writer_error_i&&owner_r==TF),.model_ready_i(model_ready_i&&ingress_idle_i),
  .parameter_reset_o(unused_parameter_reset),.verified_o(payload_verified),.boot_done_o(boot_done),
  .error_o(loader_error),.payload_bytes_o(payload_bytes),.state_o(boot_state_o));
 r10_tf_packet_source packet_source(.clk(clk),.rst_n(tf_rst_n),.enable_i(owner_r==TF&&loader_error==0),
  .section_start_i(section_start),.section_region_i(region),.section_ready_o(section_ready),
  .payload_valid_i(payload_valid),.payload_data_i(payload_data),.payload_ready_o(payload_ready),.section_last_o(section_last),
  .writer_slot_ready_i(writer_slot_ready_i),.writer_pending_i(writer_pending_i),
  .valid_o(synth_valid),.data_o(synth_data),.length_o(synth_length));
 assign parameter_valid_o=owner_r==TF?synth_valid:(owner_r==HOST&&host_valid_i&&!model_ready_i);
 assign parameter_data_o=owner_r==TF?synth_data:host_data_i;
 assign parameter_length_o=owner_r==TF?synth_length:host_length_i;
 assign parser_reset_no=rst_n&&owner_r!=CLEAR;
 assign model_qualified_o=(owner_r==TF)?(payload_verified&&loader_error==0&&sd_error==0&&fat_error==0):(owner_r==HOST);
 assign recovery_o=owner_r==HOST;
 assign error_o=sd_error!=0?sd_error:fat_error!=0?fat_error:loader_error;
 assign status_o={first_error_r,boot_state_o,retries_r,recovery_o};
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin owner_r<=TF;host_in_packet_r<=0;host_index_r<=0;host_length_r<=0;
   retries_r<=0;first_error_r<=0;hold_r<=0;tf_hold_r<=0;end
  else begin
   // Track real UDP packet boundaries even while TF owns the model input.
   // A packet already in flight at handoff is discarded in its entirety.
   if(host_valid_i)begin
    if(!host_in_packet_r)begin
     host_length_r<=host_length_i;host_index_r<=1;host_in_packet_r<=host_length_i>1;
    end else if(host_index_r+1>=host_length_r)begin host_in_packet_r<=0;host_index_r<=0;end
    else host_index_r<=host_index_r+1'b1;
   end
   case(owner_r)
    TF:if(boot_state_o==9&&error_o!=0&&!model_ready_i)begin
     owner_r<=DRAIN;
     if(first_error_r==0)first_error_r<=error_o;
    end
    DRAIN:if(ingress_idle_i&&!writer_pending_i)owner_r<=CLEAR;
    CLEAR:if(retries_r<MAX_RETRIES)begin owner_r<=RETRY_HOLD;tf_hold_r<=1;hold_r<=0;end
          else owner_r<=HOST_WAIT;
    RETRY_HOLD:if(hold_r>=RETRY_HOLD_CYCLES-1)begin
     tf_hold_r<=0;retries_r<=retries_r+1'b1;owner_r<=TF;
    end else hold_r<=hold_r+1'b1;
    HOST_WAIT:if(!host_in_packet_r&&!host_valid_i)owner_r<=HOST;
    HOST:begin end
    default:owner_r<=TF;
   endcase
  end
 end
endmodule
