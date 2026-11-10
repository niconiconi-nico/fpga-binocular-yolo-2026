// CLAUDE DEPTH v2 (2026-10-26): real-time stereo depth map (mode 47 DEPTH), semi-global matching on the upper board.
// Method after zhengdt11/fpga-sgbm-stereo-vision (census transform, Hamming cost, SGM path aggregation, min search), here
// serial in d (one disparity per clock) to fit the PH1P35 (that design computes 108 disparities in parallel on a ZCU208).
// Images: 160x90 luma, each value the mean of an 8x8 block of the 1280x720 views (bin row r = rows 8r..8r+7).
//   left  (camera clock): colour-stage output stream (4 px per beat, pixel 0 at [95:72]); bin = 2 beats x 8 lines
//   right (rx clock)    : received RGB565 pixels (address y*1280 + x); right row y is left row y + 6 (calibration DYB = -6),
//                         so the right image is binned on the left row grid
//   Both captured from one frame each after an arm toggle and held while the depth is computed (16K x 8 ERAM each).
// Per output row y = 3..87:
//   census pass : 5x5 census (24 bits, neighbour < centre) of row y for both images (5 reads per column) -> Lc / Rc
//   main pass   : per x = 0..159, d = 0..ND-1 (right x = x - d, 8 full px per step; d 47 ~ 0.33 m, 13 ~ 1 m, 3 ~ 4.5 m)
//                 C = popcount(Lc[x] ^ Rc[x-d]) (24 when x-d < 0), four causal SGM paths r (left, top-left, top, top-right):
//                 Lr(p,d) = C + min(Lr(p-r,d), Lr(p-r,d+-1) + P1, minLr(p-r) + P2) - minLr(p-r)   (<= 24 + P2, 6 bits)
//                 S = sum of the paths; winner d, uniqueness (second best outside d+-1 >= best + best/16 + UNQ),
//                 right-view winners (min over d of S(xr + d, d)) for the left-right check.
//                 Path vectors of the previous row: 3 x (160 x 48 x 6 bit) RAM; written 2 pixels late (ring of 2 pixels)
//                 so the top-left / top / top-right reads of the next pixels still see the previous row.
//   output pass : d where valid and |d_right(x - d) - d| <= 1, else 63 -> depth RAM (160x90 x 6, read by depth_overlay).
// One depth frame: 85 rows x (160 x 50 + 800 + ~280) clocks ~ 0.77 M pixel clocks (~10 ms) + the two captures.
// CDC: arm toggle pclk -> camera / rx clocks, done toggles back (SDC max_delay on the first stages).
// CLAUDE MERGE Vision Core (2026-10-27): v2 SGM (board-verified) with the two image RAMs moved to vision_core (shared with
// RANGE 45 / TEMPLATE 48 / MOTION 50, mode-exclusive). en_depth (47): capture both + SGM; en_motion (50): capture the left
// image only, then mot_go until motion_cells reports mot_done. Neither: idle (no capture, RAM ports left to the others).
// CLAUDE ZOOM5 (2026-10-28, board: depth map flickers): temporal filter in the output pass. The depth RAM holds
// {conf[1:0], d[5:0]} (explicit 16K x 8 DP ERAM: port A read-modify-write, port B display read, low 6 bits shown).
// Per cell (old o / conf c, new n): both valid and |n-o| <= 1 -> keep o (dead band), c+1 (max 2); |n-o| == 2 -> midpoint,
// c+1; n valid but far from o (or o invalid) -> c > 0: keep o, c-1, else take n; n invalid -> c > 0: keep o, c-1, else 63.
// Output pass 3 clocks per cell (read, wait, write).
module depth_map #(
    parameter integer ND=48, P1=3, P2=20, UNQ=2
)(
    input wire cam_clk, cam_rst_n, l_valid, l_sof, l_eol, input wire [95:0] l_data,
    input wire rx_clk, rx_rst, r_valid, input wire [31:0] r_addr, input wire [15:0] r_data,
    input wire pclk, prst_n,
    input wire [7:0] rd_x, input wire [6:0] rd_y, output wire [5:0] rd_d,       // display read port, 1-clock latency
    output reg [7:0] frames,
    input wire en_depth, en_motion, input wire mot_done, output reg mot_go,
    output wire l_we, output wire [13:0] l_wa, output wire [7:0] l_wd,     // left image write (camera clock) -> vision_core
    output wire r_we, output wire [13:0] r_wa, output wire [7:0] r_wd,     // right image write (rx clock) -> vision_core
    output reg [13:0] lra, input wire [7:0] lq, rq                       // image read (pixel clock, 2-clock latency)
);
    function [7:0] luma24(input [23:0] p); reg [9:0] s; begin s = {2'd0,p[23:16]} + {1'd0,p[15:8],1'b0} + {2'd0,p[7:0]}; luma24 = s[9:2]; end endfunction
    function [13:0] a160(input [6:0] r, input [7:0] c); a160 = {r, 7'd0} + {2'd0, r, 5'd0} + {6'd0, c}; endfunction
    function [12:0] a48(input [7:0] x, input [5:0] k); a48 = {x, 5'd0} + {1'd0, x, 4'd0} + {7'd0, k}; endfunction
    function [4:0] pop24(input [23:0] v); integer i; begin pop24 = 0; for(i=0; i<24; i=i+1) pop24 = pop24 + {4'd0, v[i]}; end endfunction
    function [5:0] min6(input [5:0] a, input [5:0] b); min6 = (a < b) ? a : b; endfunction

    reg a_t;                                                      // arm toggle (pixel clock)

    // ------------------------------------------------ left capture + 8x8 binning (camera clock) -----------------------------
    (* async_reg="true" *) reg la1, la2; reg la3;
    reg lpend, lon, l_done_t, lls; reg [9:0] ly; reg [8:0] lk;
    // CLAUDE MERGE: binning accumulators in ERAM (synchronous read)
    reg [13:0] lacc [0:159]; /* fehdl force_ram=1, ram_style="bram" */
    reg [13:0] lacc_q; reg [9:0] lpart;
    wire lfirst = l_valid && (l_sof || lls);
    wire [9:0] ly_c = l_sof ? 10'd0 : (lls ? ly + 10'd1 : ly);
    wire [8:0] lk_c = lfirst ? 9'd0 : lk + 9'd1;
    wire [9:0] lsum4 = {2'd0, luma24(l_data[95:72])} + {2'd0, luma24(l_data[71:48])} + {2'd0, luma24(l_data[47:24])} + {2'd0, luma24(l_data[23:0])};
    wire lcap = l_valid && (lon || (lpend && l_sof)) && ly_c < 10'd720 && lk_c < 9'd320;
    wire [13:0] lnew = (ly_c[2:0] == 3'd0 ? 14'd0 : lacc_q) + {4'd0, lpart} + {4'd0, lsum4};
    wire lwr_bin = lcap && lk_c[0] && ly_c[2:0] == 3'd7;          // last line of a bin row, odd beat: bin complete
    always @(posedge cam_clk) begin
        if(lcap && !lk_c[0]) lacc_q <= lacc[lk_c[8:1]];
        if(lcap && lk_c[0] && ly_c[2:0] != 3'd7) lacc[lk_c[8:1]] <= lnew;
    end
    always @(posedge cam_clk or negedge cam_rst_n) begin
        if(!cam_rst_n) begin la1<=0; la2<=0; la3<=0; lpend<=0; lon<=0; l_done_t<=0; lls<=0; ly<=0; lk<=0; lpart<=0; end
        else begin
            la1<=a_t; la2<=la1; la3<=la2;
            if(la2^la3) lpend<=1;
            if(l_valid) begin
                lls<=l_eol; lk<=lk_c; if(lfirst) ly<=ly_c;
                if(lpend && l_sof) begin lpend<=0; lon<=1; end
                if(lcap && !lk_c[0]) lpart<=lsum4;
                if(lcap && ly_c==10'd719 && lk_c==9'd319) begin lon<=0; l_done_t<=~l_done_t; end
            end
        end
    end
    assign l_we = lwr_bin; assign l_wa = a160(ly_c[9:3], lk_c[8:1]); assign l_wd = lnew[13:6];

    // ------------------------------------------------ right capture + 8x8 binning (rx clock) --------------------------------
    (* async_reg="true" *) reg ra1, ra2; reg ra3;
    reg rpend, ron, rmid, r_done_t;
    reg r1v, r2v, r3v; reg [19:0] r1a, r2a; reg [7:0] r1l, r2l, r3l; reg [9:0] r2y, r3y; reg [10:0] r3x;
    reg [13:0] racc [0:159]; /* fehdl force_ram=1, ram_style="bram" */
    reg [13:0] racc_q; reg [10:0] rps;
    wire [25:0] yq = {14'd0, r1a[19:8]} * 26'd13108;              // floor(a / 1280) = floor((a >> 8) / 5)
    wire [7:0] rl8 = luma24({r_data[15:11], r_data[15:13], r_data[10:5], r_data[10:9], r_data[4:0], r_data[4:2]});
    wire [9:0] yl = r3y + 10'd6;                                  // left-aligned row
    wire [7:0] rbc = r3x[10:3];
    wire rcap = ron && r3v && yl < 10'd720 && r3x < 11'd1280;
    wire [10:0] rrow = rps + {3'd0, r3l};                         // 8-pixel row sum at sub-pixel 7
    wire [13:0] rnew = (yl[2:0] == 3'd0 ? 14'd0 : racc_q) + {3'd0, rrow};
    wire rwr_bin = rcap && r3x[2:0] == 3'd7 && yl[2:0] == 3'd7;
    always @(posedge rx_clk) begin
        if(rcap && r3x[2:0] == 3'd0) racc_q <= racc[rbc];
        if(rcap && r3x[2:0] == 3'd7 && yl[2:0] != 3'd7) racc[rbc] <= rnew;
    end
    always @(posedge rx_clk or posedge rx_rst) begin
        if(rx_rst) begin
            ra1<=0; ra2<=0; ra3<=0; rpend<=0; ron<=0; rmid<=0; r_done_t<=0;
            r1v<=0; r2v<=0; r3v<=0; r1a<=0; r2a<=0; r1l<=0; r2l<=0; r3l<=0; r2y<=0; r3y<=0; r3x<=0; rps<=0;
        end else begin
            ra1<=a_t; ra2<=ra1; ra3<=ra2;
            if(ra2^ra3) rpend<=1;
            r1v<=r_valid && r_addr < 32'd921600; r1a<=r_addr[19:0]; r1l<=rl8;
            r2v<=r1v; r2a<=r1a; r2l<=r1l; r2y<=yq[25:16];
            r3v<=r2v; r3l<=r2l; r3y<=r2y; r3x<=r2a[10:0] - {r2y[0], 10'd0} - {r2y[2:0], 8'd0};   // a - 1280 y (low 11 bits)
            if(r3v) begin
                if(rpend && r3y==10'd0) begin rpend<=0; ron<=1; rmid<=0; end
                if(ron && r3y>10'd360) rmid<=1;
                if(rcap) rps <= (r3x[2:0] == 3'd0) ? {3'd0, r3l} : rrow;
                if(ron && (r3y>=10'd714 || (rmid && r3y<10'd8))) begin ron<=0; r_done_t<=~r_done_t; end
            end
        end
    end
    assign r_we = rwr_bin; assign r_wa = a160(yl[9:3], rbc); assign r_wd = rnew[13:6];

    // ------------------------------------------------ pixel clock memories --------------------------------------------------
    reg [13:0] dwa; reg [7:0] dwd; reg dwe; wire [7:0] dq, dmq;   // depth result {conf, d}, 160x90
    PH1P_LOGIC_ERAM #(.DATA_WIDTH_A(8),.DATA_WIDTH_B(8),.ADDR_WIDTH_A(14),.ADDR_WIDTH_B(14),.DATA_DEPTH_A(16384),.DATA_DEPTH_B(16384),
      .MODE("DP"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),.WRITEMODE_A("NORMAL"),.WRITEMODE_B("NORMAL"),
      .CLKMODE("ASYNC"),.SSROVERCE("DISABLE"),.OREGSET_A("RESET"),.OREGSET_B("RESET"),.RESETMODE_A("ASYNC"),.RESETMODE_B("ASYNC"),
      .ASYNC_RESET_RELEASE_A("ASYNC"),.ASYNC_RESET_RELEASE_B("ASYNC"),.ECC_ENCODE("DISABLE"),.ECC_DECODE("DISABLE"),
      .IMPLEMENT("20K(FAST)"),.INIT_FILE("NONE"),.FILL_ALL("NONE")) dram8(
      .dia(dwd),.addra(dwa),.cea(1'b1),.ocea(1'b0),.clka(pclk),.wea(dwe),.rsta(1'b0),.bea(1'b0),
      .dib(8'd0),.addrb(a160(rd_y, rd_x)),.ceb(1'b1),.oceb(1'b0),.clkb(pclk),.web(1'b0),.rstb(1'b0),.beb(1'b0),
      .ecc_sbiterrinj(1'b0),.ecc_dbiterrinj(1'b0),.doa(dq),.dob(dmq),.ecc_sbiterr(),.ecc_dbiterr());
    assign rd_d = dmq[5:0];
    // temporal filter of the output pass (o, c from dq; n new)
    reg [5:0] tf_n; reg [1:0] tf_ph;
    wire [5:0] tf_o = dq[5:0]; wire [1:0] tf_c = dq[7:6];
    wire tf_nv = tf_n != 6'd63, tf_ov = tf_o != 6'd63;
    wire [5:0] tf_ad = (tf_n > tf_o) ? tf_n - tf_o : tf_o - tf_n;
    wire [6:0] tf_sum = {1'b0, tf_n} + {1'b0, tf_o};
    wire [1:0] tf_cu = (tf_c == 2'd2) ? 2'd2 : tf_c + 2'd1;
    wire [7:0] tf_out = (tf_nv && tf_ov && tf_ad <= 6'd1) ? {tf_cu, tf_o} :
                        (tf_nv && tf_ov && tf_ad == 6'd2) ? {tf_cu, tf_sum[6:1]} :
                        (tf_c != 2'd0 && tf_ov)          ? {tf_c - 2'd1, tf_o} :
                        tf_nv                            ? {2'd0, tf_n} : {2'd0, 6'd63};
    // previous-row path vectors (top-left, top, top-right), address x*48 + d
    (* ram_style="bram" *) reg [5:0] vtl [0:8191]; (* ram_style="bram" *) reg [5:0] vtt [0:8191]; (* ram_style="bram" *) reg [5:0] vtr [0:8191];
    reg [12:0] vwa; reg vwe; reg [5:0] vwd_tl, vwd_tt, vwd_tr; wire [12:0] vra_tl, vra_tt, vra_tr; reg [5:0] vq_tl, vq_tt, vq_tr;
    always @(posedge pclk) begin
        if(vwe) begin vtl[vwa] <= vwd_tl; vtt[vwa] <= vwd_tt; vtr[vwa] <= vwd_tr; end
        vq_tl <= vtl[vra_tl]; vq_tt <= vtt[vra_tt]; vq_tr <= vtr[vra_tr];
    end
    // distributed buffers (async read)
    // CLAUDE Z20 (area): lcen in block RAM (the last ERAM; was 160 x 24 distributed RAM). Read address mx is a register and
    // the data was registered (a_xor <= lcen[mx] ^ ...): same timing as a synchronous read lcq <= lcen[mx], a_xor = lcq ^ a_rcq.
    // CLAUDE Z22C: a 24-bit wide ERAM takes 2 blocks (18-bit ports; z22 = 109 > 108): bits 17..0 in one ERAM (synchronous
    // read lcq), bits 23..18 distributed as in z21 (read XOR rcen registered into a_xh; a registered plain read became an ERAM
    // in z22b). Same a_xor every clock.
    (* ram_style="bram" *) reg [17:0] lcen [0:159]; reg [5:0] lcenh [0:159]; reg [17:0] lcq; reg [5:0] a_xh;
    reg [23:0] rcen [0:159];                                      // census of the current row
    reg [5:0] ring_lr [0:127], ring_tl [0:127], ring_tt [0:127], ring_tr [0:127];   // {pixel parity, d}: current-row vectors
    reg [5:0] mb_tl [0:159], mb_tt [0:159], mb_tr [0:159];       // previous-row path minima
    reg [5:0] dsp [0:159];                                        // left winner per x (63 invalid)
    reg [7:0] minr [0:159]; reg [5:0] argr [0:159];               // right-view winner per xr

    // ------------------------------------------------ pixel clock control ---------------------------------------------------
    (* async_reg="true" *) reg ld1, ld2; reg ld3; (* async_reg="true" *) reg rd1, rd2; reg rd3;
    localparam [3:0] S_ARM=0, S_WAIT=1, S_EDGE=2, S_CEN=3, S_CDR=4, S_MAIN=5, S_MDR=6, S_OUT=7, S_NEXT=8, S_MOT=9;
    reg [3:0] st; reg gl, gr; reg [6:0] y; reg [7:0] ex; reg [2:0] eph; reg [3:0] dr;
    // census pass
    reg [7:0] cx; reg [2:0] cj; reg ct_v, cu_v; reg [7:0] ct_x, cu_x; reg [2:0] ct_j, cu_j;   // tags: address issued / data valid
    reg [7:0] cl0, cl1, cl2, cl3, cr0, cr1, cr2, cr3;              // column being collected (rows 0..3)
    reg [7:0] wl [0:24], wr [0:24];                               // 5x5 windows [col*5 + row]
    reg cw_v; reg [7:0] cw_x;
    // main pass
    reg [7:0] mx; reg [5:0] mk;
    wire yfirst = (y == 7'd3);
    wire [7:0] rca = mx - {2'd0, mk};
    wire iv = (st == S_MAIN) && mx < 8'd160 && mk <= 6'd48;     // issue valid (k = 48: sentinel for d = 47)
    assign vra_tl = a48(mx - 8'd1, mk); assign vra_tt = a48(mx, mk); assign vra_tr = a48(mx + 8'd1, mk);
    // stage A
    reg a_v; reg [7:0] a_x; reg [5:0] a_k; reg [23:0] a_rcq; reg a_cinv; reg [5:0] a_plr; reg a_ztl, a_ztt, a_ztr;
    // stage B
    reg b_v; reg [7:0] b_x; reg [5:0] b_k; reg [4:0] b_c, b_c1;
    reg [5:0] b_plr, b_ptl, b_ptt, b_ptr;                         // Lprev(k)
    reg [5:0] h1_lr, h1_tl, h1_tt, h1_tr, h2_lr, h2_tl, h2_tt, h2_tr;   // Lprev(k-1), Lprev(k-2)
    reg [5:0] min_lr;                                             // minimum of the left neighbour's vector
    // stage C
    reg c_v; reg [7:0] c_x; reg [5:0] c_d; reg [5:0] c_lr, c_tl, c_tt, c_tr;
    reg [5:0] rm_lr, rm_tl, rm_tt, rm_tr;                         // running minima over d
    reg [5:0] mq1_tl, mq1_tt, mq1_tr, mq2_tl, mq2_tt, mq2_tr;    // minima of pixels x-1, x-2 (written 2 pixels late)
    // stage D
    reg e_v; reg [7:0] e_x; reg [5:0] e_d; reg [7:0] e_s;
    reg [7:0] w_best, w_sec, w_pend; reg [5:0] w_bd;

    // SGM update for one path: d = b_k - 1, Lprev(d-1) = h2, Lprev(d) = h1, Lprev(d+1) = current
    wire [5:0] bd_ = b_k - 6'd1;
    function [5:0] sgm(input [4:0] c, input [5:0] pm1, input [5:0] p0, input [5:0] pp1, input [5:0] mn, input first_d);
        reg [7:0] m, t;
        begin
            m = {2'd0, p0};
            t = {2'd0, pp1} + P1; if(t < m) m = t;
            if(!first_d) begin t = {2'd0, pm1} + P1; if(t < m) m = t; end
            t = {2'd0, mn} + P2; if(t < m) m = t;
            t = {3'd0, c} + m - {2'd0, mn}; sgm = (t > 8'd63) ? 6'd63 : t[5:0];
        end
    endfunction
    wire [5:0] mn_tl = (yfirst || b_x == 8'd0) ? 6'd0 : mb_tl[b_x - 8'd1];
    wire [5:0] mn_tt = yfirst ? 6'd0 : mb_tt[b_x];
    wire [5:0] mn_tr = (yfirst || b_x == 8'd159) ? 6'd0 : mb_tr[b_x + 8'd1];
    wire [5:0] mn_lr = (b_x == 8'd0) ? 6'd0 : min_lr;
    wire b_d0 = (b_k == 6'd1);
    // stage D: winner, uniqueness, right-view winners
    wire [7:0] s_cd = {2'd0, c_lr} + {2'd0, c_tl} + {2'd0, c_tt} + {2'd0, c_tr};
    wire [6:0] e_dp = {1'b0, e_d}, e_bdp = {1'b0, w_bd};
    reg [7:0] nb, ns, np; reg [5:0] nbd; reg [7:0] fsec; reg dok;
    always @* begin
        if(e_d == 6'd0) begin nb = e_s; nbd = 6'd0; ns = 8'hff; np = e_s; end
        else if(e_s < w_best) begin nb = e_s; nbd = e_d; ns = (e_bdp + 7'd1 < e_dp && w_best < w_sec) ? w_best : w_sec; np = e_s; end
        else begin nb = w_best; nbd = w_bd; ns = (e_bdp + 7'd2 < e_dp && w_pend < w_sec) ? w_pend : w_sec; np = e_s; end
        fsec = ({1'b0, nbd} + 7'd1 < ND - 1 && np < ns) ? np : ns;
        dok = e_x >= 8'd4 && e_x <= 8'd155 && nbd < ND - 1 && {1'b0, fsec} >= {1'b0, nb} + {5'd0, nb[7:4]} + UNQ;
    end
    wire [7:0] e_xr = e_x - {2'd0, e_d};
    wire [7:0] mr_q = minr[e_xr];
    // output pass
    wire [5:0] o_dl = dsp[ex];
    wire [7:0] o_xr = ex - {2'd0, o_dl};
    wire [5:0] o_ar = argr[o_xr];
    wire o_ok = o_dl != 6'd63 && ex >= {2'd0, o_dl} && (o_ar == o_dl || o_ar == o_dl + 6'd1 || o_ar + 6'd1 == o_dl);

    integer i;
    always @(posedge pclk) begin
        // current-row rings and right winners (stage C / D writes)
        if(c_v) begin ring_lr[{c_x[0], c_d}] <= c_lr; ring_tl[{c_x[0], c_d}] <= c_tl; ring_tt[{c_x[0], c_d}] <= c_tt; ring_tr[{c_x[0], c_d}] <= c_tr; end
        if(e_v && e_x >= {2'd0, e_d} && (e_d == 6'd0 || e_s < mr_q)) begin minr[e_xr] <= e_s; argr[e_xr] <= e_d; end
        if(e_v && e_d == ND - 1) dsp[e_x] <= dok ? nbd : 6'd63;
        // previous-row minima, written 2 pixels late (bubble cycle k = 49 of pixel mx, also for the flush pixels 160 / 161)
        if(st == S_MAIN && mk == 6'd49 && mx >= 8'd2) begin
            mb_tl[mx - 8'd2] <= (mx == 8'd161) ? mq1_tl : mq2_tl;
            mb_tt[mx - 8'd2] <= (mx == 8'd161) ? mq1_tt : mq2_tt;
            mb_tr[mx - 8'd2] <= (mx == 8'd161) ? mq1_tr : mq2_tr;
        end
    end
    // census of the window centre (registered window) -> lcen / rcen
    function [23:0] cen(input integer side);
        integer q, b; reg [7:0] cc, v;
        begin
            b = 0; cen = 0; cc = side ? wr[12] : wl[12];
            for(q=0; q<25; q=q+1) if(q != 12) begin v = side ? wr[q] : wl[q]; cen[b] = (v < cc); b = b + 1; end
        end
    endfunction
    wire [23:0] lcw = cen(0);
    always @(posedge pclk) if(cw_v && cw_x >= 8'd4) begin lcen[cw_x - 8'd2] <= lcw[17:0]; lcenh[cw_x - 8'd2] <= lcw[23:18]; rcen[cw_x - 8'd2] <= cen(1); end
    always @(posedge pclk) lcq <= lcen[mx];                       // Z20: synchronous read (ERAM)
    wire [23:0] a_xor = {a_xh, lcq ^ a_rcq[17:0]};

    always @(posedge pclk or negedge prst_n) begin
        if(!prst_n) begin
            a_t<=0; lra<=0; mot_go<=0; ld1<=0; ld2<=0; ld3<=0; rd1<=0; rd2<=0; rd3<=0; st<=S_ARM; gl<=0; gr<=0; y<=0; ex<=0; eph<=0; dr<=0;
            dwa<=0; dwd<=0; dwe<=0; tf_n<=0; tf_ph<=0; frames<=0; vwa<=0; vwe<=0; vwd_tl<=0; vwd_tt<=0; vwd_tr<=0;
            cx<=0; cj<=0; ct_v<=0; ct_x<=0; ct_j<=0; cu_v<=0; cu_x<=0; cu_j<=0; cl0<=0; cl1<=0; cl2<=0; cl3<=0; cr0<=0; cr1<=0; cr2<=0; cr3<=0; cw_v<=0; cw_x<=0;
            for(i=0; i<25; i=i+1) begin wl[i]<=0; wr[i]<=0; end
            mx<=0; mk<=0; a_v<=0; a_x<=0; a_k<=0; a_rcq<=0; a_xh<=0; a_cinv<=0; a_plr<=0; a_ztl<=0; a_ztt<=0; a_ztr<=0;
            b_v<=0; b_x<=0; b_k<=0; b_c<=0; b_c1<=0; b_plr<=0; b_ptl<=0; b_ptt<=0; b_ptr<=0;
            h1_lr<=0; h1_tl<=0; h1_tt<=0; h1_tr<=0; h2_lr<=0; h2_tl<=0; h2_tt<=0; h2_tr<=0; min_lr<=0;
            c_v<=0; c_x<=0; c_d<=0; c_lr<=0; c_tl<=0; c_tt<=0; c_tr<=0; rm_lr<=0; rm_tl<=0; rm_tt<=0; rm_tr<=0;
            mq1_tl<=0; mq1_tt<=0; mq1_tr<=0; mq2_tl<=0; mq2_tt<=0; mq2_tr<=0;
            e_v<=0; e_x<=0; e_d<=0; e_s<=0; w_best<=0; w_sec<=0; w_pend<=0; w_bd<=0;
        end else begin
            ld1<=l_done_t; ld2<=ld1; ld3<=ld2; rd1<=r_done_t; rd2<=rd1; rd3<=rd2;
            if(ld2^ld3) gl<=1;
            if(rd2^rd3) gr<=1;
            dwe<=0; vwe<=0;
            // ---------------- census pass pipeline: address (ct) -> RAM -> data with ct tags
            ct_v <= (st == S_CEN); ct_x <= cx; ct_j <= cj; cu_v <= ct_v; cu_x <= ct_x; cu_j <= ct_j;
            cw_v <= 0;
            if(cu_v) begin
                case(cu_j)
                    3'd0: begin cl0<=lq; cr0<=rq; end
                    3'd1: begin cl1<=lq; cr1<=rq; end
                    3'd2: begin cl2<=lq; cr2<=rq; end
                    3'd3: begin cl3<=lq; cr3<=rq; end
                    default: begin                             // column complete: shift the windows
                        for(i=0; i<20; i=i+1) begin wl[i]<=wl[i+5]; wr[i]<=wr[i+5]; end
                        wl[20]<=cl0; wl[21]<=cl1; wl[22]<=cl2; wl[23]<=cl3; wl[24]<=lq;
                        wr[20]<=cr0; wr[21]<=cr1; wr[22]<=cr2; wr[23]<=cr3; wr[24]<=rq;
                        cw_v<=1; cw_x<=cu_x;
                    end
                endcase
            end
            // ---------------- main pass pipeline
            // issue -> A
            a_v <= iv; a_x <= mx; a_k <= mk;
            a_rcq <= rcen[rca]; a_xh <= lcenh[mx] ^ rcen[rca][23:18]; a_cinv <= {2'd0, mk} + 8'd2 > mx || mx >= 8'd158 || mk == 6'd48;   // census of columns 0, 1, 158, 159 not computed: neutral cost
            a_plr <= (mx == 8'd0) ? 6'd0 : (mk == 6'd48) ? 6'd63 : ring_lr[{~mx[0], mk}];
            a_ztl <= yfirst || mx == 8'd0; a_ztt <= yfirst; a_ztr <= yfirst || mx == 8'd159;
            // A -> B (vertical RAM data valid in A)
            b_v <= a_v; b_x <= a_x; b_k <= a_k; b_c <= a_cinv ? 5'd24 : pop24(a_xor);
            b_plr <= a_plr;
            b_ptl <= (a_k == 6'd48) ? 6'd63 : a_ztl ? 6'd0 : vq_tl;
            b_ptt <= (a_k == 6'd48) ? 6'd63 : a_ztt ? 6'd0 : vq_tt;
            b_ptr <= (a_k == 6'd48) ? 6'd63 : a_ztr ? 6'd0 : vq_tr;
            // B: history shift and the path update for d = b_k - 1
            if(b_v) begin
                h1_lr<=b_plr; h1_tl<=b_ptl; h1_tt<=b_ptt; h1_tr<=b_ptr; h2_lr<=h1_lr; h2_tl<=h1_tl; h2_tt<=h1_tt; h2_tr<=h1_tr; b_c1<=b_c;
            end
            c_v <= b_v && b_k != 6'd0; c_x <= b_x; c_d <= bd_;
            c_lr <= sgm(b_c1, h2_lr, h1_lr, b_plr, mn_lr, b_d0);
            c_tl <= sgm(b_c1, h2_tl, h1_tl, b_ptl, mn_tl, b_d0);
            c_tt <= sgm(b_c1, h2_tt, h1_tt, b_ptt, mn_tt, b_d0);
            c_tr <= sgm(b_c1, h2_tr, h1_tr, b_ptr, mn_tr, b_d0);
            // C: running minima; pixel end -> left-neighbour minimum and the 2-deep minima delay
            if(c_v) begin
                rm_lr <= (c_d == 0) ? c_lr : min6(rm_lr, c_lr); rm_tl <= (c_d == 0) ? c_tl : min6(rm_tl, c_tl);
                rm_tt <= (c_d == 0) ? c_tt : min6(rm_tt, c_tt); rm_tr <= (c_d == 0) ? c_tr : min6(rm_tr, c_tr);
                if(c_d == ND - 1) begin
                    min_lr <= min6(rm_lr, c_lr);
                    mq2_tl <= mq1_tl; mq2_tt <= mq1_tt; mq2_tr <= mq1_tr;
                    mq1_tl <= min6(rm_tl, c_tl); mq1_tt <= min6(rm_tt, c_tt); mq1_tr <= min6(rm_tr, c_tr);
                end
            end
            e_v <= c_v; e_x <= c_x; e_d <= c_d; e_s <= s_cd;
            // D: winner tracking
            if(e_v) begin w_best <= nb; w_sec <= ns; w_pend <= np; w_bd <= nbd; end
            case(st)
                S_ARM: if(en_depth || en_motion) begin a_t<=~a_t; gl<=0; gr<=0; st<=S_WAIT; end
                S_WAIT: if(!en_depth && !en_motion) st<=S_ARM;
                        else if(en_motion && gl) begin mot_go<=1; st<=S_MOT; end
                        else if(!en_motion && gl && gr) begin ex<=0; eph<=0; st<=S_EDGE; end
                S_MOT: if(mot_done || !en_motion) begin mot_go<=0; st<=S_ARM; end
                S_EDGE: begin                                    // rows 0, 1, 2, 88, 89 invalid
                    dwe<=1; dwd<={2'd0, 6'd63}; dwa<=a160((eph==3'd0) ? 7'd0 : (eph==3'd1) ? 7'd1 : (eph==3'd2) ? 7'd2 : (eph==3'd3) ? 7'd88 : 7'd89, ex);
                    if(ex==8'd159) begin ex<=0; if(eph==3'd4) begin y<=7'd3; cx<=0; cj<=0; st<=S_CEN; end else eph<=eph+3'd1; end
                    else ex<=ex+8'd1;
                end
                S_CEN: begin                                     // read rows y-2..y+2 of column cx
                    lra <= a160(y - 7'd2 + {4'd0, cj}, cx);
                    if(cj==3'd4) begin cj<=0; if(cx==8'd159) begin dr<=0; st<=S_CDR; end cx<=cx+8'd1; end
                    else cj<=cj+3'd1;
                end
                S_CDR: if(dr==4'd5) begin mx<=0; mk<=0; st<=S_MAIN; end else dr<=dr+4'd1;
                S_MAIN: begin                                    // pixels 0..159, flush pixels 160 / 161; k = 0..49
                    // write-back of pixel mx-2's vectors to the previous-row RAMs (read ring slot mx parity before reuse)
                    if(mx >= 8'd2 && mk < 6'd48) begin
                        vwe<=1; vwa<=a48(mx - 8'd2, mk);
                        vwd_tl<=ring_tl[{mx[0], mk}]; vwd_tt<=ring_tt[{mx[0], mk}]; vwd_tr<=ring_tr[{mx[0], mk}];
                    end
                    if(mk==6'd49) begin mk<=0; if(mx==8'd161) begin dr<=0; st<=S_MDR; end mx<=mx+8'd1; end
                    else mk<=mk+6'd1;
                end
                S_MDR: if(dr==4'd8) begin ex<=0; tf_ph<=0; st<=S_OUT; end else dr<=dr+4'd1;
                S_OUT: begin                                     // left-right check, temporal filter, write the row
                    if(tf_ph==2'd0) begin dwa<=a160(y, ex); tf_n<= o_ok ? o_dl : 6'd63; tf_ph<=2'd1; end   // read old
                    else if(tf_ph==2'd1) tf_ph<=2'd2;                                                  // dq valid next
                    else begin
                        dwe<=1; dwd<=tf_out; tf_ph<=2'd0;
                        if(ex==8'd159) st<=S_NEXT; else ex<=ex+8'd1;
                    end
                end
                S_NEXT: if(y==7'd87) begin frames<=frames+8'd1; st<=S_ARM; end
                        else begin y<=y+7'd1; cx<=0; cj<=0; st<=S_CEN; end
                default: st<=S_ARM;
            endcase
        end
    end
endmodule
