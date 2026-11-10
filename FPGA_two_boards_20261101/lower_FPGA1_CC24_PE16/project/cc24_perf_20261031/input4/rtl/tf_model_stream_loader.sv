// Frozen R10 envelope -> unchanged typed parameter writer. Storage-independent
// stream: no synthetic SPI ID/status commands and no host model upload.
module tf_model_stream_loader #(
 parameter HEADER_FILE="flash_model_header.hex",
 parameter integer TIMEOUT_CYCLES=100000000
)(
 input wire clk,rst_n,ddr_ready_i,
 input wire file_valid_i,output wire file_ready_o,input wire[7:0]file_data_i,
 input wire file_done_i,input wire[7:0]file_error_i,
 output wire section_start_o,output wire[1:0]section_region_o,input wire section_ready_i,
 output wire payload_valid_o,input wire payload_ready_i,output wire[7:0]payload_data_o,input wire section_last_i,
 input wire writer_error_i,model_ready_i,
 output wire parameter_reset_o,output reg verified_o,boot_done_o,output reg[7:0]error_o,
 output reg[20:0]payload_bytes_o,output wire[4:0]state_o
);
 localparam WAIT_DDR=0,HEADER=1,SECTION=2,PAYLOAD=3,CRC=4,PADDING=5,WAIT_FILE=6,WAIT_COMMIT=7,RUNNING=8,FAILED=9;
 reg[4:0]state_r;reg[7:0]header_index_r,pad_r;reg[1:0]region_r;reg[2:0]crc_bit_r;
 reg[31:0]crc_r,timer_r;reg section_end_r,model_end_r,file_done_seen_r;
 (* ram_style="bram" *)reg[7:0]header_rom[0:255];initial $readmemh(HEADER_FILE,header_rom);
 reg[7:0]expected_r;
 wire take_w=file_valid_i&&file_ready_o;
 wire[7:0]rom_index_w=state_r==HEADER&&take_w&&header_index_r!=255?header_index_r+1'b1:header_index_r;
 always @(posedge clk)expected_r<=header_rom[rom_index_w];
 wire[31:0]crc_step_w=crc_r[0]?((crc_r>>1)^32'hedb88320):(crc_r>>1);
 assign state_o=state_r;assign parameter_reset_o=state_r==FAILED;
 assign section_start_o=state_r==SECTION;assign section_region_o=region_r;
 assign payload_valid_o=state_r==PAYLOAD&&file_valid_i;assign payload_data_o=file_data_i;
 assign file_ready_o=(state_r==HEADER||state_r==PADDING)||(state_r==PAYLOAD&&payload_ready_i);
 task fail(input[7:0]code);begin error_o<=code;state_r<=FAILED;verified_o<=0;boot_done_o<=0;end endtask
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin state_r<=WAIT_DDR;header_index_r<=0;pad_r<=0;region_r<=0;crc_bit_r<=0;
   crc_r<=32'hffffffff;timer_r<=0;section_end_r<=0;model_end_r<=0;file_done_seen_r<=0;
   verified_o<=0;boot_done_o<=0;error_o<=0;payload_bytes_o<=0;
  end else begin
   if(file_done_i)file_done_seen_r<=1;
   if(take_w||state_r==CRC||(state_r==SECTION&&section_ready_i)||state_r==WAIT_DDR||state_r==RUNNING||state_r==FAILED)timer_r<=0;
   else timer_r<=timer_r+1'b1;
   if(state_r!=FAILED&&state_r!=RUNNING&&(file_error_i!=0||writer_error_i))fail(8'h31);
   else if(state_r!=WAIT_DDR&&state_r!=RUNNING&&state_r!=FAILED&&(!ddr_ready_i||timer_r>=TIMEOUT_CYCLES-1))fail(8'h32);
   else case(state_r)
    WAIT_DDR:if(ddr_ready_i)state_r<=HEADER;
    HEADER:if(take_w)begin
     if(file_data_i!==expected_r)fail(8'h33);
     else if(header_index_r==255)state_r<=SECTION;else header_index_r<=header_index_r+1'b1;
    end
    SECTION:if(section_ready_i)state_r<=PAYLOAD;
    PAYLOAD:if(take_w)begin
     crc_r<=crc_r^{24'd0,file_data_i};crc_bit_r<=0;payload_bytes_o<=payload_bytes_o+1'b1;
     section_end_r<=section_last_i;model_end_r<=payload_bytes_o==1816191;state_r<=CRC;
    end
    CRC:begin
     crc_r<=crc_step_w;
     if(crc_bit_r!=7)crc_bit_r<=crc_bit_r+1'b1;
     else if(model_end_r)begin
      if(!section_end_r||region_r!=3||(crc_step_w^32'hffffffff)!=32'ha7cc0bfc)fail(8'h34);
      else begin pad_r<=0;state_r<=PADDING;end
     end else if(section_end_r)begin
      if(region_r==3)fail(8'h35);else begin region_r<=region_r+1'b1;state_r<=SECTION;end
     end else state_r<=PAYLOAD;
    end
    PADDING:if(take_w)begin if(pad_r==127)state_r<=WAIT_FILE;else pad_r<=pad_r+1'b1;end
    WAIT_FILE:if(file_done_i||file_done_seen_r)begin verified_o<=1;state_r<=WAIT_COMMIT;end
    WAIT_COMMIT:if(model_ready_i)begin boot_done_o<=1;state_r<=RUNNING;end
    RUNNING:begin end
    FAILED:begin end
    default:fail(8'hff);
   endcase
  end
 end
endmodule
