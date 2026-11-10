create_clock -name {sys_clk_50m} -period 20.000 -waveform {0.000 10.000} [get_ports {I_sys_clk}]
create_clock -name {mipi_rx_ck_pad} -period 2.222 -waveform {0.000 1.111} [get_nets {IO_rx_clk_pad_p}]

derive_clocks

rename_clock -name {pll_clk_100m} [get_clocks {u_PLL/ph1p_phy_pll_wrapper_25a56e5ce2f9_Inst/u_PH1P_PHY_PLL.clkc[0]}]
rename_clock -name {pll_clk_24m} [get_clocks {u_PLL/ph1p_phy_pll_wrapper_25a56e5ce2f9_Inst/u_PH1P_PHY_PLL.clkc[1]}]
# HDMI transmitter is absent: clk5 has no load and is legitimately pruned.

rename_clock -name {MIPI_RX_BYTE_CLK} [get_clocks {u_mipi_dphy_rx_ph1p_mipiio_wrapper/u_ph1p_mipiio_rx_wrapper/u_PH1P_LOGIC_DPHY_MIPI_RX.o_fabric_div4_8_clk}]


# One final grouping below uses actual derived DDR clocks. The reference's
# nonexistent ddr_clk/usr_clk and pruned HDMI_SERIAL_CLK made entire group
# commands fail; no relaxed periods/IO delays or new functional false paths.

# Ethernet-A is copied from the PH1P official RGMII UDP example.  C4 remains
# the board's 50 MHz input clock; only the Ethernet PLL produces 125 MHz.
rename_clock -name {ETH_GMII_TX_CLK} [get_clocks {u_eth_pll/ph1p_phy_pll_wrapper_d2616deaaa79_Inst/u_PH1P_PHY_PLL.clkc[0]}]
rename_clock -name {ETH_PHY_25M_CLK} [get_clocks {u_eth_pll/ph1p_phy_pll_wrapper_d2616deaaa79_Inst/u_PH1P_PHY_PLL.clkc[2]}]

create_clock -name {RGMII_RXC} -period 8.000 -waveform {0.000 4.000} [get_ports {I_a_rgmii_rxc}]
set_input_delay -clock [get_clocks {RGMII_RXC}] -max 2.500 [get_ports {{I_a_rgmii_rxd[*]} I_a_rgmii_rx_ctl}]
set_input_delay -clock [get_clocks {RGMII_RXC}] -min 1.500 [get_ports {{I_a_rgmii_rxd[*]} I_a_rgmii_rx_ctl}]
set_input_delay -clock [get_clocks {RGMII_RXC}] -max -clock_fall -add_delay 2.500 [get_ports {{I_a_rgmii_rxd[*]} I_a_rgmii_rx_ctl}]
set_input_delay -clock [get_clocks {RGMII_RXC}] -min -clock_fall -add_delay 1.500 [get_ports {{I_a_rgmii_rxd[*]} I_a_rgmii_rx_ctl}]

create_generated_clock -name {RGMII_TXC} -source [get_pins {u_eth_pll/ph1p_phy_pll_wrapper_d2616deaaa79_Inst/u_PH1P_PHY_PLL.clkc[0]}] -master_clock {ETH_GMII_TX_CLK} -multiply_by 1.000 -phase 0.000 [get_ports {O_a_rgmii_txc}]
set_output_delay -clock [get_clocks {RGMII_TXC}] -max 2.800 [get_ports {O_a_rgmii_tx_ctl {O_a_rgmii_txd[*]}}]
set_output_delay -clock [get_clocks {RGMII_TXC}] -min 1.200 [get_ports {O_a_rgmii_tx_ctl {O_a_rgmii_txd[*]}}]
set_output_delay -clock [get_clocks {RGMII_TXC}] -clock_fall -max -add_delay 2.800 [get_ports {O_a_rgmii_tx_ctl {O_a_rgmii_txd[*]}}]
set_output_delay -clock [get_clocks {RGMII_TXC}] -clock_fall -min -add_delay 1.200 [get_ports {O_a_rgmii_tx_ctl {O_a_rgmii_txd[*]}}]

set_false_path -rise_from [get_clocks {ETH_GMII_TX_CLK}] -rise_to [get_clocks {RGMII_TXC}] -setup
set_false_path -fall_from [get_clocks {ETH_GMII_TX_CLK}] -fall_to [get_clocks {RGMII_TXC}] -setup
set_false_path -rise_from [get_clocks {ETH_GMII_TX_CLK}] -fall_to [get_clocks {RGMII_TXC}] -hold
set_false_path -fall_from [get_clocks {ETH_GMII_TX_CLK}] -rise_to [get_clocks {RGMII_TXC}] -hold

# Restore intended independent-domain constraints with nonempty actual names.
# Camera packetizer now synchronizes enable separately in video and UDP domains.
# DDR IP/FIFOs and MIPI/video/DDR boundaries retain reference CDC architecture.
set_clock_groups -asynchronous \
    -group [get_clocks {RGMII_RXC u_rgmii_interface/u_rgmii_rx_lclk.clkout}] \
    -group [get_clocks {ETH_GMII_TX_CLK ETH_PHY_25M_CLK RGMII_TXC}] \
    -group [get_clocks {mipi_rx_ck_pad MIPI_RX_BYTE_CLK u_mipi_dphy_rx_ph1p_mipiio_wrapper/u_ph1p_mipiio_rx_wrapper/u_PH1P_LOGIC_DPHY_MIPI_RX.tif_c16_in u_mipi_dphy_rx_ph1p_mipiio_wrapper/u_ph1p_mipiio_rx_wrapper/u_PH1P_LOGIC_DPHY_MIPI_RX.io_clk_pad_p}] \
    -group [get_clocks {sys_clk_50m pll_clk_100m pll_clk_24m}] \
    -group [get_clocks {u_ph1p35_324_ddr_wrapper/u_ddr2/ph1p_ddrmc_wrapper/u_ddr_phy/u_ddrphy_top/u_ddrphy_clk/u_pll/u_pll_inst.clkc[0] u_ph1p35_324_ddr_wrapper/u_ddr2/ph1p_ddrmc_wrapper/u_ddr_phy/u_ddrphy_top/u_ddrphy_clk/u_pll/u_pll_inst.clkc[1] u_ph1p35_324_ddr_wrapper/u_ddr2/ph1p_ddrmc_wrapper/u_ddr_phy/u_ddrphy_top/u_ddrphy_clk/u_pll/u_pll_inst.clkc[2] u_ph1p35_324_ddr_wrapper/u_ddr2/ph1p_ddrmc_wrapper/u_ddr_phy/u_ddrphy_top/u_ddrphy_clk/u_pll/u_pll_inst.clkc[3]}]
