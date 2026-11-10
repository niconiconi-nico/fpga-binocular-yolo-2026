// One GMII RX clock domain. Eight ordered UDP-payload-only packet banks.
// Long668B VIDEO drain followed by minimum legal short UDP frames can hold up
// to seven packets before the head completes. Eight banks cover that bounded
// line-rate burst with ready=1; real backpressure can still overrun and counts.
// cross-domain error wires. Input includes preamble/SFD and FCS, as emitted by
// the reference RGMII decoder. No VLAN, IPv4 options or fragments in this v1.
// Existing TX: IPv4 UDP src4 -> dst6003, <8I video header, BE RGB565.
// A busy packet bank drops a datagram, never overwrites queued/read data.
// CLAUDE TRACK47_NR (2026-10-25): the payload queue is read synchronously (ERAM instead of 712 distributed-RAM LUTs) and
// every udp_* output is registered: the output stream is the previous one delayed by exactly one clock. This requires
// udp_ready=1 (the only instance, remote_media_ingress5, ties it to 1; ready acknowledges the pre-register beat).
module checked_media_ethernet_rx3 #(
    parameter [47:0] LOCAL_MAC=48'h020000240002,
    parameter [47:0] PEER_MAC=48'h020000240001,
    parameter [31:0] LOCAL_IP=32'hc0a8f002, PEER_IP=32'hc0a8f001,
    parameter [15:0] LOCAL_PORT=16'd6003, PEER_PORT=16'd4,
    parameter [15:0] RESULT_PORT=16'd6004,
    parameter integer MAX_PAYLOAD=668
)(
    input wire clk, rst,
    input wire gmii_valid, gmii_error,
    input wire [7:0] gmii_data,
    output wire udp_valid, udp_start, udp_last,
    output wire [7:0] udp_data,
    output wire [15:0] udp_length,
    output wire [1:0] udp_kind, //1 VIDEO,2 actual Y5CD,3 future Y5R1,0 ignored
    output wire [15:0] udp_destination,
    input wire udp_ready,
    output reg rejected,
    output reg [31:0] good_packets, bad_packets, overrun_packets
);
    (* ram_style="bram" *) reg [7:0] packet[0:8191];
    reg [7:0] packet_q;
    reg [7:0] queued;reg [1:0] kinds[0:7];reg [15:0] destinations[0:7];reg [31:0] app_magic;
    reg [15:0] lengths[0:7];
    reg [2:0] wb,rb;
    integer bank;
    reg receiving, discard, reading, rx_fault;
    function automatic [2:0] next_bank(input [2:0] bank);
        next_bank=bank+1'b1;
    endfunction
    reg [3:0] preamble;
    reg [11:0] count;
    reg [10:0] out_index;
    reg [31:0] crc;
    reg [47:0] dst_mac, src_mac;
    reg [31:0] src_ip,dst_ip;
    reg [15:0] ethertype, ip_length, fragment, src_port,dst_port,udp_len,udp_check;
    reg [7:0] ip_version,protocol,hi;
    reg [31:0] ip_sum, udp_sum;
    function automatic [31:0] crc_step(input [31:0] old_crc,input [7:0] b);
        reg [31:0] c; integer j;
        begin c=old_crc^{24'd0,b};
            for(j=0;j<8;j=j+1) c=c[0] ? (c>>1)^32'hedb88320 : c>>1;
            crc_step=c;
        end
    endfunction
    function automatic [15:0] fold(input [31:0] s);
        reg [16:0] a;
        begin a={1'b0,s[15:0]}+s[31:16]; fold=a[15:0]+a[16]; end
    endfunction
    // valid_packet below still requires src_ip==PEER_IP && dst_ip==LOCAL_IP.
    // Thus only that guarded branch may authorize a packet; invalid IPs still
    // reject regardless of checksum. Same32bit addition/modulo arithmetic.
    localparam [31:0] PEER_PSEUDO_BASE={16'd0,PEER_IP[31:16]}+
        {16'd0,PEER_IP[15:0]}+{16'd0,LOCAL_IP[31:16]}+
        {16'd0,LOCAL_IP[15:0]}+32'h00000011;
    wire [15:0] physical_length=(ip_length+18<64) ? 16'd64 : ip_length+18;
    // Capture this unchanged EOP predicate independently of the UDP fold.
    // Input6 routed udp_len -> two32bitadds -> fold -> metadata CE in8.219ns.
    // Three bounded RX edges before publication break that actual chain. The
    // minimum next SFD is seven preamble bytes plus SFD after an EOP gap, so wb
    // is committed before another packet can choose/write a bank. No new clock.
    wire valid_packet_base=!discard && !rx_fault && count==physical_length &&
        count<=1518 && ethertype==16'h0800 && dst_mac==LOCAL_MAC && src_mac==PEER_MAC &&
        ip_version==8'h45 && protocol==8'h11 && (fragment & 16'hbfff)==0 &&
        src_ip==PEER_IP && dst_ip==LOCAL_IP && fold(ip_sum)==16'hffff &&
        src_port==PEER_PORT && (dst_port==LOCAL_PORT || dst_port==RESULT_PORT) && udp_len>=12 &&
        udp_len<=MAX_PAYLOAD+8 && ip_length==udp_len+20 &&
        crc==32'hdebb20e3;
    reg [2:0] check_pipe;
    reg check_base_ok,check_udp_zero,check_checksum;
    reg [31:0] check_sum_partial,check_sum_total;
    reg [15:0] check_udp_len,check_length,check_destination;
    reg [1:0] check_kind;
    reg [2:0] check_bank;
    wire cur_last=reading && out_index==lengths[rb]-1;
    reg o_valid,o_start,o_last; reg [1:0] o_kind; reg [15:0] o_destination,o_length;
    assign udp_kind=o_kind;
    assign udp_destination=o_destination;
    assign udp_valid=o_valid;
    assign udp_start=o_start;
    assign udp_last=o_last;
    assign udp_data=packet_q;
    assign udp_length=o_length;
    wire [11:0] payload_index=count-12'd42;
    wire packet_we=receiving && gmii_valid && count<2048 && !discard && count>=42 && count<42+MAX_PAYLOAD;
    always @(posedge clk) begin
        if(packet_we) packet[{wb,payload_index[9:0]}]<=gmii_data;
        packet_q<=packet[{rb,out_index[9:0]}];
    end
    always @(posedge clk or posedge rst) begin
        if(rst) begin o_valid<=0;o_start<=0;o_last<=0;o_kind<=0;o_destination<=0;o_length<=0; end
        else begin
            o_valid<=reading; o_start<=reading && out_index==0; o_last<=cur_last;
            o_kind<=kinds[rb]; o_destination<=destinations[rb]; o_length<=lengths[rb];
        end
    end
    always @(posedge clk or posedge rst) begin
        if(rst) begin
            queued<=0;for(bank=0;bank<8;bank=bank+1)begin lengths[bank]<=0;kinds[bank]<=0;destinations[bank]<=0;end
            app_magic<=0; receiving<=0; discard<=0;
            wb<=0; rb<=0; reading<=0; rx_fault<=0; preamble<=0; count<=0;
            out_index<=0; crc<=32'hffffffff; dst_mac<=0;src_mac<=0;
            src_ip<=0;dst_ip<=0;ethertype<=0;ip_length<=0;fragment<=0;
            src_port<=0;dst_port<=0;udp_len<=0;udp_check<=0;
            ip_version<=0;protocol<=0;hi<=0;ip_sum<=0;udp_sum<=0;app_magic<=0;
            rejected<=0;good_packets<=0;bad_packets<=0;overrun_packets<=0;
            check_pipe<=0;check_base_ok<=0;check_udp_zero<=0;check_checksum<=0;
            check_sum_partial<=0;check_sum_total<=0;check_udp_len<=0;
            check_length<=0;check_destination<=0;check_kind<=0;check_bank<=0;
        end else begin
            rejected<=0;
            check_pipe<={check_pipe[1:0],1'b0};
            if(check_pipe[0])check_sum_total<=check_sum_partial+check_udp_len;
            if(check_pipe[1])check_checksum<=check_udp_zero||fold(check_sum_total)==16'hffff;
            if(check_pipe[2])begin
                if(check_base_ok&&check_checksum)begin
                    queued[check_bank]<=1;lengths[check_bank]<=check_length;
                    destinations[check_bank]<=check_destination;kinds[check_bank]<=check_kind;
                    wb<=next_bank(wb);good_packets<=good_packets+1'b1;
                end else begin rejected<=1;bad_packets<=bad_packets+1'b1;end
            end
            if(!reading && queued[rb]) begin
                out_index<=0; reading<=1;
            end else if(reading && udp_ready) begin
                if(cur_last) begin queued[rb]<=0; reading<=0; rb<=next_bank(rb); end
                else out_index<=out_index+1'b1;
            end
            if(!receiving) begin
                if(!gmii_valid) preamble<=0;
                else if(gmii_data==8'h55 && preamble<7) preamble<=preamble+1'b1;
                else if(gmii_data==8'hd5 && preamble==7) begin
                    receiving<=1; preamble<=0; count<=0; crc<=32'hffffffff;
                    discard<=queued[wb];rx_fault<=gmii_error;
                    dst_mac<=0;src_mac<=0;src_ip<=0;dst_ip<=0;
                    ethertype<=0;ip_length<=0;fragment<=0;src_port<=0;dst_port<=0;
                    udp_len<=0;udp_check<=0;ip_version<=0;protocol<=0;
                    hi<=0;ip_sum<=0;udp_sum<=0;app_magic<=0;
                    if(queued[wb]) overrun_packets<=overrun_packets+1'b1;
                end else preamble<=0;
            end else if(gmii_valid) begin
                rx_fault<=rx_fault|gmii_error;
                if(count<2048) begin
                    count<=count+1'b1;
                end else discard<=1;
                crc<=crc_step(crc,gmii_data);
                if(count>=42&&count<46)app_magic[(count-42)*8+:8]<=gmii_data;
                if(count<6) dst_mac<={dst_mac[39:0],gmii_data};
                if(count>=6 && count<12) src_mac<={src_mac[39:0],gmii_data};
                if(count==12 || count==13) ethertype<={ethertype[7:0],gmii_data};
                if(count==14) ip_version<=gmii_data;
                if(count==16 || count==17) ip_length<={ip_length[7:0],gmii_data};
                if(count==20 || count==21) fragment<={fragment[7:0],gmii_data};
                if(count==23) protocol<=gmii_data;
                if(count>=26 && count<=29) src_ip<={src_ip[23:0],gmii_data};
                if(count>=30 && count<=33) dst_ip<={dst_ip[23:0],gmii_data};
                if(count==34 || count==35) src_port<={src_port[7:0],gmii_data};
                if(count==36 || count==37) dst_port<={dst_port[7:0],gmii_data};
                if(count==38 || count==39) udp_len<={udp_len[7:0],gmii_data};
                if(count==40 || count==41) udp_check<={udp_check[7:0],gmii_data};
                if(!count[0]) hi<=gmii_data;
                if(count>=14 && count<34 && count[0]) ip_sum<=ip_sum+{hi,gmii_data};
                if(count>=34 && (count<40 || count<34+udp_len)) begin
                    if(count[0]) udp_sum<=udp_sum+{hi,gmii_data};
                    else if(count==33+udp_len) udp_sum<=udp_sum+{gmii_data,8'd0};
                end
            end else begin
                receiving<=0;
                check_pipe[0]<=1;check_base_ok<=valid_packet_base;
                check_udp_zero<=udp_check==0;check_sum_partial<=udp_sum+PEER_PSEUDO_BASE;
                check_udp_len<=udp_len;check_length<=udp_len-8;
                check_destination<=dst_port;check_bank<=wb;
                check_kind<=dst_port==LOCAL_PORT&&app_magic==32'haa0055ff ? 2'd1 : 
                       dst_port==LOCAL_PORT&&app_magic==32'h44433559 ? 2'd2 : 
                       dst_port==RESULT_PORT&&app_magic==32'h31523559 ? 2'd3 : 2'd0;
            end
        end
    end
endmodule
