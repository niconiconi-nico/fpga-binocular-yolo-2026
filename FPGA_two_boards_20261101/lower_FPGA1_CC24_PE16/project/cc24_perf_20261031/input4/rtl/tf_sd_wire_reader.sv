// SDHC-v2 read-only adaptation of official18 sector/command/SPI hierarchy.
// spi_master is byte-exact official. sd_card_cmd retains original transactions
// with scoped R7/OCR visibility, finite waits and CRC16. No CMD24/write owner.
module tf_sd_wire_reader #(
 parameter integer POWERUP_CYCLES=100000, //1ms at unchanged100MHz
 parameter integer INIT_TIMEOUT_CYCLES=200000000,
 parameter integer READ_TIMEOUT_CYCLES=100000000,
 parameter integer LOW_DIV=248, HIGH_DIV=8,
 parameter integer RESPONSE_LIMIT=65535,TOKEN_LIMIT=65535
)(
 input wire clk,rst_n,enable_i,
 output wire sd_cs_n,sd_sclk,sd_mosi,input wire sd_miso,
 output wire initialized_o,request_ready_o,input wire request_i,input wire[31:0]lba_i,
 output wire valid_o,input wire ready_i,output wire[7:0]data_o,
 output reg done_o,output reg[7:0]error_o,output reg[31:0]ocr_o,
 output wire[127:0]diagnostic_trace_o,output wire[511:0]wire_trace_o,
 output reg[32:0]device_sectors_o
);
 localparam POWER=0,ISSUE=1,WAIT_CMD=2,READY=3,READ_START=4,READ_WAIT=5,EMIT=6,FAILED=7,PRIME=8;
 reg[127:0]diagnostic_latched_r;
 // YSD2 observer word: {retry_count16, first_failed_CMD0_R1, 8'hc1}.
 // Observer counters never gate the command or timeout owner.
 reg[15:0]cmd0_retries_r;reg[7:0]first_bad_cmd0_r;
 wire[31:0]retry_observation_w={cmd0_retries_r,first_bad_cmd0_r,8'hc1};
 reg[3:0]state_r;reg[2:0]init_step_r;reg initialized_r,engine_release_r;
 reg[31:0]timer_r,power_r,lba_r;
 reg[47:0]command_r;reg[7:0]expected_r;reg[15:0]extra_len_r;
 reg cmd_req_r,block_req_r;wire cmd_ack,cmd_error,block_ack,block_valid,crc_error;
 wire[7:0]block_data,response;wire[31:0]extra;
 reg[9:0]received_r;reg[8:0]emit_r;
 reg[7:0]csd_structure_r;reg[21:0]csd_size_r;
 (* ram_style="bram" *)reg[7:0]sector[0:511];
 reg[7:0]sector_q;
 assign diagnostic_trace_o=error_o!=0?diagnostic_latched_r:
   {16'hd1a6,6'd0,crc_error,cmd_error,received_r[7:0],error_o,
    init_step_r,initialized_r,state_r,command_r[47:40],response,retry_observation_w,lba_r};
 wire[8:0]next_read_w=(state_r==EMIT&&ready_i&&emit_r!=511)?emit_r+1'b1:emit_r;
 always @(posedge clk)sector_q<=sector[next_read_w];
 assign data_o=sector_q;assign valid_o=state_r==EMIT;
 assign initialized_o=initialized_r&&error_o==0;
 assign request_ready_o=state_r==READY;
 wire engine_reset=~rst_n|~engine_release_r;
 wire[2:0]spi_state_w;wire[15:0]spi_clkcnt_w,cmd_byte_count_w;wire[4:0]spi_edges_w,cmd_state_w;
 reg[383:0]aux_latched_r;wire[383:0]aux_live_w;
 reg[31:0]probe_cycles_r,probe_starts_r,probe_acks_r,probe_high_r,probe_low_r,probe_rises_r;
 reg[15:0]probe_cmdacks_r;reg[47:0]probe_tx_r;reg[5:0]probe_txcount_r;
 reg[63:0]probe_rx_r;reg[3:0]probe_rxcount_r;reg probe_sclk_prev_r;
 assign aux_live_w={
  spi_clkcnt_w,cmd_state_w,spi_state_w,spi_edges_w,sd_cs_n,sd_sclk,sd_miso,
  probe_rises_r,probe_rx_r,
  6'd0,probe_rxcount_r,probe_txcount_r,probe_tx_r,
  probe_low_r,probe_high_r,{probe_cmdacks_r,cmd_byte_count_w},
  probe_acks_r,probe_starts_r,probe_cycles_r};
 assign wire_trace_o={error_o!=0?aux_latched_r:aux_live_w,diagnostic_trace_o};
 wire cs;wire[15:0]div_out;wire spi_req,spi_ack;wire[7:0]spi_tx,spi_rx;
 wire selected_w=(state_r==ISSUE||state_r==WAIT_CMD||state_r==READ_START||state_r==READ_WAIT);
 assign sd_cs_n=selected_w?cs:1'b1;
 sd_card_cmd2_probe #(.RESPONSE_LIMIT(RESPONSE_LIMIT),.TOKEN_LIMIT(TOKEN_LIMIT)) commands(
 .probe_state_o(cmd_state_w),.probe_byte_count_o(cmd_byte_count_w),
 .sys_clk(clk),.rst(engine_reset),.spi_clk_div(initialized_r?HIGH_DIV[15:0]:LOW_DIV[15:0]),
 .cmd_req(cmd_req_r),.cmd_req_ack(cmd_ack),.cmd_req_error(cmd_error),.cmd(command_r),
 .cmd_r1(expected_r),.cmd_data_len(extra_len_r),.block_read_req(block_req_r),
 .block_read_valid(block_valid),.block_read_data(block_data),.block_read_req_ack(block_ack),
 .block_write_req(1'b0),.block_write_data(8'd0),.block_write_data_rd(),.block_write_req_ack(),
 .nCS_ctrl(cs),.clk_div(div_out),.spi_wr_req(spi_req),.spi_wr_ack(spi_ack),
 .spi_data_in(spi_tx),.spi_data_out(spi_rx),.cmd_response_o(response),.cmd_extra_o(extra),.block_crc_error_o(crc_error),
 .block_read_size_i(initialized_r?10'd512:10'd16));
 spi_master_probe spi(.probe_state_o(spi_state_w),.probe_clk_cnt_o(spi_clkcnt_w),.probe_edge_cnt_o(spi_edges_w),.sys_clk(clk),.rst(engine_reset),.nCS(),.DCLK(sd_sclk),.MOSI(sd_mosi),.MISO(sd_miso),
 .CPOL(1'b1),.CPHA(1'b1),.nCS_ctrl(sd_cs_n),.clk_div(div_out),.wr_req(spi_req),.wr_ack(spi_ack),.data_in(spi_tx),.data_out(spi_rx));
 // Observation only: no backedge into command/timeout/ready controls.
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   probe_cycles_r<=0;probe_starts_r<=0;probe_acks_r<=0;probe_cmdacks_r<=0;
   probe_high_r<=0;probe_low_r<=0;probe_rises_r<=0;
   probe_tx_r<=0;probe_txcount_r<=0;probe_rx_r<=0;probe_rxcount_r<=0;probe_sclk_prev_r<=0;
  end else begin
   probe_sclk_prev_r<=sd_sclk;
   if(engine_release_r&&error_o==0)begin
    probe_cycles_r<=probe_cycles_r+1'b1;
    if(spi_state_w==0&&spi_req)probe_starts_r<=probe_starts_r+1'b1;
    if(spi_ack)begin
     probe_acks_r<=probe_acks_r+1'b1;
     if(cmd_state_w==4&&cmd_byte_count_w>=6&&probe_rxcount_r<8)begin
      probe_rx_r<={probe_rx_r[55:0],spi_rx};probe_rxcount_r<=probe_rxcount_r+1'b1;
     end
    end
    if(cmd_ack&&probe_cmdacks_r!=16'hffff)probe_cmdacks_r<=probe_cmdacks_r+1'b1;
    if(spi_state_w==1&&spi_edges_w[0])begin
     if(sd_miso)probe_high_r<=probe_high_r+1'b1;else probe_low_r<=probe_low_r+1'b1;
    end
    if(!sd_cs_n&&!probe_sclk_prev_r&&sd_sclk)begin
     probe_rises_r<=probe_rises_r+1'b1;
     if(probe_txcount_r<48)begin probe_tx_r<={probe_tx_r[46:0],sd_mosi};probe_txcount_r<=probe_txcount_r+1'b1;end
    end
   end
  end
 end
 task fail(input[7:0]code);begin
  aux_latched_r<=aux_live_w;
  // Observation only: sample BEFORE fail resets command/SPI engine outputs.
  diagnostic_latched_r<={16'hd1a6,6'd0,crc_error,cmd_error,received_r[7:0],code,
    init_step_r,initialized_r,state_r,command_r[47:40],response,retry_observation_w,lba_r};
  error_o<=code;initialized_r<=0;engine_release_r<=0;cmd_req_r<=0;block_req_r<=0;state_r<=FAILED;end endtask
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   aux_latched_r<=0;diagnostic_latched_r<=0;cmd0_retries_r<=0;first_bad_cmd0_r<=0;
   state_r<=POWER;init_step_r<=0;initialized_r<=0;engine_release_r<=0;
   timer_r<=0;power_r<=0;lba_r<=0;command_r<=0;expected_r<=0;extra_len_r<=0;
   cmd_req_r<=0;block_req_r<=0;received_r<=0;emit_r<=0;error_o<=0;done_o<=0;ocr_o<=0;
   device_sectors_o<=0;csd_structure_r<=0;csd_size_r<=0;
  end else begin
   done_o<=0;
   if((!initialized_r&&engine_release_r)||(state_r==READ_START||state_r==READ_WAIT))timer_r<=timer_r+1'b1;
   else if(state_r==READY)timer_r<=0;
   if(!initialized_r&&engine_release_r&&timer_r>=INIT_TIMEOUT_CYCLES-1)fail(8'h01);
   else if((state_r==READ_START||state_r==READ_WAIT)&&timer_r>=READ_TIMEOUT_CYCLES-1)fail(8'h02);
   else case(state_r)
    POWER:if(enable_i)begin
     if(power_r>=POWERUP_CYCLES-1)begin engine_release_r<=1;state_r<=ISSUE;end
     else power_r<=power_r+1'b1;
    end
    ISSUE:begin
     cmd_req_r<=1;state_r<=WAIT_CMD;extra_len_r<=0;
     if(initialized_r)begin command_r<={8'd17,lba_r,8'hff};expected_r<=0;end
     else case(init_step_r)
      0:begin command_r<=48'h000000000095;expected_r<=1;end
      1:begin command_r<=48'h08000001aa87;expected_r<=1;extra_len_r<=4;end
      2:begin command_r<=48'h3700000000ff;expected_r<=1;end
      3:begin command_r<=48'h2940000000ff;expected_r<=0;end
      4:begin command_r<=48'h3a00000000ff;expected_r<=0;extra_len_r<=4;end
      5:begin command_r<=48'h0900000000ff;expected_r<=0;end
      default:fail(8'h03);
     endcase
    end
    WAIT_CMD:if(cmd_ack)begin
     cmd_req_r<=0;
     if(initialized_r)begin
      if(cmd_error||response!=0)fail(8'h10);
      else begin received_r<=0;state_r<=READ_START;end
     end else if(init_step_r==5)begin
      if(cmd_error||response!=0)fail(8'h16);else begin received_r<=0;state_r<=READ_START;end
     end else if(init_step_r==3&&response==1)begin init_step_r<=2;state_r<=ISSUE;end
     // Official18 S_CMD0 resends on erroneous ACK; retain our original finite
     // global INIT timeout and strict expected R1=01. Never accept 3f as ready.
     else if(init_step_r==0&&cmd_error)begin
      state_r<=ISSUE;
      if(cmd0_retries_r==0)first_bad_cmd0_r<=response;
      if(cmd0_retries_r!=16'hffff)cmd0_retries_r<=cmd0_retries_r+1'b1;
     end
     else if(cmd_error)fail(8'h11);
     else if(init_step_r==1&&extra!=32'h000001aa)fail(8'h12);
     else if(init_step_r==4)begin
      ocr_o<=extra;
      if((extra&32'hc0000000)!=32'hc0000000||(extra&32'h00ff8000)==0)fail(8'h13);
      else begin init_step_r<=5;state_r<=ISSUE;end
     end else begin init_step_r<=init_step_r+1'b1;state_r<=ISSUE;end
    end
    READY:if(request_i)begin lba_r<=lba_i;state_r<=ISSUE;timer_r<=0;end
    READ_START:begin block_req_r<=1;state_r<=READ_WAIT;end
    READ_WAIT:begin
     if(block_valid)begin
      if(received_r>=512)fail(8'h14);
      else begin
       sector[received_r[8:0]]<=block_data;received_r<=received_r+1'b1;
       if(!initialized_r)case(received_r)
        0:csd_structure_r<=block_data;
        7:csd_size_r[21:16]<=block_data[5:0];8:csd_size_r[15:8]<=block_data;9:csd_size_r[7:0]<=block_data;
       endcase
      end
     end
     if(block_ack)begin
      block_req_r<=0;
      if(cmd_error||crc_error||received_r!=(initialized_r?512:16))fail(8'h15);
      else if(!initialized_r)begin
       if(csd_structure_r[7:6]!=2'b01)fail(8'h17);
       else begin device_sectors_o<=({11'd0,csd_size_r}+33'd1)<<10;initialized_r<=1;state_r<=READY;timer_r<=0;end
      end
      else begin emit_r<=0;state_r<=PRIME;end
     end
    end
    PRIME:state_r<=EMIT;
    EMIT:if(ready_i)begin
     if(emit_r==511)begin done_o<=1;state_r<=READY;end else emit_r<=emit_r+1'b1;
    end
    FAILED:begin end
    default:fail(8'hff);
   endcase
  end
 end
endmodule
