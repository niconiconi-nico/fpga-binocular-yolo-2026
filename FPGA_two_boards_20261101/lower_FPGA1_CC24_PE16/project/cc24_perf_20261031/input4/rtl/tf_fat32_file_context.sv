// FAT32-only microsequencer: synchronous metadata context and fixed control ROM.
// Preserves the original full64 cluster / modulo33 BPB / modulo32 assignments.
// No YOLO operator, generic shared service, DDR writer or filesystem extension.
module tf_fat32_file_context #(
 parameter[31:0] EXPECTED_FILE_BYTES=1816576,
 parameter integer MAX_DIRECTORY_SECTORS=128,WAIT_LIMIT=200000000,
 parameter PROGRAM_FILE="fat_program3.hex"
)(
 input wire clk,rst_n,start_i,input wire[32:0]device_sectors_i,
 output wire block_request_o,input wire block_request_ready_i,output reg[31:0]block_lba_o,
 input wire block_valid_i,output wire block_ready_o,input wire[7:0]block_data_i,
 input wire block_done_i,input wire[7:0]block_error_i,
 output wire file_valid_o,input wire file_ready_i,output wire[7:0]file_data_o,
 output reg file_done_o,output reg[7:0]error_o,output reg[31:0]file_bytes_o
);
 localparam CLEAR=0,FETCH=1,EXEC=2,LOAD_WAIT=3,LOAD_DONE=4,SHIFT=5,REQUEST=6,RECEIVE=7,FAIL=8,FINISH=9,ALU_LOW=10,ALU_HIGH=11;
 localparam BOOT_KIND=0,DIR_KIND=1,FAT_KIND=2,FILE_KIND=3;
 localparam PART=0,PSIZE=1,TOTAL=2,FATSZ=3,ROOT=4,BPS=5,RESERVED=6,ROOTENT=7,FAT16=8,TOTAL16=9,
  FLAGS=10,VERSION=11,SPC=12,NFATS=13,PARTTYPE=14,SIG0=15,SIG1=16,JUMP=17,MBRSTART=18,MBRSIZE=19,
  CLUSTER=20,SECTOR=21,FATVAL=22,FATBASE=23,DATABASE=24,MAXCL=25,DIRSECT=26,CLSHIFT=27,
  OVER=28,OVERHI=29,DATA=30,DATAHI=31,COUNT=32,COUNTHI=33,VEND=34,VENDHI=35,DBASE=36,DBASEHI=37,
  EHI=38,ELO=39,ESIZE=40;
 reg[3:0]state_r;reg[9:0]pc_r;reg[31:0]instruction_r;
 (* ram_style="bram" *)reg[31:0]program_rom[0:1023];
 initial $readmemh(PROGRAM_FILE,program_rom);
 always @(posedge clk)instruction_r<=program_rom[pc_r];
 wire[7:0]op=instruction_r[31:24],arg=instruction_r[23:16];
 wire[15:0]immediate=instruction_r[15:0];
 reg[63:0]a_r,b_r;reg[5:0]clear_address_r,read_address_r;
 reg[1:0]load_mode_r;reg[5:0]shift_left_r;reg shift_right_r;
 reg[4:0]flags_r;reg[1:0]kind_r,cluster_kind_r;
 reg[9:0]index_r;reg[31:0]wait_r,remaining_r;
 reg[6:0]fat_select_r;reg entry_match_r;reg[7:0]entry_first_r,entry_attr_r;
 reg start_pending_r;
 // Metadata has no asynchronous reset port. A real64-clock clear completes
 // before any context read; reset mid-clear starts again at word0.
 (* ram_style="bram" *)reg[31:0]context_ram[0:63];
 reg[31:0]context_q;reg[5:0]write_address;
 reg[31:0]write_data;reg[3:0]byte_enable;
 wire stream_w=state_r==RECEIVE&&kind_r==FILE_KIND&&remaining_r!=0;
 assign file_valid_o=stream_w&&block_valid_i;
 assign file_data_o=block_data_i;
 assign block_ready_o=state_r==RECEIVE&&(!stream_w||file_ready_i);
 assign block_request_o=state_r==REQUEST;
 wire take_w=block_valid_i&&block_ready_o;
 function[7:0]name_byte(input[4:0]i);begin
  case(i)0:name_byte="M";1:name_byte="O";2:name_byte="D";3:name_byte="E";4:name_byte="L";
   5,6,7:name_byte=" ";8:name_byte="B";9:name_byte="I";10:name_byte="N";default:name_byte=0;endcase
 end endfunction
 function[63:0]constant_value(input[7:0]k);begin
  case(k)
   0:constant_value=0;1:constant_value=1;2:constant_value=2;3:constant_value=7;4:constant_value=16;5:constant_value=512;
   6:constant_value='h55;7:constant_value='haa;8:constant_value='heb;9:constant_value='he9;10:constant_value='hb;11:constant_value='hc;
   12:constant_value=15;13:constant_value='h0fffffff;14:constant_value='h0ffffff0;15:constant_value='h0ffffff8;
   16:constant_value=65525;17:constant_value={32'd0,EXPECTED_FILE_BYTES};18:constant_value=MAX_DIRECTORY_SECTORS-1;
   19:constant_value=4;20:constant_value=8;21:constant_value=32;22:constant_value=64;23:constant_value=128;24:constant_value=3;
   default:constant_value=0;
  endcase
 end endfunction
 reg alu_sub_r,alu_compare_r,alu_ge_r,alu_carry_r;
 reg[31:0]alu_low_r;reg[9:0]alu_target_r;
 wire[31:0]alu_a=state_r==ALU_HIGH?a_r[63:32]:a_r[31:0];
 wire[31:0]alu_b=state_r==ALU_HIGH?b_r[63:32]:b_r[31:0];
 wire[32:0]alu_sum={1'b0,alu_a}+{1'b0,(alu_sub_r?~alu_b:alu_b)}+
  {32'd0,(state_r==ALU_HIGH?alu_carry_r:alu_sub_r)};
 reg branch_w;
 always @*begin
  case(arg)
   0:branch_w=a_r==b_r;1:branch_w=a_r!=b_r;2,3:branch_w=0; // ordered comparison uses SAME serial32bit ALU
   4:branch_w=a_r==0;5:branch_w=a_r!=0;6:branch_w=a_r[63:32]!=0;default:branch_w=0;
  endcase
 end
 // One write port: context execution and verified block parsing never overlap.
 always @*begin
  write_address=0;write_data=0;byte_enable=0;
  if(state_r==CLEAR)begin write_address=clear_address_r;byte_enable=15;end
  else if(state_r==EXEC&&(op==6||op==7))begin
   write_address=arg[5:0];byte_enable=15;write_data=op==6?a_r[31:0]:a_r[63:32];
  end else if(state_r==RECEIVE&&take_w&&index_r<512&&block_error_i==0&&wait_r<WAIT_LIMIT-1)begin
   write_data={4{block_data_i}};
   if(kind_r==BOOT_KIND)begin
    case(index_r)
     0:begin write_address=JUMP;byte_enable=1;end
     11:begin write_address=BPS;byte_enable=1;end 12:begin write_address=BPS;byte_enable=2;end
     13:begin write_address=SPC;byte_enable=1;end
     14:begin write_address=RESERVED;byte_enable=1;end 15:begin write_address=RESERVED;byte_enable=2;end
     16:begin write_address=NFATS;byte_enable=1;end
     17:begin write_address=ROOTENT;byte_enable=1;end 18:begin write_address=ROOTENT;byte_enable=2;end
     19:begin write_address=TOTAL16;byte_enable=1;end 20:begin write_address=TOTAL16;byte_enable=2;end
     22:begin write_address=FAT16;byte_enable=1;end 23:begin write_address=FAT16;byte_enable=2;end
     32,33,34,35:begin write_address=TOTAL;byte_enable=4'b0001<<index_r[1:0];end
     36,37,38,39:begin write_address=FATSZ;byte_enable=4'b0001<<index_r[1:0];end
     40:begin write_address=FLAGS;byte_enable=1;end 41:begin write_address=FLAGS;byte_enable=2;end
     42:begin write_address=VERSION;byte_enable=1;end 43:begin write_address=VERSION;byte_enable=2;end
     44,45,46,47:begin write_address=ROOT;byte_enable=4'b0001<<index_r[1:0];end
     450:begin write_address=PARTTYPE;byte_enable=1;end
     454,455,456,457:begin write_address=MBRSTART;byte_enable=4'b0001<<(index_r-454);end
     458,459,460,461:begin write_address=MBRSIZE;byte_enable=4'b0001<<(index_r-458);end
     510:begin write_address=SIG0;byte_enable=1;end 511:begin write_address=SIG1;byte_enable=1;end
     default:begin end
    endcase
   end else if(kind_r==DIR_KIND&&!flags_r[3]&&!flags_r[4])begin
    case(index_r[4:0])
     20:begin write_address=EHI;byte_enable=1;end 21:begin write_address=EHI;byte_enable=2;end
     26:begin write_address=ELO;byte_enable=1;end 27:begin write_address=ELO;byte_enable=2;end
     28,29,30,31:begin write_address=ESIZE;byte_enable=4'b0001<<index_r[1:0];end
     default:begin end
    endcase
   end else if(kind_r==FAT_KIND&&index_r[8:2]==fat_select_r)begin write_address=FATVAL;byte_enable=4'b0001<<index_r[1:0];end
  end
 end
 integer lane;
 always @(posedge clk)begin
  for(lane=0;lane<4;lane=lane+1)if(byte_enable[lane])context_ram[write_address][lane*8+:8]<=write_data[lane*8+:8];
  context_q<=context_ram[read_address_r];
 end
 task fail(input[7:0]e);begin error_o<=e;state_r<=FAIL;end endtask
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   state_r<=CLEAR;pc_r<=0;a_r<=0;b_r<=0;clear_address_r<=0;read_address_r<=0;load_mode_r<=0;
   shift_left_r<=0;shift_right_r<=0;flags_r<=0;kind_r<=0;cluster_kind_r<=0;index_r<=0;wait_r<=0;
   remaining_r<=0;fat_select_r<=0;entry_match_r<=0;entry_first_r<=0;entry_attr_r<=0;
   start_pending_r<=0;block_lba_o<=0;file_done_o<=0;error_o<=0;file_bytes_o<=0;
   alu_sub_r<=0;alu_compare_r<=0;alu_ge_r<=0;alu_carry_r<=0;alu_low_r<=0;alu_target_r<=0;
  end else begin
   if(start_i)start_pending_r<=1;
   if(state_r==REQUEST||state_r==RECEIVE)begin
    if(take_w||block_done_i)wait_r<=0;else wait_r<=wait_r+1'b1;
   end
   if((state_r==REQUEST||state_r==RECEIVE)&&(block_error_i!=0||wait_r>=WAIT_LIMIT-1))fail(8'h23);
   else case(state_r)
    CLEAR:if(clear_address_r==63)begin state_r<=FETCH;pc_r<=0;end else clear_address_r<=clear_address_r+1'b1;
    FETCH:state_r<=EXEC;
    EXEC:begin
     pc_r<=pc_r+1'b1;state_r<=FETCH;
     case(op)
      1:if(!start_pending_r&&!start_i)begin pc_r<=pc_r;state_r<=EXEC;end
      2,3,4,5:begin
       read_address_r<=arg[5:0];load_mode_r<=(op==2)?0:(op==3)?1:(op==4)?2:3;state_r<=LOAD_WAIT;
      end
      6,7:begin end
      8:a_r<=constant_value(arg);
      9:b_r<=constant_value(arg);
      10,11:begin alu_sub_r<=op==11;alu_compare_r<=0;state_r<=ALU_LOW;end
      12:a_r<=a_r&b_r;13:a_r<=a_r|b_r;
      14:a_r<={32'd0,a_r[31:0]};15:a_r<={31'd0,a_r[32:0]};
      16:if(arg==2||arg==3)begin
       alu_sub_r<=1;alu_compare_r<=1;alu_ge_r<=arg==3;alu_target_r<=immediate[9:0];state_r<=ALU_LOW;
      end else if(branch_w)pc_r<=immediate[9:0];
      17:pc_r<=immediate[9:0];
      18:fail(arg);
      19:flags_r[arg[2:0]]<=immediate[0];
      20:if(flags_r[arg[3:1]]==arg[0])pc_r<=immediate[9:0];
      21:case(arg)
       0:a_r<={31'd0,device_sectors_i};
       1:begin b_r<=a_r;a_r<={31'd0,device_sectors_i};end
       2:a_r<={32'd0,remaining_r};3:a_r<={32'd0,file_bytes_o};
       4:a_r<={62'd0,kind_r};5:a_r<=b_r;default:fail(8'hff);
      endcase
      22:remaining_r<=a_r[31:0];
      23:begin
       if(a_r[63:32]!=0||a_r>={31'd0,device_sectors_i})fail(8'h21);
       else begin block_lba_o<=a_r[31:0];kind_r<=arg==4?cluster_kind_r:arg[1:0];
        fat_select_r<=b_r[6:0];index_r<=0;wait_r<=0;state_r<=REQUEST;end
      end
      24:begin file_done_o<=1;state_r<=FINISH;end
      25,26:if(b_r[5:0]!=0)begin shift_left_r<=b_r[5:0];shift_right_r<=op==26;state_r<=SHIFT;end
      27:cluster_kind_r<=arg[1:0];
      28:a_r<={48'd0,immediate};
      default:fail(8'hff);
     endcase
    end
    LOAD_WAIT:state_r<=LOAD_DONE;
    LOAD_DONE:begin
     case(load_mode_r)0:a_r<={32'd0,context_q};1:b_r<={32'd0,context_q};
      2:a_r<={context_q,a_r[31:0]};3:b_r<={context_q,b_r[31:0]};endcase
     state_r<=FETCH;
    end
    SHIFT:begin
     a_r<=shift_right_r?(a_r>>1):(a_r<<1);
     if(shift_left_r==1)state_r<=FETCH;else shift_left_r<=shift_left_r-1'b1;
    end
    ALU_LOW:begin alu_low_r<=alu_sum[31:0];alu_carry_r<=alu_sum[32];state_r<=ALU_HIGH;end
    ALU_HIGH:begin
     if(!alu_compare_r)a_r<={alu_sum[31:0],alu_low_r};
     else if(alu_ge_r?alu_sum[32]:!alu_sum[32])pc_r<=alu_target_r;
     state_r<=FETCH;
    end
    REQUEST:if(block_request_ready_i)begin state_r<=RECEIVE;index_r<=0;end
    RECEIVE:begin
     if(take_w)begin
      if(index_r>=512)fail(8'h25);
      else begin
       index_r<=index_r+1'b1;
       if(kind_r==DIR_KIND&&!flags_r[3]&&!flags_r[4])begin
        if(index_r[4:0]==0)begin entry_match_r<=block_data_i==name_byte(0);entry_first_r<=block_data_i;if(block_data_i==0)flags_r[4]<=1;end
        else if(index_r[4:0]<11)entry_match_r<=entry_match_r&&block_data_i==name_byte(index_r[4:0]);
        if(index_r[4:0]==11)entry_attr_r<=block_data_i;
        if(index_r[4:0]==31&&entry_match_r&&entry_first_r!=8'he5&&(entry_attr_r&8'h18)==0&&entry_attr_r!=8'h0f)flags_r[3]<=1;
       end else if(kind_r==FILE_KIND&&remaining_r!=0)begin remaining_r<=remaining_r-1'b1;file_bytes_o<=file_bytes_o+1'b1;end
      end
     end
     if(block_done_i)begin if(index_r!=512)fail(8'h26);else state_r<=FETCH;end
    end
    FAIL:begin end
    FINISH:begin end
    default:fail(8'hff);
   endcase
  end
 end
endmodule
