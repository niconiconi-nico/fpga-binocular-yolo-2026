

// Camera-first integration derivative. One DDR/PHY/UDP stack, actual147-layer
// frozen YOLO math. Development candidate: not qualified until own simulation,
// complete physical timing/DRC and actual Camera board acceptance.
module a2_camera_yolo_board_top (
    input wire        I_sys_clk,
      
    output wire       O_cam_scl,
    inout  wire       IO_cam_sda,
    output wire       O_cam_24m,
    output wire       O_cam_rst,
      
    inout wire [1:0]  I_button,

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
    inout wire[1:0]   ddr_dqs_n,

    input wire[3:0]   I_a_rgmii_rxd,
    input wire        I_a_rgmii_rx_ctl,
    input wire        I_a_rgmii_rxc,
    output wire[3:0]  O_a_rgmii_txd,
    output wire       O_a_rgmii_tx_ctl,
    output wire       O_a_rgmii_txc,
    output wire       O_phy_rst,
    output wire O_tf_cs_n,O_tf_sclk,O_tf_mosi,input wire I_tf_miso
);

    // Declare before any consumer; TD6.2 late implicit-net initializers lost
    // ISP control drivers in rejected R7. Logic and reset semantics unchanged.
    wire camera_yolo_reset_n,camera_stream_reset_n,camera_isp_reset_n;
    wire isp_raw_valid,isp_raw_sof,isp_raw_eol;
    wire camera_demosaic_reset_n,camera_awb_reset_n,camera_pack_reset_n;
    wire sc520_iic_error;


    wire        	S_100m_clk;
    wire        	S_24m_clk;
    wire        	S_aux_50m_clk;
	wire        	S_10m_clk;
		
	wire        	S_pll_lock;
    wire        	S_rst_n;
	
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
    wire        S_algo_hdmi_vsync;
    wire        S_algo_hdmi_hsync;
    wire        S_algo_hdmi_de;
    wire        S_algo_hdmi_frame_start;
    wire[23:0]  S_algo_hdmi_data;
    wire[7:0]   S_algo_active_mode;
    wire        S_eth_clk_125m;
    wire        S_eth_clk_125m_90;
    wire        S_eth_clk_25m;
    wire        S_eth_pll_lock;
    wire        S_phy_rst_n;
    wire        S_eth_reset;
    wire[7:0]   S_gmii_tdata;
    wire        S_gmii_tvalid;
    wire[7:0]   S_gmii_rdata;
    wire        S_gmii_rvalid;
    wire        S_gmii_rclk;
    wire        S_eth_ip_rx_error;
    wire        S_eth_mac_rx_error;
    wire        S_udp_tx_busy;
    wire        S_udp_tx_req;
    wire        S_udp_tx_valid;
    wire[7:0]   S_udp_tx_data;
    wire[15:0]  S_udp_tx_len;
    wire        S_udp_rx_valid;
    wire[7:0]   S_udp_rx_data;
    wire[15:0]  S_udp_rx_len;
    wire[15:0]  S_udp_rx_src_port;
    wire        S_udp_mode_set_valid;
    wire[7:0]   S_udp_mode_set;
    wire        S_udp_mode_set_toggle;
    wire        S_udp_mode_next;
    wire        S_udp_mode_next_toggle;
    wire        S_udp_auto_demo_enable;
    wire        S_udp_auto_demo_toggle;
    wire        S_udp_command_error;
    wire        S_eth_video_pixel_valid;
    wire        S_eth_video_frame_start;
    wire[23:0]  S_eth_video_rgb888;
    wire[15:0]  S_eth_video_rgb565;
    wire        S_eth_video_fifo_full;
    wire        S_eth_video_fifo_empty;
    wire[13:0]  S_eth_video_fifo_rdusedw;
    wire[31:0]  S_eth_video_dropped_pixels;
    wire[31:0]  S_eth_video_frame_sequence;
    wire[31:0]  S_eth_video_packet_sequence;
    wire[31:0]  S_eth_video_frame_offset;
    wire        S_eth_video_tx_active;

    wire[23:0]  S_video_rd_data;
    reg         S_dbg_raw_seen;
    reg         S_dbg_isp_seen;
    reg         S_dbg_ddr_wr_seen;
    reg         S_dbg_ddr_rd_seen;
    reg         S_dbg_cam_cfg_seen;
    reg         S_dbg_hs_seen;
    reg         S_dbg_csi_seen;
    reg         S_dbg_raw10_seen;
    reg         S_dbg_isp_fs_seen;
    reg         S_dbg_isp_valid_seen;
    reg         S_dbg_ddr_req_seen;
    reg         S_dbg_ddr_ready_seen;
    reg [1:0]   S_dbg_raw_seen_sync;
    reg [1:0]   S_dbg_isp_seen_sync;
    reg [1:0]   S_dbg_ddr_wr_seen_sync;
    reg [1:0]   S_dbg_ddr_rd_seen_sync;
    reg [1:0]   S_dbg_cam_cfg_seen_sync;
    reg [1:0]   S_dbg_hs_seen_sync;
    reg [1:0]   S_dbg_csi_seen_sync;
    reg [1:0]   S_dbg_raw10_seen_sync;
    reg [1:0]   S_dbg_isp_fs_seen_sync;
    reg [1:0]   S_dbg_isp_valid_seen_sync;
    reg [1:0]   S_dbg_ddr_req_seen_sync;
    reg [1:0]   S_dbg_ddr_ready_seen_sync;
    reg         S_dbg_video_nonzero_seen;
    reg         S_dbg_rd_req_seen;
    reg         S_dbg_rd_valid_seen;
    reg         S_dbg_rd_nonzero_seen;
    reg [1:0]   S_dbg_rd_req_seen_sync;
    reg [1:0]   S_dbg_rd_valid_seen_sync;
    reg [1:0]   S_dbg_rd_nonzero_seen_sync;
    reg         S_dbg_mc_init_seen;
    reg         S_dbg_mc_app_rdy_seen;
    reg         S_dbg_mc_wdf_rdy_seen;
    reg         S_dbg_mc_cmd_pop_seen;
    reg [1:0]   S_dbg_mc_init_seen_sync;
    reg [1:0]   S_dbg_mc_app_rdy_seen_sync;
    reg [1:0]   S_dbg_mc_wdf_rdy_seen_sync;
    reg [1:0]   S_dbg_mc_cmd_pop_seen_sync;
    wire[3:0]   S_hdmi_debug_status;
    wire        S_lane_error_any;

    wire        S_pipeline_manual_next;
    wire        S_pipeline_auto_demo_enable;
    wire        S_pipeline_mode_set_valid;
    wire [7:0]  S_pipeline_mode_set;
    wire [7:0]  S_pipeline_active_mode;
    assign S_video_out_vsync = ~S_hdmi_vsync;
	
	
    assign S_rst_n 		= S_pll_lock;
    assign S_hdmi_rst_n = S_pll_lock;

    always @(posedge S_csi_rx_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_raw_seen <= 1'b0;
        else if(S_raw10_frame_start | S_axis_tvalid)
            S_dbg_raw_seen <= 1'b1;
    end

    always @(posedge S_csi_rx_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_isp_seen <= 1'b0;
        else if(S_ISP_O_tuser | S_ISP_O_tvalid)
            S_dbg_isp_seen <= 1'b1;
    end

    always @(posedge S_ddr_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_ddr_wr_seen <= 1'b0;
        else if(S_vi_ddr_wr_en)
            S_dbg_ddr_wr_seen <= 1'b1;
    end

    always @(posedge S_ddr_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_ddr_rd_seen <= 1'b0;
        else if(S_ddr_user_rd_valid)
            S_dbg_ddr_rd_seen <= 1'b1;
    end

    always @(posedge S_24m_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_cam_cfg_seen <= 1'b0;
        else if(S_cam_cfg_done)
            S_dbg_cam_cfg_seen <= 1'b1;
    end

    always @(posedge S_csi_rx_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_hs_seen <= 1'b0;
        else if(S_hs_rx_valid)
            S_dbg_hs_seen <= 1'b1;
    end

    always @(posedge S_csi_rx_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_csi_seen <= 1'b0;
        else if(S_csi_frame_start | S_csi_valid)
            S_dbg_csi_seen <= 1'b1;
    end

    always @(posedge S_csi_rx_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_raw10_seen <= 1'b0;
        else if(S_raw10_frame_start | S_raw10_valid)
            S_dbg_raw10_seen <= 1'b1;
    end

    always @(posedge S_csi_rx_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_isp_fs_seen <= 1'b0;
        else if(S_ISP_O_tuser)
            S_dbg_isp_fs_seen <= 1'b1;
    end

    always @(posedge S_csi_rx_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_isp_valid_seen <= 1'b0;
        else if(S_ISP_O_tvalid)
            S_dbg_isp_valid_seen <= 1'b1;
    end

    always @(posedge S_ddr_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_ddr_req_seen <= 1'b0;
        else if(S_vi_ddr_wr_en)
            S_dbg_ddr_req_seen <= 1'b1;
    end

    always @(posedge S_ddr_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_ddr_ready_seen <= 1'b0;
        else if(S_ddr_user_ready)
            S_dbg_ddr_ready_seen <= 1'b1;
    end

    always @(posedge S_ddr_clk or negedge S_video_out_rst_n) begin
        if(!S_video_out_rst_n)
            S_dbg_rd_req_seen <= 1'b0;
        else if(S_video_out_vsync)
            S_dbg_rd_req_seen <= 1'b0;
        else if(S_vo_ddr_rd_en)
            S_dbg_rd_req_seen <= 1'b1;
    end

    always @(posedge S_ddr_clk or negedge S_video_out_rst_n) begin
        if(!S_video_out_rst_n)
            S_dbg_rd_valid_seen <= 1'b0;
        else if(S_video_out_vsync)
            S_dbg_rd_valid_seen <= 1'b0;
        else if(S_ddr_user_rd_valid)
            S_dbg_rd_valid_seen <= 1'b1;
    end

    always @(posedge S_hdmi_pixel_clk or negedge S_video_out_rst_n) begin
        if(!S_video_out_rst_n)
            S_dbg_rd_nonzero_seen <= 1'b0;
        else if(S_video_out_vsync)
            S_dbg_rd_nonzero_seen <= 1'b0;
        else if(S_hdmi_window_rd_en && (S_video_rd_data != 24'd0))
            S_dbg_rd_nonzero_seen <= 1'b1;
    end

    always @(posedge S_ddr_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_mc_init_seen <= 1'b0;
        else if(S_init_calib_complete)
            S_dbg_mc_init_seen <= 1'b1;
    end

    always @(posedge S_ddr_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_mc_app_rdy_seen <= 1'b0;
        else if(S_mc_dbg_app_rdy)
            S_dbg_mc_app_rdy_seen <= 1'b1;
    end

    always @(posedge S_ddr_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_mc_wdf_rdy_seen <= 1'b0;
        else if(S_mc_dbg_wdf_rdy)
            S_dbg_mc_wdf_rdy_seen <= 1'b1;
    end

    always @(posedge S_ddr_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_mc_cmd_pop_seen <= 1'b0;
        else if(S_mc_dbg_cmd_pop)
            S_dbg_mc_cmd_pop_seen <= 1'b1;
    end

    always @(posedge S_hdmi_pixel_clk or negedge S_hdmi_rst_n) begin
        if(!S_hdmi_rst_n) begin
            S_dbg_cam_cfg_seen_sync <= 2'b00;
            S_dbg_hs_seen_sync      <= 2'b00;
            S_dbg_csi_seen_sync     <= 2'b00;
            S_dbg_raw10_seen_sync   <= 2'b00;
            S_dbg_raw_seen_sync    <= 2'b00;
            S_dbg_isp_seen_sync    <= 2'b00;
            S_dbg_ddr_wr_seen_sync <= 2'b00;
            S_dbg_ddr_rd_seen_sync <= 2'b00;
            S_dbg_isp_fs_seen_sync  <= 2'b00;
            S_dbg_isp_valid_seen_sync <= 2'b00;
            S_dbg_ddr_req_seen_sync <= 2'b00;
            S_dbg_ddr_ready_seen_sync <= 2'b00;
            S_dbg_video_nonzero_seen <= 1'b0;
            S_dbg_rd_req_seen_sync <= 2'b00;
            S_dbg_rd_valid_seen_sync <= 2'b00;
            S_dbg_rd_nonzero_seen_sync <= 2'b00;
            S_dbg_mc_init_seen_sync <= 2'b00;
            S_dbg_mc_app_rdy_seen_sync <= 2'b00;
            S_dbg_mc_wdf_rdy_seen_sync <= 2'b00;
            S_dbg_mc_cmd_pop_seen_sync <= 2'b00;
        end
        else begin
            S_dbg_cam_cfg_seen_sync <= {S_dbg_cam_cfg_seen_sync[0], S_dbg_cam_cfg_seen};
            S_dbg_hs_seen_sync      <= {S_dbg_hs_seen_sync[0],      S_dbg_hs_seen};
            S_dbg_csi_seen_sync     <= {S_dbg_csi_seen_sync[0],     S_dbg_csi_seen};
            S_dbg_raw10_seen_sync   <= {S_dbg_raw10_seen_sync[0],   S_dbg_raw10_seen};
            S_dbg_raw_seen_sync    <= {S_dbg_raw_seen_sync[0],    S_dbg_raw_seen};
            S_dbg_isp_seen_sync    <= {S_dbg_isp_seen_sync[0],    S_dbg_isp_seen};
            S_dbg_ddr_wr_seen_sync <= {S_dbg_ddr_wr_seen_sync[0], S_dbg_ddr_wr_seen};
            S_dbg_ddr_rd_seen_sync <= {S_dbg_ddr_rd_seen_sync[0], S_dbg_ddr_rd_seen};
            S_dbg_isp_fs_seen_sync  <= {S_dbg_isp_fs_seen_sync[0],  S_dbg_isp_fs_seen};
            S_dbg_isp_valid_seen_sync <= {S_dbg_isp_valid_seen_sync[0], S_dbg_isp_valid_seen};
            S_dbg_ddr_req_seen_sync <= {S_dbg_ddr_req_seen_sync[0], S_dbg_ddr_req_seen};
            S_dbg_ddr_ready_seen_sync <= {S_dbg_ddr_ready_seen_sync[0], S_dbg_ddr_ready_seen};
            S_dbg_rd_req_seen_sync <= {S_dbg_rd_req_seen_sync[0], S_dbg_rd_req_seen};
            S_dbg_rd_valid_seen_sync <= {S_dbg_rd_valid_seen_sync[0], S_dbg_rd_valid_seen};
            S_dbg_rd_nonzero_seen_sync <= {S_dbg_rd_nonzero_seen_sync[0], S_dbg_rd_nonzero_seen};
            S_dbg_mc_init_seen_sync <= {S_dbg_mc_init_seen_sync[0], S_dbg_mc_init_seen};
            S_dbg_mc_app_rdy_seen_sync <= {S_dbg_mc_app_rdy_seen_sync[0], S_dbg_mc_app_rdy_seen};
            S_dbg_mc_wdf_rdy_seen_sync <= {S_dbg_mc_wdf_rdy_seen_sync[0], S_dbg_mc_wdf_rdy_seen};
            S_dbg_mc_cmd_pop_seen_sync <= {S_dbg_mc_cmd_pop_seen_sync[0], S_dbg_mc_cmd_pop_seen};
            if(S_hdmi_window_rd_en && (S_video_rd_data != 24'd0))
                S_dbg_video_nonzero_seen <= 1'b1;
        end
    end

    assign S_lane_error_any = |S_lane_error;

    assign S_vo_dbg_fifo_rst = 1'b0;
    assign S_vo_dbg_ddr_rd_valid = 1'b0;
    assign S_vo_dbg_fifo_rd_en = 1'b0;
    assign S_vo_dbg_fifo_empty = 1'b0;
    assign S_mc_dbg_fifo_afull = 1'b0;
    assign S_mc_dbg_app_rdy = 1'b0;
    assign S_mc_dbg_wdf_rdy = 1'b0;
    assign S_mc_dbg_cmd_pop = 1'b0;

    assign S_hdmi_debug_status = {
        (|S_ddr_user_rd_data),
        S_ddr_user_rd_valid,
        S_vo_ddr_rd_en,
        S_vi_ddr_wr_en
    };
	
	wire sc520_i2c_ready;
    sc520_power_sequence u_sc520_power (
        .clk(S_24m_clk), .pll_locked(S_pll_lock),
        .pwdnb(O_cam_rst), .i2c_ready(sc520_i2c_ready));
    // L3 is HDIO in the actual TD pin report. Forward the unchanged PLL
    // clock through the I/O DDR cell, not a GCLK-to-GPIO local data route.
    camera_clock_forward u_camera_clock_forward (.q(O_cam_24m), .clk(S_24m_clk));
	
	
	
	
    PLL u_PLL(
        .refclk      ( I_sys_clk         ),
        .reset    	 ( 1'b0               ),
        
        .clk0_out    ( S_100m_clk        ),
        .clk1_out    ( S_24m_clk         ),

        .clk4_out    ( S_hdmi_pixel_clk  ),
        .clk5_out    ( S_hdmi_serial_clk ),

        .lock        ( S_pll_lock        )

    );

    // Ethernet-A uses the official PH1P RGMII/UDP reference stack.  The
    // Ethernet PLL and PHY reset are independent of the MIPI image clock.
    pll u_eth_pll(
        .refclk   ( I_sys_clk          ),
        .reset    ( 1'b0               ),
        .lock     ( S_eth_pll_lock     ),
        .clk0_out ( S_eth_clk_125m     ),
        .clk1_out ( S_eth_clk_125m_90  ),
        .clk2_out ( S_eth_clk_25m      )
    );

    uiphyrst #(
        .CLK_FREQ(32'd25_000_000)
    ) u_eth_phy_reset (
        .I_CLK   ( S_eth_clk_25m  ),
        .I_rstn  ( S_eth_pll_lock ),
        .I_phyrst( S_eth_pll_lock ),
        .O_phyrst( S_phy_rst_n    )
    );

    assign O_phy_rst   = S_phy_rst_n;
    assign S_eth_reset = ~S_phy_rst_n;

    uiudp_stack #(
        .CRC_GEN_EN       (1'b1),
        .INTER_FRAME_GAP  (4'd12)
    ) u_eth_udp_stack (
        .I_uclk             (S_ddr_clk),
        .I_reset            (!camera_yolo_reset_n),
        .I_mac_local_addr   (48'h02_00_00_24_00_01),
        .I_udp_local_port   (16'd4),
        .I_ip_local_addr    (`NET_BOARD_IP),
        .I_udp_dest_port    (`NET_VIDEO_PORT),
        .I_ip_dest_addr     (`NET_PC_IP),
        .O_W_udp_busy       (S_udp_tx_busy),
        .I_W_udp_req        (S_udp_tx_req),
        .I_W_udp_valid      (S_udp_tx_valid),
        .I_W_udp_data       (S_udp_tx_data),
        .I_W_udp_len        (S_udp_tx_len),
        .O_R_udp_valid      (S_udp_rx_valid),
        .O_R_udp_data       (S_udp_rx_data),
        .O_R_udp_len        (S_udp_rx_len),
        .O_R_udp_src_port   (S_udp_rx_src_port),
        .I_gmii_rclk        (S_gmii_rclk),
        .I_gmii_rvalid      (S_gmii_rvalid),
        .I_gmii_rdata       (S_gmii_rdata),
        .I_gmii_tclk        (S_eth_clk_125m),
        .O_gmii_tvalid      (S_gmii_tvalid),
        .O_gmii_tdata       (S_gmii_tdata),
        .O_ip_rerror        (S_eth_ip_rx_error),
        .O_mac_rerror       (S_eth_mac_rx_error)
    );

    rgmii_interface u_rgmii_interface (
        .speed_10_100   (1'b0),
        .gmii_tx_clk_d  (S_eth_clk_125m),
        .gmii_tx_reset_d(S_eth_reset),
        .rgmii_txd      (O_a_rgmii_txd),
        .rgmii_tx_ctl   (O_a_rgmii_tx_ctl),
        .rgmii_txc      (O_a_rgmii_txc),
        .rgmii_rxd      (I_a_rgmii_rxd),
        .rgmii_rx_ctl   (I_a_rgmii_rx_ctl),
        .rgmii_rxc      (I_a_rgmii_rxc),
        .gmii_tx_reset  (S_eth_reset),
        .gmii_tx_clk    (S_eth_clk_125m),
        .gmii_txd       (S_gmii_tdata),
        .gmii_tx_en     (S_gmii_tvalid),
        .gmii_tx_er     (1'b0),
        .gmii_rx_reset  (S_eth_reset),
        .gmii_rx_clk    (S_gmii_rclk),
        .gmii_rxd       (S_gmii_rdata),
        .gmii_rx_dv     (S_gmii_rvalid),
        .gmii_rx_er     (),
        .gmii_crs       (),
        .gmii_col       (),
        .link_status    (),
        .clock_speed    (),
        .duplex_status  ()
    );

    // CC20: PC -> FPGA receive path removed (TF card is the only model source, user decision 2026-10-24).
    // udp_mode_command_rx / mode_command_cdc only fed the ISP mode inputs, which camera_min_resource_isp ignores
    // (O_active_mode = 0); tie them to the no-command values.
    assign S_pipeline_mode_set_valid=1'b0; assign S_pipeline_mode_set=8'd0; assign S_pipeline_manual_next=1'b0; assign S_pipeline_auto_demo_enable=1'b0;


	

  
  // First SC520CS migration keeps supplied exposure/gain table unchanged.
  // SC500 button AE units/range are not applied to the new sensor.
  // AE25: common assertion and per-clock synchronized release for both mailboxes.
  wire ae_common_ready=S_rst_n && sc520_i2c_ready;
  (* async_reg="true" *) reg [1:0] ae_pixel_reset_sync,ae_cfg_reset_sync;
  always @(posedge S_csi_rx_clk or negedge ae_common_ready)
    if(!ae_common_ready)ae_pixel_reset_sync<=0;
    else ae_pixel_reset_sync<={ae_pixel_reset_sync[0],1'b1};
  always @(posedge S_24m_clk or negedge ae_common_ready)
    if(!ae_common_ready)ae_cfg_reset_sync<=0;
    else ae_cfg_reset_sync<={ae_cfg_reset_sync[0],1'b1};
  wire [15:0] ae_applied_exp,ae_applied_gain;
  wire [31:0] ae_transactions,ae_raw_sequence,ae_command_sequence;
  wire [27:0] ae_green_sum;wire [18:0] ae_clipped;wire ae_fault;
  sc520_auto_exposure u_sc520_ae (
      .pixel_clk(S_csi_rx_clk),.pixel_rst_n(ae_pixel_reset_sync[1]),
      .raw_valid(S_raw_tvalid),.raw_sof(S_raw_tuser),.raw_eol(S_raw_tlast),
      .raw_data(S_raw_tdata),.cfg_clk(S_24m_clk),.cfg_rst_n(ae_cfg_reset_sync[1]),
      .cfg_done(S_cam_cfg_done),.ae_done(S_ae_cfg_done),.cfg_error(sc520_iic_error),
      .ae_req(S_ae_req),.exposure(S_ae),.gain_index(S_ag),
      .applied_exposure(ae_applied_exp),.applied_gain_index(ae_applied_gain),.fault(ae_fault),
      .applied_transactions(ae_transactions),.measured_green_sum(ae_green_sum),
      .measured_clipped(ae_clipped),.measurement_pulse(),
      .measured_raw_sequence(ae_raw_sequence),.command_raw_sequence(ae_command_sequence));
  wire [15:0] sc520_sensor_id;
  wire sc520_sensor_id_ok;
  uicfgcs520 #(.CLK_DIV(241)) u_sc520_config (
      .I_clk(S_24m_clk), .I_rst_n(sc520_i2c_ready),
      .I_ae_req(S_ae_req), .I_ae(S_ae), .I_ag(S_ag),
      .O_cam_scl(O_cam_scl), .IO_cam_sda(IO_cam_sda),
      .O_cfg_done(S_cam_cfg_done), .O_ae_cfg_done(S_ae_cfg_done),
      .O_sensor_id(sc520_sensor_id), .O_sensor_id_ok(sc520_sensor_id_ok),
      .O_iic_error(sc520_iic_error));

    mipi_dphy_rx_ph1p_mipiio_wrapper#(
        .DPHY_RX_LOCATION      ( "DPHY0" ),
        .HS_EQUALIZER          ( "3dB"   ),//"0dB","1.5dB","3dB","4.5dB","6dB","7.5dB","9dB","10.5dB"
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
.O_csi_data            ( S_csi_data        )
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
// Full 1280x720 sensor -> ISP -> owned DDR. YOLO retains central ROI.
// No blank-cycle line detection; explicit valid-word and frame boundaries.
wire sc520_crop_error;
sc520_raw10_crop u_sc520_crop (
    .clk(S_csi_rx_clk), .rst_n(S_rst_n),
    .frame_start(S_raw10_frame_start), .frame_end(S_raw10_frame_end),
    .valid(S_raw10_valid), .data(S_raw10_data),
    .out_data(S_raw_tdata), .out_valid(S_raw_tvalid),
    .out_sof(S_raw_tuser), .out_eol(S_raw_tlast),
    .frame_error(sc520_crop_error));

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


//ISP算法顶层模块
// Minimal integration candidate: keep native demosaic RGB, omit optional AWB.
// This is not asserted pixel-equivalent to the preserved qualified video ISP.
camera_min_resource_isp #(.ENABLE_AWB(1),.SPLIT_LOCAL_RESETS(1)) u_isp_top (
.axi4s_video_aclk(S_csi_rx_clk),
.I_rst_n         (camera_isp_reset_n),
.I_demosaic_reset_n(camera_demosaic_reset_n),
.I_awb_reset_n(camera_awb_reset_n),
.I_pack_reset_n(camera_pack_reset_n),
.I_tlast         (isp_raw_eol),
.I_tuser         (isp_raw_sof),
.I_tdata         (S_raw_tdata	),
.I_tvalid        (isp_raw_valid),
.I_tdest         (10'd0), // unused by active mipi_to_raw_converter, no floating input
.O_tready        (S_ISP_O_tready),
.O_tdata         (S_ISP_O_tdata ),
.O_tlast         (S_ISP_O_tlast ),
.O_tuser         (S_ISP_O_tuser ),
.O_tvalid        (S_ISP_O_tvalid),
.I_tready        (),
.I_manual_next   (S_pipeline_manual_next),
.I_auto_demo_enable(S_pipeline_auto_demo_enable),
.I_mode_set_valid(S_pipeline_mode_set_valid),
.I_mode_set      (S_pipeline_mode_set),
.O_active_mode   (S_pipeline_active_mode)
  );


    // Keep the original ring source in this derivative for provenance only.
    // It is NOT elaborated: it conflicts with frozen feature/parameter DDR
    // addresses and cannot protect a YOLO reader's frame bank.
    generate if(0)begin:G_UNELABORATED_REFERENCE_RING
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
        .I_ddr_user_ready     ( S_ddr_user_ready      )
    );



    assign S_ddr_user_wr_en    = S_vi_ddr_wr_en;

    assign S_ddr_user_rd_en    = S_vo_ddr_rd_en;

    assign S_ddr_user_addr     = S_vi_ddr_wr_en ? S_vi_ddr_wr_addr :
                                 S_vo_ddr_rd_en ? S_vo_ddr_rd_addr : 'd0;

    assign S_ddr_user_wr_data  = S_vi_ddr_wr_data;


    assign S_video_out_rst_n = S_hdmi_rst_n;

    video_out u_video_out(
        .I_rst_n             ( S_video_out_rst_n    ),
        .I_ddr_clk           ( S_ddr_clk            ),
 
        .O_video_out_rd_busy ( S_video_out_rd_busy  ),
        .I_video_in_wr_busy  ( S_video_in_wr_busy   ),
        .I_video_out_rp      ( S_video_out_rp       ),
 
        .O_ddr_user_rd_en    ( S_vo_ddr_rd_en       ),
        .O_ddr_user_addr     ( S_vo_ddr_rd_addr     ),
        .I_ddr_user_ready    ( S_ddr_user_ready     ),
        .I_ddr_user_rd_valid ( S_ddr_user_rd_valid  ),
        .I_ddr_user_rd_data  ( S_ddr_user_rd_data   ),

        .I_dsi_clk           ( S_hdmi_pixel_clk     ),
        .I_video_vsync       ( S_video_out_vsync    ),
        .I_video_rd_en       ( S_hdmi_window_rd_en  ),
        .O_vdieo_data        ( S_video_rd_data      )
    );



    mc_to_user_interface u_mc_to_user_interface(
        .I_clk                   ( S_ddr_clk               ),
        .I_rst_n                 ( S_rst_n                 ),

        .I_ddr_user_wr_en        ( S_ddr_user_wr_en        ),
        .I_ddr_user_rd_en        ( S_ddr_user_rd_en        ),
        .I_ddr_user_addr         ( S_ddr_user_addr         ),
        .I_ddr_user_wr_data      ( S_ddr_user_wr_data      ),
        .O_ddr_user_ready        ( S_ddr_user_ready        ),
        .O_ddr_user_rd_valid     ( S_ddr_user_rd_valid     ),
        .O_ddr_user_rd_data      ( S_ddr_user_rd_data      ),
            
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



    end endgenerate
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



    // HDMI scanout and the second framebuffer FIFO are not required by this
    // Camera/Ethernet application. The owned DDR video reader preserves exact
    // 4x4 sample positions, RGB565 and original packet framing.
    generate if(0)begin:G_UNELABORATED_REFERENCE_SCANOUT
    uivtc #(
        .H_ActiveSize ( 1024 ),
        .H_FrameSize  ( 1344 ),
        .H_SyncStart  ( 1184 ),
        .H_SyncEnd    ( 1208 ),
        .V_ActiveSize ( 600  ),
        .V_FrameSize  ( 635  ),
        .V_SyncStart  ( 612  ),
        .V_SyncEnd    ( 614  )
    )u_hdmi_vtc(
        .I_vtc_rstn    ( S_hdmi_rst_n    ),
        .I_vtc_clk     ( S_hdmi_pixel_clk ),
        .O_vtc_vs      ( S_hdmi_vsync     ),
        .O_vtc_hs      ( S_hdmi_hsync     ),
        .O_vtc_de_valid( S_hdmi_de        ),
        .O_vtc_user    ( S_hdmi_user      ),
        .O_vtc_last    ( S_hdmi_last      )
    );

    hdmi_mixer #(
        .H_OFFSET   ( 0    ),
        .V_OFFSET   ( 0    ),
        .IMG_WIDTH  ( 1024 ),
        .IMG_HEIGHT ( 600  ),
        .DEBUG_MODE ( 0    )
    )u_hdmi_mixer(
        .I_clk           ( S_hdmi_pixel_clk   ),
        .I_rst_n         ( S_hdmi_rst_n       ),
        .I_video_vsync   ( S_hdmi_vsync       ),
        .I_video_hsync   ( S_hdmi_hsync       ),
        .I_video_de      ( S_hdmi_de          ),
        .I_video_user    ( S_hdmi_user        ),
        .I_video_last    ( S_hdmi_last        ),
        .I_debug_status  ( S_hdmi_debug_status),
        .O_video_rd_en   ( S_hdmi_window_rd_en),
        .I_video_rd_data ( S_video_rd_data    ),
        .O_hdmi_vsync    ( S_hdmi_out_vsync   ),
        .O_hdmi_hsync    ( S_hdmi_out_hsync   ),
        .O_hdmi_de       ( S_hdmi_out_de      ),
        .O_hdmi_data     ( S_hdmi_out_data    )
    );

    camera_video_scanout u_camera_video_scanout (
        .pix_clk         (S_hdmi_pixel_clk),
        .rst_n           (S_hdmi_rst_n),
        .in_hs           (S_hdmi_out_hsync),
        .in_vs           (S_hdmi_out_vsync),
        .in_de           (S_hdmi_out_de),
        .in_rgb888       (S_hdmi_out_data),
        .out_hs          (S_algo_hdmi_hsync),
        .out_vs          (S_algo_hdmi_vsync),
        .out_de          (S_algo_hdmi_de),
        .out_frame_start (S_algo_hdmi_frame_start),
        .out_rgb888      (S_algo_hdmi_data),
        .active_mode     (S_algo_active_mode)
    );

    // Ethernet video is taken from the same post-DDR display stream as HDMI.
    // Sampling every fourth source row and column limits the sustained UDP
    // payload to roughly 40 Mbit/s at 60 fps, leaving enough headroom for
    // ARP/IP/MAC overhead and avoiding a continuously full CDC FIFO.
    video_downsample_4x4 u_eth_video_downsample (
        .I_clk         (S_hdmi_pixel_clk),
        .I_rst_n       (S_hdmi_rst_n),
        .I_video_de    (S_algo_hdmi_de),
        .I_frame_start (S_algo_hdmi_frame_start),
        .I_rgb888      (S_algo_hdmi_data),
        .O_pixel_valid (S_eth_video_pixel_valid),
        .O_frame_start (S_eth_video_frame_start),
        .O_rgb888      (S_eth_video_rgb888)
    );

    rgb888_to_rgb565 u_eth_rgb888_to_rgb565 (
        .I_rgb888 (S_eth_video_rgb888),
        .O_rgb565 (S_eth_video_rgb565)
    );

    udp_rgb565_video_tx #(
        .IMAGE_WIDTH        (`NET_VIDEO_W),
        .IMAGE_HEIGHT       (`NET_VIDEO_H),
        .PACKET_DATA_BYTES  (`NET_PACKET_DATA_BYTES),
        .FIFO_ADDR_WIDTH_W  (13)
    ) u_eth_video_tx (
        .I_rst               (S_eth_reset),
        .I_enable            (S_eth_pll_lock && S_phy_rst_n),
        .I_video_clk         (S_hdmi_pixel_clk),
        .I_pixel_valid       (S_eth_video_pixel_valid),
        .I_frame_start       (S_eth_video_frame_start),
        .I_pixel_rgb565      (S_eth_video_rgb565),
        .I_udp_clk           (S_eth_clk_125m),
        .I_W_udp_busy        (S_udp_tx_busy),
        .O_W_udp_req         (S_udp_tx_req),
        .O_W_udp_valid       (S_udp_tx_valid),
        .O_W_udp_data        (S_udp_tx_data),
        .O_W_udp_len         (S_udp_tx_len),
        .O_fifo_full         (S_eth_video_fifo_full),
        .O_fifo_empty        (S_eth_video_fifo_empty),
        .O_fifo_rdusedw      (S_eth_video_fifo_rdusedw),
        .O_dropped_pixels    (S_eth_video_dropped_pixels),
        .O_frame_sequence    (S_eth_video_frame_sequence),
        .O_packet_sequence   (S_eth_video_packet_sequence),
        .O_frame_offset      (S_eth_video_frame_offset),
        .O_tx_active         (S_eth_video_tx_active)
    );

    end endgenerate

    // Begin local reset and real RAW admission logic (declared above consumers).
    (* async_reg="true" *) reg [1:0] camera_yolo_reset_sync,camera_stream_reset_sync;
    wire combined_async_ready=S_rst_n&&S_init_calib_complete&&S_phy_rst_n;
    always @(posedge S_ddr_clk or negedge combined_async_ready)
        if(!combined_async_ready)camera_yolo_reset_sync<=0;
        else camera_yolo_reset_sync<={camera_yolo_reset_sync[0],1'b1};
    assign camera_yolo_reset_n=camera_yolo_reset_sync[1];
    always @(posedge S_csi_rx_clk or negedge camera_yolo_reset_n)
        if(!camera_yolo_reset_n)camera_stream_reset_sync<=0;
        else camera_stream_reset_sync<={camera_stream_reset_sync[0],1'b1};
    assign camera_stream_reset_n=camera_stream_reset_sync[1];
    // Independent demosaic/AWB releases; third readiness branch only.
    (* async_reg="true" *) reg [2:0] camera_demosaic_reset_sync;
    (* async_reg="true" *) reg [2:0] camera_awb_reset_sync;
    (* async_reg="true" *) reg [2:0] camera_pack_reset_sync;
    always @(posedge S_csi_rx_clk or negedge camera_yolo_reset_n)
        if(!camera_yolo_reset_n) begin
            camera_demosaic_reset_sync<=0;
            camera_awb_reset_sync<=0;
            camera_pack_reset_sync<=0;
        end else begin
            camera_demosaic_reset_sync<={camera_demosaic_reset_sync[1:0],1'b1};
            camera_awb_reset_sync<={camera_awb_reset_sync[1:0],1'b1};
            camera_pack_reset_sync<={camera_pack_reset_sync[1:0],1'b1};
        end
    assign camera_demosaic_reset_n=camera_demosaic_reset_sync[2];
    assign camera_awb_reset_n=camera_awb_reset_sync[2];
    assign camera_pack_reset_n=camera_pack_reset_sync[2];
    assign camera_isp_reset_n=camera_demosaic_reset_n && camera_awb_reset_n && camera_pack_reset_n;
    // A frame whose RAW SOF was not accepted after local release must not seed
    // zhenghe's reset-origin synthetic output SOF. Admit only the next real SOF.
    reg isp_raw_frame_armed;
    always @(posedge S_csi_rx_clk or negedge camera_isp_reset_n)
        if(!camera_isp_reset_n)isp_raw_frame_armed<=1'b0;
        else if(S_raw_tvalid && S_raw_tuser)isp_raw_frame_armed<=1'b1;
    wire isp_raw_open=camera_isp_reset_n && (isp_raw_frame_armed || (S_raw_tvalid && S_raw_tuser));
    assign isp_raw_valid=S_raw_tvalid && isp_raw_open;
    assign isp_raw_sof=S_raw_tuser && isp_raw_valid;
    assign isp_raw_eol=S_raw_tlast && isp_raw_valid;
    assign S_ISP_O_tready=1'b1;
    wire shared_req_valid,shared_req_ready,shared_req_write,shared_read_valid,shared_read_ready;
    wire [27:0] shared_req_address;wire [127:0] shared_req_data,shared_read_data;wire [15:0] shared_req_strobe;
    wire app_udp_req,app_udp_valid,ae_udp_req,ae_udp_valid;
    wire [7:0] app_udp_data,ae_udp_data;wire [15:0] app_udp_len,ae_udp_len;
    wire [1:0] ae_outer_grants;
    wire [15:0] ae_status={11'd0,ae_fault,sc520_iic_error,S_ae_cfg_done,sc520_sensor_id_ok,S_cam_cfg_done};
    // CC13: TF boot status (S_ddr_clk, quasi-static, observation only) -> per-bit two-flop sync into the 24 MHz
    // telemetry source domain. Y5AE word6[31:19] = {first_error[7:0], boot_state[4:0]} (was 13'd0) and
    // word5[31:28] = {retries[1:0], recovery, model_ready} (was 4'd0). Packet format/length unchanged.
    wire [16:0] tf_status_ddr; (* ASYNC_REG="TRUE" *) reg [16:0] tf_status_s1,tf_status_s2;
    always @(posedge S_24m_clk) begin tf_status_s1<=tf_status_ddr; tf_status_s2<=tf_status_s1; end
    wire [12:0] tf_word6={tf_status_s2[15:8],tf_status_s2[7:3]}; wire [3:0] tf_word5={tf_status_s2[2:1],tf_status_s2[0],tf_status_s2[16]};
    // CC4: original AE telemetry (byte-identical il3/R10 instance) restored, plus two
    // board-bring-up diagnostics using the SAME sc520_ae_telemetry module (Y5AE, 40 B,
    // every ~0.1 s), tagged in word7[31:24]: 0xD1 = 100 MHz app counters, 0xD2 = camera
    // stream counters. Diagnostic only; no YOLO/Camera/Video datapath change.
    wire l1_req,l1_valid,l1_grant,l2_req,l2_valid,l2_grant;wire [7:0] l1_data,l2_data;wire [15:0] l1_len,l2_len;
    wire diag_model_ready,diag_yolo_busy,diag_yolo_error;wire [7:0] diag_active_layer;
    wire [12:0] diag_app_state; // CC9: {ystate[3:0],vstate[2:0],prep_busy,latest_valid,yolo_locked,video_locked,release_error,core_idle}
    wire [31:0] diag_commits,diag_skips,diag_bad_frames,diag_overflow_lines,diag_model_loads,diag_yolo_starts,diag_yolo_dones;
    // CC14: camera / YOLO hand-off state for startup diagnosis (observation only) -> Y5AE word7[31:21] (were zero):
    // {ystate[3:0], vstate[2:0], latest_valid, video_locked, commits!=0, skips!=0}; same per-bit 2-flop sync.
    wire [10:0] hs_ddr={diag_app_state[12:6],diag_app_state[4],diag_app_state[2],|diag_commits,|diag_skips};
    (* ASYNC_REG="TRUE" *) reg [10:0] hs_s1,hs_s2;
    always @(posedge S_24m_clk) begin hs_s1<=hs_ddr; hs_s2<=hs_s1; end
    sc520_ae_telemetry u_sc520_ae_telemetry (
      .source_clk(S_24m_clk),.dest_clk(S_ddr_clk),
      .common_reset_n(ae_common_ready && camera_yolo_reset_n),
      .values_i({hs_s2,ae_status[4:0],sc520_sensor_id,tf_word6,ae_clipped,tf_word5,ae_green_sum,
        ae_transactions,ae_applied_gain,ae_applied_exp,S_ag,S_ae,ae_command_sequence,ae_raw_sequence}),
      .udp_busy_i(ae_outer_grants[1]),.udp_request_o(ae_udp_req),.udp_valid_o(ae_udp_valid),
      .udp_data_o(ae_udp_data),.udp_length_o(ae_udp_len));
    camera_udp_packet_arbiter u_ae_outer_packet_arbiter (
      .clk(S_ddr_clk),.rst_n(camera_yolo_reset_n),
      .request_i({ae_udp_req,app_udp_req}),.valid_i({ae_udp_valid,app_udp_valid}),
      .data_i({ae_udp_data,app_udp_data}),.length_i({ae_udp_len,app_udp_len}),
      .grant_o(ae_outer_grants),.request_o(l1_req),.valid_o(l1_valid),
      .data_o(l1_data),.length_o(l1_len),.vendor_busy_i(l1_grant),.active_o());
    // CC12: D1 diagnostic packet removed as well (CC11 phys2 routing diverged at 98% Slice; area for the
    // colour stage). Y5AE AE/sensor telemetry kept: the AE outer arbiter output drives the UDP TX port directly.
    assign S_udp_tx_req=l1_req;assign S_udp_tx_valid=l1_valid;assign S_udp_tx_data=l1_data;assign S_udp_tx_len=l1_len;assign l1_grant=S_udp_tx_busy;
    camera_yolo_application u_camera_yolo_application(
        .sd_cs_n(O_tf_cs_n),.sd_sclk(O_tf_sclk),.sd_mosi(O_tf_mosi),.sd_miso(I_tf_miso),
        .clk(S_ddr_clk),.rst_n(camera_yolo_reset_n),.camera_clk(S_csi_rx_clk),.camera_rst_n(camera_stream_reset_n),
        .camera_frame_start_i(S_ISP_O_tuser),.camera_word_valid_i(S_ISP_O_tvalid),.camera_word_data_i(S_ISP_O_tdata),
        .udp_rx_valid_i(S_udp_rx_valid),.udp_rx_data_i(S_udp_rx_data),.udp_rx_length_i(S_udp_rx_len),
        .udp_busy_i(ae_outer_grants[0]),.udp_request_o(app_udp_req),.udp_valid_o(app_udp_valid),.udp_data_o(app_udp_data),.udp_length_o(app_udp_len),
        .memory_req_valid_o(shared_req_valid),.memory_req_ready_i(shared_req_ready),.memory_req_write_o(shared_req_write),
        .memory_req_address_o(shared_req_address),.memory_req_data_o(shared_req_data),.memory_req_strobe_o(shared_req_strobe),
        .memory_read_valid_i(shared_read_valid),.memory_read_ready_o(shared_read_ready),.memory_read_data_i(shared_read_data),
        .model_ready_o(diag_model_ready),.model_load_count_o(diag_model_loads),.yolo_busy_o(diag_yolo_busy),.yolo_done_o(),.yolo_error_o(diag_yolo_error),.active_layer_o(diag_active_layer),
        .yolo_start_count_o(diag_yolo_starts),.yolo_done_count_o(diag_yolo_dones),.yolo_source_frame_id_o(),.camera_commit_count_o(diag_commits),.camera_skip_count_o(diag_skips),.camera_bad_frames_o(diag_bad_frames),.camera_overflow_lines_o(diag_overflow_lines),.diag_state_o(diag_app_state),.tf_status_o(tf_status_ddr));
    v5n_ph1p_ddr_line_bridge u_shared_physical_memory_bridge(
        .clk_i(S_ddr_clk),.rst_ni(camera_yolo_reset_n),.req_valid_i(shared_req_valid),.req_ready_o(shared_req_ready),.req_write_i(shared_req_write),
        .req_line_address_i(shared_req_address),.req_write_data_i(shared_req_data),.req_write_strobe_i(shared_req_strobe),
        .read_valid_o(shared_read_valid),.read_ready_i(shared_read_ready),.read_data_o(shared_read_data),
        .mc_app_addr_o(S_mc_app_addr),.mc_app_cmd_o(S_mc_app_cmd),.mc_app_en_o(S_mc_app_en),.mc_app_rdy_i(S_mc_app_rdy),
        .mc_wdf_data_o(S_mc_app_wdf_data),.mc_wdf_end_o(S_mc_app_wdf_end),.mc_wdf_mask_o(S_mc_app_wdf_mask),.mc_wdf_wren_o(S_mc_app_wdf_wren),.mc_wdf_rdy_i(S_mc_app_wdf_rdy),
        .mc_read_data_i(S_mc_app_rd_data),.mc_read_valid_i(S_mc_app_rd_data_valid));

    // Reserved reference connector pins; HDMI functionality intentionally absent.
    assign O_tmds_ch0_p=1'b0;
    assign O_tmds_ch1_p=1'b0;
    assign O_tmds_ch2_p=1'b0;
    assign O_tmds_clk_p=1'b0;


    
endmodule
