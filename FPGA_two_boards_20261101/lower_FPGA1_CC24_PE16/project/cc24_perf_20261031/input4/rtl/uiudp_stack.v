// CC20: transmit-only UDP stack with mini ARP (candidate copy of the MiLianKe uiudp_stack, same module name and ports).
// User decision 2026-10-24: remove the PC -> FPGA receive path (TF card is the only model source) and keep ARP as a
// minimal "learn the peer MAC from its ARP reply" function (see mini_arp.v). Transmit path unchanged:
//   uiudp_tx -> uiip_tx (CC18 copy, ICMP inputs tied off as in the CC18 uiip_layer) -> uiip_arp_tx (unchanged)
//   -> uimac_tx (pause frames never received -> pause inputs tied off).
// Removed: uiudp_rx, uiip_rx (+ICMP), uimac_rx (+pause FIFO), uiarp_rx, mac_cache. O_R_udp_* / error outputs are 0.
// Peer contract (left FPGA-2 checked_media_ethernet_rx3 / ethernet_control_reply1): it only receives our UDP
// frames and answers ARP requests; it sends no application data to this board.
`timescale 1ns / 1ps
module uiudp_stack #
(
parameter               CRC_GEN_EN        = 1'b1,
parameter               INTER_FRAME_GAP   = 4'd12
)
(
input  wire             I_uclk,
input  wire             I_reset,
input  wire[47:0]       I_mac_local_addr,
input  wire[15:0]       I_udp_local_port,
input  wire[31:0]       I_ip_local_addr,
input  wire[15:0]       I_udp_dest_port,
input  wire[31:0]       I_ip_dest_addr,
output wire             O_W_udp_busy,
input  wire             I_W_udp_req,
input  wire             I_W_udp_valid,
input  wire[7:0]        I_W_udp_data,
input  wire[15:0]       I_W_udp_len,
output wire             O_R_udp_valid,
output wire [7:0]       O_R_udp_data,
output wire [15:0]      O_R_udp_len,
output wire [15:0]      O_R_udp_src_port,
input                   I_gmii_rclk,
input                   I_gmii_rvalid,
input [7:0]             I_gmii_rdata,
input                   I_gmii_tclk,
output wire             O_gmii_tvalid,
output wire [7:0]       O_gmii_tdata,
output wire             O_ip_rerror,
output wire             O_mac_rerror
);
assign O_R_udp_valid = 1'b0; assign O_R_udp_data = 8'd0; assign O_R_udp_len = 16'd0; assign O_R_udp_src_port = 16'd0;
assign O_ip_rerror = 1'b0; assign O_mac_rerror = 1'b0;

wire         udp_ip_treq, udp_ip_tvalid, udp_ip_tbusy;
wire [7 :0]  udp_ip_tdata;
wire [15:0]  udp_ip_tpkg_len;
uiudp_tx udp_tx_inst (
.I_udp_local_port(I_udp_local_port), .I_udp_dest_port(I_udp_dest_port), .I_reset(I_reset), .I_W_udp_clk(I_uclk),
.I_W_udp_req(I_W_udp_req), .I_W_udp_valid(I_W_udp_valid), .I_W_udp_data(I_W_udp_data), .I_W_udp_len(I_W_udp_len),
.O_W_udp_busy(O_W_udp_busy), .I_udp_ip_tbusy(udp_ip_tbusy), .O_udp_ip_treq(udp_ip_treq), .O_udp_ip_tvalid(udp_ip_tvalid),
.O_udp_ip_tdata(udp_ip_tdata), .O_udp_ip_tpkg_len(udp_ip_tpkg_len));

wire        ip_tbusy, ip_treq, ip_tvalid;
wire [7 :0] ip_tdata;
wire [31:0] ip_taddr;
uiip_tx #(.VERSION(4'h4), .IHL(4'h5), .TOS(8'h00), .ID_BASE(16'h0000), .FLAG(3'b010), .FRAGMENT_OFFSET(13'd0)) ip_tx_inst (
.I_ip_local_addr(I_ip_local_addr), .I_ip_dest_addr(I_ip_dest_addr), .I_reset(I_reset), .I_ip_clk(I_uclk),
.O_ip_udp_tbusy(udp_ip_tbusy), .I_ip_udp_treq(udp_ip_treq), .I_ip_udp_tvalid(udp_ip_tvalid), .I_ip_udp_tdata(udp_ip_tdata),
.I_ip_udp_tdata_len(udp_ip_tpkg_len), .I_ip_tbusy(ip_tbusy), .O_ip_treq(ip_treq), .O_ip_taddr(ip_taddr),
.O_ip_tvalid(ip_tvalid), .O_ip_tdata(ip_tdata),
.I_icmp_req_en(1'b0), .I_icmp_req_id(16'd0), .I_icmp_req_sq_num(16'd0), .I_icmp_req_checksum(16'd0), .I_icmp_req_ip_addr(32'd0),
.I_icmp_ping_echo_data(8'd0), .I_icmp_ping_echo_data_len(10'd0), .O_icmp_ping_echo_ren());

// mini ARP: peer MAC learned in the GMII RX clock domain (reset synchronised there)
(* async_reg = "true" *) reg [1:0] rx_rst_sync;
always @(posedge I_gmii_rclk or posedge I_reset)
    if (I_reset) rx_rst_sync <= 2'b11; else rx_rst_sync <= {rx_rst_sync[0], 1'b0};
wire [47:0] peer_mac;
wire        learn_toggle;
mini_arp_rx arp_rx_inst (.clk(I_gmii_rclk), .rst(rx_rst_sync[1]), .rvalid(I_gmii_rvalid), .rdata(I_gmii_rdata),
    .local_mac(I_mac_local_addr), .local_ip(I_ip_local_addr), .peer_ip(I_ip_dest_addr), .peer_mac(peer_mac), .learn_toggle(learn_toggle));

wire        mac_cache_ren, mac_cache_rdone, arp_treq_en, arp_tbusy, arp_treq, arp_tvalid, arp_ttype, arp_treply_done;
wire [31:0] mac_cache_rip_addr, arp_treq_ip_addr;
wire [47:0] mac_cache_rdest_addr, arp_tdest_mac_addr;
wire [7 :0] arp_tdata;
mini_arp_layer arp_layer_inst (
.I_mac_local_addr(I_mac_local_addr), .I_ip_local_addr(I_ip_local_addr), .I_arp_clk(I_uclk), .I_arp_reset(I_reset),
.I_arp_treq_en(arp_treq_en), .I_arp_tip_addr(arp_treq_ip_addr), .I_arp_tbusy(arp_tbusy), .O_arp_treq(arp_treq),
.O_arp_tvalid(arp_tvalid), .O_arp_tdata(arp_tdata), .O_arp_ttype(arp_ttype), .O_arp_tdest_mac_addr(arp_tdest_mac_addr),
.O_arp_reply_done(arp_treply_done), .I_mac_cache_ren(mac_cache_ren), .I_mac_cache_rip_addr(mac_cache_rip_addr),
.O_mac_cache_rdest_addr(mac_cache_rdest_addr), .O_mac_cache_rdone(mac_cache_rdone),
.I_peer_mac(peer_mac), .I_learn_toggle(learn_toggle));

wire         mac_tvalid, mac_tbusy;
wire [7 :0]  mac_tdata;
wire [1 :0]  mac_tdata_type;
wire [47:0]  mac_tdest_addr;
uiip_arp_tx ip_arp_tx_inst (
.I_ip_arp_clk(I_uclk), .I_ip_arp_reset(I_reset), .O_mac_cache_ren(mac_cache_ren), .O_mac_cache_rip_addr(mac_cache_rip_addr),
.I_mac_cache_rdest_addr(mac_cache_rdest_addr), .I_mac_cache_rdone(mac_cache_rdone), .O_arp_treq_en(arp_treq_en),
.O_arp_treq_ip_addr(arp_treq_ip_addr), .O_arp_tbusy(arp_tbusy), .I_arp_treq(arp_treq), .I_arp_tvalid(arp_tvalid),
.I_arp_tdata(arp_tdata), .I_arp_tdata_type(arp_ttype), .I_arp_tdest_mac_addr(arp_tdest_mac_addr), .I_arp_treply_done(arp_treply_done),
.O_ip_tbusy(ip_tbusy), .I_ip_treq(ip_treq), .I_ip_tvalid(ip_tvalid), .I_ip_tdata(ip_tdata), .I_ip_tdest_addr(ip_taddr),
.I_mac_tbusy(mac_tbusy), .O_mac_tvalid(mac_tvalid), .O_mac_tdata(mac_tdata), .O_mac_tdata_type(mac_tdata_type),
.O_mac_tdest_addr(mac_tdest_addr));

uimac_tx #(.IFG(INTER_FRAME_GAP)) mac_tx_inst (
.I_mac_local_addr(I_mac_local_addr), .I_crc32_en(CRC_GEN_EN), .I_reset(I_reset), .I_mac_tclk(I_uclk), .O_mac_tbusy(mac_tbusy),
.I_mac_tvalid(mac_tvalid), .I_mac_tdata(mac_tdata), .I_mac_tdata_type(mac_tdata_type), .I_mac_tdest_addr(mac_tdest_addr),
.I_mac_pause_en(1'b0), .I_mac_pause_time(22'd0), .I_mac_pause_addr(48'd0),
.I_gmii_tclk(I_gmii_tclk), .O_gmii_tvalid(O_gmii_tvalid), .O_gmii_tdata(O_gmii_tdata));
endmodule
