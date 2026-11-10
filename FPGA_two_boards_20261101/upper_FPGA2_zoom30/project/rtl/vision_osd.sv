// CLAUDE MERGE (2026-10-27): one display stage for the mode-exclusive Vision Core functions (replaces range_overlay,
// depth_overlay and target_overlay: one pixel counter, one font lookup, one text engine whose strings depend on the mode).
//   45 RANGE / 48 TEMPLATE: 36x36 box (2 px) + centre mark at (cx, cy); text panel (16, 36), 12 chars x 2 lines
//        "Z=1.234 M" / "D=106.4 P5"  (RANGE)   "TEMPLATE" / "TRACK LOCK"  (TEMPLATE); colours as range_overlay
//   47 DEPTH: jet map of the 160x90 disparity (8x8 px cells), invalid dark grey (FULL) or camera (MIX, KEY4 toggles);
//        bottom strip y 672..703: "DEPTH FULL 1.04M", colour bar 560..1039, "FAR" / "NEAR"
//        CLAUDE ZOOM7 (2026-10-28): the number is the distance of the centre 3x3 depth cells (white box 632..655 x
//        352..375; it was the depth frame counter): S = sum, n = count of valid cells, Z_cm = 118870 n / (80 S + 112 n)
//        (RANGE centre table fit Z = 118870 / (d_px + 11.2) mm, d_px = 8 d), one restoring division per frame,
//        shown value moves only by >= 2 cm (or valid change); n < 3 -> "-.--M", > 9.99 m -> "FAR ".
//   49 COLOR / 50 MOTION: target box (32 px cells, 3 px frame); panel (16, 36) 16 chars "COLOR R    FOUND" / "MOTION      NONE"
// Latency 2 clocks for vs / hs / de / rgb alike (the depth RAM is read with the current pixel address).
// CLAUDE Z8C: KDEB = 1 -> key_n is the already debounced KEY4 level (range_meter kst, shared); the local debouncer is unused.
// CLAUDE Z10 GIMBAL: follow state bar (16..39 x 80..91 since Z14) in the follow-capable modes 38 / 48 / 49 / 50 (fshow): grey OFF,
// yellow armed / axes busy, green FOLLOW ON, red FAULT; TEMPLATE line 1 = board22 text (FOLLOW OFF / ON / WAIT,
// FAULT P<pitch code> Y<yaw code> C<control code>).
// CLAUDE Z10 AREA: one jet() for the depth cells and the colour bar (exclusive per pixel: strip1), one BCD converter for
// the DEPTH distance (cm) and the ZOOM factor (zn = zoom x 100, from zoom_ctrl); displayed values unchanged.
module vision_osd #(parameter integer DEBOUNCE=1500000, KDEB=0)(
    input wire clk, rst_n, key_n,
    input wire m45, m47, m48, m49, m50, m51, input wire [9:0] zn,      // m51: ZOOM text (x.xx), zn = zoom x 100
    input wire [10:0] cx, input wire [9:0] cy, input wire [3:0] pos, input wire [1:0] lock,
    input wire [2:0] status, input wire [15:0] z_bcd, input wire [11:0] d_bcd, input wire [3:0] d_tenth,
    output wire [7:0] rd_x, output wire [6:0] rd_y, input wire [5:0] rd_d, input wire [7:0] frames,
    input wire [1:0] csel, input wire found, input wire [5:0] bx0, bx1, input wire [4:0] by0, by1,
    input wire hs_i, vs_i, de_i, input wire [23:0] rgb_i,
    output reg hs_o, vs_o, de_o, output reg [23:0] rgb_o,
    input wire fshow, f_armed, f_ready, f_fault, input wire [7:0] f_pc, f_yc, input wire [3:0] f_cc
);
    `include "G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/modes/font5x7.vh"
    wire rng = m45 || m48, tgt = m49 || m50 || m51, en = rng || m47 || tgt;   // 51 uses the one-line panel
    reg [10:0] x; reg [9:0] y; reg pd;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin x<=0; y<=0; pd<=0; end
        else begin pd<=de_i; if(de_i) x<=x+1'b1; else x<=0; if(vs_i) y<=0; else if(pd&&!de_i) y<=y+1'b1; end
    end
    assign rd_x = x[10:3]; assign rd_y = y[9:3];
    // DEPTH: KEY4 FULL / MIX (the frame counter fbcd is no longer shown)
    (* async_reg="true" *) reg k1, k2; reg kst, mix; reg [20:0] kcnt; reg [7:0] fl; reg [11:0] fbcd;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin k1<=1; k2<=1; kst<=1; mix<=0; kcnt<=0; fl<=0; fbcd<=0; end
        else begin
            k1<=key_n; k2<=k1;
            if(KDEB) begin kst<=key_n; if(kst && !key_n && m47) mix<=~mix; end
            else if(k2==kst) kcnt<=0;
            else if(kcnt==DEBOUNCE[20:0]) begin kst<=k2; kcnt<=0; if(!k2 && m47) mix<=~mix; end
            else kcnt<=kcnt+21'd1;
            fl<=frames;
            if(fl!=frames) begin
                if(fbcd[3:0]!=4'd9) fbcd[3:0]<=fbcd[3:0]+4'd1;
                else begin fbcd[3:0]<=0; if(fbcd[7:4]!=4'd9) fbcd[7:4]<=fbcd[7:4]+4'd1;
                           else begin fbcd[7:4]<=0; fbcd[11:8]<=(fbcd[11:8]==4'd9) ? 4'd0 : fbcd[11:8]+4'd1; end end
            end
        end
    end
    function [7:0] dg(input [3:0] v); dg = 8'd48 + {4'd0, v}; endfunction
    function [7:0] hx(input [3:0] v); hx = v < 4'd10 ? 8'd48 + {4'd0, v} : 8'd55 + {4'd0, v}; endfunction
    // text: 16 chars per line, line ln of the panel
    function [127:0] line_str(input ln);
        begin
            if(m47) line_str = {"DEPTH ", mix ? "MIX  " : "FULL ", !zc_ok ? "-.--M" : zc_far ? "FAR  " : {dg(zc_h), ".", dg(zc_t), dg(zc_u), "M"}};
            else if(m51) line_str = {"ZOOM ", dg(zc_h), ".", dg(zc_t), dg(zc_u), "X      "};
            else if(tgt) line_str = {m50 ? "MOTION " : (csel == 2'd0) ? "COLOR R" : (csel == 2'd1) ? "COLOR G" : "COLOR B", "    ", found ? "FOUND" : " NONE"};
            else if(m48) line_str = !ln ? (f_fault ? {"FAULT P", hx(f_pc[7:4]), hx(f_pc[3:0]), " Y", hx(f_yc[7:4]), hx(f_yc[3:0]), " C", hx(f_cc)} :
                                           f_armed ? (f_ready ? "FOLLOW ON       " : "FOLLOW WAIT     ") : "FOLLOW OFF      ") : {"TRACK ", (lock==2'd1) ? "LOCK  " : (lock==2'd2) ? "LOST  " : "HOLD K", "    "};
            else if(!ln) begin
                if(status==3'd0 || status==3'd3) line_str = {"Z=", dg(z_bcd[15:12]), ".", dg(z_bcd[11:8]), dg(z_bcd[7:4]), dg(z_bcd[3:0]),
                                                             (status==3'd3) ? " M ? " : " M   ", "    "};
                else case(status)
                    3'd1: line_str = "Z=---- WAIT     ";
                    3'd2: line_str = "Z=---- TEX      ";
                    3'd4: line_str = "Z=---- NEAR     ";
                    default: line_str = "Z=---- FAR      ";
                endcase
            end else line_str = {"D=", dg(d_bcd[11:8]), dg(d_bcd[7:4]), dg(d_bcd[3:0]), ".", dg(d_tenth), " ",
                                 (lock==2'd1) ? "LOCK" : (lock==2'd2) ? "LOST" : {"P", dg(pos + 4'd1), "  "}, "    "};
        end
    endfunction
    wire [9:0] TY = m47 ? 10'd680 : 10'd36;
    wire [4:0] NC = (m47 || tgt || (m48 && f_fault)) ? 5'd16 : 5'd12;
    wire [10:0] tx = x - 11'd16; wire [9:0] ty = y - TY;
    wire ln = !m47 && !tgt && ty >= 10'd20;                       // second line (RANGE / TEMPLATE); Z20: COLOR readout removed
    wire [9:0] tyl = ln ? ty - 10'd20 : ty;
    wire inline_ = x >= 11'd16 && tx < {NC, 4'd0} && y >= TY && tyl < 10'd16 && (ty < 10'd36);
    wire [127:0] ls = line_str(ln);
    wire [3:0] kk = tx[7:4];
    wire [7:0] tch = ls[(15 - kk) * 8 +: 8];
    // DEPTH labels "FAR" at 504.., "NEAR" at 1048.. (cells aligned at 504 + 16 n)
    wire labr = m47 && y >= TY && ty < 10'd16 && ((x >= 11'd504 && x < 11'd552) || (x >= 11'd1048 && x < 11'd1112));
    wire [7:0] lch = (x < 11'd520) ? "F" : (x < 11'd536) ? "A" : (x < 11'd552) ? "R" : (x < 11'd1064) ? "N" : (x < 11'd1080) ? "E" : (x < 11'd1096) ? "A" : "R";
    wire [10:0] cc0 = inline_ ? tx : x - 11'd504;
    wire [2:0] col = cc0[3:1]; wire [3:0] row = tyl[4:1];
    wire [4:0] bits = font_row(inline_ ? tch : lch, row);
    wire ink = (inline_ || labr) && row < 4'd7 && col >= 3'd1 && col <= 3'd5 && bits[3'd5 - col];
    // panels
    wire strip = m47 && y >= 10'd672 && y < 10'd704;
    wire cbox = m47 && (((x == 11'd632 || x == 11'd655) && y >= 10'd352 && y <= 10'd375) ||
                        ((y == 10'd352 || y == 10'd375) && x >= 11'd632 && x <= 11'd655));   // centre 3x3 cells
    wire panel = !m47 && x >= 11'd12 && x < 11'd16 + {NC, 4'd0} + 11'd4 && y >= 10'd32 && y < (tgt ? 10'd56 : 10'd76);
    wire bar = m47 && x >= 11'd560 && x < 11'd1040 && y >= 10'd680 && y < 10'd696;
    wire [15:0] btm = {5'd0, x - 11'd560} * 16'd17;               // 0..479 -> 0..254
    // RANGE / TEMPLATE box + centre mark
    wire [10:0] rbx0 = cx - 11'd18, rbx1 = cx + 11'd18; wire [9:0] rby0 = cy - 10'd18, rby1 = cy + 10'd18;
    wire rin = x >= rbx0 && x < rbx1 && y >= rby0 && y < rby1;
    wire redge = rng && ((rin && (x < rbx0 + 2 || x + 2 >= rbx1 || y < rby0 + 2 || y + 2 >= rby1)) ||
                         (x == cx && y + 4 >= cy && y < cy + 5) || (y == cy && x + 4 >= cx && x < cx + 5));
    // COLOR / MOTION box
    wire [10:0] tx0 = {bx0, 5'd0}, tx1 = {bx1, 5'd0} + 11'd31; wire [9:0] ty0 = {by0, 5'd0}, ty1 = {by1, 5'd0} + 10'd31;
    wire tin = found && x >= tx0 && x <= tx1 && y >= ty0 && y <= ty1;
    wire tedge = (m49 || m50) && tin && (x < tx0 + 3 || x + 3 > tx1 || y < ty0 + 3 || y + 3 > ty1);
    // CLAUDE Z20 (area): the Z17 COLOR centre-pixel readout and its cross are removed (thresholds set from the board readout)
    // colours
    wire [23:0] mark = (status == 3'd0) ? 24'h00ff40 : (status == 3'd3) ? 24'hffff00 : 24'hff8000;
    wire [23:0] rboxc = (lock == 2'd1) ? 24'h00ffff : (lock == 2'd2) ? 24'hff2020 : m48 ? 24'hffffff : mark;
    wire [23:0] tboxc = m50 ? 24'hff40ff : (csel == 2'd0) ? 24'h00ff40 : (csel == 2'd1) ? 24'hff4040 : 24'hffff00;
    wire [23:0] inkc = m51 ? 24'hffffff : tgt ? (found ? tboxc : 24'hffffff) : (rng && !ln) ? mark : 24'hffffff;
    function [7:0] clamp8(input signed [11:0] v); clamp8 = v[11] ? 8'd0 : (v > 12'sd255) ? 8'd255 : v[7:0]; endfunction
    function [23:0] jet(input [7:0] t);
        reg signed [11:0] t4, r1, r2, g1, g2, b1, b2;
        begin
            t4 = $signed({2'd0, t, 2'd0});
            r1 = t4 - 12'sd384; r2 = 12'sd1152 - t4; g1 = t4 - 12'sd128; g2 = 12'sd896 - t4; b1 = t4 + 12'sd128; b2 = 12'sd640 - t4;
            jet = {clamp8((r1 < r2) ? r1 : r2), clamp8((g1 < g2) ? g1 : g2), clamp8((b1 < b2) ? b1 : b2)};
        end
    endfunction
    // stage 1
    reg hs1, vs1, de1, en1, d47, strip1, bar1, panel1, ink1, edge1, cbox1; reg [23:0] rgb1, ovc1; reg [7:0] bt1;
    reg gbar1; reg [23:0] gcol1;
    wire gbar = fshow && x >= 11'd16 && x < 11'd40 && y >= 10'd80 && y < 10'd92;   // Z14: below the panels (y 8..19 hid the mode name)
    wire [23:0] gcol = f_fault ? 24'hff2020 : f_armed ? (f_ready ? 24'h00ff40 : 24'hffc000) : 24'h808080;
    reg [10:0] x1; reg [9:0] y1;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin hs1<=0; vs1<=0; de1<=0; en1<=0; d47<=0; strip1<=0; bar1<=0; panel1<=0; ink1<=0; edge1<=0; cbox1<=0; rgb1<=0; ovc1<=0; bt1<=0; x1<=0; y1<=0; gbar1<=0; gcol1<=0; end
        else begin
            hs1<=hs_i; vs1<=vs_i; de1<=de_i; rgb1<=rgb_i; en1<=en && de_i; d47<=m47;
            strip1<=strip; bar1<=bar; panel1<=panel; ink1<=ink; edge1<=redge || tedge; bt1<=btm[12:5]; cbox1<=cbox; x1<=x; y1<=y;
            ovc1 <= redge ? rboxc : tedge ? tboxc : inkc;
            gbar1 <= gbar && de_i; gcol1 <= gcol;
        end
    end
    // stage 2 (rd_d belongs to the stage-1 pixel)
    wire dval = rd_d != 6'd63;
    wire [9:0] t10 = {4'd0, rd_d} * 10'd21;
    wire [23:0] dc = jet(strip1 ? bt1 : t10[9:2]);                // shared: colour bar (strip) / depth cell
    wire [23:0] mixc = {1'b0, rgb1[23:17], 1'b0, rgb1[15:9], 1'b0, rgb1[7:1]} + {1'b0, dc[23:17], 1'b0, dc[15:9], 1'b0, dc[7:1]};
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin hs_o<=0; vs_o<=0; de_o<=0; rgb_o<=0; end
        else begin
            hs_o<=hs1; vs_o<=vs1; de_o<=de1;
            if(gbar1) rgb_o<=gcol1;
            else if(!en1) rgb_o<=rgb1;
            else if(d47) begin
                if(strip1) rgb_o<= bar1 ? dc : ink1 ? 24'hffffff : 24'h000000;
                else if(cbox1) rgb_o<= 24'hffffff;
                else if(dval) rgb_o<= mix ? mixc : dc;
                else rgb_o<= mix ? rgb1 : 24'h181818;
            end
            else if(edge1) rgb_o<=ovc1;
            else if(panel1) rgb_o<= ink1 ? ovc1 : 24'h000000;
            else rgb_o<=rgb1;
        end
    end
    // centre distance (depth mode): accumulate the 3x3 centre cells (sample at cell pixel (3, 3), rd_d of the stage-1 pixel)
    wire csmp = d47 && de1 && x1[2:0] == 3'd3 && y1[2:0] == 3'd3 && x1[10:3] >= 8'd79 && x1[10:3] <= 8'd81 &&
                y1[9:3] >= 7'd44 && y1[9:3] <= 7'd46;
    reg [8:0] cs_acc, cs_l; reg [3:0] cn_acc, cn_l; reg vsq; reg [4:0] dv_c; reg [20:0] dv_r, dv_q; reg [15:0] dv_d; reg dv_busy;
    reg [9:0] zc; reg zc_ok, zc_far; reg [3:0] zc_h, zc_t, zc_u;
    function [20:0] knum(input [3:0] n); case(n) 4'd3: knum=21'd356610; 4'd4: knum=21'd475480; 4'd5: knum=21'd594350;
        4'd6: knum=21'd713220; 4'd7: knum=21'd832090; 4'd8: knum=21'd950960; 4'd9: knum=21'd1069830; default: knum=21'd0; endcase endfunction
    wire [20:0] dv_sh = {dv_r[19:0], dv_q[20]};
    wire [9:0] zq_n = (dv_q[20:10] != 11'd0) ? 10'd1000 : dv_q[9:0];        // quotient (cm), >= 1000 -> FAR
    wire [9:0] zdiff = (zq_n > zc) ? zq_n - zc : zc - zq_n;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin cs_acc<=0; cn_acc<=0; cs_l<=0; cn_l<=0; vsq<=0; dv_c<=0; dv_r<=0; dv_q<=0; dv_d<=0; dv_busy<=0;
                         zc<=0; zc_ok<=0; zc_far<=0; end
        else begin
            vsq <= vs_i;
            if(vs_i && !vsq) begin                                        // frame end: latch, start Z = knum(n) / (80 S + 112 n)
                cs_l<=cs_acc; cn_l<=cn_acc; cs_acc<=0; cn_acc<=0;
                dv_q<=knum(cn_acc); dv_r<=0; dv_d<={1'b0, cs_acc, 6'd0} + {3'd0, cs_acc, 4'd0} + {5'd0, cn_acc, 7'd0} - {8'd0, cn_acc, 4'd0};
                dv_c<=5'd21; dv_busy<=(cn_acc >= 4'd3);
                if(cn_acc < 4'd3) zc_ok<=0;
            end else if(csmp && dval) begin cs_acc<=cs_acc+{3'd0, rd_d}; cn_acc<=cn_acc+4'd1; end
            if(dv_busy) begin                                             // restoring division, quotient bits into dv_q
                if(dv_sh >= {5'd0, dv_d}) begin dv_r<=dv_sh - {5'd0, dv_d}; dv_q<={dv_q[19:0], 1'b1}; end
                else begin dv_r<=dv_sh; dv_q<={dv_q[19:0], 1'b0}; end
                dv_c<=dv_c-5'd1;
                if(dv_c==5'd1) dv_busy<=0;
            end else if(dv_c==5'd0 && cn_l >= 4'd3 && (!zc_ok || zdiff >= 10'd2)) begin   // shown value: >= 2 cm hysteresis
                zc<=zq_n; zc_ok<=1; zc_far<=(zq_n >= 10'd1000);
            end
        end
    end
    reg [9:0] bn; always @(posedge clk) bn <= m51 ? zn : zc;      // shared BCD input (ZOOM / DEPTH)
    always @(*) begin zc_h = bn / 10'd100; zc_t = (bn - zc_h * 10'd100) / 10'd10; zc_u = bn - zc_h * 10'd100 - zc_t * 10'd10; end
endmodule
