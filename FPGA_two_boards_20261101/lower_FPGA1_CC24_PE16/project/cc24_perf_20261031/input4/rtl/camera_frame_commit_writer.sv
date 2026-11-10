// DDR-domain consumer of framed Camera FIFO. Banks are published only after
// all172800actual writes physically commit. No enqueue-ready publication.
module camera_frame_commit_writer(
 input wire clk,rst_n,input wire framed_valid_i,output wire framed_ready_o,input wire [162:0] framed_data_i,
 output wire frame_begin_o,output reg [31:0] frame_id_o,input wire capture_accept_i,input wire [1:0] capture_bank_i,
 output wire committed_o,output wire rejected_o,
 output wire req_valid_o,input wire req_ready_i,output wire [27:0] req_address_o,
 output wire [127:0] req_data_o,output reg [31:0] bad_frames_o
);
 localparam LOOK=0,RESERVE=1,WRITE=2,NEXT=3,SKIP=4,ABORT=5;
 reg [2:0] state;reg [1:0] bank;reg [17:0] words;
 reg [127:0] data;reg last,bad;reg reject_pulse;
 wire next_first=framed_data_i[160];wire next_last=framed_data_i[161];
 wire next_bad=framed_data_i[162];wire [31:0] next_id=framed_data_i[159:128];
 wire final_accept=(state==WRITE)&&req_ready_i&&last;
 wire valid_frame=(words==172799)&&!bad;
 assign framed_ready_o=(state==LOOK)||(state==NEXT)||(state==SKIP);
 assign frame_begin_o=(state==RESERVE);
 assign req_valid_o=(state==WRITE);
 // bank0/1/2 byte bases0x01800000/0x01c00000/0x02000000 (4MiB stride).
 assign req_address_o=28'h0180000+({26'd0,bank}<<18)+words;
 assign req_data_o=data;
 assign committed_o=final_accept&&valid_frame;
 assign rejected_o=reject_pulse||(final_accept&&!valid_frame);
 always @(posedge clk or negedge rst_n)begin
   if(!rst_n)begin state<=LOOK;bank<=0;words<=0;data<=0;last<=0;bad<=0;frame_id_o<=0;bad_frames_o<=0;reject_pulse<=0;end
   else begin
     reject_pulse<=0;
     case(state)
       LOOK,SKIP,NEXT:if(framed_valid_i)begin
         if(next_first)begin
           // Abort unfinished frame before reserving the next bank (next edge).
           if(state==NEXT)begin reject_pulse<=1;bad_frames_o<=bad_frames_o+1'b1;end
           frame_id_o<=next_id;data<=framed_data_i[127:0];last<=next_last;bad<=next_bad;words<=0;state<=(state==NEXT)?ABORT:RESERVE;
         end else if(state==NEXT)begin
           if(next_id!=frame_id_o)begin reject_pulse<=1;bad_frames_o<=bad_frames_o+1'b1;state<=SKIP;end
           else begin data<=framed_data_i[127:0];last<=next_last;bad<=bad||next_bad;state<=WRITE;end
         end
       end
       ABORT:state<=RESERVE;
       RESERVE:if(capture_accept_i)begin bank<=capture_bank_i;state<=WRITE;end else state<=SKIP;
       WRITE:if(req_ready_i)begin
         if(last)begin
           if(!valid_frame)bad_frames_o<=bad_frames_o+1'b1;
           state<=LOOK;
         end else if(words==172799)begin reject_pulse<=1;bad_frames_o<=bad_frames_o+1'b1;state<=SKIP;end
         else begin words<=words+1'b1;state<=NEXT;end
       end
       default:state<=LOOK;
     endcase
   end
 end
endmodule
