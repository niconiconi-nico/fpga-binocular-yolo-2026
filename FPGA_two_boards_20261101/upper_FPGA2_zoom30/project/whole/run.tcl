cd [file dirname [info script]]
if {[catch {
import_device ph1_35p.db -package PH1P35MDG324 -speed 3
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/rtl/local_sad8_1.sv}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/eth_stereo_raw_top1.v}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/source/hdl_source/mipi_dphy_rx/mipi_dphy_rx_ph1p_mipiio_wrapper.sv}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/source/hdl_source/mipi_dphy_rx/ph1p_mipiio_rx_wrapper.v}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/source/hdl_source/video_in.v}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/source/hdl_source/mc_to_user_interface.v}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/source/hdl_source/mipi_dphy_rx/byte_aligner.enc.v}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/source/hdl_source/mipi_dphy_rx/byte_aligner_wrapper.enc.sv}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/source/hdl_source/mipi_dphy_rx/channel_aligner.enc.v}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/source/hdl_source/mipi_dphy_rx/channel_aligner_wrapper.enc.sv}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/source/hdl_source/mipi_dphy_rx/hs_detect.enc.v}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/source/hdl_source/signal_delay.v}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/source/hdl_source/awb.v}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/source/hdl_source/ph1p35_ddr/ph1p35_324_ddr_wrapper.v}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/source/hdl_source/isp/csi_unpacket_2lane.v}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/source/hdl_source/isp/isp_top.v}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/source/hdl_source/isp/raw10_unpacket_2lane.v}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/source/hdl_source/isp/uial2axis.v}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/source/hdl_source/isp/demosaic_4x_2_0/bilinear_interpolation.v}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/source/hdl_source/isp/demosaic_4x_2_0/demosaic.v}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/source/hdl_source/isp/demosaic_4x_2_0/line_buffer_demosaic.v}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/source/hdl_source/isp/demosaic_4x_2_0/mipi_to_raw_converter.v}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/source/hdl_source/isp/demosaic_4x_2_0/raw_matrix_3x3_buffer.v}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/source/hdl_source/isp/demosaic_4x_2_0/zhenghe.v}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/source/hdl_source/isp/data128_96/data128_96.v}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/source/hdl_source/isp/data96_128/data96_128.v}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/source/hdl_source/uics500_cfg/SC500GainTbl.v}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/source/hdl_source/uics500_cfg/uicfgcs500.v}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/source/hdl_source/uics500_cfg/uics500regAE.v}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/source/hdl_source/uics500_cfg/uii2c.v}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/rtl/sc520_auto_exposure.sv}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/source/hdl_source/hdmi_tx.v}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/source/hdl_source/hdmi_1_4b_transmitter_core_wrapper.enc.v}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/source/hdl_source/hdmi_phy_warpper.v}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/source/hdl_source/lane_lvds_10_1.v}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/source/hdl_source/vtc/uivtc.v}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/source/hdl_source/I2S_receiver.v}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/source/hdl_source/audio_arc_calculate.v}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/source/hdl_source/key_remove_shakes.v}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/source/hdl_source/uics520_cfg/SC520GainTbl.v}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/uicfgcs520_sensor180.v}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/source/hdl_source/uics520_cfg/uics520reg_720p60.v}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/source/hdl_source/uics520_cfg/uics520regAE.v}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/source/hdl_source/uics520_cfg/uics520reg.v}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/source/hdl_source/uics520_cfg/uics520reg_full_2560x1920_30.v}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/source/ip_source/PLL/PLL.v}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/source/ip_source/PLL/RTL/ph1p_phy_pll_wrapper_25a56e5ce2f9.v}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/source/ip_source/blk_mem_gen_awb_delay_signal/blk_mem_gen_awb_delay_signal.v}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/source/ip_source/blk_mem_gen_awb_delay_signal/ram_f84573da5ab5.v}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/source/hdl_source/ph1p35_ddr/ddr2/src/rtl/clk/ph1p_ddrphy_clk_top.v} -global_include {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/source/hdl_source/ph1p35_ddr/ddr2/src/rtl/include/ph1p_mis_define.vh}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/source/hdl_source/ph1p35_ddr/ddr2/src/rtl/clk/ph1p_ddrphy_pll0.v} -global_include {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/source/hdl_source/ph1p35_ddr/ddr2/src/rtl/include/ph1p_mis_define.vh}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/source/hdl_source/ph1p35_ddr/ddr2/src/rtl/clk/ph1p_ddrphy_pll1.v} -global_include {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/source/hdl_source/ph1p35_ddr/ddr2/src/rtl/include/ph1p_mis_define.vh}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/source/hdl_source/ph1p35_ddr/ddr2/src/rtl/init/ph1p_ddrphy_dram_init_ddr2.v} -global_include {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/source/hdl_source/ph1p35_ddr/ddr2/src/rtl/include/ph1p_mis_define.vh}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/source/hdl_source/ph1p35_ddr/ddr2/src/rtl/misc/ph1p_ddrphy_sync_rst_gen.v} -global_include {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/source/hdl_source/ph1p35_ddr/ddr2/src/rtl/include/ph1p_mis_define.vh}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/source/hdl_source/ph1p35_ddr/ddr2/src/rtl/misc/ph1p_ddr_fifo_dram_sync.v} -global_include {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/source/hdl_source/ph1p35_ddr/ddr2/src/rtl/include/ph1p_mis_define.vh}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/source/hdl_source/ph1p35_ddr/ddr2/src/rtl/top/ph1p_ddrmc_top.v} -global_include {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/source/hdl_source/ph1p35_ddr/ddr2/src/rtl/include/ph1p_mis_define.vh}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/source/hdl_source/ph1p35_ddr/ddr2/src/rtl/mc/alc_mc_top_all.enc.sv} -global_include {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/source/hdl_source/ph1p35_ddr/ddr2/src/rtl/include/ph1p_mis_define.vh}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/source/hdl_source/ph1p35_ddr/ddr2/src/rtl/mc/alc_phy2mc_fifo_ctrl.v} -global_include {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/source/hdl_source/ph1p35_ddr/ddr2/src/rtl/include/ph1p_mis_define.vh}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/source/hdl_source/ph1p35_ddr/ddr2/src/rtl/phy/ph1p_ddrphy_top.v} -global_include {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/source/hdl_source/ph1p35_ddr/ddr2/src/rtl/include/ph1p_mis_define.vh}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/source/hdl_source/ph1p35_ddr/ddr2/src/rtl/phy/ph1p_ddrphy_wrapper.v} -global_include {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/source/hdl_source/ph1p35_ddr/ddr2/src/rtl/include/ph1p_mis_define.vh}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/source/hdl_source/ph1p35_ddr/ddr2/src/rtl/phy/ph1p_ddrphy.v} -global_include {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/source/hdl_source/ph1p35_ddr/ddr2/src/rtl/include/ph1p_mis_define.vh}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/source/hdl_source/ph1p35_ddr/ddr2/src/rtl/phy/ph1p_ddrphy_apb_bridge.v} -global_include {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/source/hdl_source/ph1p35_ddr/ddr2/src/rtl/include/ph1p_mis_define.vh}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/source/hdl_source/ph1p35_ddr/ddr2/src/rtl/phy/ph1p_ddrphy_bankref_cfg.v} -global_include {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/source/hdl_source/ph1p35_ddr/ddr2/src/rtl/include/ph1p_mis_define.vh}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/source/hdl_source/ph1p35_ddr/ddr2/src/rtl/phy/ph1p_ddrphy_byte_wrapper.v} -global_include {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/source/hdl_source/ph1p35_ddr/ddr2/src/rtl/include/ph1p_mis_define.vh}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/source/hdl_source/ph1p35_ddr/ddr2/src/rtl/phy/ph1p_ddrphy_cmd_decode.v} -global_include {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/source/hdl_source/ph1p35_ddr/ddr2/src/rtl/include/ph1p_mis_define.vh}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/source/hdl_source/ph1p35_ddr/ddr2/src/rtl/phy/ph1p_ddrphy_cmd_execution.v} -global_include {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/source/hdl_source/ph1p35_ddr/ddr2/src/rtl/include/ph1p_mis_define.vh}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/source/hdl_source/ph1p35_ddr/ddr2/src/rtl/phy/ph1p_ddrphy_cmd_wrapper.v} -global_include {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/source/hdl_source/ph1p35_ddr/ddr2/src/rtl/include/ph1p_mis_define.vh}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/source/hdl_source/ph1p35_ddr/ddr2/src/rtl/phy/ph1p_ddrphy_dcu.v} -global_include {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/source/hdl_source/ph1p35_ddr/ddr2/src/rtl/include/ph1p_mis_define.vh}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/source/hdl_source/ph1p35_ddr/ddr2/src/rtl/phy/ph1p_ddrphy_dcu_wrapper.v} -global_include {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/source/hdl_source/ph1p35_ddr/ddr2/src/rtl/include/ph1p_mis_define.vh}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/source/hdl_source/ph1p35_ddr/ddr2/src/rtl/phy/ph1p_ddrphy_fast_init.v} -global_include {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/source/hdl_source/ph1p35_ddr/ddr2/src/rtl/include/ph1p_mis_define.vh}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/source/hdl_source/ph1p35_ddr/ddr2/src/rtl/phy/ph1p_ddrphy_fast_init_wrapper.v} -global_include {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/source/hdl_source/ph1p35_ddr/ddr2/src/rtl/include/ph1p_mis_define.vh}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/source/hdl_source/ph1p35_ddr/ddr2/src/rtl/phy/ph1p_ddrphy_init.v} -global_include {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/source/hdl_source/ph1p35_ddr/ddr2/src/rtl/include/ph1p_mis_define.vh}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/source/hdl_source/ph1p35_ddr/ddr2/src/rtl/phy/ph1p_ddrphy_mdl_cal.v} -global_include {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/source/hdl_source/ph1p35_ddr/ddr2/src/rtl/include/ph1p_mis_define.vh}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/source/hdl_source/ph1p35_ddr/ddr2/src/rtl/phy/ph1p_ddrphy_mdl_cal_wrapper.v} -global_include {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/source/hdl_source/ph1p35_ddr/ddr2/src/rtl/include/ph1p_mis_define.vh}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/source/hdl_source/ph1p35_ddr/ddr2/src/rtl/phy/ph1p_ddrphy_rphase_ctl.v} -global_include {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/source/hdl_source/ph1p35_ddr/ddr2/src/rtl/include/ph1p_mis_define.vh}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/source/hdl_source/ph1p35_ddr/ddr2/src/rtl/phy/ph1p_ddrphy_wphase_ctl.v} -global_include {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/source/hdl_source/ph1p35_ddr/ddr2/src/rtl/include/ph1p_mis_define.vh}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/source/hdl_source/ph1p35_ddr/ddr2/ddr2.v} -global_include {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/source/hdl_source/ph1p35_ddr/ddr2/src/rtl/include/ph1p_mis_define.vh}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/source/hdl_source/ph1p35_ddr/ddr2/ph1p_ddrmc_wrapper_63f4ac254419.v} -global_include {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/source/hdl_source/ph1p35_ddr/ddr2/src/rtl/include/ph1p_mis_define.vh}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/source/hdl_source/isp/demosaic_4x_2_0/blk_mem_gen_zhenghe/blk_mem_gen_zhenghe.v}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/source/hdl_source/isp/demosaic_4x_2_0/blk_mem_gen_zhenghe/RTL/ram_d32970204f32.v}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/source/hdl_source/isp/demosaic_4x_2_0/blk_mem_gen_demosaic/blk_mem_gen_demosaic.v}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/source/hdl_source/isp/demosaic_4x_2_0/blk_mem_gen_demosaic/RTL/ram_c36c2ca3b3a7.v}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/source/ip_source/divider/divider_gate.v}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/source/ip_source/PLL/RTL/include/define.v}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/source/ip_source/w128_d512_fifo/soft_fifo_al_4057d6b76aa6.v}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/source/ip_source/w128_d512_fifo/w128_d512_fifo.v}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/source/ip_source/w155_d512_fifo/soft_fifo_al_f58e8b3e1f3d.v}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/source/ip_source/w155_d512_fifo/w155_d512_fifo.v}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/ethernet/ip_source/ethernet_pll/pll.v}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/ethernet/ip_source/ethernet_pll/RTL/ph1p_phy_pll_wrapper_d2616deaaa79.v}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/ethernet/hdl_source/uiphyrst.v}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/ethernet/hdl_source/udp_pkg_buf.v}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/ethernet/hdl_source/uiudp_stack/crc32_check.v}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/ethernet/hdl_source/uiudp_stack/crc32_gen.v}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/ethernet/hdl_source/uiudp_stack/mac_cache.v}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/ethernet/hdl_source/uiudp_stack/rgmii_interface.v}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/ethernet/hdl_source/uiudp_stack/uiarp_layer.v}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/ethernet/hdl_source/uiudp_stack/uiarp_rx.v}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/ethernet/hdl_source/uiudp_stack/uiarp_tx.v}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/ethernet/hdl_source/uiudp_stack/uiicmp_pkg_ctrl.v}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/ethernet/hdl_source/uiudp_stack/uiicmp_pkg_tx.v}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/ethernet/hdl_source/uiudp_stack/uiip_arp_rx.v}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/ethernet/hdl_source/uiudp_stack/uiip_arp_tx.v}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/ethernet/hdl_source/uiudp_stack/uiip_header_checksum.v}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/ethernet/hdl_source/uiudp_stack/uiip_layer.v}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/ethernet/hdl_source/uiudp_stack/uiip_rx.v}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/ethernet/hdl_source/uiudp_stack/uiip_tx.v}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/ethernet/hdl_source/uiudp_stack/uimac_layer.v}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/ethernet/hdl_source/uiudp_stack/uimac_rx.v}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/ethernet/hdl_source/uiudp_stack/uimac_tx_frame_ctrl.v}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/ethernet/hdl_source/uiudp_stack/uimac_tx_pause_ctrl.v}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/ethernet/hdl_source/uiudp_stack/uimac_tx.v}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/ethernet/hdl_source/uiudp_stack/uiudp_layer.v}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/ethernet/hdl_source/uiudp_stack/uiudp_rx.v}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/ethernet/hdl_source/uiudp_stack/uiudp_stack.v}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/ethernet/hdl_source/uiudp_stack/uiudp_tx.v}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/rtl/camera_framed_async_fifo.sv}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/rtl/checked_media_ethernet_rx3.sv}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/rtl/frame_publish_cdc5.sv}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/rtl/local_remote_mc_arbiter2.sv}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/rtl/phy_reset20ms.sv}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/rtl/remote_media_ingress5.sv}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/rtl/reset_domain_sync.sv}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/rtl/rgb565_beat_packer.sv}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/rtl/stereo_line_cache3.sv}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/rtl/video_udp_receiver.sv}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/rtl/raw_xy1.sv}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/rtl/stereo_raw_reader1.sv}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/rtl/y5cd_tracks1.sv}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/rtl/yolo_box_overlay1.sv}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/rtl/depth_map.sv}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/rtl/range_meter.sv}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/rtl/bottle_seed.sv}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/rtl/gimbal_lite.sv}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/rtl/gimbal_mc.sv}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/rtl/vision_osd.sv}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/rtl/zoom_ctrl.sv}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/rtl/vision_core.sv}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/rtl/motion_cells.sv}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/rtl/color_cells.sv}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/rtl/blob_engine.sv}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/rtl/common_logo1.sv}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/rtl/stereo_pair_points2.sv}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/rtl/stereo_raw_memory1.sv}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/rtl/local_native_commit1.sv}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/rtl/latency_meter5.sv}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/modes/mono_keys1.sv}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/modes/mono_window2.sv}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/modes/mono_algorithms4.sv}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/modes/mono_display6.sv}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/modes/match_mul72x36_2.sv}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/modes/template_score_core2.sv}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/modes/template_search2.sv}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/control2/ethernet_control_reply1.sv}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/control2/arp_reply_lite.sv}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/rtl/camera_awb_frame_gain.sv}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/rtl/camera_fifo_handoff1.sv}
analyze -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/rtl/stereo_pair_selected1.sv}
elaborate -top eth_stereo_raw_top1
read_ip_adc -ip ddr2 -file {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/source/hdl_source/ph1p35_ddr/ddr2/src/adc/ddr2.adc}
read_adc {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/stereo.adc}
read_sdc {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/raw_signoff2.sdc}
optimize_rtl
optimize_gate -packarea local_gate.area
legalize_phy_inst
export_db local_gate.db
write_verilog local_gate_mapped.v
update_timing
report_area -io_info -file local_synth.area
report_timing_status -file local_gate.ts
report_timing_summary -file local_gate.timing
puts {LOCAL_CAMERA_RECOVERY_WHOLE_DONE}
} e]} {puts stderr $e;puts stderr $::errorInfo;exit 2}
exit 0
