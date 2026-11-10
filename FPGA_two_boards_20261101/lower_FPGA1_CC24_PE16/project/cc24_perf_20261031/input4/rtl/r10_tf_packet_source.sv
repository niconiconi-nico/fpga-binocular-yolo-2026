// TF payload -> ORIGINAL R10 type3 parser ABI. No DDR master, second parser,
// payload RAM, model checksum bank or replacement YOLO implementation here.
// Headers are generated while file input is backpressured. Original parser
// retains all accepted-byte accounting, destination addressing and FIFO writes.
module r10_tf_packet_source (
 input wire clk,rst_n,enable_i,
 input wire section_start_i,input wire [1:0]section_region_i,
 output wire section_ready_o,
 input wire payload_valid_i,input wire [7:0]payload_data_i,
 output wire payload_ready_o,section_last_o,
 input wire writer_slot_ready_i,input wire writer_pending_i,
 output wire valid_o,output reg [7:0]data_o,output wire [15:0]length_o
);
 localparam IDLE=0,HEADER=1,OFFER=2,PAYLOAD=3,DRAIN=4;
 reg [2:0]state_r; reg [1:0]region_r;
 reg [4:0]header_index_r; reg first_r,section_end_r;
 reg [31:0]offset_r,section_size_r;
 reg [15:0]packet_r,packets_r,chunk_size_r,chunk_index_r;
 reg [1:0]settle_r;
 wire payload_take=state_r==PAYLOAD&&enable_i&&payload_valid_i&&writer_slot_ready_i;
 assign section_ready_o=enable_i&&state_r==OFFER;
 assign payload_ready_o=enable_i&&state_r==PAYLOAD&&writer_slot_ready_i;
 assign section_last_o=state_r==PAYLOAD&&(offset_r+{16'd0,chunk_index_r}+1==section_size_r);
 assign valid_o=enable_i&&((state_r==HEADER)||payload_take);
 assign length_o=chunk_size_r+16'd20;
 always @* begin
  data_o=0;
  if(state_r==PAYLOAD)data_o=payload_data_i;
  else case(header_index_r)
   0:data_o=8'h59;1:data_o=8'h38;2:data_o=8'h4e;3:data_o=8'h33;
   4:data_o=1;5:data_o=3;6:data_o={6'd0,region_r};
   12:data_o=packet_r[7:0];13:data_o=packet_r[15:8];
   14:data_o=packets_r[7:0];15:data_o=packets_r[15:8];
   16:data_o=offset_r[7:0];17:data_o=offset_r[15:8];
   18:data_o=offset_r[23:16];19:data_o=offset_r[31:24];
   default:data_o=0;
  endcase
 end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   state_r<=IDLE;region_r<=0;header_index_r<=0;first_r<=0;section_end_r<=0;
   offset_r<=0;section_size_r<=0;packet_r<=0;packets_r<=0;chunk_size_r<=0;chunk_index_r<=0;settle_r<=0;
  end else if(!enable_i)begin state_r<=IDLE;end
  else case(state_r)
   IDLE:if(section_start_i)begin
    region_r<=section_region_i;offset_r<=0;packet_r<=0;header_index_r<=0;
    first_r<=1;chunk_index_r<=0;chunk_size_r<=512;state_r<=HEADER;
    case(section_region_i)
     0:begin section_size_r<=1759744;packets_r<=3437;end
     1,2:begin section_size_r<=19344;packets_r<=38;end
     3:begin section_size_r<=17760;packets_r<=35;end
    endcase
   end
   HEADER:if(header_index_r==19)begin
    header_index_r<=0;state_r<=first_r?OFFER:PAYLOAD;
   end else header_index_r<=header_index_r+1'b1;
   OFFER:begin first_r<=0;state_r<=PAYLOAD;end
   PAYLOAD:if(payload_take)begin
    if(chunk_index_r+1==chunk_size_r)begin
     section_end_r<=section_last_o;settle_r<=0;state_r<=DRAIN;
    end else chunk_index_r<=chunk_index_r+1'b1;
   end
   // Parser registers the pending write one edge after the input byte. Do not
   // issue another packet until that pending write is truly accepted downstream.
   DRAIN:if(settle_r!=2)settle_r<=settle_r+1'b1;
    else if(!writer_pending_i)begin
     if(section_end_r)state_r<=IDLE;
     else begin
      offset_r<=offset_r+{16'd0,chunk_size_r};packet_r<=packet_r+1'b1;
      chunk_index_r<=0;header_index_r<=0;
      if(section_size_r-offset_r-{16'd0,chunk_size_r}<512)
       chunk_size_r<=section_size_r-offset_r-{16'd0,chunk_size_r};
      state_r<=HEADER;
     end
    end
   default:state_r<=IDLE;
  endcase
 end
endmodule
