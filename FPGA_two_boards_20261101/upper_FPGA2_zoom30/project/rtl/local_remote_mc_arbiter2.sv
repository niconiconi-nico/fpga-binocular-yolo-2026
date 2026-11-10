// Insert BEFORE the existing working mc_to_user_interface, do not replace it.
// Local video retains priority/burst behavior and delayed write-enable credit.
// Remote requests obey ready/valid; actual native acceptance consumes metadata.
// Commit is a native command+WDF acceptance fence, never FIFO-empty/UDP-last.
module local_remote_mc_arbiter2(
 input wire clk,rst_n,
 input wire local_wr_en,local_rd_en,local_wr_busy,local_rd_busy,
 input wire [24:0] local_addr,input wire [127:0] local_write_data,
 output wire local_ready,local_read_valid,output wire [127:0] local_read_data,
 input wire remote_valid,remote_write,remote_frame_last,
 input wire [24:0] remote_addr,input wire [127:0] remote_write_data,
 output wire remote_ready,remote_read_valid,output wire [127:0] remote_read_data,
 output wire bridge_wr_en,bridge_rd_en,output wire [24:0] bridge_addr,
 output wire [127:0] bridge_write_data,input wire bridge_ready,
 input wire bridge_read_valid,input wire [127:0] bridge_read_data,
 input wire native_command_accepted,native_command_read,
 output reg remote_commit_toggle,output reg protocol_error
);
 // Metadata mirrors EVERY command in the original512-deep bridge FIFO.
 // [0]read,[1]remote,[2]last-remote-write. No alternate data queue is added.
 (* async_reg="true" *) reg [1:0] bridge_release;
 always @(posedge clk or negedge rst_n)
  if(!rst_n)bridge_release<=0;else bridge_release<={bridge_release[0],1'b1};
 wire startup_ready=bridge_release[1];
 reg [2:0] command_tags[0:511];reg [8:0] wp,rp;reg[9:0] pending;
 // Read responses are ordered; tags are captured at native read acceptance.
 // Local reader has<=451 reservations and remote has<=192;1024 is bounded.
 reg read_tags[0:1023];reg[9:0] rwp,rrp;reg[10:0] reads_pending;
 reg[8:0] remote_reads_reserved;
 wire local_command=local_wr_en||local_rd_en;
 wire remote_slot=startup_ready&&bridge_ready&&pending<500&&!local_command&&!local_wr_busy&&!local_rd_busy;
 assign local_ready=startup_ready&&bridge_ready&&pending<500;
 assign remote_ready=remote_slot&&(remote_write||remote_reads_reserved<192);
 wire remote_fire=remote_valid&&remote_ready;
 wire push=local_command||remote_fire;
 wire[2:0] incoming=local_command?{2'b00,local_rd_en&&!local_wr_en}:
       {remote_frame_last&&remote_write,1'b1,!remote_write};
 wire[2:0] head=command_tags[rp];
 wire native_read=native_command_accepted&&native_command_read;
 wire remote_response=bridge_read_valid&&reads_pending!=0&&read_tags[rrp];
 assign bridge_wr_en=local_wr_en||(remote_fire&&remote_write);
 assign bridge_rd_en=(!local_wr_en&&local_rd_en)||(remote_fire&&!remote_write);
 assign bridge_addr=local_command?local_addr:remote_addr;
 assign bridge_write_data=local_command?local_write_data:remote_write_data;
 assign local_read_valid=bridge_read_valid&&reads_pending!=0&&!read_tags[rrp];
 assign remote_read_valid=remote_response;
 assign local_read_data=bridge_read_data;assign remote_read_data=bridge_read_data;
 always @(posedge clk)begin
  if(rst_n&&push)command_tags[wp]<=incoming;
  if(rst_n&&native_read&&pending!=0)read_tags[rwp]<=head[1];
 end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   wp<=0;rp<=0;pending<=0;rwp<=0;rrp<=0;reads_pending<=0;
   remote_reads_reserved<=0;remote_commit_toggle<=0;protocol_error<=0;
  end else begin
   if(push)wp<=wp+1'b1;
   if(native_command_accepted)rp<=rp+1'b1;
   case({push,native_command_accepted})2'b10:pending<=pending+1'b1;2'b01:pending<=pending-1'b1;default:;endcase
   if(native_read)rwp<=rwp+1'b1;
   if(bridge_read_valid)rrp<=rrp+1'b1;
   case({native_read,bridge_read_valid})2'b10:reads_pending<=reads_pending+1'b1;2'b01:reads_pending<=reads_pending-1'b1;default:;endcase
   case({remote_fire&&!remote_write,remote_response})2'b10:remote_reads_reserved<=remote_reads_reserved+1'b1;2'b01:remote_reads_reserved<=remote_reads_reserved-1'b1;default:;endcase
   if(native_command_accepted&&pending!=0&&head[2]&&!head[0])remote_commit_toggle<=~remote_commit_toggle;
   if((local_wr_en&&local_rd_en)||(push&&pending==512)||
      (native_command_accepted&&(pending==0||head[0]!=native_command_read))||
      (native_read&&reads_pending==1024)||(bridge_read_valid&&reads_pending==0)||
      (remote_response&&remote_reads_reserved==0))protocol_error<=1;
  end
 end
endmodule
