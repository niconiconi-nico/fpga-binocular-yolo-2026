// Independent CRC rejection experiment: keep and drain every payload; suppress bad-frame valid.
// No change to payload, YOLO arithmetic or FIFO scheduling. Existing overflow limits remain.
/*******************************MILIANKE*******************************
*Company : MiLianKe Electronic Technology Co., Ltd.
*WebSite:https://www.milianke.com
*TechWeb:https://www.uisrc.com
*tmall-shop:https://milianke.tmall.com
*jd-shop:https://milianke.jd.com
*taobao-shop1: https://milianke.taobao.com
*Create Date: 2022/12/23
*Module Name:
*File Name:
*Description: 
*The reference demo provided by Milianke is only used for learning. 
*We cannot ensure that the demo itself is free of bugs, so users 
*should be responsible for the technical problems and consequences
*caused by the use of their own products.
*Copyright: Copyright (c) MiLianKe
*All rights reserved.
*Revision: 1.1
*Signal description
*1) I_ input
*2) O_ output
*3) IO_ input output
*4) S_ system internal signal
*5) _n activ low
*6) _dg debug signal 
*7) _r delay or register
*8) _s state mechine
*********************************************************************/

/*******************************uimac_rx模锟斤拷*********************
--锟斤拷锟斤拷锟斤拷锟斤拷锟斤拷锟斤拷锟斤拷频锟絬imac_rx锟斤拷锟秸匡拷锟斤拷锟斤拷模锟斤拷
--锟斤拷模锟斤拷锟斤拷要锟斤拷锟斤拷锟铰硷拷锟斤拷锟斤拷锟杰ｏ拷
--1.锟斤拷锟解部phy芯片锟斤拷锟斤拷mac帧锟斤拷锟斤拷锟斤拷mac帧锟阶诧拷锟斤拷锟斤拷锟斤拷mac锟斤拷址锟斤拷锟剿猴拷帧锟斤拷锟酵癸拷锟剿★拷
--2.锟节诧拷锟斤拷模锟斤拷crc32_check 锟斤拷每帧锟斤拷锟斤拷迚锟斤拷 CRC32 值锟侥硷拷锟姐，锟叫讹拷锟斤拷锟捷碉拷锟斤拷确锟皆★拷
--3.识锟斤拷锟斤拷盏锟絤ac锟斤拷锟斤拷帧锟斤拷锟斤拷模锟斤拷uimac_tx_frame_ctrl锟斤拷取锟斤拷锟斤拷帧锟叫碉拷锟斤拷停时锟斤拷锟皆磎ac锟斤拷址锟斤拷锟斤拷锟絬imac_tx模锟介。
--4.mac_receive_fifo锟斤拷桑锟絧hy锟斤拷锟斤拷时锟接猴拷锟矫伙拷锟斤拷锟斤拷时锟斤拷之锟斤拷锟绞憋拷锟斤拷锟阶拷锟斤拷锟斤拷锟斤拷锟斤拷锟斤拷锟斤拷锟斤拷
*********************************************************************/

`timescale 1ns / 1ps

module uimac_rx 
(
input 	wire [47:0]  	I_mac_local_addr,	//锟斤拷锟斤拷MAC锟斤拷址
input 	wire         	I_crc32_en,//使锟斤拷CRC校锟斤拷
input 	wire         	I_reset,//系统锟斤拷位

//MAC锟斤拷锟斤拷锟斤拷锟捷凤拷锟酵革拷锟较诧拷协锟斤拷
input	wire         	I_mac_rclk,	
output 	wire         	O_mac_rvalid,
output 	wire [7 :0]   	O_mac_rdata,
output 	wire [15:0]  	O_mac_rdata_type,
output 	wire         	O_mac_rdata_error,
//锟斤拷锟斤拷PUASE锟斤拷锟狡碉拷mac_send
output 	wire        	O_mac_pause_en,
output 	wire [21:0] 	O_mac_pause_time,
output 	wire [47:0] 	O_mac_pause_addr,
//锟斤拷硬锟斤拷锟斤拷锟饺★拷锟斤拷锟斤拷MAC锟斤拷锟斤拷
input 	wire         	I_gmii_rclk,
input 	wire        	I_gmii_rvalid,
input 	wire [7:0]   	I_gmii_rdata
);

wire [7 :0]  mac_rdata;
reg          mac_rdata_valid;
reg [15:0]	 mac_rdata_type;
reg          mac_rdata_error;

assign O_mac_rdata       = mac_rdata;
assign O_mac_rvalid 	 = mac_rdata_valid;
assign O_mac_rdata_type  = mac_rdata_type;
reg mac_read_error;
assign O_mac_rdata_error = mac_read_error;

reg  [10:0]  mac_rdata_cnt;
reg          mac_wfifo_en;
reg          mac_rfifo_en;
reg          crc_en;
reg  [2:0]   crc_cnt;
reg  [2:0]   STATE;
reg  [1:0]   S_RFIFO;
wire [31:0]  crc_data_out;

reg  [47:0]  dst_mac_addr;
reg  [47:0]  src_mac_addr;
reg  [15:0]  mac_frame_type;
reg          mac_pause_en;
reg  [3:0]   cnt;

reg  [10:0]  mac_wfifo_data_cnt_info;
reg          mac_wfifo_en_info;
reg          mac_rfifo_en_info;
wire [26:0]  mac_rfifo_data_info; // CRC encoded in bit15: accepted EtherTypes have bit15=0
reg  [10:0]  mac_rdata_len;
wire         mac_rfifo_empty_info;

reg  [7:0]   mac_rdata_r1, mac_rdata_r2, mac_rdata_r3 ,mac_rdata_r4;
reg          mac_rvalid_r1, mac_rvalid_r2, mac_rvalid_r3 ,mac_rvalid_r4;


localparam  WAIT_SFD 			= 3'd0;
localparam  CHECK_MAC_HEADER 	= 3'd1;
localparam  WRITE_FIFO 			= 3'd2;
localparam  RECORD_FRAME_LENGTH = 3'd3;
localparam  WAIT_FRAME_END 		= 3'd4;

localparam  WAIT_MAC_FRAME 		= 0;
localparam  READ_MAC_FRAME_DATA_LENGTH = 1;
localparam  READ_MAC_FRAME_DATA = 2;

localparam  ARP_TYPE = 16'h0806;
localparam  IP_TYPE  = 16'h0800;
localparam  MAC_CONTROL_TYPE  = 16'h8808;

assign  O_mac_pause_addr = src_mac_addr;
//assign frame_detect_next = (data_window==56'h55555555555555)&(I_gmii_rdata==8'hd5);//锟叫讹拷前锟斤拷锟斤拷
//assign frame_detect_next = (data_window==48'h555555555555)&(I_gmii_rdata==8'h55);

reg [7:0] rst_cnt;	
(* async_reg = "true" *) reg [1:0] gmii_rx_reset_sync;
always @(posedge I_gmii_rclk or posedge I_reset) begin
    if (I_reset) gmii_rx_reset_sync <= 2'b00;
    else gmii_rx_reset_sync <= {gmii_rx_reset_sync[0], 1'b1};
end
wire gmii_rx_common_reset = ~gmii_rx_reset_sync[1];
always@(posedge I_gmii_rclk or posedge gmii_rx_common_reset)begin
	if(gmii_rx_common_reset)
		rst_cnt <=0;
	else if(rst_cnt[7]==0 )
		rst_cnt <= rst_cnt + 1'b1;
end

wire gmii_rx_rst = ~rst_cnt[7];
// FIFO and receive pipeline retain their common reset; reader releases locally.
(* async_reg = "true" *) reg [1:0] mac_rx_reset_sync;
always @(posedge I_mac_rclk or posedge gmii_rx_rst) begin
    if (gmii_rx_rst) mac_rx_reset_sync <= 2'b00;
    else mac_rx_reset_sync <= {mac_rx_reset_sync[0], 1'b1};
end
wire mac_rx_reset = ~mac_rx_reset_sync[1];

always@(posedge I_gmii_rclk or posedge gmii_rx_rst)begin
	if(gmii_rx_rst) begin
		mac_rdata_r1 		<= 8'd0;
		mac_rdata_r2 		<= 8'd0;
		mac_rdata_r3 		<= 8'd0;
		mac_rdata_r4 		<= 8'd0;
	end
	else begin //锟斤拷4锟斤拷 锟斤拷锟斤拷锟斤拷锟叫碏IFO只写锟斤拷效锟斤拷锟斤拷,锟斤拷锟斤拷写锟斤拷CRC锟斤拷锟斤拷
		mac_rdata_r1 		<= I_gmii_rdata;
		mac_rdata_r2 		<= mac_rdata_r1;
		mac_rdata_r3 		<= mac_rdata_r2;
		mac_rdata_r4 		<= mac_rdata_r3;
	end
end	

always@(posedge I_gmii_rclk or posedge gmii_rx_rst)begin
	if(gmii_rx_rst) begin
		mac_rvalid_r1 		<= 8'd0;
		mac_rvalid_r2 		<= 8'd0;
		mac_rvalid_r3 		<= 8'd0;
		mac_rvalid_r4 		<= 8'd0;
	end
	else begin //锟斤拷4锟斤拷 锟斤拷锟斤拷锟斤拷锟叫碏IFO只写锟斤拷效锟斤拷锟斤拷,锟斤拷锟斤拷写锟斤拷CRC锟斤拷锟斤拷
		mac_rvalid_r1 		<= I_gmii_rvalid;
		mac_rvalid_r2 		<= mac_rvalid_r1;
		mac_rvalid_r3 		<= mac_rvalid_r2;
		mac_rvalid_r4 		<= mac_rvalid_r3;
	end
end

udp_pkg_buf #(
.DATA_WIDTH_W(8), 
.DATA_WIDTH_R(8)  , 
.ADDR_WIDTH_W(12) , 
.ADDR_WIDTH_R(12) , 
.SHOW_AHEAD_EN(1'b1), 
.OUTREG_EN("NOREG")
) 
mac_receive_fifo(
.rst	(gmii_rx_rst),  //asynchronous port,active hight
.clkw	(I_gmii_rclk),  //write clock
.we		(mac_wfifo_en & I_gmii_rvalid),  //write enable,active hight
.di		(mac_rdata_r4),  //write data
.clkr	(I_mac_rclk),  //read clock
.re		(mac_rfifo_en),  //read enable,active hight
.dout	(mac_rdata),  //read data
.wrusedw(),  //stored data number in fifo
.rdusedw() //available data number for read      
) ;


udp_pkg_buf #(
.DATA_WIDTH_W(27), 
.DATA_WIDTH_R(27)  , 
.ADDR_WIDTH_W(7) , 
.ADDR_WIDTH_R(7) , 
.SHOW_AHEAD_EN(1'b1), 
.OUTREG_EN("NOREG")
) 
mac_rdata_len_fifo(
.rst	(gmii_rx_rst),  //asynchronous port,active hight
.clkw	(I_gmii_rclk),  //write clock
.we		(mac_wfifo_en_info),  //write enable,active hight
.di		({mac_wfifo_data_cnt_info,mac_rdata_error,mac_frame_type[14:0]}),   //write data
.clkr	(I_mac_rclk),  //read clock
.re		(mac_rfifo_en_info),  //read enable,active hight
.dout	(mac_rfifo_data_info),  //read data
.empty_flag	(mac_rfifo_empty_info)     
) ;

crc32_check crc32_check_inst
(
.reset			(gmii_rx_rst), 
.clk			(I_gmii_rclk), 
.CRC32_en		(crc_en & I_crc32_en), 
.CRC32_init		(~mac_rvalid_r4),       
.data			(mac_rdata_r4), 
.CRC_data		(crc_data_out)
);

//MAC帧锟斤拷锟斤拷,锟斤拷锟斤拷锟秸凤拷锟斤拷锟斤拷锟斤拷锟斤拷锟斤拷锟斤拷锟斤拷锟斤拷锟捷ｏ拷锟斤拷要锟斤拷锟斤拷帧锟斤拷锟狡ｏ拷通知锟斤拷锟斤拷模锟斤拷
uimac_tx_frame_ctrl mac_tx_frame_ctrl_inst (
.I_clk				(I_gmii_rclk), 
.I_reset			(gmii_rx_rst), 
.I_mac_pause_en		(mac_rvalid_r4 & mac_pause_en), 
.I_mac_data			(mac_rdata_r4), 
.O_mac_pause_en		(O_mac_pause_en), 
.O_mac_pause_time	(O_mac_pause_time)
);
	 
			 
always@(posedge I_gmii_rclk or posedge gmii_rx_rst)  begin
    if(gmii_rx_rst) begin
		dst_mac_addr 		<= 48'd0;
		src_mac_addr 		<= 48'd0;
		mac_frame_type 		<= 16'd0;
		mac_wfifo_en 		<= 1'b0;
		mac_wfifo_en_info 	<= 1'b0;	
		mac_wfifo_data_cnt_info <= 11'd0;
		cnt 				<= 4'd0;
		crc_en 				<= 1'b0;
		crc_cnt 			<= 3'd4;
        mac_rdata_error 	<= 1'b1;
		mac_pause_en 		<= 1'b0;	
		STATE 				<= WAIT_SFD;	
	end
	else begin
		case(STATE)
			WAIT_SFD:begin
				if( mac_rvalid_r4 & (mac_rdata_r4 == 8'hd5)) begin//锟斤拷太锟斤拷帧锟斤拷始同锟斤拷锟斤拷一锟斤拷锟街斤拷为MAC锟街讹拷
					crc_en <= 1'b1;//使锟斤拷CRC
					STATE  <= CHECK_MAC_HEADER;//锟斤拷锟斤拷帧头锟斤拷锟斤拷
				end					
				else
					STATE <= WAIT_SFD;
			end
			CHECK_MAC_HEADER:begin		   
				case(cnt)
				4'd0 : begin dst_mac_addr[47:40] 	<= mac_rdata_r4; cnt <= cnt + 1'b1; end //目锟侥碉拷MAC
				4'd1 : begin dst_mac_addr[39:32] 	<= mac_rdata_r4; cnt <= cnt + 1'b1; end //目锟侥碉拷MAC
				4'd2 : begin dst_mac_addr[31:24] 	<= mac_rdata_r4; cnt <= cnt + 1'b1; end //目锟侥碉拷MAC
				4'd3 : begin dst_mac_addr[23:16] 	<= mac_rdata_r4; cnt <= cnt + 1'b1; end //目锟侥碉拷MAC
				4'd4 : begin dst_mac_addr[15 :8] 	<= mac_rdata_r4; cnt <= cnt + 1'b1; end //目锟侥碉拷MAC
				4'd5 : begin dst_mac_addr[7  :0] 	<= mac_rdata_r4; cnt <= cnt + 1'b1; end //目锟侥碉拷MAC
				4'd6 : begin src_mac_addr[47:40] 	<= mac_rdata_r4; cnt <= cnt + 1'b1; end //目锟侥碉拷MAC
				4'd7 : begin src_mac_addr[39:32] 	<= mac_rdata_r4; cnt <= cnt + 1'b1; end //源锟斤拷MAC
				4'd8 : begin src_mac_addr[31:24] 	<= mac_rdata_r4; cnt <= cnt + 1'b1; end //源锟斤拷MAC
				4'd9 : begin src_mac_addr[23:16] 	<= mac_rdata_r4; cnt <= cnt + 1'b1; end //源锟斤拷MAC
				4'd10: begin src_mac_addr[15 :8] 	<= mac_rdata_r4; cnt <= cnt + 1'b1; end //源锟斤拷MAC
				4'd11: begin src_mac_addr[7  :0] 	<= mac_rdata_r4; cnt <= cnt + 1'b1; end //源锟斤拷MAC
				4'd12: begin mac_frame_type[15 :8] 	<= mac_rdata_r4; cnt <= cnt + 1'b1; end //源锟斤拷MAC
				4'd13: begin 
						cnt <= 4'd0; 
						mac_frame_type[7:0] <= mac_rdata_r4; 									 
						if(dst_mac_addr == I_mac_local_addr) begin //锟叫讹拷MAC锟斤拷址锟角凤拷一锟斤拷
							if({mac_frame_type[15:8],mac_rdata_r4} == IP_TYPE || {mac_frame_type[15:8],mac_rdata_r4} == ARP_TYPE) begin //帧锟斤拷锟酵癸拷锟斤拷
								mac_wfifo_en 	<= 1'b1;//写FIFO使锟杰ｏ拷只写锟斤拷锟斤拷效锟斤拷锟捷诧拷锟斤拷
								STATE 			<= WRITE_FIFO;
							end
							else begin //锟斤拷要锟斤拷锟剿碉拷帧
								mac_wfifo_en 	<= 1'b0;//锟斤拷止写FIFO
								STATE 			<= WAIT_FRAME_END;//锟斤拷锟剿革拷帧锟饺达拷帧锟斤拷锟斤拷											 
							end
						end
						else if(dst_mac_addr == 48'h0180c2000001) begin  //锟斤拷锟侥匡拷牡锟街肺?8'h0180c2000001锟斤拷锟教讹拷值锟斤拷锟斤拷mac锟斤拷锟斤拷帧锟斤拷锟斤拷要锟斤拷锟斤拷PAUSE锟斤拷锟斤拷锟斤拷
							mac_wfifo_en <= 1'b0;
						 	STATE 		 <= WAIT_FRAME_END;
							if({mac_frame_type[15:8],mac_rdata_r4} == MAC_CONTROL_TYPE)//锟斤拷锟斤拷锟斤拷锟斤拷锟街讹拷 锟斤拷要锟斤拷锟斤拷PAUSE锟斤拷锟斤拷锟斤拷
								mac_pause_en <= 1'b1;//MAC锟斤拷锟斤拷帧锟斤拷效
							 else
								mac_pause_en <= 1'b0;
						end
						else if(dst_mac_addr == 48'hffffffffffff) begin  //锟斤拷锟节广播锟斤拷址锟斤拷只锟斤拷锟斤拷ARP锟斤拷锟斤拷锟斤拷锟斤拷锟斤拷锟酵的广播锟斤拷全锟斤拷锟斤拷锟斤拷
							if({mac_frame_type[15:8],mac_rdata_r4} == ARP_TYPE) begin
								mac_wfifo_en 		<= 1'b1;	//写帧锟斤拷锟斤拷FIFO使锟杰ｏ拷只写锟斤拷锟斤拷效锟斤拷锟捷诧拷锟斤拷
								STATE 				<= WRITE_FIFO; 
                            end  											 
							else begin //锟斤拷要锟斤拷锟剿碉拷帧
								mac_wfifo_en 		<= 1'b0;  //停止写帧锟斤拷锟斤拷FIFO
								STATE 				<= WAIT_FRAME_END;//锟斤拷锟剿革拷帧锟饺达拷帧锟斤拷锟斤拷
							end
						end
						else begin //锟斤拷要锟斤拷锟剿碉拷帧
							mac_wfifo_en 			<= 1'b0; //停止写帧锟斤拷锟斤拷FIFO
							STATE 					<= WAIT_FRAME_END;//锟斤拷锟剿革拷帧锟饺达拷帧锟斤拷锟斤拷
						end
				end
				endcase
            end					
			WRITE_FIFO:begin//锟斤拷去锟斤拷锟阶诧拷锟斤拷锟絠p锟斤拷锟捷憋拷锟斤拷锟斤拷arp帧锟斤拷锟斤拷 mac_receive_fifo 锟叫ｏ拷同时锟皆碉拷前锟斤拷锟捷帮拷锟侥筹拷锟斤拷迚锟斤拷统锟斤拷
				if(I_gmii_rvalid) begin //写帧锟斤拷息FIFO
					mac_wfifo_data_cnt_info 	<= mac_wfifo_data_cnt_info + 1'b1;//锟斤拷效锟斤拷锟捷硷拷锟斤拷锟斤拷					
					STATE 						<= WRITE_FIFO;
				end
				else begin
					if(crc_cnt == 3'd0) begin //CRC校锟斤拷
						if(I_crc32_en && crc_data_out != 32'hc704dd7b)
							mac_rdata_error 	<= 1'b1;//校锟斤拷锟斤拷确					
						else
							 mac_rdata_error 	<= 1'b0;//校锟斤拷锟斤拷锟?
						mac_wfifo_en 			<= 1'b0;
						mac_wfifo_en_info 		<= 1'b1;	//写帧锟斤拷息FIFO使锟斤拷	
						crc_en 					<= 1'b0;
						crc_cnt 				<= 3'd4;
						STATE 					<= RECORD_FRAME_LENGTH; //写锟斤拷帧锟斤拷息锟斤拷 帧锟斤拷息FIFO			  
					end	
					else 
						crc_cnt	 <= crc_cnt - 1'b1; //CRC锟斤拷锟斤拷锟斤拷锟斤拷锟?       				
				end			
			end
			RECORD_FRAME_LENGTH:begin//写帧锟斤拷息锟斤拷珊螅氐锟阶刺拷锟絎AIT_SFD
				mac_wfifo_en_info 		<= 1'b0;
				mac_wfifo_data_cnt_info <= 11'd0;
				STATE 					<= WAIT_SFD;//锟截碉拷帧探锟斤拷状态锟斤拷
			end
			WAIT_FRAME_END:begin//锟饺达拷帧锟斤拷锟斤拷   				
				if(mac_rvalid_r4)
					STATE 				<= WAIT_FRAME_END;
				else begin
					crc_en 				<= 1'b0;     //add bug fixed 2016.10.7
                    mac_pause_en 		<= 1'b0;							
					STATE 				<= WAIT_SFD;
				end
			end
		endcase	
    end
end

always@(posedge I_mac_rclk or posedge mac_rx_reset) begin
    if(mac_rx_reset) begin
        mac_rfifo_en_info 	<= 1'b0;
        mac_read_error <= 1'b0;
		mac_rdata_len 		<= 11'd0;
		mac_rdata_cnt 		<= 11'd0;
		mac_rfifo_en 		<= 1'b0;
		mac_rdata_type   	<= 16'd0;
		mac_rdata_valid 	<= 1'b0;
		S_RFIFO 			<= WAIT_MAC_FRAME;
	end
    else begin
		case(S_RFIFO)
			WAIT_MAC_FRAME:begin
				if(!mac_rfifo_empty_info) begin //锟斤拷锟斤拷MAC锟斤拷息FIFO锟角匡拷
					mac_rfifo_en_info 	<= 1'b1;//锟斤拷1帧MAC锟斤拷息			
					S_RFIFO 			<= READ_MAC_FRAME_DATA_LENGTH;
				end
				else
					S_RFIFO 			<= WAIT_MAC_FRAME;
			end
			READ_MAC_FRAME_DATA_LENGTH:begin
				mac_rdata_len 		<= mac_rfifo_data_info[26:16];//MAC帧锟斤拷锟斤拷
				mac_rdata_type   	<= {1'b0,mac_rfifo_data_info[14:0]}; //MAC锟斤拷锟斤拷
				mac_rfifo_en_info 	<= 1'b0;
				mac_rfifo_en 		<= 1'b1;//锟斤拷锟斤拷锟斤拷FIFO
				mac_read_error <= mac_rfifo_data_info[15];
				mac_rdata_valid 	<= !mac_rfifo_data_info[15];//锟斤拷锟斤拷锟斤拷效
				S_RFIFO 			<= READ_MAC_FRAME_DATA;
			end
			READ_MAC_FRAME_DATA:begin
				if(mac_rdata_cnt	< (mac_rdata_len - 1) ) begin//锟斤拷锟斤拷一帧锟斤拷锟斤拷
					mac_rdata_cnt 	<= mac_rdata_cnt + 1'b1;
					S_RFIFO 		<= READ_MAC_FRAME_DATA;
				end
				else begin
					mac_rfifo_en		<= 1'b0;
					mac_rdata_valid 	<= 1'b0;
					mac_rdata_cnt 		<= 11'd0;
					mac_rdata_len 		<= 11'd0;
					mac_rdata_type   	<= 16'd0;
					S_RFIFO 			<= WAIT_MAC_FRAME;
				end
			end
         endcase
		end
	end

endmodule
