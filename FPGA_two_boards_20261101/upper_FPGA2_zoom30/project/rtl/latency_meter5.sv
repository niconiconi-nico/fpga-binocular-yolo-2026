// CLAUDE Z28C MONITOR (2026-11-01): area-reduced latency_meter4 (z28b), same display items.
//   Time base: t = BCD 0.1 ms timer 0000..9999, i.e. it wraps exactly every 1 s; the wrap is the statistics window.
//   Capture: BCD time stamp per camera frame slot; DDR side returns the slot of the bank the reader selects for each display
//   frame; latency = t - stamp (BCD, mod 1 s). LAT = mean of 10 display frames, all in BCD: acc starts at 5 (rounding),
//   mean = (acc + sum) / 10 = the sum without its last digit (no binary -> BCD converter). ok = mean < 100.0 ms.
//   CAP / LAG latched at the selection that closes the group; DISP = CAP - LAG (combinational, no register).
//   Per 1 s window (BCD): show_fps = display frames showing a NEW camera frame (slot differs from the previous selection,
//   repeats not counted), udp_fps = complete received UDP video frames, mbps = received video payload in 0.1 Mbit/s
//   (net_rate_meter2 toggles, see there for the byte definition).
module latency_meter5 #(parameter integer TICK=7500, G=10)(       // pixel clocks per 0.1 ms (75 MHz), frames per mean
    input wire cam_clk, cam_rst_n, cam_sof,
    input wire clk, rst_n,
    output reg [1:0] sof_g,
    input wire sel_tg, input wire [1:0] sel_idx,
    input wire unit_tg, frame_tg,
    output reg ok, output reg [11:0] lat_bcd, output reg [15:0] cap_bcd, output wire [15:0] dsp_bcd, output reg [1:0] lag,
    output reg [7:0] show_fps, udp_fps, output reg [15:0] mbps
);
    reg ct;
    always @(posedge cam_clk or negedge cam_rst_n) if(!cam_rst_n) ct<=0; else if(cam_sof) ct<=~ct;
    (* async_reg="true" *) reg c1, c2; (* async_reg="true" *) reg s1, s2; (* async_reg="true" *) reg u1, u2; (* async_reg="true" *) reg f1, f2;
    reg c3, s3, u3, f3;
    reg [12:0] pre; reg [15:0] t; reg [1:0] n, pidx, lastp; reg [15:0] ts [0:3]; reg [15:0] fc;
    reg [3:0] mc; reg [19:0] acc; reg go; reg [7:0] sf, nf; reg [15:0] nb;
    wire sof = c2 ^ c3, sel = s2 ^ s3, unit = u2 ^ u3, fdone = f2 ^ f3;
    wire tick = pre==TICK-1, sec = tick && t==16'h9999;
    wire [1:0] n1 = n + 2'd1, dn = n - pidx;
    wire nfr = go && pidx!=lastp;                                     // new camera frame on screen
    function [15:0] binc(input [15:0] v);                     // BCD + 1, 9999 -> 0000
        reg c; integer k;
        begin c = 1'b1; for(k=0;k<4;k=k+1) begin binc[4*k+:4] = !c ? v[4*k+:4] : (v[4*k+:4]==4'd9) ? 4'd0 : v[4*k+:4] + 4'd1; c = c && v[4*k+:4]==4'd9; end end
    endfunction
    function [15:0] bsub(input [15:0] v, input [1:0] d);      // BCD - d (0..3), mod 10000
        reg b; integer k;
        begin
            b = v[3:0] < {2'd0, d}; bsub[3:0] = b ? v[3:0] + 4'd10 - {2'd0, d} : v[3:0] - {2'd0, d};
            for(k=1;k<4;k=k+1) begin bsub[4*k+:4] = !b ? v[4*k+:4] : (v[4*k+:4]==4'd0) ? 4'd9 : v[4*k+:4] - 4'd1; b = b && v[4*k+:4]==4'd0; end
        end
    endfunction
    function [15:0] bdiff(input [15:0] a, input [15:0] b);    // BCD a - b, mod 10000
        reg w; reg [4:0] x; integer k;
        begin w = 1'b0; for(k=0;k<4;k=k+1) begin x = {1'b0, a[4*k+:4]} - {1'b0, b[4*k+:4]} - {4'd0, w}; w = x[4]; bdiff[4*k+:4] = w ? x[3:0] + 4'd10 : x[3:0]; end end
    endfunction
    function [19:0] badd(input [19:0] a, input [15:0] b);     // BCD a + b (5 + 4 digits)
        reg c; reg [4:0] x; integer k;
        begin c = 1'b0; for(k=0;k<5;k=k+1) begin x = {1'b0, a[4*k+:4]} + {1'b0, (k<4) ? b[4*k+:4] : 4'd0} + {4'd0, c}; c = x > 5'd9; badd[4*k+:4] = c ? x[3:0] + 4'd6 : x[3:0]; end end
    endfunction
    function [7:0] binc2(input [7:0] v);                      // 2-digit BCD + 1, saturating at 99
        binc2 = (v==8'h99) ? v : (v[3:0]==4'd9) ? {v[7:4] + 4'd1, 4'd0} : {v[7:4], v[3:0] + 4'd1};
    endfunction
    wire [15:0] lat = bdiff(t, ts[pidx]);
    wire [19:0] fin = badd(acc, lat);
    assign dsp_bcd = bsub(cap_bcd, lag);
    always @(posedge clk) if(sof) ts[n1]<=t;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin c1<=0; c2<=0; c3<=0; s1<=0; s2<=0; s3<=0; u1<=0; u2<=0; u3<=0; f1<=0; f2<=0; f3<=0; pre<=0; t<=0; n<=0; sof_g<=0;
                         pidx<=0; lastp<=0; fc<=0; mc<=0; acc<=20'h5; go<=0; ok<=0; sf<=0; nf<=0; nb<=0; end
        else begin
            c1<=ct; c2<=c1; c3<=c2; s1<=sel_tg; s2<=s1; s3<=s2; u1<=unit_tg; u2<=u1; u3<=u2; f1<=frame_tg; f2<=f1; f3<=f2;
            if(tick) begin pre<=0; t<=binc(t); end else pre<=pre+13'd1;
            if(sof) begin n<=n1; sof_g<={n1[1], n1[1]^n1[0]}; fc<=binc(fc); end
            if(sel) pidx<=sel_idx;
            go<=sel;                                                  // one clock later: pidx belongs to this selection
            if(go) begin
                lastp<=pidx;
                if(mc==G-1) begin mc<=0; acc<=20'h5; ok<=fin[19:16]==4'd0; end
                else begin mc<=mc+4'd1; acc<=fin; end
            end
            if(sec) begin sf<={7'd0, nfr}; nf<={7'd0, fdone}; nb<={15'd0, unit}; end
            else begin if(nfr) sf<=binc2(sf); if(fdone) nf<=binc2(nf); if(unit && nb!=16'h9999) nb<=binc(nb); end
        end
    end
    // display values: no reset (shown only after the first update; ok gates LAT)
    always @(posedge clk) begin
        if(go && mc==G-1) begin lat_bcd<=fin[15:4]; cap_bcd<=fc; lag<=dn; end
        if(sec) begin show_fps<=sf; udp_fps<=nf; mbps<=nb; end
    end
endmodule

// CLAUDE Z28B MONITOR, rx clock: received UDP video events for latency_meter4/5 (counting / 1 s window in the pixel clock).
//   unit_tg toggles once per 6250 accepted RGB565 pixels = 12500 video payload bytes = 0.1 Mbit. Counted bytes: pixel bytes of
//   VIDEO UDP datagrams that passed Ethernet FCS / MAC / IPv4 / UDP checks (checked_media_ethernet_rx3) and the video
//   header / offset / order checks of video_udp_receiver, at the write into the frame-memory path (mem_valid && mem_ready);
//   not counted: Ethernet / IP / UDP / video headers, FCS, YOLO result datagrams, rejected or dropped packets.
//   frame_tg toggles once per complete received video frame (every packet accepted and drained to DDR, frame_complete).
//   Toggle rates: <= 1 per 6250 rx clocks (50 us) and <= 1 per frame, far below the 2-FF synchronizer rate limit.
module net_rate_meter2(
    input wire clk, rst, px, frame,
    output reg unit_tg, frame_tg
);
    reg [12:0] pre;
    always @(posedge clk or posedge rst) begin
        if(rst) begin pre<=0; unit_tg<=0; frame_tg<=0; end
        else begin
            if(px) begin pre <= (pre==13'd6249) ? 13'd0 : pre + 13'd1; if(pre==13'd6249) unit_tg<=~unit_tg; end
            if(frame) frame_tg<=~frame_tg;
        end
    end
endmodule
