cd [file dirname [info script]]
if {[catch {
import_device ph1_35p.db -package PH1P35MDG324 -speed 3
import_db {G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/place1/place_pre_reports.db}
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
export_db own_placed_input.db
# CLAUDE Z13: route parameters of the CC24 flow (same device)
set_param route effort high
set_param route multi_try_route_bad_qor_check off
set_param route post_route_opt high
route
fix_hold   ;# CLAUDE ZOOM4: post-route hold fix (z4a: HWNS -0.085 reader data -> line cache ERAM)
export_db route_builtin_hold_result.db
export_db route_raw.db
export_db hold_fixed.db
update_timing -mode final
export_db final_pre_reports.db
export_db final.db
write_verilog routed.v
report_area -io_info -file final.area
report_timing_status -file final.ts
report_timing_summary -file all_clocks.timing
report_timing -file final_timing.rpt
report_qor -step route -file final.qor
report_route_status -file route_status.rpt
report_timing_exception -file exceptions.rpt
check_timing -verbose -file health.rpt
drc_check -all -verbose
puts {MODE3_STEREO_ROUTE1_DONE}
} e]} {puts stderr $e;puts stderr $::errorInfo;exit 2}
exit 0
