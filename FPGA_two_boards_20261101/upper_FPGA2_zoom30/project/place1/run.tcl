cd [file dirname [info script]]
if {[catch {
import_device ph1_35p.db -package PH1P35MDG324 -speed 3
import_db {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/whole/local_gate.db}
clear_sdc
read_sdc {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/physical_signoff1.sdc}
update_timing
if {[llength [get_clocks {rgmii/u_rgmii_rx_lclk.clkdivout}]]!=1} {error {Own required clock missing after checkpoint import}}
if {[llength [get_clocks {u_ph1p35_324_ddr_wrapper/u_ddr2/ph1p_ddrmc_wrapper/ph1p_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_clk/u_pll1/u_pll_inst.clkc[0]}]]!=1} {error {Own required clock missing after checkpoint import}}
if {[llength [get_clocks {u_PLL/ph1p_phy_pll_wrapper_25a56e5ce2f9_Inst/u_PH1P_PHY_PLL.clkc[4]}]]!=1} {error {Own required clock missing after checkpoint import}}
if {[llength [get_clocks {u_mipi_dphy_rx_ph1p_mipiio_wrapper/u_ph1p_mipiio_rx_wrapper/u_PH1P_LOGIC_DPHY_MIPI_RX.o_fabric_div4_8_clk}]]!=1} {error {Own required clock missing after checkpoint import}}
if {[llength [get_clocks {sys_clk_50m}]]!=1} {error {Own required clock missing after checkpoint import}}
if {[llength [get_clocks {u_PLL/ph1p_phy_pll_wrapper_25a56e5ce2f9_Inst/u_PH1P_PHY_PLL.clkc[1]}]]!=1} {error {Own required clock missing after checkpoint import}}
if {[llength [get_clocks {u_eth_pll/ph1p_phy_pll_wrapper_d2616deaaa79_Inst/u_PH1P_PHY_PLL.clkc[0]}]]!=1} {error {Own required clock missing after checkpoint import}}
if {[llength [get_clocks {u_PLL/ph1p_phy_pll_wrapper_25a56e5ce2f9_Inst/u_PH1P_PHY_PLL.clkc[5]}]]!=1} {error {Own required clock missing after checkpoint import}}
if {[llength [get_clocks {u_ph1p35_324_ddr_wrapper/u_ddr2/ph1p_ddrmc_wrapper/ph1p_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_clk/u_pll0/u_pll_inst.clkc[3]}]]!=1} {error {Own required clock missing after checkpoint import}}
if {[llength [get_clocks {camera_i2c_internal}]]!=1} {error {Own required clock missing after checkpoint import}}
if {[llength [get_clocks {u_eth_pll/ph1p_phy_pll_wrapper_d2616deaaa79_Inst/u_PH1P_PHY_PLL.clkc[2]}]]!=1} {error {Own required clock missing after checkpoint import}}
if {[llength [get_clocks {rgmii/u_rgmii_rx_lclk.clkout}]]!=1} {error {Own required clock missing after checkpoint import}}
if {[llength [get_clocks {u_PLL/ph1p_phy_pll_wrapper_25a56e5ce2f9_Inst/u_PH1P_PHY_PLL.clkc[0]}]]!=1} {error {Own required clock missing after checkpoint import}}
if {[llength [get_clocks {u_ph1p35_324_ddr_wrapper/u_ddr2/ph1p_ddrmc_wrapper/ph1p_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_clk/u_pll0/u_pll_inst.clkc[1]}]]!=1} {error {Own required clock missing after checkpoint import}}
if {[llength [get_clocks {u_ph1p35_324_ddr_wrapper/u_ddr2/ph1p_ddrmc_wrapper/ph1p_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_clk/u_pll0/u_pll_inst.clkc[2]}]]!=1} {error {Own required clock missing after checkpoint import}}
if {[llength [get_clocks {u_eth_pll/ph1p_phy_pll_wrapper_d2616deaaa79_Inst/u_PH1P_PHY_PLL.clkc[1]}]]!=1} {error {Own required clock missing after checkpoint import}}
if {[llength [get_clocks {rgmii_rx_pad}]]!=1} {error {Own required clock missing after checkpoint import}}
if {[llength [get_clocks {mipi_rx_ck_pad}]]!=1} {error {Own required clock missing after checkpoint import}}
if {[llength [get_clocks {u_mipi_dphy_rx_ph1p_mipiio_wrapper/u_ph1p_mipiio_rx_wrapper/u_PH1P_LOGIC_DPHY_MIPI_RX.tif_c16_in}]]!=1} {error {Own required clock missing after checkpoint import}}
if {[llength [get_clocks {u_ph1p35_324_ddr_wrapper/u_ddr2/ph1p_ddrmc_wrapper/ph1p_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_clk/u_pll0/u_pll_inst.clkc[0]}]]!=1} {error {Own required clock missing after checkpoint import}}
if {[llength [get_clocks {rgmii_txc_forward}]]!=1} {error {Own required clock missing after checkpoint import}}
if {[llength [get_clocks {u_mipi_dphy_rx_ph1p_mipiio_wrapper/u_ph1p_mipiio_rx_wrapper/u_PH1P_LOGIC_DPHY_MIPI_RX.io_clk_pad_p}]]!=1} {error {Own required clock missing after checkpoint import}}
if {[llength [get_regs {frames/fifo/rg[*]}]]==0} {error {Own exact SDC selector absent}}
if {[llength [get_regs {frames/fifo/rgs1[*]}]]==0} {error {Own exact SDC selector absent}}
if {[llength [get_regs {frames/fifo/wg[*]}]]==0} {error {Own exact SDC selector absent}}
if {[llength [get_regs {frames/fifo/wgs1[*]}]]==0} {error {Own exact SDC selector absent}}
if {[llength [get_regs {frames/ingress/ownership/ack}]]==0} {error {Own exact SDC selector absent}}
if {[llength [get_regs {frames/ingress/ownership/ack_s1}]]==0} {error {Own exact SDC selector absent}}
if {[llength [get_regs {frames/ingress/ownership/req}]]==0} {error {Own exact SDC selector absent}}
if {[llength [get_regs {frames/ingress/ownership/req_s1}]]==0} {error {Own exact SDC selector absent}}
if {[llength [get_regs {frames/reader/ack}]]==0} {error {Own exact SDC selector absent}}
if {[llength [get_regs {frames/reader/as1}]]==0} {error {Own exact SDC selector absent}}
if {[llength [get_regs {frames/reader/req}]]==0} {error {Own exact SDC selector absent}}
if {[llength [get_regs {frames/reader/qs1}]]==0} {error {Own exact SDC selector absent}}
if {[llength [get_regs {frames/reader/cache/done_toggle[*]}]]==0} {error {Own exact SDC selector absent}}
if {[llength [get_regs {frames/reader/cache/ds1[*]}]]==0} {error {Own exact SDC selector absent}}
if {[llength [get_regs {frames/arb/remote_commit_toggle}]]==0} {error {Own exact SDC selector absent}}
if {[llength [get_regs {frames/c1}]]==0} {error {Own exact SDC selector absent}}
if {[llength [get_regs {frames/ingress/ownership/published_bank[*]}]]==0} {error {Own exact SDC selector absent}}
if {[llength [get_regs {frames/ingress/ownership/rd_bank[*]}]]==0} {error {Own exact SDC selector absent}}
if {[llength [get_regs {frames/ingress/ownership/published_id[*]}]]==0} {error {Own exact SDC selector absent}}
if {[llength [get_regs {frames/ingress/ownership/rd_frame_id[*]}]]==0} {error {Own exact SDC selector absent}}
if {[llength [get_regs {frames/reader/wanted[*] frames/reader/rb[*] frames/reader/rid[*] frames/reader/request_epoch[*] frames/reader/request_stereo frames/reader/request_remote}]]==0} {error {Own exact SDC selector absent}}
if {[llength [get_clocks {u_ph1p35_324_ddr_wrapper/u_ddr2/ph1p_ddrmc_wrapper/ph1p_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_clk/u_pll1/u_pll_inst.clkc[0]}]]==0} {error {Own exact SDC selector absent}}
if {[llength [get_regs {frames/reader/cache/row_tag[0][*] frames/reader/cache/lid[0][*] frames/reader/cache/rid[0][*]}]]==0} {error {Own exact SDC selector absent}}
if {[llength [get_clocks {u_PLL/ph1p_phy_pll_wrapper_25a56e5ce2f9_Inst/u_PH1P_PHY_PLL.clkc[4]}]]==0} {error {Own exact SDC selector absent}}
if {[llength [get_regs {frames/reader/cache/row_tag[1][*] frames/reader/cache/lid[1][*] frames/reader/cache/rid[1][*]}]]==0} {error {Own exact SDC selector absent}}
if {[llength [get_clocks {u_PLL/ph1p_phy_pll_wrapper_25a56e5ce2f9_Inst/u_PH1P_PHY_PLL.clkc[4]}]]==0} {error {Own exact SDC selector absent}}
if {[llength [get_regs {frames/reader/cache/row_tag[2][*] frames/reader/cache/lid[2][*] frames/reader/cache/rid[2][*]}]]==0} {error {Own exact SDC selector absent}}
if {[llength [get_clocks {u_PLL/ph1p_phy_pll_wrapper_25a56e5ce2f9_Inst/u_PH1P_PHY_PLL.clkc[4]}]]==0} {error {Own exact SDC selector absent}}
if {[llength [get_regs {frames/reader/cache/row_tag[3][*] frames/reader/cache/lid[3][*] frames/reader/cache/rid[3][*]}]]==0} {error {Own exact SDC selector absent}}
if {[llength [get_clocks {u_PLL/ph1p_phy_pll_wrapper_25a56e5ce2f9_Inst/u_PH1P_PHY_PLL.clkc[4]}]]==0} {error {Own exact SDC selector absent}}
if {[llength [get_regs {control_reply/req}]]==0} {error {Own exact SDC selector absent}}
if {[llength [get_regs {control_reply/req1}]]==0} {error {Own exact SDC selector absent}}
if {[llength [get_regs {control_reply/ack}]]==0} {error {Own exact SDC selector absent}}
if {[llength [get_regs {control_reply/ack1}]]==0} {error {Own exact SDC selector absent}}
if {[llength [get_regs {control_reply/smac[*][*] control_reply/sip[*][*]}]]==0} {error {Own exact SDC selector absent}}
if {[llength [get_clocks {u_eth_pll/ph1p_phy_pll_wrapper_d2616deaaa79_Inst/u_PH1P_PHY_PLL.clkc[0]}]]==0} {error {Own exact SDC selector absent}}
if {[llength [get_regs {frames/yolo/req}]]==0} {error {Own exact SDC selector absent}}
if {[llength [get_regs {frames/yolo/req1}]]==0} {error {Own exact SDC selector absent}}
if {[llength [get_regs {frames/yolo/ack}]]==0} {error {Own exact SDC selector absent}}
if {[llength [get_regs {frames/yolo/ack1}]]==0} {error {Own exact SDC selector absent}}
if {[llength [get_regs {frames/yolo/held_tracks[*] frames/yolo/held_id[*] frames/yolo/held_total[*] frames/yolo/held_selected[*]}]]==0} {error {Own exact SDC selector absent}}
if {[llength [get_clocks {u_PLL/ph1p_phy_pll_wrapper_25a56e5ce2f9_Inst/u_PH1P_PHY_PLL.clkc[4]}]]==0} {error {Own exact SDC selector absent}}
if {[llength [get_regs {u_video_in/U_w128_d512_fifo/soft_fifo_al_4057d6b76aa6_Inst/rd_to_wr_cross_inst/primary_addr_gray_reg[*]}]]==0} {error {Own exact SDC selector absent}}
if {[llength [get_regs {u_video_in/U_w128_d512_fifo/soft_fifo_al_4057d6b76aa6_Inst/rd_to_wr_cross_inst/sync_r1[*]}]]==0} {error {Own exact SDC selector absent}}
if {[llength [get_regs {u_video_in/U_w128_d512_fifo/soft_fifo_al_4057d6b76aa6_Inst/wr_to_rd_cross_inst/primary_addr_gray_reg[*]}]]==0} {error {Own exact SDC selector absent}}
if {[llength [get_regs {u_video_in/U_w128_d512_fifo/soft_fifo_al_4057d6b76aa6_Inst/wr_to_rd_cross_inst/sync_r1[*]}]]==0} {error {Own exact SDC selector absent}}
if {[llength [get_regs {u_video_in/S_camera_frame_start_extend}]]==0} {error {Own exact SDC selector absent}}
if {[llength [get_regs {u_video_in/S_camera_frame_start_extend_1d}]]==0} {error {Own exact SDC selector absent}}
if {[llength [get_regs {u_video_in/S_camera_frame_start_extend_3d}]]==0} {error {Own exact SDC selector absent}}
if {[llength [get_regs {u_video_in/U_w128_d512_fifo/soft_fifo_al_4057d6b76aa6_Inst/asy_w_rst0}]]==0} {error {Own exact SDC selector absent}}
if {[llength [get_regs {u_video_in/S_camera_frame_start_extend_3d}]]==0} {error {Own exact SDC selector absent}}
if {[llength [get_regs {u_video_in/U_w128_d512_fifo/soft_fifo_al_4057d6b76aa6_Inst/ram_inst/rsta}]]==0} {error {Own exact SDC selector absent}}
# CLAUDE UPPER_V1: tracking_mailbox1 removed (mode 47); selector check dropped
# CLAUDE UPPER_V1: tracking_mailbox1 removed (mode 47); selector check dropped
# CLAUDE UPPER_V1: tracking_mailbox1 removed (mode 47); selector check dropped
# CLAUDE UPPER_V1: tracking_mailbox1 removed (mode 47); selector check dropped
# CLAUDE UPPER_V1: tracking_mailbox1 removed (mode 47); selector check dropped
if {[llength [get_clocks {rgmii/u_rgmii_rx_lclk.clkdivout}]]==0} {error {Own exact SDC selector absent}}
# CLAUDE UPPER_V1: tracking_mailbox1 removed (mode 47); selector check dropped
if {[llength [get_clocks {u_PLL/ph1p_phy_pll_wrapper_25a56e5ce2f9_Inst/u_PH1P_PHY_PLL.clkc[4]}]]==0} {error {Own exact SDC selector absent}}
if {[llength [get_regs {phy_reset/ready}]]==0} {error {Own exact SDC selector absent}}
if {[llength [get_regs {control_reply/rx_release/release_chain[0] control_reply/rx_release/release_chain[1] rx_release/release_chain[0] rx_release/release_chain[1]}]]==0} {error {Own exact SDC selector absent}}
if {[llength [get_regs {u_video_in/camera_fifo_flush_ack}]]==0} {error {Own exact SDC selector absent}}
if {[llength [get_regs {u_video_in/camera_handoff/ack1}]]==0} {error {Own exact SDC selector absent}}
export_db mapped_pre_place.db
# CLAUDE Z13 (2026-10-31): placement parameters of the routed CC24 flow on the same device (R10_TF_INTEGRATION/cc24/phys1,
# 93.64 % slice); z11b / z12 default placement did not converge in timing-driven routing.
set_param place pr_strategy 2
set_param place effort high
set_param place hfn_opt_effort high
set_param place opt_timing high
set_param place logic_level_opt off
set_param place aggressive_opt 20
set_param place aggr_neighbor_dist 5
set_param place enhanced_beeline_opt 3
set_param place timing_driven_mode off
set_param place shifter_opt on
set_param place crit_path_opt off
set_param place post_place_opt high
set_param place split_data_from_clock on
set_param place preplace_floorplan off
place
export_db place_raw.db
export_db place_pre_reports.db
write_verilog placed.v
update_timing -mode manhattan
report_area -io_info -file placed.area
report_timing_status -file placed.ts
report_timing_summary -file placed.timing
puts {MODE3_STEREO_PLACE1_DONE}
} e]} {puts stderr $e;puts stderr $::errorInfo;exit 2}
exit 0
