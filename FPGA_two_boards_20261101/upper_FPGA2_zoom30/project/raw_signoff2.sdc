# Initial measurement; no falsepath/clockgroup/multicycle waiver.
create_clock -name sys_clk_50m -period 20.000 -waveform {0 10} [get_ports I_sys_clk]
create_clock -name mipi_rx_ck_pad -period 2.415 -waveform {0 1.208} [get_nets IO_rx_clk_pad_p]
create_clock -name rgmii_rx_pad -period 8.000 -waveform {0 4} [get_ports I_a_rgmii_rxc]
derive_clocks

# Actual uiI2C CLK_DIV237, SCL_DIV118: toggles every119 camera edges.
create_generated_clock -name camera_i2c_internal -source [get_pins {u_PLL/ph1p_phy_pll_wrapper_25a56e5ce2f9_Inst/u_PH1P_PHY_PLL.clkc[1]}] -edges {237 475 713} [get_nets {u_uicfgcs520/u_i2c/scl_clk}]
# Exact vendor FIFO Gray FIRST entry only; source periods>=9.66ns, conservative7ns bound. Subsequent stages normal STA.
set_max_delay -from [get_regs {u_video_in/U_w128_d512_fifo/soft_fifo_al_4057d6b76aa6_Inst/rd_to_wr_cross_inst/primary_addr_gray_reg[*]}] -to [get_regs {u_video_in/U_w128_d512_fifo/soft_fifo_al_4057d6b76aa6_Inst/rd_to_wr_cross_inst/sync_r1[*]}] -datapath_only 7.000
# Exact vendor FIFO Gray FIRST entry only; source periods>=9.66ns, conservative7ns bound. Subsequent stages normal STA.
set_max_delay -from [get_regs {u_video_in/U_w128_d512_fifo/soft_fifo_al_4057d6b76aa6_Inst/wr_to_rd_cross_inst/primary_addr_gray_reg[*]}] -to [get_regs {u_video_in/U_w128_d512_fifo/soft_fifo_al_4057d6b76aa6_Inst/wr_to_rd_cross_inst/sync_r1[*]}] -datapath_only 7.000
# Exact vendor FIFO Gray FIRST entry only; source periods>=9.66ns, conservative7ns bound. Subsequent stages normal STA.
# Exact vendor FIFO Gray FIRST entry only; source periods>=9.66ns, conservative7ns bound. Subsequent stages normal STA.

# Own native graph + bounded release evidence: true async FIRST entry only, not functional downstream waiver.
set_max_delay -from [get_regs {u_video_in/S_camera_frame_start_extend}] -to [get_regs {u_video_in/S_camera_frame_start_extend_1d}] -datapath_only 7.000

# Own native graph + bounded release evidence: true async FIRST entry only, not functional downstream waiver.

# Own native graph + bounded release evidence: true async FIRST entry only, not functional downstream waiver.
set_max_delay -from [get_regs {u_video_in/S_camera_frame_start_extend_3d}] -to [get_regs {u_video_in/U_w128_d512_fifo/soft_fifo_al_4057d6b76aa6_Inst/asy_w_rst0}] -datapath_only 7.000

# Own native graph + bounded release evidence: true async FIRST entry only, not functional downstream waiver.
set_max_delay -from [get_regs {u_video_in/S_camera_frame_start_extend_3d}] -to [get_regs {u_video_in/U_w128_d512_fifo/soft_fifo_al_4057d6b76aa6_Inst/ram_inst/rsta}] -datapath_only 7.000

# Own native graph + bounded release evidence: true async FIRST entry only, not functional downstream waiver.

# Own native graph + bounded release evidence: true async FIRST entry only, not functional downstream waiver.

# Own Gray first-entry only; min source period8ns; second stage remains normal STA
set_max_delay -from [get_regs {frames/fifo/rg[*]}] -to [get_regs {frames/fifo/rgs1[*]}] -datapath_only 7.000
# Own Gray first-entry only; min source period8ns; second stage remains normal STA
set_max_delay -from [get_regs {frames/fifo/wg[*]}] -to [get_regs {frames/fifo/wgs1[*]}] -datapath_only 7.000
# Exact preserved MAC Gray transfer FIRST entry,125MHz source
# Exact preserved MAC Gray transfer FIRST entry,125MHz source
# Exact preserved MAC Gray transfer FIRST entry,125MHz source
# Exact preserved MAC Gray transfer FIRST entry,125MHz source
# Exact preserved MAC Gray transfer FIRST entry,125MHz source
# Exact preserved MAC Gray transfer FIRST entry,125MHz source
# Own verified twoFF ownership FIRST entry only
set_max_delay -from [get_regs {frames/ingress/ownership/ack}] -to [get_regs {frames/ingress/ownership/ack_s1}] -datapath_only 7.000
# Own verified twoFF ownership FIRST entry only
set_max_delay -from [get_regs {frames/ingress/ownership/req}] -to [get_regs {frames/ingress/ownership/req_s1}] -datapath_only 7.000
# Own verified first-only toggle synchronization; subsequent setup/hold unchanged
set_max_delay -from [get_regs {frames/reader/ack}] -to [get_regs {frames/reader/as1}] -datapath_only 7.000
# Own verified first-only toggle synchronization; subsequent setup/hold unchanged
set_max_delay -from [get_regs {frames/reader/req}] -to [get_regs {frames/reader/qs1}] -datapath_only 7.000
# Own verified first-only toggle synchronization; subsequent setup/hold unchanged
set_max_delay -from [get_regs {frames/reader/cache/done_toggle[*]}] -to [get_regs {frames/reader/cache/ds1[*]}] -datapath_only 7.000
# Own verified first-only toggle synchronization; subsequent setup/hold unchanged
set_max_delay -from [get_regs {frames/arb/remote_commit_toggle}] -to [get_regs {frames/c1}] -datapath_only 7.000
# Held until ACK; earliest consumption>=two13.333ns pixel periods
set_max_delay -from [get_regs {frames/ingress/ownership/published_bank[*]}] -to [get_regs {frames/ingress/ownership/rd_bank[*]}] -datapath_only 20.000
# Held FID until ACK; earliest consumption>=26.666ns
set_max_delay -from [get_regs {frames/ingress/ownership/published_id[*]}] -to [get_regs {frames/ingress/ownership/rd_frame_id[*]}] -datapath_only 20.000
# Only request-captured stable fields; req->qs1->qs2 then consumer,>=two15ns DDR periods; held through ACK
set_max_delay -from [get_regs {frames/reader/wanted[*] frames/reader/wreal[*] frames/reader/rb[*] frames/reader/rid[*] frames/reader/request_epoch[*] frames/reader/request_stereo frames/reader/request_remote frames/reader/req_first frames/reader/req_last}] -to [get_clocks {u_ph1p35_324_ddr_wrapper/u_ddr2/ph1p_ddrmc_wrapper/ph1p_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_clk/u_pll1/u_pll_inst.clkc[0]}] -datapath_only 14.000
# Only complete-row metadata captured after done toggle ds1/ds2; held through row-bank reuse
set_max_delay -from [get_regs {frames/reader/cache/row_tag[0][*] frames/reader/cache/lid[0][*] frames/reader/cache/rid[0][*]}] -to [get_clocks {u_PLL/ph1p_phy_pll_wrapper_25a56e5ce2f9_Inst/u_PH1P_PHY_PLL.clkc[4]}] -datapath_only 20.000
# Only complete-row metadata captured after done toggle ds1/ds2; held through row-bank reuse
set_max_delay -from [get_regs {frames/reader/cache/row_tag[1][*] frames/reader/cache/lid[1][*] frames/reader/cache/rid[1][*]}] -to [get_clocks {u_PLL/ph1p_phy_pll_wrapper_25a56e5ce2f9_Inst/u_PH1P_PHY_PLL.clkc[4]}] -datapath_only 20.000
# Same held metadata bound for the two new prefetch banks.
set_max_delay -from [get_regs {frames/reader/cache/row_tag[2][*] frames/reader/cache/lid[2][*] frames/reader/cache/rid[2][*]}] -to [get_clocks {u_PLL/ph1p_phy_pll_wrapper_25a56e5ce2f9_Inst/u_PH1P_PHY_PLL.clkc[4]}] -datapath_only 20.000
set_max_delay -from [get_regs {frames/reader/cache/row_tag[3][*] frames/reader/cache/lid[3][*] frames/reader/cache/rid[3][*]}] -to [get_clocks {u_PLL/ph1p_phy_pll_wrapper_25a56e5ce2f9_Inst/u_PH1P_PHY_PLL.clkc[4]}] -datapath_only 20.000
# YT8511 datasheet p85, with RX internal delay: setup/hold min1.65ns.
# Explicit OFFLINE board contract: nominal8ns clock/4ns halves and differential PCB skew<=0.1ns.
# Describe NEXT data transition after capture; not a fictitious external zero launch phase.
# Actual strap/delay-mode/PCB/load remain BOARD TEST PENDING.
set_input_delay -clock rgmii_rx_pad -max 2.450 [get_ports {I_a_rgmii_rxd[*] I_a_rgmii_rx_ctl}]
set_input_delay -clock rgmii_rx_pad -min 1.550 [get_ports {I_a_rgmii_rxd[*] I_a_rgmii_rx_ctl}]
set_input_delay -clock rgmii_rx_pad -clock_fall -add_delay -max 2.450 [get_ports {I_a_rgmii_rxd[*] I_a_rgmii_rx_ctl}]
set_input_delay -clock rgmii_rx_pad -clock_fall -add_delay -min 1.550 [get_ports {I_a_rgmii_rxd[*] I_a_rgmii_rx_ctl}]
# Actual native125MHz90deg PLL output forwards TXC through ODDR.
create_generated_clock -name rgmii_txc_forward -source [get_pins {u_eth_pll/ph1p_phy_pll_wrapper_d2616deaaa79_Inst/u_PH1P_PHY_PLL.clkc[1]}] -divide_by 1 [get_ports O_a_rgmii_txc]
# PHY receiver setup/hold>=1ns plus explicit0.1ns skew contract.
set_output_delay -clock rgmii_txc_forward -max 1.100 [get_ports {O_a_rgmii_txd[*] O_a_rgmii_tx_ctl}]
set_output_delay -clock rgmii_txc_forward -min -1.100 [get_ports {O_a_rgmii_txd[*] O_a_rgmii_tx_ctl}]
set_output_delay -clock rgmii_txc_forward -clock_fall -add_delay -max 1.100 [get_ports {O_a_rgmii_txd[*] O_a_rgmii_tx_ctl}]
set_output_delay -clock rgmii_txc_forward -clock_fall -add_delay -min -1.100 [get_ports {O_a_rgmii_txd[*] O_a_rgmii_tx_ctl}]
# Control reply metadata/bank held from validated RX through complete TX and IFG.
set_max_delay -from [get_regs {control_reply/req}] -to [get_regs {control_reply/req1}] -datapath_only 7.000
set_max_delay -from [get_regs {control_reply/ack}] -to [get_regs {control_reply/ack1}] -datapath_only 7.000
set_max_delay -from [get_regs {control_reply/smac[*][*] control_reply/sip[*][*]}] -to [get_clocks {u_eth_pll/ph1p_phy_pll_wrapper_d2616deaaa79_Inst/u_PH1P_PHY_PLL.clkc[0]}] -datapath_only 14.000


# Actual result snapshot held until pixel-VS acknowledgement; first toggle stages only.
set_max_delay -from [get_regs {frames/yolo/req}] -to [get_regs {frames/yolo/req1}] -datapath_only 7.000
set_max_delay -from [get_regs {frames/yolo/ack}] -to [get_regs {frames/yolo/ack1}] -datapath_only 7.000
set_max_delay -from [get_regs {frames/yolo/held_tracks[*] frames/yolo/held_id[*] frames/yolo/held_total[*] frames/yolo/held_selected[*]}] -to [get_clocks {u_PLL/ph1p_phy_pll_wrapper_25a56e5ce2f9_Inst/u_PH1P_PHY_PLL.clkc[4]}] -datapath_only 20.000

# Actual bound source after reset OR: old S_fifo_rst is combinational, not a reg.
# Same7ns/two intended reset-chain ASR entries; interstage and downstream normal STA.
if {[llength [get_regs {u_video_in/S_camera_frame_start_extend_3d}]] != 1} {error {FIFO reset actual source not unique}}

# CLAUDE DEPTH: depth_map CDC first stages (arm toggle pclk -> camera / rx, done toggles back)
set_max_delay -from [get_regs {u_vision/u_depth/a_t}] -to [get_regs {u_vision/u_depth/la1 u_vision/u_depth/ra1}] -datapath_only 7.000
set_max_delay -from [get_regs {u_vision/u_depth/l_done_t}] -to [get_regs {u_vision/u_depth/ld1}] -datapath_only 7.000
set_max_delay -from [get_regs {u_vision/u_depth/r_done_t}] -to [get_regs {u_vision/u_depth/rd1}] -datapath_only 7.000

# CLAUDE MERGE: range_meter CDC first stages (arm toggles, done toggles, quasi-static position / band bus)
set_max_delay -from [get_regs {u_vision/u_range/al_t}] -to [get_regs {u_vision/u_range/la1}] -datapath_only 7.000
set_max_delay -from [get_regs {u_vision/u_range/ar_t}] -to [get_regs {u_vision/u_range/ra1}] -datapath_only 7.000
set_max_delay -from [get_regs {u_vision/u_range/l_done_t}] -to [get_regs {u_vision/u_range/ld1}] -datapath_only 7.000
set_max_delay -from [get_regs {u_vision/u_range/r_done_t}] -to [get_regs {u_vision/u_range/rd1}] -datapath_only 7.000
set_max_delay -from [get_regs {u_vision/u_range/bx[*] u_vision/u_range/by[*]}] -to [get_regs {u_vision/u_range/lb1[*] u_vision/u_range/rb1[*]}] -datapath_only 20.000

# CLAUDE MERGE Vision Core: mode levels copied into the camera / rx clocks (2 FF, quasi-static)
# CLAUDE BOTTLE: + rw1 (mode 38 BOTTLE level into the rx clock)
set_false_path -to [get_regs {u_vision/cl1 u_vision/cd1 u_vision/rs1 u_vision/rd1 u_vision/rw1}]
# CLAUDE ZOOM2: same first-entry bound for the eth90 / eth125 reset synchronizers (async assert, 2-FF synchronous release)
set_max_delay -from [get_regs {phy_reset/ready}] -to [get_regs {eth90_release/release_chain[0] eth90_release/release_chain[1] eth125_release/release_chain[0] eth125_release/release_chain[1]}] -datapath_only 7.000

# CLAUDE Z14: auto exposure mailbox (CC24 sc520_auto_exposure): async toggle first stages, and the dark / bright flags
# held with the request (stable >= 2 cfg clocks before the synchronized toggle is seen) into the 24 MHz decision.
set_max_delay -from [get_regs {u_sc520_ae/request_toggle}] -to [get_regs {u_sc520_ae/req_meta}] -datapath_only 7.000
set_max_delay -from [get_regs {u_sc520_ae/ack_toggle}] -to [get_regs {u_sc520_ae/ack_meta}] -datapath_only 7.000
set_max_delay -from [get_regs {u_sc520_ae/held_bright u_sc520_ae/enc_held_dark}] -datapath_only 20.000
# CLAUDE Z17: AE lock level (pixel clock, quasi-static) into the 24 MHz AE decision, 2-FF first stage
set_false_path -to [get_regs {u_sc520_ae/hold_meta}]
# CLAUDE Z25 LATENCY (latency_meter1): camera frame-start toggle -> pixel clock, slot Gray -> DDR clock, selection toggle ->
# pixel clock (2-FF first stages), held selected slot (sampled >= 2 pixel clocks after the toggle)
set_max_delay -from [get_regs {lat/ct}] -to [get_regs {lat/c1}] -datapath_only 7.000
set_max_delay -from [get_regs {lat/sof_g[*]}] -to [get_regs {frames/local_commit/sg1[*]}] -datapath_only 7.000
set_max_delay -from [get_regs {frames/reader/sel_tg}] -to [get_regs {lat/s1}] -datapath_only 7.000
set_max_delay -from [get_regs {frames/reader/sel_idx*}] -to [get_regs {lat/pidx*}] -datapath_only 20.000
# CLAUDE Z28B MONITOR: rx event toggles (0.1 Mbit unit, complete video frame) -> pixel clock (2-FF)
set_max_delay -from [get_regs {netm/unit_tg netm/frame_tg}] -to [get_regs {lat/u1 lat/f1}] -datapath_only 7.000
