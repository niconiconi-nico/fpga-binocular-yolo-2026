// CLAUDE RANGE v3 (2026-10-26): stereo ranging with target lock (mode 47 RANGE). Calibration: CLAUDE_STEREO_CALIB_20261024/
// calib2_run1/final (baseline 63.96 mm, HDMI raster coordinates of the left / right full views).
// Measurement block: 32x32 px of the LEFT colour-stage output centred at (cx, cy).
//   unlocked: (cx, cy) = one of 9 points (X 420/640/860, Y 180/360/540), KEY4 short press = next point.
//   KEY4 long press (~0.6 s) = lock: the current block becomes the template; every update the template is searched in a
//   96x96 left window around the previous position (+-32 px; coarse: 2 px steps with the template sampled every 2nd pixel,
//   fine: +-1 px full-resolution zero-mean SAD), the box follows the target (x 400..1200, y 120..600) and the template is
//   refreshed from the new block when the residual is small (else LOST: position kept). Short press while locked = unlock.
//   (Reference: GPT mono_match4 mode 48 = 32x32 grey SAD on a 4-px point-sampled 128x128 patch; here full-resolution template
//   and zero-mean fine score against its point-sampling phase / light sensitivity.)
// Stereo: right pixels (x - d, y - 6 + dyoff(d)), d = 0..383, zero-mean SAD per d, minimum, second minimum outside +-2,
// parabola sub-pixel (1/16 px), median of the last 3 + 1/2 IIR within 3 px, depth from 15 tables on a 5x3 grid
// (X 400..1200 step 200, Y 120..600 step 240; dyoff from the nearest table, Z bilinear over the 4 surrounding tables,
// pc/grid_interp_check.py: median 0.32 %, 95 % 1.1 %). Display hold: after an OK result the last OK reading stays shown for up
// to 8 updates of non-OK results. status 0 OK, 1 WAIT, 2 LOW TEXTURE, 3 UNSURE (Z shown, flagged), 4 NEAR, 5 FAR (>= 10 m).
// Captures: left window 96 rows x 26 beats (4 byte-lane ERAMs, camera clock), right strip 40 rows x 415 columns (rx clock).
// CDC: arm toggles (left / right) pclk -> camera / rx, done toggles back, position bus {cx, cy} quasi-static (set >= 8 pclk
// before the arm toggle, latched by the capture domain at the toggle) -> SDC set_max_delay on the first stages.
// v2 (fixed 9 points) is kept in ../v2_block32, v1 in ../v1_block16.
// CLAUDE MERGE Vision Core (2026-10-27): same algorithm (full search, board-verified v3). The left window (4 byte lanes) and
// the right strip live in vision_core's image RAMs (shared with DEPTH 47 / MOTION 50, mode-exclusive); strip 40 x 409
// (one 16K RAM) -> d = 0..377 (~0.33 m). run: 0 = idle (no captures). track_only (TEMPLATE 48): template tracking only,
// no stereo; the tracking area is then the whole frame (window inside the image).
// CLAUDE ZOOM4 (2026-10-28, board: lock drifts / reading unsteady): template refreshed only on a confident match (residual
// < REFRES = 12, was every match < 20) and not when the box stays within +-1 px (no drift accumulation); lock kept up to
// residual MAXRES = 28 (was 20); box dead band +-1 px; disparity IIR 1/4 (was 1/2) within 3 px; a reading is shown only
// when confirmed by 3 agreeing results (else the held reading <= 8 updates, else WAIT): no one-off outlier on screen.
// CLAUDE ZOOM7 (board: TEMPLATE still drifts with a moving target): anchored template. The locked template is kept as
// long as it still matches well (residual < REFRES = 16); it is refreshed only when the match degrades (REFRES ..
// MAXRES - 1, appearance changed) and the box moved. (ZOOM4/5 refreshed on every confident move: sub-pixel error of
// each refresh accumulated as drift while the target moved.)
// CLAUDE BOTTLE (2026-10-28): remote-window tracking for the YOLO bottle tracker (mode 38, rwin = 1, track_only = 1): the
// 96 x 104 window is captured from the RECEIVED image (rx clock) by the strip capture (width 104, 96 rows, base
// (by - 48) * 1280 + bx - 48 - bx[1:0]) into the R image RAM at {row, column} (read back through waddr14 / rq), so the
// window geometry and the whole search are unchanged. KEY4 is not used (enable = 0); bottle_seed sets the position and
// lock through seed / drop, applied at the start of the next update.
// CLAUDE Z10 GIMBAL (2026-10-30): matcher of board22 (MONO_GIMBAL_20261029, user-confirmed smooth on the board): candidate
// selection with a small displacement prior (coarse: + distance * 128, fine: + distance * 256 on the raw SAD; acceptance
// still on the raw residual), template texture range recorded at capture, one target_update per tracking result with
// target_good = matched, locked and texture range >= 24. TEMPLATE (track_only, not rwin) keeps the captured anchor (no
// refresh, board22); RANGE and the BOTTLE remote window keep the degraded-match refresh (YOLO reseeds BOTTLE anyway).
// CLAUDE Z12 AREA (same outputs cycle for cycle): (1) one shared accumulator adder acc + acc_in (acc_in selected by the
// state: template / |T-W| / window / zero-mean |T-W| / right / stereo |dz|) instead of one 20-bit adder per state, the block
// means taken from the same sum; (2) the disparity BCD (was a bcd3 function: constant /100, /10 dividers) by double dabble
// in S_BCD next to the Z conversion (di is stable from S_ZC to S_PUB, <= 382); (3) the right strip write address
// rr * 409 + col from a row base register stepped by 409 with rr (was five adders per write).
// CLAUDE Z17 (board: TEMPLATE lost a turning / moving cup): TEMPLATE refreshes the template like RANGE / BOTTLE (match
// residual REFRES..MAXRES - 1 and the box moved), the board22 anchor-only template is dropped.
// CLAUDE Z30 (2026-11-01, board video: TEMPLATE 48 box crept from the cup logo onto the blank cup wall while showing TRACK
// LOCK): TEMPLATE only (track_only && !rwin; RANGE 45 and the BOTTLE remote window unchanged):
//   (1) anchor: the lock-time block is kept next to the current template (upper byte of the same template RAM, 1024 x 16).
//       After the current-template search, a second fine +-1 search with the anchor around its result: anchor residual
//       < MAXRES -> the box takes the anchor position (no accumulated refresh drift) and a degraded match may refresh the
//       current template; else the box keeps the current-template position and the template is not refreshed.
//   (2) + (3) texture: max - min of the final 32x32 block < TEXMIN -> LOST (box kept, no refresh, target_good = 0, the
//       gimbal holds): a flat block matches any flat area (zero-mean SAD) and would otherwise stay locked anywhere.
module range_meter #(
    parameter GRID_FILE="range_grid.hex",
    parameter integer DEBOUNCE=1500000, LONGPRESS=44000000, MAXRES=28, REFRES=16, TEXMIN=24,   // Z30: TEXMIN
    parameter integer MS_TICK=0, DEBOUNCE_MS=20, LONGPRESS_MS=587   // CLAUDE Z11: KEY4 timers on the shared 1 ms tick
)(
    input wire cam_clk, cam_rst_n, l_valid, l_sof, l_eol, input wire [95:0] l_data,
    input wire rx_clk, rx_rst, r_valid, input wire [31:0] r_addr, input wire [15:0] r_data,
    input wire pclk, prst_n, enable, key_n, run, track_only,
    input wire rwin, rwin_rx, seed, input wire [10:0] seed_x, input wire [9:0] seed_y, input wire drop,   // CLAUDE BOTTLE
    output wire [13:0] waddr14, output wire kst_o, output reg moved,      // CLAUDE Z8B: debounced KEY4 level, position-update pulse
    output wire w_we, output wire [11:0] w_wa, output wire [31:0] w_wd,    // left window write (camera clock), 4 lanes
    output wire [11:0] waddr, input wire [7:0] wq0, wq1, wq2, wq3,        // window read (pixel clock)
    output wire s_we, output wire [13:0] s_wa, output wire [7:0] s_wd,     // right strip write (rx clock)
    output reg [13:0] raddr, input wire [7:0] rq,                        // strip read (pixel clock)
    output reg [3:0] pos, output reg [10:0] cx, output reg [9:0] cy, output reg [1:0] lock,
    output reg [2:0] status, output reg [15:0] z_bcd, output reg [11:0] d_bcd, output reg [3:0] d_tenth, output reg [7:0] results,
    output reg target_update, target_good,                             // CLAUDE Z10 GIMBAL
    input wire ms                                                      // CLAUDE Z11: 1 ms tick (MS_TICK = 1)
);
    localparam integer ND=378, SW=409;                            // disparities, strip width (32 + ND - 1)
    function [7:0] luma24(input [23:0] p); reg [9:0] s; begin s = {2'd0,p[23:16]} + {1'd0,p[15:8],1'b0} + {2'd0,p[7:0]}; luma24 = s[9:2]; end endfunction
    function [10:0] px9(input [3:0] p); px9 = (p==0||p==3||p==6) ? 11'd420 : (p==1||p==4||p==7) ? 11'd640 : 11'd860; endfunction
    function [9:0] py9(input [3:0] p); py9 = (p<3) ? 10'd180 : (p<6) ? 10'd360 : 10'd540; endfunction

    // ------------------------------------------------ pixel-clock state seen by captures / read ports ------------------------
    reg al_t, ar_t; reg [10:0] bx; reg [9:0] by;                  // arm toggles, position bus for the captures
    reg [6:0] w_r; reg [6:0] w_c;                                 // window read position (row 0..95, column 0..103)
    reg [1:0] w_lane;
    assign waddr = {w_r, w_c[6:2]};
    assign waddr14 = {w_r, w_c};                                  // remote window in the R image RAM (row * 128 + column)
    reg [11:0] sc; reg [8:0] d; reg signed [3:0] dyo;
    wire [4:0] sj = sc[9:5], si = sc[4:0];
    wire [5:0] rrow = {1'b0, sj} + 6'd4 + {{2{dyo[3]}}, dyo};
    wire [8:0] rcolr = ND - 1 - d + {4'd0, si};
    wire [13:0] raddr_n = {rrow, 8'd0} + {1'd0, rrow, 7'd0} + {4'd0, rrow, 4'd0} + {5'd0, rrow, 3'd0} + {8'd0, rrow} + {5'd0, rcolr};   // rrow*409 + col

    // ------------------------------------------------ left window capture (camera clock) ------------------------------------
    (* async_reg="true" *) reg la1, la2; reg la3; (* async_reg="true" *) reg [20:0] lb1, lb2;
    reg lpend, lon, l_done_t, lls; reg [9:0] ly, wy0; reg [8:0] lk, wb0;
    wire lfirst = l_valid && (l_sof || lls);
    wire [9:0] ly_c = l_sof ? 10'd0 : (lls ? ly + 10'd1 : ly);
    wire [8:0] lk_c = lfirst ? 9'd0 : lk + 9'd1;
    wire [9:0] lrow = ly_c - wy0; wire [8:0] lkk = lk_c - wb0;
    wire lhit = l_valid && (lon || (lpend && l_sof)) && ly_c >= wy0 && lrow < 10'd96 && lk_c >= wb0 && lkk < 9'd26;
    wire [10:0] lbx = lb2[20:10] - 11'd48;
    always @(posedge cam_clk or negedge cam_rst_n) begin
        if(!cam_rst_n) begin la1<=0; la2<=0; la3<=0; lb1<=0; lb2<=0; lpend<=0; lon<=0; l_done_t<=0; lls<=0; ly<=0; lk<=0; wy0<=0; wb0<=0; end
        else begin
            la1<=al_t; la2<=la1; la3<=la2; lb1<={bx, by}; lb2<=lb1;
            if(la2^la3) begin lpend<=1; wy0<=lb2[9:0] - 10'd48; wb0<=lbx[10:2]; end
            if(l_valid) begin
                lls<=l_eol; lk<=lk_c; if(lfirst) ly<=ly_c;
                if(lpend && l_sof) begin lpend<=0; lon<=1; end
                if(lhit && lrow==10'd95 && lkk==9'd25) begin lon<=0; l_done_t<=~l_done_t; end
            end
        end
    end
    assign w_we = lhit; assign w_wa = {lrow[6:0], lkk[4:0]};
    assign w_wd = {luma24(l_data[95:72]), luma24(l_data[71:48]), luma24(l_data[47:24]), luma24(l_data[23:0])};   // [31:24] lane 0 (pixel 0) .. [7:0] lane 3
    reg [1:0] lane_d;
    wire [7:0] wsel = rwin ? rq : lane_d==2'd0 ? wq0 : lane_d==2'd1 ? wq1 : lane_d==2'd2 ? wq2 : wq3;

    // ------------------------------------------------ right strip capture (rx clock) ----------------------------------------
    (* async_reg="true" *) reg ra1, ra2; reg ra3; (* async_reg="true" *) reg [20:0] rb1, rb2;
    reg rpend, ron, r_done_t; reg [6:0] rr; reg [19:0] rbase, rstart; reg [13:0] rrow409;   // Z12: rr * 409 (strip rows <= 39)
    wire [9:0] rys = rb2[9:0] - (rwin_rx ? 10'd48 : 10'd26);            // first strip row y - 16 - 6 - 4 (window: y - 48)
    wire [10:0] rxo = rwin_rx ? 11'd48 + {9'd0, rb2[11:10]} : 11'd16 + (ND - 1);
    wire [19:0] rbase_n = {rys, 10'd0} + {2'b0, rys, 8'd0} + {9'd0, rb2[20:10]} - {9'd0, rxo};   // rys*1280 + x - 16 - (ND-1)
    wire [8:0] rsw = rwin_rx ? 9'd104 : SW;
    reg rvq; reg [19:0] raq; reg [15:0] rdq;                          // received pixel registered first (timing: ingress logic)
    always @(posedge rx_clk) begin raq <= r_addr[19:0]; rdq <= r_data; end
    wire [19:0] rad = raq; wire [19:0] rcol = rad - rstart;
    wire rin = ron && rvq && rad >= rstart && rcol < rsw;
    wire [7:0] rluma = luma24({rdq[15:11], rdq[15:13], rdq[10:5], rdq[10:9], rdq[4:0], rdq[4:2]});
    always @(posedge rx_clk or posedge rx_rst) begin
        if(rx_rst) begin ra1<=0; ra2<=0; ra3<=0; rb1<=0; rb2<=0; rpend<=0; ron<=0; r_done_t<=0; rr<=0; rrow409<=0; rbase<=0; rstart<=0; rvq<=0; end
        else begin
            rvq<=r_valid;
            ra1<=ar_t; ra2<=ra1; ra3<=ra2; rb1<={bx, by}; rb2<=rb1;
            if(ra2^ra3) begin rpend<=1; rbase<=rbase_n; end
            if(rvq) begin
                if(rpend && rad < rbase) begin rpend<=0; ron<=1; rr<=0; rrow409<=0; rstart<=rbase; end
                else if(ron && rad >= rstart + rsw) begin
                    if(rr==(rwin_rx ? 7'd95 : 7'd39)) begin ron<=0; r_done_t<=~r_done_t; end
                    else begin rr<=rr+7'd1; rrow409<=rrow409+14'd409; rstart<=rstart+20'd1280; end
                end
            end
        end
    end
    assign s_we = rin; assign s_wd = rluma;
    assign s_wa = rwin_rx ? {rr, rcol[6:0]} : rrow409 + {5'd0, rcol[8:0]};                 // rr*409 + col

    // ------------------------------------------------ pixel clock memories --------------------------------------------------
    (* ram_style="bram" *) reg [19:0] rom [0:15*384-1];                  // 15 tables x 384 (d >= ND unused)
    initial $readmemh(GRID_FILE, rom);
    reg [12:0] rom_a; reg [19:0] rom_q;
    always @(posedge pclk) rom_q <= rom[rom_a];
    always @(posedge pclk) raddr <= raddr_n;
    (* ram_style="bram" *) reg [15:0] sadm [0:ND-1];
    reg [8:0] sad_a; reg [15:0] sad_q, sad_wd; reg sad_we;
    always @(posedge pclk) begin if(sad_we) sadm[sad_a] <= sad_wd; sad_q <= sadm[sad_a]; end
    (* ram_style="bram" *) reg [15:0] tpl [0:1023];               // tracking template 32x32 {Z30 anchor, current}
    reg [9:0] t_a, t_wa; reg [15:0] t_q16, t_wd; reg t_we; reg apass;   // Z30: separate write address, anchor pass
    always @(posedge pclk) begin if(t_we) tpl[t_wa] <= t_wd; t_q16 <= tpl[t_a]; end
    wire [7:0] t_q = apass ? t_q16[15:8] : t_q16[7:0];

    // ------------------------------------------------ pixel clock control ---------------------------------------------------
    (* async_reg="true" *) reg ld1, ld2; reg ld3; (* async_reg="true" *) reg rd1, rd2; reg rd3;
    localparam integer KDB = MS_TICK ? DEBOUNCE_MS : DEBOUNCE, KLP = MS_TICK ? LONGPRESS_MS : LONGPRESS;
    wire kstep = MS_TICK ? ms : 1'b1;
    (* async_reg="true" *) reg k1, k2; reg kst; reg [$clog2(KDB+1)-1:0] kcnt; reg [$clog2(KLP+1)-1:0] pcnt; reg lp_done;
    localparam [5:0] S_ARML=0, S_WAITL=1, S_TSEL=2, S_TMEAN=3, S_CO=4, S_COE=5, S_FA=6, S_FB=7, S_FE=8, S_DEC=9, S_COPY=10,
                     S_ARMR=11, S_WAITR=12, S_LPRE=13, S_ROM=14, S_ROMW=15, S_ROMV=16, S_P1=17, S_P2=18, S_STORE=19, S_P3=20,
                     S_P3E=21, S_DIV=22, S_MED=23, S_FILT=24, S_ZC=25, S_ZR0=26, S_ZR1=27, S_ZR2=28, S_ZACC=29, S_ZEND=30,
                     S_BCD=31, S_PUB=32, S_FPRE=33, S_ZMUL=34, S_CO_RANK=35, S_FINE_RANK=36, S_TEX=37, S_DEC2=38;
    wire tm = track_only && !rwin;                                // Z30: TEMPLATE 48
    reg acopy, anc_ok; reg [9:0] cres; reg [6:0] crb, ccb; reg [7:0] bmin, bmax;
    reg [5:0] st; reg gl_f, gr_f; reg [3:0] dly; reg tinit;
    reg [10:0] ax; reg [9:0] ay; reg [1:0] ox;                   // window origin of this update: centre (ax, ay), lane offset ox
    reg [6:0] rb0, cb0;                                           // left block top-left inside the window
    reg [5:0] cu, cv, cub, cvb; reg [1:0] fdu, fdv; reg [3:0] fk; reg [6:0] fr0, fc0, frb, fcb;
    reg [19:0] acc, cbest, fbest; reg [7:0] tmean, wmean;
    reg [8:0] dmin, di; reg [15:0] best, best2, sm, sp; reg [7:0] lmin, lmax, ml, mr; reg [3:0] q, frac; reg [19:0] num, den;
    reg [2:0] stt; reg [3:0] bcnt; reg [31:0] bsh; reg [20:0] dsh;
    reg [12:0] draw, h1, h2, dflt; reg [1:0] hv;
    reg [3:0] tn, t00; reg [8:0] fxw, fyw; reg [1:0] zk; reg [15:0] z0, zc; reg zfar; reg [33:0] zacc; reg [15:0] zfin; reg [16:0] zi;
    reg [15:0] hold_z; reg [11:0] hold_d; reg [3:0] hold_t; reg [3:0] hold_age; reg have_good;
    reg seed_p, drop_p;
    reg match_done, match_good; reg [7:0] texture_min, texture_max;
    reg [6:0] coarse_distance, best_coarse_distance; reg [7:0] fine_distance, best_fine_distance;
    reg [20:0] rank_score, coarse_rank_best, fine_rank_best;
    wire [6:0] co_dist = (cu>16 ? cu-16 : 16-cu) + (cv>16 ? cv-16 : 16-cv);
    wire [7:0] fi_dist = (fr0>32 ? fr0-32 : 32-fr0) + (fc0>32+ox ? fc0-32-ox : 32+ox-fc0);
    assign kst_o = kst;
    wire [7:0] lsel = wsel;
    wire [6:0] fv7 = {cvb, 1'b0} + {5'd0, fk / 4'd3}, fu7 = {cub, 1'b0} + {5'd0, fk % 4'd3};   // coarse best + (dv|du + 1)
    wire [7:0] ar7 = {1'b0, crb} + {4'd0, fk / 4'd3}, ac7 = {1'b0, ccb} + {4'd0, fk % 4'd3};   // Z30 anchor: (crb, ccb) + (dv|du + 1)
    wire signed [10:0] dz = $signed({3'b0, lsel}) - $signed({3'b0, rq}) + $signed({3'b0, mr}) - $signed({3'b0, ml});
    wire [9:0] adz = dz[10] ? -dz[9:0] : dz[9:0];
    wire [8:0] tdiff = {1'b0, t_q} - {1'b0, wsel};
    wire [7:0] tabs = tdiff[8] ? -tdiff[7:0] : tdiff[7:0];                               // plain |T - W| (coarse)
    wire signed [10:0] zt = $signed({3'b0, t_q}) - $signed({3'b0, wsel}) - $signed({3'b0, tmean}) + $signed({3'b0, wmean});
    wire [9:0] zabs = zt[10] ? -zt[9:0] : zt[9:0];                                       // zero-mean |T - W| (fine)
    wire [9:0] acc_in = (st==S_TMEAN) ? {2'd0, t_q} : (st==S_CO) ? {2'd0, tabs} : (st==S_FB) ? zabs :
                        (st==S_P1) ? {2'd0, rq} : (st==S_P2) ? adz : {2'd0, wsel};      // S_FA / S_LPRE: window pixel
    wire [19:0] acc_s = acc + {10'd0, acc_in};                                          // Z12: the one accumulator adder
    wire [15:0] sad16 = acc_s[18:3];
    wire [11:0] base384 = {tn, 8'd0} + {1'b0, tn, 7'd0};
    wire signed [16:0] zdiff = $signed({1'b0, rom_q[15:0]}) - $signed({1'b0, z0});
    wire signed [22:0] zprod = zdiff * $signed({1'b0, frac});
    wire signed [17:0] zint = $signed({2'b0, z0}) + (zprod >>> 4);
    wire [16:0] w00 = (9'd256 - fxw) * (9'd256 - fyw), w10 = fxw * (9'd256 - fyw), w01 = (9'd256 - fxw) * fyw, w11 = fxw * fyw;
    wire [16:0] wk = zk==2'd0 ? w00 : zk==2'd1 ? w10 : zk==2'd2 ? w01 : w11;
    wire [3:0] tk = zk==2'd0 ? t00 : zk==2'd1 ? t00 + 4'd1 : zk==2'd2 ? t00 + 4'd5 : t00 + 4'd6;
    wire [12:0] tk384 = {tk, 8'd0} + {1'b0, tk, 7'd0};
    wire [12:0] med3 = (h1 > h2) ? ((draw > h1) ? h1 : (draw > h2) ? draw : h2) : ((draw > h2) ? h2 : (draw > h1) ? draw : h1);
    wire signed [13:0] fdel = $signed({1'b0, (hv==2'd2) ? med3 : draw}) - $signed({1'b0, dflt});
    wire signed [13:0] hd1 = $signed({1'b0, draw}) - $signed({1'b0, h1}), hd2 = $signed({1'b0, h1}) - $signed({1'b0, h2});
    reg hstable;                                                   // last 3 raw disparities within 3 px of each other
    // new centre from the fine best block (window row 32 / column ox + 32 = previous centre), clamped to the tracking area
    wire signed [12:0] ncx_s = $signed({2'b0, ax}) + $signed({6'b0, fcb}) - $signed({11'b0, ox}) - 13'sd32;
    wire signed [11:0] ncy_s = $signed({2'b0, ay}) + $signed({5'b0, frb}) - 12'sd32;
    wire signed [12:0] xlo = track_only ? 13'sd64 : 13'sd400, xhi = track_only ? 13'sd1212 : 13'sd1200;
    wire signed [11:0] ylo = track_only ? 12'sd64 : 12'sd120, yhi = track_only ? 12'sd652 : 12'sd600;
    wire [10:0] ncx = ncx_s < xlo ? xlo[10:0] : ncx_s > xhi ? xhi[10:0] : ncx_s[10:0];
    wire [9:0] ncy = ncy_s < ylo ? ylo[9:0] : ncy_s > yhi ? yhi[9:0] : ncy_s[9:0];
    wire signed [12:0] ddx = $signed({2'b0, ncx}) - $signed({2'b0, cx});
    wire signed [11:0] ddy = $signed({2'b0, ncy}) - $signed({2'b0, cy});
    wire still = ddx >= -13'sd1 && ddx <= 13'sd1 && ddy >= -12'sd1 && ddy <= 12'sd1;   // match within +-1 px of the box
    always @(posedge pclk or negedge prst_n) begin
        if(!prst_n) begin
            pos<=4'd4; cx<=11'd640; cy<=10'd360; lock<=0; status<=3'd1; z_bcd<=0; d_bcd<=0; d_tenth<=0; results<=0;
            al_t<=0; ar_t<=0; bx<=11'd640; by<=10'd360; w_r<=0; w_c<=0; lane_d<=0; sc<=0; d<=0; dyo<=0;
            ld1<=0; ld2<=0; ld3<=0; rd1<=0; rd2<=0; rd3<=0; k1<=1; k2<=1; kst<=1; kcnt<=0; pcnt<=0; lp_done<=0;
            rom_a<=0; sad_a<=0; sad_wd<=0; sad_we<=0; t_a<=0; t_wa<=0; t_wd<=0; t_we<=0;
            apass<=0; acopy<=0; anc_ok<=0; cres<=0; crb<=0; ccb<=0; bmin<=255; bmax<=0;
            st<=S_ARML; gl_f<=0; gr_f<=0; dly<=0; tinit<=0; ax<=0; ay<=0; ox<=0; rb0<=7'd32; cb0<=7'd32;
            cu<=0; cv<=0; cub<=0; cvb<=0; fdu<=0; fdv<=0; fk<=0; fr0<=0; fc0<=0; frb<=0; fcb<=0; acc<=0; cbest<=0; fbest<=0; tmean<=0; wmean<=0;
            dmin<=0; di<=0; best<=16'hffff; best2<=16'hffff; sm<=0; sp<=0; lmin<=8'hff; lmax<=0; ml<=0; mr<=0; q<=0; frac<=0; num<=0; den<=0;
            stt<=0; bcnt<=0; bsh<=0; dsh<=0; draw<=0; h1<=0; h2<=0; dflt<=0; hv<=0; tn<=0; t00<=0; fxw<=0; fyw<=0; zk<=0; z0<=0; zc<=0; zfar<=0;
            zacc<=0; zfin<=0; zi<=0; hold_z<=0; hold_d<=0; hold_t<=0; hold_age<=4'd15; have_good<=0; hstable<=0;
            seed_p<=0; drop_p<=0; moved<=0;
            target_update<=0; target_good<=0; match_done<=0; match_good<=0; texture_min<=255; texture_max<=0;
            rank_score<=0; coarse_rank_best<=21'h1fffff; fine_rank_best<=21'h1fffff; coarse_distance<=0; best_coarse_distance<=127;
            fine_distance<=0; best_fine_distance<=255;
        end else begin
            // ---- KEY4: debounce, short press = next point / unlock, long press = lock
            k1<=key_n; k2<=k1;
            if(k2==kst) kcnt<=0;
            else if(kcnt==KDB && kstep) begin
                kst<=k2; kcnt<=0;
                if(k2 && !lp_done && enable) begin                // released after a short press
                    if(lock!=2'd0) begin lock<=2'd0; hv<=0; have_good<=0; end
                    else begin pos<=(pos==4'd8) ? 4'd0 : pos+4'd1; hv<=0; have_good<=0; end
                end
                if(k2) lp_done<=0;
            end else if(kstep) kcnt<=kcnt+1'b1;
            if(!kst) begin
                if(pcnt!=KLP) begin if(kstep) pcnt<=pcnt+1'b1; end
                else if(!lp_done && enable) begin lp_done<=1; lock<=2'd1; tinit<=1; hv<=0; have_good<=0; end
            end else pcnt<=0;
            ld1<=l_done_t; ld2<=ld1; ld3<=ld2; rd1<=r_done_t; rd2<=rd1; rd3<=rd2;
            if(ld2^ld3) gl_f<=1;
            if(rd2^rd3) gr_f<=1;
            sad_we<=0; t_we<=0;
            if(seed) seed_p<=1;                                   // seed_x / seed_y held by bottle_seed until the next result
            moved<=0; target_update<=0;
            if(drop) drop_p<=1;
            case(st)
                // ---- left window around the current centre
                S_ARML: begin
                    if(!run) dly<=0;
                    else if(dly==0) begin
                        if(seed_p) begin cx<=seed_x; cy<=seed_y; bx<=seed_x; by<=seed_y; lock<=2'd1; tinit<=1; seed_p<=0; drop_p<=0; end   // BOTTLE
                        else if(drop_p) begin lock<=2'd0; bx<=cx; by<=cy; drop_p<=0; end
                        else if(lock==2'd0) begin cx<=px9(pos); cy<=py9(pos); bx<=px9(pos); by<=py9(pos); end else begin bx<=cx; by<=cy; end
                        dly<=1;
                    end else if(dly==4'd9) begin
                        dly<=0; ax<=bx; ay<=by; ox<=bx[1:0];            // (bx - 48) mod 4 = bx mod 4
                        match_done<=0; match_good<=0;
                        if(rwin) begin ar_t<=~ar_t; gr_f<=0; end else begin al_t<=~al_t; gl_f<=0; end
                        st<=S_WAITL;
                    end else dly<=dly+4'd1;
                end
                S_WAITL: if(rwin ? gr_f : gl_f) begin
                    rb0<=7'd32; cb0<={5'd0, ox} + 7'd32; fcb<={5'd0, ox} + 7'd32; frb<=7'd32; apass<=0;
                    if(lock==2'd0) st<=S_ARMR;
                    else if(tinit) begin tinit<=0; sc<=0; texture_min<=255; texture_max<=0; acopy<=1; st<=S_COPY; end   // Z30: + anchor
                    else begin sc<=0; acc<=0; st<=S_TMEAN; end
                end
                // ---- tracking: template mean (fine score), coarse search (2 px steps, every 2nd template pixel), fine +-1
                S_TMEAN: begin
                    t_a<=sc[9:0]; sc<=sc+12'd1;
                    if(sc>=12'd2) acc<=acc_s;
                    if(sc==12'd1025) begin
                        tmean<=acc_s[17:10]; sc<=0; acc<=0;
                        if(apass) begin fk<=0; fbest<=20'hfffff; fine_rank_best<=21'h1fffff; best_fine_distance<=255; st<=S_FPRE; end   // Z30
                        else begin cu<=0; cv<=0; cbest<=20'hfffff; coarse_rank_best<=21'h1fffff; best_coarse_distance<=127; st<=S_CO; end
                    end
                end
                S_CO: begin                                      // candidate (cu, cv): block at (2cv, ox + 2cu); sample (2a, 2b)
                    t_a<={sc[7:4], 1'b0, sc[3:0], 1'b0};
                    w_r<={cv, 1'b0} + {2'b0, sc[7:4], 1'b0}; w_c<={5'd0, ox} + {cu, 1'b0} + {2'b0, sc[3:0], 1'b0};
                    lane_d<=w_c[1:0]; sc<=sc+12'd1;
                    if(sc>=12'd2) acc<=acc_s;
                    if(sc==12'd257) begin coarse_distance<=co_dist; st<=S_CO_RANK; end
                end
                S_CO_RANK: begin rank_score<={1'b0,acc}+{7'd0,coarse_distance,7'd0}; st<=S_COE; end   // + 0.25 gray / px per 2 px step
                S_COE: begin
                    if(rank_score < coarse_rank_best || (rank_score==coarse_rank_best && coarse_distance<best_coarse_distance)) begin
                        coarse_rank_best<=rank_score; cbest<=acc; cub<=cu; cvb<=cv; best_coarse_distance<=coarse_distance; end
                    sc<=0; acc<=0;
                    if(cu==6'd32) begin cu<=0; if(cv==6'd32) begin fk<=0; st<=S_FPRE; end else begin cv<=cv+6'd1; st<=S_CO; end end
                    else begin cu<=cu+6'd1; st<=S_CO; end
                    fbest<=20'hfffff; fine_rank_best<=21'h1fffff; best_fine_distance<=255;
                end
                S_FPRE: begin                                    // fine candidate fk = 3*dv + du (dv, du = -1..1 around the coarse best)
                    if(apass) begin                              // Z30: anchor, +-1 around the current-template result
                        fr0 <= (ar7 == 8'd0) ? 7'd0 : (ar7 - 8'd1 > 8'd64) ? 7'd64 : ar7[6:0] - 7'd1;
                        fc0 <= (ac7 <= {6'd0, ox}) ? {5'd0, ox} : (ac7 - 8'd1 > {6'd0, ox} + 8'd64) ? {5'd0, ox} + 7'd64 : ac7[6:0] - 7'd1;
                    end else begin
                    fr0 <= (fv7 == 7'd0) ? 7'd0 : (fv7 - 7'd1 > 7'd64) ? 7'd64 : fv7 - 7'd1;
                    fc0 <= (fu7 == 7'd0) ? {5'd0,ox} : (fu7 - 7'd1 > 7'd64) ? {5'd0,ox} + 7'd64 : {5'd0,ox} + fu7 - 7'd1;
                    end
                    sc<=0; acc<=0; st<=S_FA;
                end
                S_FA: begin                                      // fine candidate: window block mean
                    w_r<=fr0 + {2'b0, sc[9:5]}; w_c<=fc0 + {2'b0, sc[4:0]}; lane_d<=w_c[1:0]; sc<=sc+12'd1;
                    if(sc>=12'd2) acc<=acc_s;
                    if(sc==12'd1025) begin wmean<=acc_s[17:10]; sc<=0; acc<=0; st<=S_FB; end
                end
                S_FB: begin                                      // fine candidate: zero-mean SAD against the template
                    t_a<=sc[9:0]; w_r<=fr0 + {2'b0, sc[9:5]}; w_c<=fc0 + {2'b0, sc[4:0]}; lane_d<=w_c[1:0]; sc<=sc+12'd1;
                    if(sc>=12'd2) acc<=acc_s;
                    if(sc==12'd1025) begin fine_distance<=fi_dist; st<=S_FINE_RANK; end
                end
                S_FINE_RANK: begin rank_score<={1'b0,acc}+{5'd0,fine_distance,8'd0}; st<=S_FE; end
                S_FE: begin
                    if(rank_score < fine_rank_best || (rank_score==fine_rank_best && fine_distance<best_fine_distance)) begin
                        fine_rank_best<=rank_score; fbest<=acc; frb<=fr0; fcb<=fc0; best_fine_distance<=fine_distance; end
                    sc<=0; acc<=0;
                    if(fk==4'd8) st<=S_DEC; else begin fk<=fk+4'd1; st<=S_FPRE; end
                end
                S_DEC: if(apass) begin                           // Z30: anchor pass done
                    anc_ok <= fbest[19:10] < MAXRES;
                    if(!(fbest[19:10] < MAXRES)) begin frb<=crb; fcb<=ccb; end     // anchor lost: current-template position
                    sc<=0; bmin<=8'hff; bmax<=8'd0; st<=S_TEX;
                end else begin                                   // residual = mean |zero-mean difference|
                    match_done<=1; match_good<=fbest[19:10]<MAXRES;
                    if(fbest[19:10] < MAXRES && tm) begin         // Z30: TEMPLATE: anchor pass, texture, then decide (S_DEC2)
                        cres<=fbest[19:10]; crb<=frb; ccb<=fcb; apass<=1; sc<=0; acc<=0; st<=S_TMEAN;
                    end
                    else if(fbest[19:10] < MAXRES) begin
                        lock<=2'd1; rb0<=frb; cb0<=fcb; sc<=0;
                        if(!still) begin cx<=ncx; cy<=ncy; moved<=1; end               // dead band +-1 px
                        st <= (!still && fbest[19:10] >= REFRES) ? S_COPY : S_ARMR;   // Z17: TEMPLATE refreshes a degraded match too
                    end
                    else begin lock<=2'd2; rb0<=7'd32; cb0<={5'd0, ox} + 7'd32; st<=S_ARMR; end
                end
                S_TEX: begin                                     // Z30: texture (max - min) of the final block (frb, fcb)
                    w_r<=frb + {2'b0, sc[9:5]}; w_c<=fcb + {2'b0, sc[4:0]}; lane_d<=w_c[1:0]; sc<=sc+12'd1;
                    if(sc>=12'd2) begin if(wsel<bmin) bmin<=wsel; if(wsel>bmax) bmax<=wsel; end
                    if(sc==12'd1025) st<=S_DEC2;
                end
                S_DEC2: begin                                    // Z30: TEMPLATE decision
                    if(bmax - bmin < TEXMIN) begin lock<=2'd2; match_good<=0; rb0<=7'd32; cb0<={5'd0, ox} + 7'd32; st<=S_ARMR; end   // flat: LOST
                    else begin
                        lock<=2'd1; rb0<=frb; cb0<=fcb; sc<=0;
                        if(!still) begin cx<=ncx; cy<=ncy; moved<=1; end
                        st <= (!still && cres >= REFRES && anc_ok) ? S_COPY : S_ARMR;   // refresh only anchor-confirmed
                    end
                end
                S_COPY: begin                                    // template <- block (rb0, cb0) of this window
                    w_r<=rb0 + {2'b0, sc[9:5]}; w_c<=cb0 + {2'b0, sc[4:0]}; lane_d<=w_c[1:0]; sc<=sc+12'd1;
                    t_a<=sc[9:0];                                // Z30: read the anchor byte of the word written 2 clocks later
                    if(sc>=12'd2) begin if(wsel<texture_min) texture_min<=wsel; if(wsel>texture_max) texture_max<=wsel;
                                        t_we<=1; t_wa<=sc[9:0]-10'd2; t_wd<=acopy ? {wsel, wsel} : {t_q16[15:8], wsel}; end
                    if(sc==12'd1025) begin acopy<=0; st<=S_ARMR; end
                end
                // ---- right strip at the (new) centre
                S_ARMR: begin
                    if(track_only) begin                         // TEMPLATE 48 / BOTTLE: no stereo
                        target_update<=1; target_good<=match_done && match_good && lock==2'd1 && texture_max-texture_min>=8'd24;
                        results<=results+8'd1; st<=S_ARML; end
                    else if(dly==0) begin bx<=cx; by<=cy; dly<=1; end
                    else if(dly==4'd9) begin dly<=0; ar_t<=~ar_t; gr_f<=0; st<=S_WAITR; end
                    else dly<=dly+4'd1;
                end
                S_WAITR: if(gr_f) begin
                    st<=S_LPRE; sc<=0; acc<=0; lmin<=8'hff; lmax<=0;
                    tn <= ((cy < 10'd240) ? 4'd0 : (cy < 10'd480) ? 4'd5 : 4'd10) +
                          ((cx < 11'd500) ? 4'd0 : (cx < 11'd700) ? 4'd1 : (cx < 11'd900) ? 4'd2 : (cx < 11'd1100) ? 4'd3 : 4'd4);
                end
                // ---- stereo: left block statistics, then per d right mean + zero-mean SAD
                S_LPRE: begin
                    w_r<=rb0 + {2'b0, sc[9:5]}; w_c<=cb0 + {2'b0, sc[4:0]}; lane_d<=w_c[1:0]; sc<=sc+12'd1;
                    if(sc>=12'd2) begin acc<=acc_s; if(wsel<lmin) lmin<=wsel; if(wsel>lmax) lmax<=wsel; end
                    if(sc==12'd1025) begin ml<=acc_s[17:10]; d<=0; best<=16'hffff; dmin<=0; st<=S_ROM; end
                end
                S_ROM:  begin rom_a<={1'b0, base384} + {4'd0, d}; st<=S_ROMW; end
                S_ROMW: st<=S_ROMV;
                S_ROMV: begin dyo<=rom_q[19:16]; sc<=0; acc<=0; st<=S_P1; end
                S_P1: begin
                    sc<=sc+12'd1;
                    if(sc>=12'd2) acc<=acc_s;
                    if(sc==12'd1025) begin mr<=acc_s[17:10]; sc<=0; acc<=0; st<=S_P2; end
                end
                S_P2: begin                                      // left byte at (rb0 + j, cb0 + i) issued one cycle earlier
                    w_r<=rb0 + {2'b0, sc[9:5]}; w_c<=cb0 + {2'b0, sc[4:0]}; lane_d<=w_c[1:0];
                    sc<=sc+12'd1;
                    if(sc>=12'd2) acc<=acc_s;
                    if(sc==12'd1025) begin
                        sad_a<=d; sad_wd<=sad16; sad_we<=1;
                        if(sad16 < best) begin best<=sad16; dmin<=d; end
                        st<=S_STORE;
                    end
                end
                S_STORE: if(d==ND-1) begin st<=S_P3; sc<=0; sad_a<=0; best2<=16'hffff; sm<=16'hffff; sp<=16'hffff; end
                         else begin d<=d+9'd1; st<=S_ROM; end
                S_P3: begin
                    sc<=sc+12'd1; sad_a<=sc[8:0]+9'd1;
                    if(sc!=0) begin
                        if((sc[8:0]-9'd1)+9'd2 < dmin || (sc[8:0]-9'd1) > dmin+9'd2) begin if(sad_q<best2) best2<=sad_q; end
                        if((sc[8:0]-9'd1)+9'd1==dmin) sm<=sad_q;
                        if((sc[8:0]-9'd1)==dmin+9'd1) sp<=sad_q;
                    end
                    if(sc==ND) st<=S_P3E;
                end
                S_P3E: begin
                    q<=0;
                    num<=((sm>sp) ? {4'd0,sm-sp} : {4'd0,sp-sm}) * 20'd8 + (({4'd0,sm} + {4'd0,sp} - {4'd0,best} - {4'd0,best})>>1);
                    den<={4'd0,sm} + {4'd0,sp} - {4'd0,best} - {4'd0,best};
                    st<=S_DIV;
                end
                S_DIV: if(num>=den && den!=0 && q!=4'd8) begin num<=num-den; q<=q+4'd1; end
                       else begin
                           draw <= (sm>sp) ? {dmin,4'd0} + {9'd0,q} : {dmin,4'd0} - {9'd0,q};
                           stt<= (lmax-lmin < 8'd16) ? 3'd2 : (dmin==0 || dmin==ND-1) ? 3'd4 :
                                 ({best2,2'b0} < {2'b0,best} + {best,2'b0}) ? 3'd3 : 3'd0;
                           st<=S_MED;
                       end
                S_MED: begin                                     // median of the last 3, then 1/2 IIR within 3 px
                    if(stt==3'd0 || stt==3'd3) begin
                        if(hv!=0 && fdel < 14'sd48 && fdel > -14'sd48) dflt <= dflt + {fdel[13], fdel[13:2]};   // 1/4, explicit sign extension (dflt unsigned)
                        else dflt <= (hv==2'd2) ? med3 : draw;
                        hstable <= hd1 < 14'sd48 && hd1 > -14'sd48 && hd2 < 14'sd48 && hd2 > -14'sd48;
                        h2<=h1; h1<=draw; if(hv!=2'd2) hv<=hv+2'd1;
                    end else hv<=0;
                    st<=S_FILT;
                end
                S_FILT: begin                                    // bilinear cell and weights for (cx, cy)
                    {di, frac} <= dflt;
                    t00 <= ((cy < 10'd360) ? 4'd0 : 4'd5) + ((cx < 11'd600) ? 4'd0 : (cx < 11'd800) ? 4'd1 : (cx < 11'd1000) ? 4'd2 : 4'd3);
                    fxw <= ({11'd0, (cx < 11'd600) ? cx - 11'd400 : (cx < 11'd800) ? cx - 11'd600 : (cx < 11'd1000) ? cx - 11'd800 : cx - 11'd1000} * 22'd1311) >> 10;
                    fyw <= ({12'd0, (cy < 10'd360) ? cy - 10'd120 : cy - 10'd360} * 22'd1092) >> 10;
                    zk<=0; zacc<=0; zfar<=0; st<=S_ZC;
                end
                S_ZC: begin if(di>=9'd383) begin di<=9'd382; frac<=4'd15; end st<=S_ZR0; end
                S_ZR0: begin rom_a<=tk384 + {4'd0, di}; st<=S_ZR1; end          // Z[tk][di]
                S_ZR1: begin rom_a<=rom_a+13'd1; st<=S_ZR2; end                   // Z[tk][di+1]
                S_ZR2: begin z0<=rom_q[15:0]; st<=S_ZACC; end
                S_ZACC: begin                                    // interpolated table value (registered: timing)
                    if(z0==16'hffff || rom_q[15:0]==16'hffff) zfar<=1;
                    zi <= zint[17] ? 17'd0 : zint[16:0]; st<=S_ZMUL;
                end
                S_ZMUL: begin
                    zacc <= zacc + {17'd0, zi} * {17'd0, wk};
                    if(zk==2'd3) st<=S_ZEND; else begin zk<=zk+2'd1; st<=S_ZR0; end
                end
                S_ZEND: begin zfin <= |zacc[33:32] ? 16'hffff : zacc[31:16]; st<=S_BCD; bcnt<=0; end
                S_BCD: begin
                    if(bcnt==0) begin
                        if((stt==3'd0 || stt==3'd3) && (zfar || zfin>=16'd10000)) stt<=3'd5;
                        bsh<={18'd0, (zfin>=16'd10000) ? 14'd0 : zfin[13:0]}; dsh<={12'd0, di}; bcnt<=1;
                    end else if(bcnt<=4'd14) begin bsh<=dab(bsh[31:14], bsh[13:0]); if(bcnt<=4'd9) dsh<=dab3(dsh); bcnt<=bcnt+4'd1; end
                    else st<=S_PUB;
                end
                S_PUB: begin                                     // display hold: keep the last OK reading for <= 8 updates
                    if(stt==3'd0 && hv==2'd2 && hstable) begin                // ZOOM4: show only confirmed readings (3 agreeing)
                        status<=3'd0; z_bcd<=bsh[29:14]; d_bcd<=dsh[20:9]; d_tenth<=({4'd0,frac}*8'd5)>>3;
                        hold_z<=bsh[29:14]; hold_d<=dsh[20:9]; hold_t<=({4'd0,frac}*8'd5)>>3; hold_age<=0; have_good<=1'b1;
                    end else if(have_good && hold_age<4'd8) begin
                        status<=3'd0; z_bcd<=hold_z; d_bcd<=hold_d; d_tenth<=hold_t; hold_age<=hold_age+4'd1;
                    end else begin
                        status<=(stt==3'd0) ? 3'd1 : stt; z_bcd<=bsh[29:14]; d_bcd<=dsh[20:9]; d_tenth<=({4'd0,frac}*8'd5)>>3; have_good<=0;   // unconfirmed OK -> WAIT
                    end
                    results<=results+8'd1; st<=S_ARML;
                end
                default: st<=S_ARML;
            endcase
        end
    end
    function [31:0] dab(input [17:0] b, input [13:0] n);
        reg [17:0] t; integer k;
        begin t = b; for(k=0;k<4;k=k+1) if(t[4*k +: 4] >= 4'd5) t[4*k +: 4] = t[4*k +: 4] + 4'd3; dab = {t[16:0], n, 1'b0}; end
    endfunction
    function [20:0] dab3(input [20:0] v);                         // Z12: one double-dabble step, 3 BCD digits + 9 binary bits
        reg [11:0] t; integer k;
        begin t = v[20:9]; for(k=0;k<3;k=k+1) if(t[4*k +: 4] >= 4'd5) t[4*k +: 4] = t[4*k +: 4] + 4'd3; dab3 = {t[10:0], v[8:0], 1'b0}; end
    endfunction
endmodule
