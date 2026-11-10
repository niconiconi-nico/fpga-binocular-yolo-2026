// CC20 mini ARP (replaces the uiarp_layer + 4-entry mac_cache + uiarp_rx and the whole UDP/IP/MAC receive path).
// The board only TRANSMITS application data (video / Y5CD / Y5AE to the peer). The peer (left FPGA-2
// ethernet_control_reply1, or a PC) sends nothing to this board except ARP replies, so the only received
// information needed is the peer MAC:
//   mini_arp_rx  (GMII RX clock): accepts one frame type only, an ARP REPLY addressed to us
//                 (dst MAC = local or broadcast, ethertype 0806, HTYPE 1 / PTYPE 0800 / HLEN 6 / PLEN 4 / OPER 2,
//                 sender MAC = Ethernet source MAC, sender IP = peer IP, target IP = local IP, >= 64 bytes, good FCS),
//                 latches the sender MAC and toggles learn_toggle.
//   mini_arp_layer (user clock): same ports as uiarp_layer towards uiip_arp_tx (unchanged). One-entry cache:
//                 lookup answers in one clock with the learned MAC, or 0 (unknown) -> uiip_arp_tx sends a
//                 broadcast ARP request through the original uiarp_tx and waits / retries exactly as before.
//                 This board does not answer ARP requests (nobody needs this board's MAC).
// The GMII stream includes the preamble and SFD (0xD5) and the FCS (same as the reference uimac_rx input).
module mini_arp_rx (
    input  wire        clk, rst,
    input  wire        rvalid,
    input  wire [7:0]  rdata,
    input  wire [47:0] local_mac,
    input  wire [31:0] local_ip, peer_ip,
    output reg  [47:0] peer_mac,
    output reg         learn_toggle
);
    reg        infrm, prev_valid, ok;
    reg  [6:0] idx;              // byte index after the SFD, saturates at 127
    reg [47:0] src;
    reg [31:0] crc;
    reg        bcast, ucast;     // dst MAC == broadcast / == local, built byte by byte
    function [31:0] crc_step(input [31:0] c0, input [7:0] b);
        reg [31:0] c; integer k;
        begin c = c0 ^ {24'd0, b};
            for (k = 0; k < 8; k = k + 1) c = c[0] ? (c >> 1) ^ 32'hedb88320 : c >> 1;
            crc_step = c;
        end
    endfunction
    function [7:0] byte_of48(input [47:0] v, input [2:0] i);   // i = 0 -> most significant byte
        byte_of48 = v >> (8 * (5 - i));
    endfunction
    function [7:0] byte_of32(input [31:0] v, input [1:0] i);
        byte_of32 = v >> (8 * (3 - i));
    endfunction
    function [7:0] fixed_hdr(input [6:0] i);                   // bytes 12..21: ethertype + ARP fixed fields, OPER = reply
        case (i)
            7'd12: fixed_hdr = 8'h08; 7'd13: fixed_hdr = 8'h06; 7'd14: fixed_hdr = 8'h00; 7'd15: fixed_hdr = 8'h01;
            7'd16: fixed_hdr = 8'h08; 7'd17: fixed_hdr = 8'h00; 7'd18: fixed_hdr = 8'h06; 7'd19: fixed_hdr = 8'h04;
            7'd20: fixed_hdr = 8'h00; default: fixed_hdr = 8'h02;
        endcase
    endfunction
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            infrm <= 1'b0; prev_valid <= 1'b0; ok <= 1'b0; idx <= 7'd0; src <= 48'd0; crc <= 32'hffffffff;
            bcast <= 1'b0; ucast <= 1'b0; peer_mac <= 48'd0; learn_toggle <= 1'b0;
        end else begin
            prev_valid <= rvalid;
            if (rvalid) begin
                if (!infrm) begin
                    if (rdata == 8'hd5) begin
                        infrm <= 1'b1; ok <= 1'b1; idx <= 7'd0; crc <= 32'hffffffff; bcast <= 1'b1; ucast <= 1'b1;
                    end
                end else begin
                    crc <= crc_step(crc, rdata);
                    if (idx != 7'd127) idx <= idx + 1'b1;
                    if (idx < 7'd6) begin
                        if (rdata != 8'hff) bcast <= 1'b0;
                        if (rdata != byte_of48(local_mac, idx[2:0])) ucast <= 1'b0;
                    end else if (idx < 7'd12) src <= {src[39:0], rdata};
                    else if (idx < 7'd22) begin if (rdata != fixed_hdr(idx)) ok <= 1'b0; end
                    else if (idx < 7'd28) begin if (rdata != byte_of48(src, idx - 7'd22)) ok <= 1'b0; end
                    else if (idx < 7'd32) begin if (rdata != byte_of32(peer_ip, idx - 7'd28)) ok <= 1'b0; end
                    else if (idx >= 7'd38 && idx < 7'd42) begin if (rdata != byte_of32(local_ip, idx - 7'd38)) ok <= 1'b0; end
                end
            end else if (prev_valid) begin             // end of frame
                if (infrm && ok && (bcast || ucast) && idx >= 7'd64 && crc == 32'hdebb20e3) begin
                    peer_mac <= src; learn_toggle <= ~learn_toggle;
                end
                infrm <= 1'b0;
            end
        end
    end
endmodule

module mini_arp_layer (
    input  wire [47:0] I_mac_local_addr,
    input  wire [31:0] I_ip_local_addr,
    input  wire        I_arp_clk,
    input  wire        I_arp_reset,
    input  wire        I_arp_treq_en,
    input  wire [31:0] I_arp_tip_addr,
    input  wire        I_arp_tbusy,
    output wire        O_arp_treq,
    output wire        O_arp_tvalid,
    output wire [7:0]  O_arp_tdata,
    output wire        O_arp_ttype,
    output wire [47:0] O_arp_tdest_mac_addr,
    output reg         O_arp_reply_done,
    input  wire        I_mac_cache_ren,
    input  wire [31:0] I_mac_cache_rip_addr,
    output reg  [47:0] O_mac_cache_rdest_addr,
    output reg         O_mac_cache_rdone,
    input  wire [47:0] I_peer_mac,          // from mini_arp_rx (GMII RX clock), stable when learn toggles
    input  wire        I_learn_toggle
);
    uiarp_tx arp_tx (
        .I_mac_local_addr(I_mac_local_addr), .I_ip_local_addr(I_ip_local_addr), .I_arp_clk(I_arp_clk), .I_arp_reset(I_arp_reset),
        .I_arp_treq_en(I_arp_treq_en), .I_arp_tip_addr(I_arp_tip_addr), .I_arp_tbusy(I_arp_tbusy),
        .O_arp_treq(O_arp_treq), .O_arp_tvalid(O_arp_tvalid), .O_arp_tdata(O_arp_tdata), .O_arp_ttype(O_arp_ttype),
        .O_arp_tdest_mac_addr(O_arp_tdest_mac_addr),
        .I_arp_rreply_en(1'b0), .I_arp_rreply_ip_addr(32'd0), .I_arp_rreply_mac_addr(48'd0));
    (* async_reg = "true" *) reg [2:0] lt;   // learn toggle synchroniser; I_peer_mac is held stable for a whole frame
    reg [47:0] mac;
    always @(posedge I_arp_clk or posedge I_arp_reset) begin
        if (I_arp_reset) begin
            lt <= 3'd0; mac <= 48'd0; O_arp_reply_done <= 1'b0; O_mac_cache_rdest_addr <= 48'd0; O_mac_cache_rdone <= 1'b0;
        end else begin
            lt <= {lt[1:0], I_learn_toggle};
            O_arp_reply_done <= lt[2] ^ lt[1];
            if (lt[2] ^ lt[1]) mac <= I_peer_mac;
            O_mac_cache_rdone <= I_mac_cache_ren;          // one destination IP only (the peer)
            if (I_mac_cache_ren) O_mac_cache_rdest_addr <= mac;
        end
    end
endmodule
