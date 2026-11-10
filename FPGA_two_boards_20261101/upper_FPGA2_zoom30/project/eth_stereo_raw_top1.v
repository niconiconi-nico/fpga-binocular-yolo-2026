

module eth_stereo_raw_top1 (
    input wire        I_sys_clk,
    input wire[2:0] I_mode_key_n,input wire I_capture_key_n,
    output wire O_left_tx,O_right_tx,input wire I_left_rx,I_right_rx,   // CLAUDE Z10 GIMBAL: Emm pitch (left) / yaw (right) UART
    input wire I_a_rgmii_rxc,I_a_rgmii_rx_ctl,input wire [3:0] I_a_rgmii_rxd,
    output wire O_a_rgmii_txc,O_a_rgmii_tx_ctl,output wire [3:0] O_a_rgmii_txd,
    output wire O_phy_rst,

      
    output wire       O_cam_scl,
    inout  wire       IO_cam_sda,
    output wire       O_cam_24m,
    output wire       O_cam_rst,
      



    output wire       O_tmds_ch0_p,
    output wire       O_tmds_ch1_p,
    output wire       O_tmds_ch2_p,
    output wire       O_tmds_clk_p,

    inout wire        IO_rx_clk_pad_n, 
    inout wire        IO_rx_clk_pad_p, 
    inout wire[3:0]   IO_rx_data_pad_n,
    inout wire[3:0]   IO_rx_data_pad_p,

    output wire[12:0] ddr_addr,
    output wire[ 1:0] ddr_ba,
    output wire[ 0:0] ddr_cke,
    output wire[ 0:0] ddr_odt,
    output wire[ 0:0] ddr_cs_n,
    output wire       ddr_ras_n,
    output wire       ddr_cas_n,
    output wire       ddr_we_n,
    output wire[ 0:0] ddr_ck_p,
    output wire[ 0:0] ddr_ck_n,
    inout wire[1:0]   ddr_dm,
    inout wire[15:0]  ddr_dq,
    inout wire[1:0]   ddr_dqs_p,
    inout wire[1:0]   ddr_dqs_n   
);
    wire local_reader_hold;wire[1:0]local_reader_bank;

    // Local diagnostic pin adaptation only: no R10 reset, N2/J14 buttons or R11 screen output.
    // Those pins conflict with the final Ethernet board pin contract; reference data chain unchanged.
    wire I_rst_n=1'b1; wire [1:0] I_button=2'b11; wire O_screen_pwm;



    wire        	S_100m_clk;
    wire        	S_24m_clk;
    wire        	S_aux_50m_clk;
	wire        	S_10m_clk;
		
	wire        	S_pll_lock;
    wire        	S_rst_n;
	reg  [17:0] 	S_cam_power_cnt;
	reg         	S_cam_pwdnb;
	reg         	S_cam_i2c_ready;
	wire [15:0] S_cam_sensor_id;
	wire        S_cam_sensor_id_ok;
	wire        S_cam_i2c_error;
	localparam integer CAM_PWDNB_LOW_CYCLES = 23810;  // >= 1 ms at 23.809524 MHz
	localparam integer CAM_I2C_START_CYCLES = 142857; // release + >= 5 ms
	
	wire [15:0] 	S_ae;
    wire [15:0] 	S_ag;
    wire 			S_cam_cfg_done;
    wire 			S_ae_cfg_done;
    wire 			S_ae_req; 
	
	wire        	S_csi_rx_clk;  
    wire        	S_hs_rx_valid;  
    wire[15:0]  	S_hs_rx_data;   
	wire[1:0]   	S_lane_error;
	
	wire        	S_csi_frame_start;       
	wire        	S_csi_frame_end;         
	wire        	S_csi_valid;             
	wire[31:0]  	S_csi_data;  
	wire [15:0] S_csi_data_length;
		
	wire        	S_raw10_frame_start; 
	wire        	S_raw10_frame_end;   
	wire        	S_raw10_valid;       
	wire [39:0] 	S_raw10_data;

	wire 			S_axis_tlast;  
	wire 			S_axis_tuser;  
	wire [39:0]		S_axis_tdata;  
	wire 			S_axis_tvalid; 
	
	wire [39:0]		S_raw_tdata ;
	wire			S_raw_tlast ;
	wire 			S_raw_tvalid;
	wire 			S_raw_tuser ;
	
	wire			S_ISP_O_tready;
	wire [127:0]	S_ISP_O_tdata ;
	wire 			S_ISP_O_tlast ;
	wire 			S_ISP_O_tuser ;
	wire 			S_ISP_O_tvalid; 
	

    wire        S_ddr_clk;
    wire        S_hdmi_pixel_clk;
    wire        S_hdmi_serial_clk;
    wire        S_hdmi_rst_n;
    wire        S_video_out_rst_n;


    wire        S_vi_128b_frame_start;
    wire        S_vi_128b_valid;      
    wire[127:0] S_vi_128b_data;    
    
    wire        S_video_out_rd_busy;
    wire        S_video_in_wr_busy; 
    wire[1:0]   S_video_out_rp;     

    wire        S_ddr_user_wr_en;       
    wire        S_ddr_user_rd_en;       
    wire[24:0]  S_ddr_user_addr;        
    wire[127:0] S_ddr_user_wr_data;     
    wire        S_ddr_user_ready;       
    wire        S_ddr_user_rd_valid;    
    wire[127:0] S_ddr_user_rd_data;     

    wire        S_vi_ddr_wr_en;   
    wire[24:0]  S_vi_ddr_wr_addr; 
    wire[127:0] S_vi_ddr_wr_data;
    wire        S_vi_ddr_wr_ready;

    wire        S_vo_ddr_rd_en;   
    wire[24:0]  S_vo_ddr_rd_addr; 
    wire        S_vo_ddr_rd_ready;
    wire        S_vo_dbg_fifo_rst;
    wire        S_vo_dbg_ddr_rd_valid;
    wire        S_vo_dbg_fifo_rd_en;
    wire        S_vo_dbg_fifo_empty;

    wire        S_init_calib_complete; 
    wire[24:0]  S_mc_app_addr;          
    wire[2:0]   S_mc_app_cmd;           
    wire        S_mc_app_en;            
    wire[127:0] S_mc_app_wdf_data;      
    wire        S_mc_app_wdf_end;       
    wire[15:0]  S_mc_app_wdf_mask;      
    wire        S_mc_app_wdf_wren;      
    wire[127:0] S_mc_app_rd_data;       
    wire        S_mc_app_rd_data_end;   
    wire        S_mc_app_rd_data_valid; 
    wire        S_mc_app_rdy;           
    wire        S_mc_app_wdf_rdy;       
    wire        S_mc_dbg_fifo_afull;
    wire        S_mc_dbg_app_rdy;
    wire        S_mc_dbg_wdf_rdy;
    wire        S_mc_dbg_cmd_pop;

    wire        S_hdmi_vsync;
    wire        S_hdmi_hsync;
    wire        S_hdmi_de;
    wire        S_hdmi_user;
    wire        S_hdmi_last;
    wire        S_video_out_vsync;
    wire        S_hdmi_window_rd_en;
    wire        S_hdmi_out_vsync;
    wire        S_hdmi_out_hsync;
    wire        S_hdmi_out_de;
    wire[23:0]  S_hdmi_out_data;

    wire[23:0]  S_video_rd_data;
    // CLAUDE TRACK47_NR: unconsumed debug-seen flags and MIPI diagnostic registers removed (no reader in this design).


    assign O_screen_pwm = 1'b1;
    assign S_video_out_vsync = ~S_hdmi_vsync;
	
	
    assign S_rst_n 		= S_pll_lock;
    assign S_hdmi_rst_n = S_pll_lock;

	
	// J9 pin 37 is connected to the module's PWDNB/XSHUTDN input.
	// Hold the sensor in power-down after PLL lock, then allow its internal
	// power-up sequence to finish before the first I2C transaction.
	always @(posedge S_24m_clk or negedge S_pll_lock) begin
		if (!S_pll_lock) begin
			S_cam_power_cnt <= 18'd0;
			S_cam_pwdnb <= 1'b0;
			S_cam_i2c_ready <= 1'b0;
		end else begin
			if (S_cam_power_cnt < CAM_I2C_START_CYCLES)
				S_cam_power_cnt <= S_cam_power_cnt + 1'b1;
			if (S_cam_power_cnt >= CAM_PWDNB_LOW_CYCLES)
				S_cam_pwdnb <= 1'b1;
			if (S_cam_power_cnt >= CAM_I2C_START_CYCLES - 1)
				S_cam_i2c_ready <= 1'b1;
		end
	end

	assign O_cam_rst 	= S_cam_pwdnb;
    assign O_cam_24m 	= S_24m_clk;
	
	
	
	
    PLL u_PLL(
        .refclk      ( I_sys_clk         ),
        .reset    	 ( ~I_rst_n          ),
        
        .clk0_out    ( S_100m_clk        ),
        .clk1_out    ( S_24m_clk         ),

        .clk4_out    ( S_hdmi_pixel_clk  ),
        .clk5_out    ( S_hdmi_serial_clk ),

        .lock        ( S_pll_lock        )

    );


	

  
  // CLAUDE Z14 (2026-10-31, board: left view washed out next to the right view): closed-loop auto exposure of the lower
  // board (CC24 u_sc520_ae, il3 sc520_auto_exposure.sv unchanged: RAW10 green frame mean kept in 256..384 by exposure
  // then gain steps, 4 settle frames) replaces the fixed maximum exposure / 16x gain of ae_set. Resets as CC24 (common
  // assertion, per-clock synchronized release); telemetry outputs left open.
  wire ae_common_ready=S_rst_n && S_cam_i2c_ready;
  (* async_reg="true" *) reg [1:0] ae_pixel_reset_sync,ae_cfg_reset_sync;
  always @(posedge S_csi_rx_clk or negedge ae_common_ready)
    if(!ae_common_ready)ae_pixel_reset_sync<=0;
    else ae_pixel_reset_sync<={ae_pixel_reset_sync[0],1'b1};
  always @(posedge S_24m_clk or negedge ae_common_ready)
    if(!ae_common_ready)ae_cfg_reset_sync<=0;
    else ae_cfg_reset_sync<={ae_cfg_reset_sync[0],1'b1};
  wire ae_hold;                                                  // CLAUDE Z17: AE lock (driven below, after the vision core)
  sc520_auto_exposure u_sc520_ae (
      .pixel_clk(S_csi_rx_clk),.pixel_rst_n(ae_pixel_reset_sync[1]),
      .raw_valid(S_raw_tvalid),.raw_sof(S_raw_tuser),.raw_eol(S_raw_tlast),
      .raw_data(S_raw_tdata),.cfg_clk(S_24m_clk),.cfg_rst_n(ae_cfg_reset_sync[1]),
      .cfg_done(S_cam_cfg_done),.ae_done(S_ae_cfg_done),.cfg_error(S_cam_i2c_error),.hold(ae_hold),
      .ae_req(S_ae_req),.exposure(S_ae),.gain_index(S_ag),
      .applied_exposure(),.applied_gain_index(),.fault(),
      .applied_transactions(),.measured_green_sum(),
      .measured_clipped(),.measurement_pulse(),
      .measured_raw_sequence(),.command_raw_sequence());
  
    uicfgcs520_sensor180 #(
      .CLK_DIV(23809524 / 100000 - 1)
  ) u_uicfgcs520 (
      .I_clk(S_24m_clk),  //系统时钟输入
      .I_rst_n(S_cam_i2c_ready), // SC520CS power-up delay completed
      .I_ae_req(S_ae_req),
      .I_ae(S_ae),
      .I_ag(S_ag),
      .O_cam_scl(O_cam_scl),  //I2C总线，SCL时钟
      .IO_cam_sda(IO_cam_sda),  //I2C总线，SDA数据
      .O_cfg_done(S_cam_cfg_done),  //摄像头寄存器初始化完成
      .O_ae_cfg_done(S_ae_cfg_done),  //AE配置完成
      .O_sensor_id(S_cam_sensor_id),
      .O_sensor_id_ok(S_cam_sensor_id_ok),
      .O_iic_error(S_cam_i2c_error)
  );
	
    mipi_dphy_rx_ph1p_mipiio_wrapper#(
        .DPHY_RX_LOCATION      ( "DPHY0" ),
        .HS_EQUALIZER          ( "3dB"   ),// 828 Mbps/Lane接收均衡
        .HS_VGA_GAIN           ( "8dB" ),//"-3dB","-1.5dB","0dB","1.5dB","3dB","4.5dB","6dB","7.5dB"
        .LANE_NUM              ( 2       ),
        .BYTE_NUM              ( 1       )
    )u_mipi_dphy_rx_ph1p_mipiio_wrapper(
        .I_lp_clk              ( S_100m_clk       ),
        .I_rst                 ( ~S_rst_n         ),

        .I_clk_lane_in_delay   ( 6'd0             ),
        .I_data_lane0_in_delay ( 6'd0             ),
        .I_data_lane1_in_delay ( 6'd0             ),
        .I_data_lane2_in_delay ( 6'd0             ),
        .I_data_lane3_in_delay ( 6'd0             ),

        .I_lane_invert         ( 4'b0000          ),
     
        .O_hs_rx_clk           ( S_csi_rx_clk     ),
        .O_hs_rx_valid         ( S_hs_rx_valid    ),
        .O_hs_rx_data          ( S_hs_rx_data     ),
      
        .O_lp_rx_lane0_p       (  ),
        .O_lp_rx_lane0_n       (  ),
      
        .I_lp_tx_en            ( 1'b0             ),
        .I_lp_tx_lane0_p       ( 1'b1             ),
        .I_lp_tx_lane0_n       ( 1'b1             ),
      
        .O_lane_match_error    (                  ),
        .O_lane_error          ( S_lane_error     ),
      
        .IO_rx_clk_pad_n       ( IO_rx_clk_pad_n  ),
        .IO_rx_clk_pad_p       ( IO_rx_clk_pad_p  ),
        .IO_rx_data_pad_n      ( IO_rx_data_pad_n ),
        .IO_rx_data_pad_p      ( IO_rx_data_pad_p )
    );
	
	
 //  cwc cwc_inst
 //(
 //    .probe0(S_hs_rx_valid),
 //    .probe1(S_hs_rx_data),
 //    .probe2(S_lane_error),
 //    .clk(S_csi_rx_clk)
 //);

 //csi 解码为RAW数据
csi_unpacket_2lane u_csi_unpacket(
.I_clk                 ( S_csi_rx_clk       ),
.I_rst_n               ( S_rst_n        	),
.I_hs_valid            ( S_hs_rx_valid     ),
.I_hs_data             ( S_hs_rx_data      ),

.O_csi_frame_start     ( S_csi_frame_start ),
.O_csi_frame_end       ( S_csi_frame_end   ),
.O_csi_valid           ( S_csi_valid       ),
.O_csi_data            ( S_csi_data        ),
.O_data_length         ( S_csi_data_length )
);


//解码为RAW8
raw10_unpacket_2lane u_raw10_unpacket (
.I_clk  (S_csi_rx_clk),
.I_rst_n(S_rst_n),

.I_csi_frame_start(S_csi_frame_start),
.I_csi_frame_end  (S_csi_frame_end),
.I_csi_valid      (S_csi_valid),
.I_csi_data       (S_csi_data),

.O_raw10_frame_start(S_raw10_frame_start),
.O_raw10_frame_end  (S_raw10_frame_end),
.O_raw10_valid      (S_raw10_valid),
.O_raw10_data       (S_raw10_data)
  );


//将数据转为stream流
uial2axis #(
.IMG_WIDTH(1280),
.IMG_HEIGHT(720),
.INPUT_DATA_WIDTH(40)
) 
u_uial2axis (
.I_native_clk(S_csi_rx_clk),
.I_rst_n     (S_rst_n),
.I_data      (S_raw10_data       ),
.I_data_valid(S_raw10_valid      ),
.I_data_start(S_raw10_frame_start),
.I_data_end  (S_raw10_frame_end  ),
.axis_tvalid (S_axis_tvalid),
.axis_tdata  (S_axis_tdata ),
.axis_tuser  (S_axis_tuser ),
.axis_tlast  (S_axis_tlast )
);
	

// SC520CS原厂HD模式已经直接输出1280x720 RAW10，无需FPGA窗口裁剪。
assign S_raw_tdata  = S_axis_tdata;
assign S_raw_tlast  = S_axis_tlast;
assign S_raw_tvalid = S_axis_tvalid;
assign S_raw_tuser  = S_axis_tuser;


//cwc1 cwc1_Inst
//  (
//      .probe0(S_axis_tuser),
//      .probe1(S_axis_tvalid),
//      .probe2(S_axis_tlast),
//      .probe3(S_axis_tdata),
//      .probe4(S_ISP_O_tuser),
//      .probe5(S_ISP_O_tvalid),
//      .probe6(S_ISP_O_tlast),
//      .probe7(S_ISP_O_tdata),
//      .probe8 (S_raw_tdata ),
//      .probe9 (S_raw_tlast ),
//      .probe10(S_raw_tvalid),
//      .probe11(S_raw_tuser ),
//      .clk(S_csi_rx_clk)
//  );


    // CLAUDE DEPTH: colour-stage output tap (camera clock) for the depth map left capture
    wire [95:0] S_tap_out_data;wire S_tap_out_valid,S_tap_out_sof,S_tap_out_eol;
//ISP算法顶层模块
isp_top u_isp_top (
.axi4s_video_aclk(S_csi_rx_clk),
.I_rst_n         (S_rst_n),
.I_tlast         (S_raw_tlast	),
.I_tuser         (S_raw_tuser	),
.I_tdata         (S_raw_tdata	),
.I_tvalid        (S_raw_tvalid	),
.I_tdest         (),
.O_tready        (S_ISP_O_tready),
.O_tdata         (S_ISP_O_tdata ),
.O_tlast         (S_ISP_O_tlast ),
.O_tuser         (S_ISP_O_tuser ),
.O_tvalid        (S_ISP_O_tvalid),
.I_tready        (),
.O_tap_out_data(S_tap_out_data),.O_tap_out_valid(S_tap_out_valid),.O_tap_out_sof(S_tap_out_sof),.O_tap_out_eol(S_tap_out_eol)
  );


    // ISP output is now RGB565 packed128bit, eight pixels/beat. RAW10 and ISP colour math remain unchanged.
    video_in u_video_in(
        .I_rst_n              (  S_rst_n             ),

        .I_camera_clk         ( S_csi_rx_clk          ),
        .I_camera_frame_start ( S_ISP_O_tuser  ),
        .I_camera_valid       ( S_ISP_O_tvalid ),
        .I_camera_data        ( S_ISP_O_tdata  ),
        .I_mipi_rx_error      ( 1'b0			      ),

        .I_ddr_clk            ( S_ddr_clk             ),
		.I_display_pause      ( 1'b0                  ),
        .I_video_out_rd_busy  ( S_video_out_rd_busy   ),
        .O_video_in_wr_busy   ( S_video_in_wr_busy    ),
        .O_video_out_rp       ( S_video_out_rp        ),

        .O_ddr_user_wr_en     ( S_vi_ddr_wr_en        ),
        .O_ddr_user_addr      ( S_vi_ddr_wr_addr      ),
        .O_ddr_user_wr_data   ( S_vi_ddr_wr_data      ),
        .I_ddr_user_ready     ( S_ddr_user_ready      ),
        .I_reader_hold(local_reader_hold),.I_reader_bank(local_reader_bank)
    );



    assign S_ddr_user_wr_en    = S_vi_ddr_wr_en;

    assign S_ddr_user_rd_en    = S_vo_ddr_rd_en;

    assign S_ddr_user_addr     = S_vi_ddr_wr_en ? S_vi_ddr_wr_addr :
                                 S_vo_ddr_rd_en ? S_vo_ddr_rd_addr : 'd0;

    assign S_ddr_user_wr_data  = S_vi_ddr_wr_data;


    assign S_video_out_rst_n = S_hdmi_rst_n;

    mc_to_user_interface u_mc_to_user_interface(
        .I_clk                   ( S_ddr_clk               ),
        .I_rst_n                 ( S_rst_n                 ),

        .I_ddr_user_wr_en        ( raw_bridge_we        ),
        .I_ddr_user_rd_en        ( raw_bridge_re        ),
        .I_ddr_user_addr         ( raw_bridge_addr         ),
        .I_ddr_user_wr_data      ( raw_bridge_wdata      ),
        .O_ddr_user_ready        ( raw_bridge_ready        ),
        .O_ddr_user_rd_valid     ( raw_bridge_rvalid     ),
        .O_ddr_user_rd_data      ( raw_bridge_rdata      ),
            
        .O_mc_app_en             ( S_mc_app_en             ),
        .O_mc_app_addr           ( S_mc_app_addr           ),
        .O_mc_app_cmd            ( S_mc_app_cmd            ),
        .I_mc_app_rdy            ( S_mc_app_rdy            ),
        .O_mc_app_wdf_wren       ( S_mc_app_wdf_wren       ),
        .O_mc_app_wdf_data       ( S_mc_app_wdf_data       ),
        .O_mc_app_wdf_end        ( S_mc_app_wdf_end        ),
        .O_mc_app_wdf_mask       ( S_mc_app_wdf_mask       ),
        .I_mc_app_wdf_rdy        ( S_mc_app_wdf_rdy        ),
        .I_mc_app_rd_data        ( S_mc_app_rd_data        ),
        .I_mc_app_rd_data_end    ( S_mc_app_rd_data_end    ),
        .I_mc_app_rd_data_valid  ( S_mc_app_rd_data_valid  )
    );



    ph1p35_324_ddr_wrapper u_ph1p35_324_ddr_wrapper(
        .I_sys_clk              ( I_sys_clk              ),
        .I_sys_rst_n            ( S_rst_n                ),

        .O_ddr_clk              ( S_ddr_clk              ),
        .O_init_calib_complete  ( S_init_calib_complete  ),
        .I_mc_app_addr          ( S_mc_app_addr          ),
        .I_mc_app_cmd           ( S_mc_app_cmd           ),
        .I_mc_app_en            ( S_mc_app_en            ),
        .I_mc_app_wdf_data      ( S_mc_app_wdf_data      ),
        .I_mc_app_wdf_end       ( S_mc_app_wdf_end       ),
        .I_mc_app_wdf_mask      ( S_mc_app_wdf_mask      ),
        .I_mc_app_wdf_wren      ( S_mc_app_wdf_wren      ),
        .O_mc_app_rd_data       ( S_mc_app_rd_data       ),
        .O_mc_app_rd_data_end   ( S_mc_app_rd_data_end   ),
        .O_mc_app_rd_data_valid ( S_mc_app_rd_data_valid ),
        .O_mc_app_rdy           ( S_mc_app_rdy           ),
        .O_mc_app_wdf_rdy       ( S_mc_app_wdf_rdy       ),

        .ddr_addr               ( ddr_addr               ),
        .ddr_ba                 ( ddr_ba                 ),
        .ddr_cke                ( ddr_cke                ),
        .ddr_odt                ( ddr_odt                ),
        .ddr_cs_n               ( ddr_cs_n               ),
        .ddr_ras_n              ( ddr_ras_n              ),
        .ddr_cas_n              ( ddr_cas_n              ),
        .ddr_we_n               ( ddr_we_n               ),
        .ddr_ck_p               ( ddr_ck_p               ),
        .ddr_ck_n               ( ddr_ck_n               ),
        .ddr_dm                 ( ddr_dm                 ),
        .ddr_dq                 ( ddr_dq                 ),
        .ddr_dqs_p              ( ddr_dqs_p              ),
        .ddr_dqs_n              ( ddr_dqs_n              )
    );



    uivtc #(
        .H_ActiveSize ( 1280 ),
        .H_FrameSize  ( 1650 ),
        .H_SyncStart  ( 1390 ),
        .H_SyncEnd    ( 1430 ),
        .V_ActiveSize ( 720  ),
        .V_FrameSize  ( 750  ),
        .V_SyncStart  ( 725  ),
        .V_SyncEnd    ( 730  )
    )u_hdmi_vtc(
        .I_vtc_rstn    ( S_hdmi_rst_n    ),
        .I_vtc_clk     ( S_hdmi_pixel_clk ),
        .O_vtc_vs      ( S_hdmi_vsync     ),
        .O_vtc_hs      ( S_hdmi_hsync     ),
        .O_vtc_de_valid( S_hdmi_de        ),
        .O_vtc_user    ( S_hdmi_user      ),
        .O_vtc_last    ( S_hdmi_last      )
    );

    wire eth_lock,eth_ready;
    wire eth125,eth90,eth25;
    pll u_eth_pll(.refclk(I_sys_clk),.reset(1'b0),.clk0_out(eth125),.clk1_out(eth90),.clk2_out(eth25),.lock(eth_lock));
    phy_reset20ms phy_reset(.clk(eth25),.pll_locked(eth_lock),.reset_n(O_phy_rst),.ready(eth_ready));
    wire rxclk,gmii_valid,gmii_error,tx_valid;wire [7:0] gmii_data,tx_data;
    wire eth_reset125,eth_reset_rx;
    reset_domain_sync eth125_release(eth125,!eth_ready,eth_reset125);
    wire eth_reset90;
    reset_domain_sync eth90_release(eth90,!eth_ready,eth_reset90);
    reset_domain_sync rx_release(rxclk,!eth_ready,eth_reset_rx);
    // CLAUDE Z11: ARP-only responder (zoom10 removed the ARP / ICMP responder: the lower board learns this board's MAC only
    // from the ARP reply, so it sent nothing and the right eye stayed black). ICMP echo not answered (user: no ping).
    arp_reply_lite control_reply(.rx_clk(rxclk),.tx_clk(eth125),.rst(!eth_ready),
      .rx_valid(gmii_valid),.rx_error(gmii_error),.rx_data(gmii_data),.tx_valid(tx_valid),.tx_data(tx_data));
    // Actual HDPAD reset hold cause: use existing+90degree release for TX pads.
    // Asynchronous assertion remains; CLK0 data and CLK1 forwarded TXC unchanged.
    rgmii_interface rgmii(.speed_10_100(1'b0),.gmii_tx_clk_d(eth90),.gmii_tx_reset_d(eth_reset90),
        .rgmii_txd(O_a_rgmii_txd),.rgmii_tx_ctl(O_a_rgmii_tx_ctl),.rgmii_txc(O_a_rgmii_txc),
        .rgmii_rxd(I_a_rgmii_rxd),.rgmii_rx_ctl(I_a_rgmii_rx_ctl),.rgmii_rxc(I_a_rgmii_rxc),
        .gmii_tx_reset(eth_reset90),.gmii_tx_clk(eth125),.gmii_txd(tx_data),.gmii_tx_en(tx_valid),.gmii_tx_er(1'b0),
        .gmii_rx_reset(eth_reset_rx),.gmii_rx_clk(rxclk),.gmii_rxd(gmii_data),.gmii_rx_dv(gmii_valid),.gmii_rx_er(gmii_error),
        .gmii_crs(),.gmii_col(),.link_status(),.clock_speed(),.duplex_status());


    wire raw_bridge_we,raw_bridge_re,raw_bridge_ready,raw_bridge_rvalid;
    wire [24:0]raw_bridge_addr;wire[127:0]raw_bridge_wdata,raw_bridge_rdata;
    wire raw_hs,raw_vs,raw_de;wire[23:0]raw_rgb;
    wire mode_hs,mode_vs,mode_de;wire[23:0]mode_rgb;
    wire[7:0]active_mode,requested_mode;reg mode_vs_d;
    wire[7:0]pair_effect_delta=active_mode-8'd38;
    // CLAUDE UPPER_V1: modes 45 (ALIGN, pair effect 7) and 47 (YOLO FLOW tracking) removed
    wire[3:0]pair_effect_mode=4'd0;   // CLAUDE MERGE: pair filters 39-44/46 removed
    always @(posedge S_hdmi_pixel_clk or negedge S_hdmi_rst_n)
      if(!S_hdmi_rst_n)mode_vs_d<=0;else mode_vs_d<=S_hdmi_vsync;
    wire f_mode,f_update,f_good,f_armed,f_fault,f_rta,f_ready,f_arm,f_stop;wire[15:0]f_fid;wire[10:0]f_cx;wire[9:0]f_cy;
    wire[7:0]f_pc,f_yc;wire[3:0]f_cc;wire ms_tick;   // CLAUDE Z11: shared 1 ms tick (gimbal_mc) for the key / hold timers
    mono_keys1 #(.LAST_MODE(51),.DEFAULT_MODE(37),.SKIP_TEMPLATE(1),.MS_TICK(1)) mode_keys(   // CLAUDE DEPTH: 47 = DEPTH
      S_hdmi_pixel_clk,S_hdmi_rst_n,I_mode_key_n,S_hdmi_vsync&&!mode_vs_d,requested_mode,active_mode,
      f_mode,f_armed,f_arm,f_stop,ms_tick);                     // CLAUDE Z10 GIMBAL: K3 hold 1 s = arm, any mode key while armed = STOP
    // CLAUDE Z25 LATENCY: capture (RAW frame start) -> display (bank selected for the next HDMI frame), shown by mono_display6
    wire[1:0]lat_sof_g;wire lat_sel_tg,lat_ok;wire[1:0]lat_sel_idx;wire[11:0]lat_bcd;wire[15:0]lat_cap_bcd,lat_dsp_bcd;
    // CLAUDE Z28C MONITOR: + LAG, 1 s SHOW fps / UDP fps / Mbps (window = wrap of the BCD 0.1 ms timer); rx side only prescales
    wire[1:0]lat_lag;wire net_px,net_frame,net_unit_tg,net_frame_tg;wire[7:0]mon_show_fps,mon_udp_fps;wire[15:0]mon_mbps;
    latency_meter5 lat(.cam_clk(S_csi_rx_clk),.cam_rst_n(S_rst_n),.cam_sof(S_raw_tuser&&S_raw_tvalid),
      .clk(S_hdmi_pixel_clk),.rst_n(S_hdmi_rst_n),.sof_g(lat_sof_g),.sel_tg(lat_sel_tg),.sel_idx(lat_sel_idx),
      .unit_tg(net_unit_tg),.frame_tg(net_frame_tg),
      .ok(lat_ok),.lat_bcd(lat_bcd),.cap_bcd(lat_cap_bcd),.dsp_bcd(lat_dsp_bcd),.lag(lat_lag),
      .show_fps(mon_show_fps),.udp_fps(mon_udp_fps),.mbps(mon_mbps));
    net_rate_meter2 netm(.clk(rxclk),.rst(eth_reset_rx),.px(net_px),.frame(net_frame),.unit_tg(net_unit_tg),.frame_tg(net_frame_tg));
    mono_display6 #(.ENABLE_TEMPLATE(0)) mono(.clk(S_hdmi_pixel_clk),.rst_n(S_hdmi_rst_n),
      .key_n(I_mode_key_n),.capture_key_n(I_capture_key_n),.external_mode_i(active_mode),.diag_flags_i(13'd0),
      .hs_i(raw_hs),.vs_i(raw_vs),.de_i(raw_de),.rgb_i(raw_rgb),
      .hs_o(mode_hs),.vs_o(mode_vs),.de_o(mode_de),.rgb_o(mode_rgb),
      .active_mode_o(),.requested_mode_o(),.det_found_o(),.det_x_o(),.det_y_o(),
      .det_score_o(),.det_status_o(),.det_epoch_o(),
      .lat_ok(lat_ok),.lat_bcd(lat_bcd),.cap_bcd(lat_cap_bcd),.dsp_bcd(lat_dsp_bcd),
      .lag(lat_lag),.show_fps(mon_show_fps),.udp_fps(mon_udp_fps),.mbps(mon_mbps));
    // CLAUDE MERGE Vision Core: one set of image buffers for RANGE 45 / DEPTH 47 / TEMPLATE 48 / MOTION 50 (mode-exclusive),
    // COLOR 49 and MOTION 50 share the cell / blob engine. Overlays: mono -> range (45/48) -> depth (47) -> target (49/50) -> logo.
    wire rpx_valid;wire[31:0]rpx_addr;wire[15:0]rpx_data;
    wire[7:0]dep_rx;wire[6:0]dep_ry;wire[5:0]dep_d;wire[7:0]dep_frames;
    wire[3:0]rng_pos;wire[1:0]rng_lock;wire[10:0]rng_cx;wire[9:0]rng_cy;wire[2:0]rng_status;wire[15:0]rng_z;wire[11:0]rng_d;wire[3:0]rng_dt;wire[7:0]rng_n;
    wire tgt_found;wire[5:0]tgt_bx0,tgt_bx1;wire[4:0]tgt_by0,tgt_by1;wire[1:0]col_sel;
    // CLAUDE BOTTLE: mode 38 KEY4 = ALL / BOTTLE (YOLO-seeded template tracking of one bottle)
    wire[319:0]yolo_tracks;wire[31:0]yolo_id;wire[7:0]yolo_vid;wire yolo_recent,bt_mode;wire[79:0]bt_entry;wire[2:0]bt_status;
  // CLAUDE Z17 (board: TEMPLATE drifted once exposure moved under a locked template): AE lock while TEMPLATE 48 or the
  // BOTTLE tracker is locked (pixel-clock level, registered; synchronized in the AE configuration clock).
  reg ae_hold_q; assign ae_hold=ae_hold_q;
  always @(posedge S_hdmi_pixel_clk or negedge S_hdmi_rst_n) if(!S_hdmi_rst_n) ae_hold_q<=1'b0;
    else ae_hold_q <= (active_mode==8'd48 || (active_mode==8'd38 && bt_mode)) && rng_lock==2'd1;
    wire key_deb;   // CLAUDE Z8C: KEY4 debounced once (range_meter) for vision_core, zoom_ctrl, vision_osd
    vision_core #(.MS_TICK(1),.GRID_FILE("G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/rtl/range_grid.hex")) u_vision(
      .cam_clk(S_csi_rx_clk),.cam_rst_n(S_rst_n),.l_valid(S_tap_out_valid),.l_sof(S_tap_out_sof),.l_eol(S_tap_out_eol),.l_data(S_tap_out_data),
      .rx_clk(rxclk),.rx_rst(eth_reset_rx),.r_valid(rpx_valid),.r_addr(rpx_addr),.r_data(rpx_data),
      .pclk(S_hdmi_pixel_clk),.prst_n(S_hdmi_rst_n),.key_n(I_capture_key_n),.key_deb(key_deb),
      .m45(active_mode==45),.m47(active_mode==47),.m48(active_mode==48),.m49(active_mode==49),.m50(active_mode==50),
      .hs_i(mode_hs),.vs_i(mode_vs),.de_i(mode_de),.rgb_i(mode_rgb),
      .dep_rx(dep_rx),.dep_ry(dep_ry),.dep_d(dep_d),.dep_frames(dep_frames),
      .rng_pos(rng_pos),.rng_cx(rng_cx),.rng_cy(rng_cy),.rng_lock(rng_lock),.rng_status(rng_status),.rng_z(rng_z),.rng_d(rng_d),.rng_dt(rng_dt),.rng_n(rng_n),
      .tgt_found(tgt_found),.tgt_bx0(tgt_bx0),.tgt_bx1(tgt_bx1),.tgt_by0(tgt_by0),.tgt_by1(tgt_by1),.col_sel(col_sel),
      .m38(active_mode==38),.yolo_tracks(yolo_tracks),.yolo_id(yolo_id),.yolo_recent(yolo_recent),.yolo_vid(yolo_vid),.bt_mode(bt_mode),.bt_entry(bt_entry),.bt_status(bt_status),
      .f_mode(f_mode),.f_update(f_update),.f_good(f_good),.f_fid(f_fid),.f_cx(f_cx),.f_cy(f_cy),.ms(ms_tick));
    // CLAUDE Z10 GIMBAL: board22 follow chain (time-multiplexed gimbal_mc) for TEMPLATE 48, BOTTLE 38, COLOR 49, MOTION 50
    gimbal_mc #(.CLK_HZ(75000000),.KP_A(9),.KP_B(8),.KD_S(7)) follow(.clk(S_hdmi_pixel_clk),   // board22 gains: KP 768, KD 128
     .rst(!S_hdmi_rst_n),.mode_sel((active_mode==38&&bt_mode)||active_mode==48||active_mode==49),.mode_ok(f_mode),.arm_pulse(f_arm),.stop_pulse(f_stop),   // Z19: track loss holds the gimbal
      .target_update(f_update),.target_good(f_good),.target_fid(f_fid),.cx(f_cx),.cy(f_cy),
      .pitch_rx(I_left_rx),.yaw_rx(I_right_rx),.pitch_tx(O_left_tx),.yaw_tx(O_right_tx),
      .armed(f_armed),.fault(f_fault),.ready_to_arm(f_rta),.ready(f_ready),.pitch_code(f_pc),.yaw_code(f_yc),.control_code(f_cc),
      .pitch_acks(),.yaw_acks(),.pitch_last(),.yaw_last(),.ms_o(ms_tick));
    // CLAUDE ZOOM: mode 51 step-less zoom (KEY4 hold = zoom, short press = reverse), nearest neighbour in the display reader
    wire zoom_en;wire[18:0]zoom_step;wire[9:0]zoom_bcd;   // ZOOM6: 0.25x .. 4.00x
    zoom_ctrl #(.KDEB(1),.MS_TICK(1)) zoomc(.clk(S_hdmi_pixel_clk),.rst_n(S_hdmi_rst_n),.en(active_mode==51),.key_n(key_deb),.vs(S_hdmi_vsync),.ms(ms_tick),
      .zoom_en(zoom_en),.zstep(zoom_step),.zn(zoom_bcd));
    wire tov_hs,tov_vs,tov_de;wire[23:0]tov_rgb;
    vision_osd #(.KDEB(1)) vosd(.clk(S_hdmi_pixel_clk),.rst_n(S_hdmi_rst_n),.key_n(key_deb),
      .m45(active_mode==45),.m47(active_mode==47),.m48(active_mode==48),.m49(active_mode==49),.m50(active_mode==50),.m51(active_mode==51),.zn(zoom_bcd),
      .cx(rng_cx),.cy(rng_cy),.pos(rng_pos),.lock(rng_lock),.status(rng_status),.z_bcd(rng_z),.d_bcd(rng_d),.d_tenth(rng_dt),
      .rd_x(dep_rx),.rd_y(dep_ry),.rd_d(dep_d),.frames(dep_frames),
      .csel(col_sel),.found(tgt_found),.bx0(tgt_bx0),.bx1(tgt_bx1),.by0(tgt_by0),.by1(tgt_by1),
      .hs_i(mode_hs),.vs_i(mode_vs),.de_i(mode_de),.rgb_i(mode_rgb),.hs_o(tov_hs),.vs_o(tov_vs),.de_o(tov_de),.rgb_o(tov_rgb),
      .fshow((active_mode==38&&bt_mode)||active_mode==48||active_mode==49),.f_armed(f_armed),.f_ready(f_ready),.f_fault(f_fault),   // CLAUDE Z14: no follow bar in MOTION 50
      .f_pc(f_pc),.f_yc(f_yc),.f_cc(f_cc));
    // CLAUDE MERGE: ANLOGIC logo (80x80 artwork without text, common_logo1 from the dehaze build) top-right on every mode
    wire logo_hs,logo_vs,logo_de;wire[23:0]logo_rgb;
    common_logo1 #(.ROM_FILE("G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/rtl/logo80.hex")) logo(.clk(S_hdmi_pixel_clk),.rst_n(S_hdmi_rst_n),
      .hs_i(tov_hs),.vs_i(tov_vs),.de_i(tov_de),.rgb_i(tov_rgb),.first_local_i(1'b0),
      .hs_o(logo_hs),.vs_o(logo_vs),.de_o(logo_de),.rgb_o(logo_rgb),.first_local_o());
    wire[10:0] raw_x;wire[9:0]raw_y;
    raw_xy1 xy(S_hdmi_pixel_clk,!S_hdmi_rst_n,S_hdmi_de,S_hdmi_vsync,raw_x,raw_y);
    wire raw_error;wire[31:0]raw_remote_frames,raw_missed_lines;
    stereo_raw_memory1 frames(.ddr_clk(S_ddr_clk),.pixel_clk(S_hdmi_pixel_clk),.rx_clk(rxclk),
      .rst(!S_rst_n),.calibrated(S_init_calib_complete),
      .gmii_valid(gmii_valid&&!eth_reset_rx),.gmii_error(gmii_error),.gmii_data(gmii_data),
      .local_wr_en(S_vi_ddr_wr_en),.local_wr_busy(S_video_in_wr_busy),
      .local_addr(S_vi_ddr_wr_addr),.local_data(S_vi_ddr_wr_data),.local_bank(S_video_out_rp),
      .local_ready(S_ddr_user_ready),
      .bridge_we(raw_bridge_we),.bridge_re(raw_bridge_re),.bridge_addr(raw_bridge_addr),.bridge_wdata(raw_bridge_wdata),
      .bridge_ready(raw_bridge_ready),.bridge_rvalid(raw_bridge_rvalid),.bridge_rdata(raw_bridge_rdata),
      .native_accept(S_mc_app_en && S_mc_app_rdy && (S_mc_app_cmd[0] || S_mc_app_wdf_rdy)),.native_read(S_mc_app_cmd==1),.native_addr(S_mc_app_addr),
      .x(raw_x),.y(raw_y),.hs(S_hdmi_hsync),.vs(S_hdmi_vsync),.de(S_hdmi_de),
      .out_hs(raw_hs),.out_vs(raw_vs),.out_de(raw_de),.out_rgb(raw_rgb),
      .remote_frames(raw_remote_frames),.missed_lines(raw_missed_lines),.protocol_error(raw_error),.stereo_mode_i(active_mode==37),.remote_full_i(active_mode==38),.yolo_overlay_i(active_mode==38),.local_reader_hold(local_reader_hold),.local_reader_bank(local_reader_bank),.pair_mode_i(pair_effect_mode),.tracking_mode_i(bt_mode&&active_mode==38),.zoom_i(zoom_en),.zstep_i(zoom_step),.rpx_valid(rpx_valid),.rpx_addr(rpx_addr),.rpx_data(rpx_data),
      .yolo_tracks_o(yolo_tracks),.yolo_id_o(yolo_id),.yolo_recent_o(yolo_recent),.yolo_vid_o(yolo_vid),.bt_entry_i(bt_entry),.bt_status_i(bt_status),
      .lat_sof_g(lat_sof_g),.lat_sel_tg(lat_sel_tg),.lat_sel_idx(lat_sel_idx),.net_px_o(net_px),.net_frame_o(net_frame));
    assign S_video_out_rd_busy=1'b0;
    assign S_vo_ddr_rd_en=1'b0;assign S_vo_ddr_rd_addr=25'd0;
    assign S_ddr_user_rd_valid=1'b0;assign S_ddr_user_rd_data=128'd0;
    assign S_video_rd_data=24'd0;assign S_hdmi_window_rd_en=1'b0;

    hdmi_tx u_hdmi_tx(
        .I_pixel_clk        ( S_hdmi_pixel_clk  ),
        .I_serial_clk       ( S_hdmi_serial_clk ),
        .I_rst              ( ~S_hdmi_rst_n     ),
        .I_key_in           ( 1'b0              ),
        .I_edid_read_trig   ( 1'b0              ),
        .O_edid_read_valid  (                   ),
        .O_edid_read_data   (                   ),
        .I_video_rgb_enable ( 1'b1              ),
        .I_video_in_vs      ( logo_vs            ),
        .I_video_in_de      ( logo_de            ),
        .I_video_in_user    ( 1'b0              ),
        .I_video_in_valid   ( 1'b0              ),
        .I_video_in_last    ( 1'b0              ),
        .O_video_in_ready   (                   ),
        .I_video_in_data    ( logo_rgb           ),
        .I_audio_valid      ( 1'b0              ),
        .I_audio_left_data  ( 24'd0             ),
        .I_audio_right_data ( 24'd0             ),
        .I_i2s_BCLK         ( 1'b0              ),
        .I_i2s_LRCK         ( 1'b0              ),
        .I_i2s_DOUT         ( 1'b0              ),
        .O_ddc_scl          (                   ),
        .O_hdmi_clk_p       (                   ),
        .O_hdmi_tx_p        (                   ),
        .O_tmds_ch0_p       ( O_tmds_ch0_p      ),
        .O_tmds_ch1_p       ( O_tmds_ch1_p      ),
        .O_tmds_ch2_p       ( O_tmds_ch2_p      ),
        .O_tmds_clk_p       ( O_tmds_clk_p      )
    );

    
endmodule
