// CLAUDE MERGE Vision Core (2026-10-27): one set of image buffers for the mode-exclusive vision functions.
//   L image RAM: 4 byte lanes x 4096 x 8 (8 ERAM).  write port camera clock, read port pixel clock.
//     DEPTH 47 / MOTION 50 : 160x90 binned left image, byte address a -> lane a[1:0], word a[13:2]
//     RANGE 45 / TEMPLATE 48: 96 x 104 px left window, 4 pixels per beat in the 4 lanes (word {row, beat})
//   R image RAM: 16384 x 8 (8 ERAM).  write port rx clock, port B pixel clock (read; MOTION also writes).
//     DEPTH 47: 160x90 binned right image      RANGE 45: 40 x 409 right strip      MOTION 50: previous left frame
// Mode bits are pixel-clock levels; their copies in the camera / rx clocks (2 FF) select the write-port owner. A mode change
// may leave one corrupted frame in a buffer (each function restarts its capture on entry).
// Also here: depth_map (SGM v2), range_meter (RANGE / TEMPLATE tracking), motion_cells, color_cells, blob_engine (49 / 50).
// CLAUDE BOTTLE (2026-10-28): mode 38 KEY4 = ALL / BOTTLE. In BOTTLE (bm) bottle_seed seeds range_meter from the YOLO
// bottle box and range_meter tracks a 32x32 template in the received image: its 96 x 104 window goes to the R image RAM
// (write rx clock at {row, column}, read waddr14), the L image RAM is not used.
module vision_core #(parameter GRID_FILE="range_grid.hex", parameter integer DEBOUNCE=1500000, LONGPRESS=44000000, MS_TICK=0)(
    input wire cam_clk, cam_rst_n, l_valid, l_sof, l_eol, input wire [95:0] l_data,
    input wire rx_clk, rx_rst, r_valid, input wire [31:0] r_addr, input wire [15:0] r_data,
    input wire pclk, prst_n, key_n,
    output wire key_deb,                                          // CLAUDE Z8C: debounced KEY4 level (range_meter)
    input wire m45, m47, m48, m49, m50,                            // active mode (pixel clock, one-hot or none)
    input wire hs_i, vs_i, de_i, input wire [23:0] rgb_i,          // displayed camera stream (COLOR 49 input)
    // DEPTH display
    input wire [7:0] dep_rx, input wire [6:0] dep_ry, output wire [5:0] dep_d, output wire [7:0] dep_frames,
    // RANGE / TEMPLATE
    output wire [3:0] rng_pos, output wire [10:0] rng_cx, output wire [9:0] rng_cy, output wire [1:0] rng_lock,
    output wire [2:0] rng_status, output wire [15:0] rng_z, output wire [11:0] rng_d, output wire [3:0] rng_dt, output wire [7:0] rng_n,
    // COLOR / MOTION target
    output wire tgt_found, output wire [5:0] tgt_bx0, tgt_bx1, output wire [4:0] tgt_by0, tgt_by1, output wire [1:0] col_sel,
    // BOTTLE (mode 38): received YOLO results (pixel clock) in, tracked bottle box out
    input wire m38, input wire [319:0] yolo_tracks, input wire [31:0] yolo_id, input wire yolo_recent,
    input wire [7:0] yolo_vid,                                    // CLAUDE Z9: displayed remote frame id (y5cd video id)
    output wire bt_mode, output wire [79:0] bt_entry, output wire [2:0] bt_status,
    // CLAUDE Z10 GIMBAL: follow target of the active tracking mode (TEMPLATE 48, BOTTLE 38, COLOR 49, MOTION 50)
    output wire f_mode, output reg f_update, output reg f_good, output reg [15:0] f_fid, output reg [10:0] f_cx, output reg [9:0] f_cy,
    input wire ms                                                 // CLAUDE Z11: shared 1 ms tick (KEY4 timers, MS_TICK = 1)
);
    // ---------------- mode copies in the write clocks
    (* async_reg="true" *) reg cl1, cl2, cd1, cd2; (* async_reg="true" *) reg rs1, rs2, rd1, rd2;
    always @(posedge cam_clk) begin cl1 <= m45 || m48; cl2 <= cl1; cd1 <= m47 || m50; cd2 <= cd1; end
    wire bm = m38 && bt_mode;                                    // BOTTLE sub-mode active
    (* async_reg="true" *) reg rw1, rw2;
    always @(posedge rx_clk) begin rs1 <= m45; rs2 <= rs1; rd1 <= m47; rd2 <= rd1; rw1 <= bm; rw2 <= rw1; end

    // ---------------- clients
    wire d_lwe, d_rwe; wire [13:0] d_lwa, d_rwa, d_ra; wire [7:0] d_lwd, d_rwd; wire mot_go, mot_done;
    wire g_we; wire [11:0] g_wa, g_ra; wire [31:0] g_wd;            // range window
    wire s_we; wire [13:0] s_wa, s_ra; wire [7:0] s_wd;             // range strip
    wire [13:0] m_a; wire m_rwe; wire [7:0] m_rwd;                  // motion
    wire [7:0] lq0, lq1, lq2, lq3, rq; reg [1:0] lsel;
    wire [13:0] g_ra14; wire bseed, bdrop, rng_kst, rng_moved; wire [10:0] bsx; wire [9:0] bsy;
    wire r_tu, r_tg;                                              // CLAUDE Z10: range_meter tracking result / good

    // ---------------- L image RAM (4 lanes)
    wire use_rng_l = cl2;
    wire [11:0] la_a = use_rng_l ? g_wa : d_lwa[13:2];
    wire [11:0] la_b = (m45 || m48) ? g_ra : m50 ? m_a[13:2] : d_ra[13:2];
    always @(posedge pclk) lsel <= m50 ? m_a[1:0] : d_ra[1:0];
    wire [7:0] lq_sel = (lsel == 2'd0) ? lq0 : (lsel == 2'd1) ? lq1 : (lsel == 2'd2) ? lq2 : lq3;
    genvar k;
    generate for(k=0; k<4; k=k+1) begin : g_l
        wire we = use_rng_l ? g_we : (cd2 && d_lwe && d_lwa[1:0] == k);
        wire [7:0] di = use_rng_l ? g_wd[31-8*k -: 8] : d_lwd;
        wire [7:0] q;
        PH1P_LOGIC_ERAM #(.DATA_WIDTH_A(8),.DATA_WIDTH_B(8),.ADDR_WIDTH_A(12),.ADDR_WIDTH_B(12),.DATA_DEPTH_A(4096),.DATA_DEPTH_B(4096),
          .MODE("DP"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),.WRITEMODE_A("READBEFOREWRITE"),.WRITEMODE_B("READBEFOREWRITE"),
          .CLKMODE("ASYNC"),.SSROVERCE("DISABLE"),.OREGSET_A("RESET"),.OREGSET_B("RESET"),.RESETMODE_A("ASYNC"),.RESETMODE_B("ASYNC"),
          .ASYNC_RESET_RELEASE_A("ASYNC"),.ASYNC_RESET_RELEASE_B("ASYNC"),.ECC_ENCODE("DISABLE"),.ECC_DECODE("DISABLE"),
          .IMPLEMENT("20K(FAST)"),.INIT_FILE("NONE"),.FILL_ALL("NONE")) lram(
          .dia(di),.addra(la_a),.cea(1'b1),.ocea(1'b0),.clka(cam_clk),.wea(we),.rsta(1'b0),.bea(1'b0),
          .dib(8'd0),.addrb(la_b),.ceb(1'b1),.oceb(1'b0),.clkb(pclk),.web(1'b0),.rstb(1'b0),.beb(1'b0),
          .ecc_sbiterrinj(1'b0),.ecc_dbiterrinj(1'b0),.doa(),.dob(q),.ecc_sbiterr(),.ecc_dbiterr());
    end endgenerate
    assign lq0 = g_l[0].q; assign lq1 = g_l[1].q; assign lq2 = g_l[2].q; assign lq3 = g_l[3].q;

    // ---------------- R image RAM
    wire ra_we = (rs2 || rw2) ? s_we : (rd2 && d_rwe);
    wire [13:0] ra_a = (rs2 || rw2) ? s_wa : d_rwa;
    wire [7:0] ra_d = (rs2 || rw2) ? s_wd : d_rwd;
    wire [13:0] rb_a = bm ? g_ra14 : m45 ? s_ra : m50 ? m_a : d_ra;
    PH1P_LOGIC_ERAM #(.DATA_WIDTH_A(8),.DATA_WIDTH_B(8),.ADDR_WIDTH_A(14),.ADDR_WIDTH_B(14),.DATA_DEPTH_A(16384),.DATA_DEPTH_B(16384),
      .MODE("DP"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),.WRITEMODE_A("READBEFOREWRITE"),.WRITEMODE_B("READBEFOREWRITE"),
      .CLKMODE("ASYNC"),.SSROVERCE("DISABLE"),.OREGSET_A("RESET"),.OREGSET_B("RESET"),.RESETMODE_A("ASYNC"),.RESETMODE_B("ASYNC"),
      .ASYNC_RESET_RELEASE_A("ASYNC"),.ASYNC_RESET_RELEASE_B("ASYNC"),.ECC_ENCODE("DISABLE"),.ECC_DECODE("DISABLE"),
      .IMPLEMENT("20K(FAST)"),.INIT_FILE("NONE"),.FILL_ALL("NONE")) rram(
      .dia(ra_d),.addra(ra_a),.cea(1'b1),.ocea(1'b0),.clka(rx_clk),.wea(ra_we),.rsta(1'b0),.bea(1'b0),
      .dib(m_rwd),.addrb(rb_a),.ceb(1'b1),.oceb(1'b0),.clkb(pclk),.web(m50 && m_rwe),.rstb(1'b0),.beb(1'b0),
      .ecc_sbiterrinj(1'b0),.ecc_dbiterrinj(1'b0),.doa(),.dob(rq),.ecc_sbiterr(),.ecc_dbiterr());

    // ---------------- DEPTH 47 / MOTION 50 capture + SGM
    depth_map u_depth(
      .cam_clk(cam_clk),.cam_rst_n(cam_rst_n),.l_valid(l_valid),.l_sof(l_sof),.l_eol(l_eol),.l_data(l_data),
      .rx_clk(rx_clk),.rx_rst(rx_rst),.r_valid(r_valid),.r_addr(r_addr),.r_data(r_data),.pclk(pclk),.prst_n(prst_n),
      .rd_x(dep_rx),.rd_y(dep_ry),.rd_d(dep_d),.frames(dep_frames),.en_depth(m47),.en_motion(m50),.mot_done(mot_done),.mot_go(mot_go),
      .l_we(d_lwe),.l_wa(d_lwa),.l_wd(d_lwd),.r_we(d_rwe),.r_wa(d_rwa),.r_wd(d_rwd),.lra(d_ra),.lq(lq_sel),.rq(rq));

    // ---------------- RANGE 45 / TEMPLATE 48
    range_meter #(.GRID_FILE(GRID_FILE),.DEBOUNCE(DEBOUNCE),.LONGPRESS(LONGPRESS),.MS_TICK(MS_TICK)) u_range(
      .cam_clk(cam_clk),.cam_rst_n(cam_rst_n),.l_valid(l_valid),.l_sof(l_sof),.l_eol(l_eol),.l_data(l_data),
      .rx_clk(rx_clk),.rx_rst(rx_rst),.r_valid(r_valid),.r_addr(r_addr),.r_data(r_data),
      .pclk(pclk),.prst_n(prst_n),.enable(m45 || m48),.key_n(key_n),.run(m45 || m48 || bm),.track_only(m48 || bm),
      .rwin(bm),.rwin_rx(rw2),.seed(bseed),.seed_x(bsx),.seed_y(bsy),.drop(bdrop),.waddr14(g_ra14),.kst_o(rng_kst),.moved(rng_moved),
      .w_we(g_we),.w_wa(g_wa),.w_wd(g_wd),.waddr(g_ra),.wq0(lq0),.wq1(lq1),.wq2(lq2),.wq3(lq3),
      .s_we(s_we),.s_wa(s_wa),.s_wd(s_wd),.raddr(s_ra),.rq(rq),
      .pos(rng_pos),.cx(rng_cx),.cy(rng_cy),.lock(rng_lock),.status(rng_status),.z_bcd(rng_z),.d_bcd(rng_d),.d_tenth(rng_dt),.results(rng_n),
      .target_update(r_tu),.target_good(r_tg),.ms(ms));

    // ---------------- BOTTLE: YOLO seed / box
    assign key_deb = rng_kst;
    bottle_seed u_bottle(.clk(pclk),.rst_n(prst_n),.en(m38),.kst(rng_kst),.vs(vs_i),.upd(rng_n[0]),.vid(yolo_vid),
      .tracks(yolo_tracks),.rid(yolo_id),.recent(yolo_recent),.cx(rng_cx),.cy(rng_cy),.lock(rng_lock),
      .bmode(bt_mode),.seed(bseed),.sx(bsx),.sy(bsy),.drop(bdrop),.entry(bt_entry),.status(bt_status));

    // ---------------- COLOR 49 / MOTION 50 -> shared blob engine
    wire c_inc, c_bstart, m_inc, m_bstart, b_busy; wire [9:0] c_cell, m_cell; wire [5:0] b_x0, b_x1; wire [4:0] b_y0, b_y1;
    motion_cells u_motion(.clk(pclk),.rst_n(prst_n),.en(m50),.go(mot_go),.done(mot_done),.ma(m_a),.lq(lq_sel),.rq(rq),
      .r_we(m_rwe),.r_wd(m_rwd),.inc(m_inc),.inc_cell(m_cell),.bstart(m_bstart),.bbusy(b_busy),.valid_hist());
    color_cells #(.DEBOUNCE(DEBOUNCE),.KDEB(1)) u_color(.clk(pclk),.rst_n(prst_n),.en(m49),.key_n(rng_kst),.hs_i(hs_i),.vs_i(vs_i),.de_i(de_i),.rgb_i(rgb_i),
      .inc(c_inc),.inc_cell(c_cell),.bstart(c_bstart),.csel(col_sel));
    blob_engine u_blob(.clk(pclk),.rst_n(prst_n),.inc(m49 ? c_inc : m_inc),.inc_cell(m49 ? c_cell : m_cell),
      .start(m49 ? c_bstart : m_bstart),.th(m49 ? 10'd96 : 10'd6),.gap(m49 ? 2'd1 : 2'd2),.busy(b_busy),.found(tgt_found),
      .bx0(b_x0),.bx1(b_x1),.by0(b_y0),.by1(b_y1),.runs());
    // CLAUDE Z18 (board: MOTION box too large and jumping): MOTION blob cells need >= 6 of 16 bin hits (was 3), joined over
    // <= 1 empty cell (gap 2, was 3); its shown box edge = mean of this and the previous result (rounded towards this one:
    // half the jitter, half a result of lag), a new target or a jump >= 6 cells snaps. One shared adder, edges x0, x1, y0,
    // y1 in 4 clocks after the blob search. COLOR keeps the raw box.
    reg [5:0] mbs [0:3]; reg [5:0] mo0, mo1; reg [4:0] mo2, mo3; reg [2:0] mk; reg mhave, mbq;
    wire [5:0] mt = (mk[1:0]==2'd0) ? b_x0 : (mk[1:0]==2'd1) ? b_x1 : (mk[1:0]==2'd2) ? {1'b0, b_y0} : {1'b0, b_y1};
    wire [5:0] mprev = mbs[mk[1:0]];
    wire signed [6:0] md = $signed({1'b0, mt}) - $signed({1'b0, mprev});
    wire msnap = !mhave || md >= 7'sd6 || md <= -7'sd6;
    wire [6:0] msum = {1'b0, mt} + {1'b0, mprev} + {6'd0, mt > mprev};
    wire [5:0] mnew = msnap ? mt : msum[6:1];
    always @(posedge pclk) if(!mk[2]) mbs[mk[1:0]] <= mt;
    always @(posedge pclk or negedge prst_n) begin
        if(!prst_n) begin mk<=3'd4; mhave<=0; mbq<=0; mo0<=0; mo1<=0; mo2<=0; mo3<=0; end
        else begin
            mbq <= b_busy;
            if(!m50) begin mhave<=0; mk<=3'd4; end
            else if(mbq && !b_busy) begin if(tgt_found) mk<=3'd0; else mhave<=0; end
            else if(!mk[2]) begin
                case(mk[1:0]) 2'd0: mo0<=mnew; 2'd1: mo1<=mnew; 2'd2: mo2<=mnew[4:0]; default: mo3<=mnew[4:0]; endcase
                if(mk==3'd3) mhave<=1;
                mk <= mk + 3'd1;
            end
        end
    end
    assign tgt_bx0 = m50 ? mo0 : b_x0; assign tgt_bx1 = m50 ? mo1 : b_x1; assign tgt_by0 = m50 ? mo2 : b_y0; assign tgt_by1 = m50 ? mo3 : b_y1;

    // ---------------- CLAUDE Z10 GIMBAL: follow target. Mode condition as board22 for TEMPLATE (KEY4 released, LOCK); BOTTLE
    // tracking with LOCK; COLOR / MOTION while the mode is active. One update per tracking result (range_meter) or per blob
    // search (busy falling edge), centre of the blob cells; a lost / missing target is a bad result (gimbal stops).
    reg bbq;
    // CLAUDE Z14 (user 2026-10-31): MOTION 50 no longer drives the gimbal (it also detects the operator's hand); COLOR 49 does.
    assign f_mode = (m48 && key_deb && rng_lock == 2'd1) || (bm && rng_lock == 2'd1) || m49;
    always @(posedge pclk or negedge prst_n) begin
        if(!prst_n) begin bbq<=0; f_update<=0; f_good<=0; f_fid<=0; f_cx<=11'd640; f_cy<=10'd360; end
        else begin
            bbq <= b_busy; f_update <= 0;
            if((m48 || bm) && r_tu) begin
                f_update<=1; f_good<=r_tg; f_fid<=f_fid+16'd1; f_cx<=rng_cx; f_cy<=rng_cy;
            end else if(m49 && bbq && !b_busy) begin
                f_update<=1; f_good<=tgt_found; f_fid<=f_fid+16'd1;
                f_cx <= {({1'b0, tgt_bx0} + {1'b0, tgt_bx1}), 4'd15}; f_cy <= {({1'b0, tgt_by0} + {1'b0, tgt_by1}), 4'd15};
            end
        end
    end
endmodule
