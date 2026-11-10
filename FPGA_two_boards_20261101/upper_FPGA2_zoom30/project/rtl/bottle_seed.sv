// CLAUDE BOTTLE (2026-10-28): YOLO-seeded bottle tracking in mode 38 (YOLO ONLY), KEY4 short press toggles ALL / BOTTLE.
// YOLO (FPGA-1) delivers a few delayed results per second; between them range_meter (track_only, remote window) follows a
// 32x32 template of the received image every frame. This block decides when the template is (re)seeded and draws the box:
//   new result with a bottle (class 3, observed, first = highest confidence; boxes are in full 1280x720 remote coordinates):
//     box size <- YOLO box. Not tracking or tracker LOST: seed at the YOLO box centre.
//   result without a bottle: MISS_MAX + 1 consecutive (or one while LOST) -> track dropped.  no new result for AGE_MAX
//   frames -> dropped.
// Output: one track entry in the y5cd_tracks1 format (x1, y1, x2, y2, Q15, class 3, ID 1, valid, observed) centred on the
// tracker position, and the overlay tracking status (0 TRAK, 4 LOST, 5 WAIT).
// Z8B (z8a did not route: congestion): all arithmetic runs on ONE 13-bit adder, sequenced; the found YOLO entry is read in
// place (slot kf) instead of copied; KEY4 uses range_meter's debounced level (kst); the seed position is the clamped seed
// centre (range_meter latches it with the seed pulse).
// Z9 (board: the box followed the bottle but sat off it, z8 corrected only after 45 still frames): every result corrects
// the position, delay-compensated. Each tracker update stores its position with the displayed remote frame id (vid) in a
// 16-entry history; a result of source frame rid reads the tracker position of THAT frame, e = YOLO centre - history, and
// when |e| > FAR on an axis the tracker is reseeded at (current position + e): the drift seen at the YOLO frame is removed
// from the current position, also while the bottle moves. No history for rid (just seeded, frame not seen): the tracker
// keeps its position (size only). History is cleared at every seed and the first update after a seed is skipped (it may
// still be of the old point).
// Z10 (board: box stayed ~1/3 box width left of a transparent cup for seconds, i.e. no correction ran): history 16 -> 32
// tracker updates (YOLO latency may exceed 16 frames), lookup by the latched result id (rid_q, stable during the job), and
// a result with no history still corrects when |YOLO centre - current position| > FARN on an axis (not delay-compensated,
// hence the wider threshold). status 1 (SRC?) = tracking, last result had no history (board diagnostic).
// History survives correction seeds (with latency > result period every seed used to wipe the entries the next result
// needs): each correction shift t is added to an offset (offx / offy), entries are stored as position - offset and read
// as entry + offset, i.e. older positions are moved with the track. Only a fresh seed (not tracking / LOST) clears it.
// CLAUDE Z17 (board: BOTTLE box not smooth, jumps with each tracker update / correction): the drawn box centre (dx, dy)
// follows the tracker position with a per-frame half step, d += (c - d) / 2, snapping when |c - d| > 48 (seed / jump);
// two extra frame-job steps per axis on the same shared adder. Tracking and corrections unchanged.
// CLAUDE Z19 (board, lower board PE16: YOLO latency 1.88 s = ~113 remote frames at 60 fps, one result per 2.05 s; the box
// fell back 1-2 s, the template was reseeded on background, lock lost, gimbal stopped): the history held 32 frames (vid[4:0]),
// so no result found its source frame and every result took the no-history correction to the 1.9 s old YOLO position.
// History now 128 entries of 2 frames (vid[7:1], 256 frames = 4.3 s); validity by a seed generation tag (gen, +1 per fresh
// seed) instead of the 32 valid bits. A result without history no longer moves a tracking (locked) track: it only takes
// the box size; LOST / not tracking still seeds at the YOLO centre.
// Z19 extrapolation: with 1.9 s latency a moving bottle is far from its YOLO box (the template was taken on background and
// the tracker then held still background, LOCK). A fresh seed, or a correction larger than FARX (tracker evidently not on
// the bottle), seeds at YOLO centre + (this - previous YOLO centre): latency ~ result period (113 / 123 frames), i.e.
// linear extrapolation by one period. Needs two consecutive bottle results and |step| < XMAX per axis; such a seed starts a
// new history generation. Two extra steps per axis on the shared adder (s3 e = yc - prev, s5 yc = target + e).
// Z21 (board, z19 / PE16: much better, but the box sometimes drifts or falls behind): the YOLO box of a 1-3 % confidence
// bottle jitters by ~10 px, and FAR = 4 reseeded the template at almost every result (template recaptured slightly off ->
// drift); extrapolation also fired whenever a correction exceeded FARX, also after the bottle had stopped or turned.
//   correction (with history): |t| <= FAR (8) none, FAR < |t| <= FARH (24) half of t, larger full t;
//   extrapolation of a running track only when the tracker stood still since the result's source frame (|c - hp| < MST,
//   i.e. it holds background) while YOLO saw a large offset (|t| > FARX);
//   box size: mean of the previous and the new YOLO size while tracking (no size jump per result).
// job 1 per axis, 8 steps on the shared adder: s0 yc = (p1+p2)/2 (old size saved), s1 h = p2 - yc, s2 t = yc - hp,
// s3 e = yc - prev (prev <- yc), s4 yc = c + t or c + t/2, s5 m = yc - prev (tracker motion), s6 yc = yc + e, s7 h mean.
module bottle_seed #(parameter integer MISS_MAX=2, AGE_MAX=180, FAR=8, FARH=24, FARN=16, FARX=48, XMAX=320, MST=12)(
    input wire clk, rst_n, en, kst, vs, upd,
    input wire [319:0] tracks, input wire [31:0] rid, input wire recent, input wire [7:0] vid,
    input wire [10:0] cx, input wire [9:0] cy, input wire [1:0] lock,
    output reg bmode, output reg seed, output wire [10:0] sx, output wire [9:0] sy, output reg drop,
    output wire [79:0] entry, output reg [2:0] status
);
    reg kq, vsq, vsp, scan, chk, go, busy, job, dcd, found, trk, tv, far, updq, sk, nh;
    reg [7:0] rid_q, age; reg [1:0] k, kf, miss; reg [3:0] op; reg [12:0] tmp; reg [2:0] gen;
    reg [10:0] ycx, hw, ex1, ex2; reg [9:0] ycy, hh, ey1, ey2;
    reg [10:0] dx; reg [9:0] dy;                                  // Z17: smoothed box centre
    reg [28:0] hist [0:127];                                      // Z19: {gen, x - offx, y - offy} per vid[7:1] (distributed RAM)
    reg [12:0] offx, offy, tx, ty;                                // accumulated correction shift; this job's shift
    reg [10:0] pyx; reg [9:0] pyy; reg pv, bigt, xap; reg [12:0] ee;   // Z19: previous YOLO centre, its step, extrapolated
    reg thalf, mstill; reg [10:0] ho;                             // Z21: half correction, tracker still, previous size
    wire [79:0] e = tracks[k*80 +: 80], f = tracks[kf*80 +: 80];
    wire [28:0] hq = hist[rid_q[7:1]];
    wire hok = trk && hq[28:26] == gen;                           // tracker position of the result's source frame known
    wire [12:0] hpx = hq[25:13] + offx, hpy = hq[12:0] + offy;   // in current track coordinates
    wire on = en && bmode;
    wire up = upd ^ updq;                                         // tracker update (range_meter results counter)
    wire hwe = up && on && trk && !sk;
    // ---- shared adder. job 1 (result), op = {axis, step}: 0 yc = p1 + p2 (>> 1), 1 h = p2 - yc, 2 t = yc - hp (|t| > FAR
    //      -> far), 3 yc = c + t (seed target).  job 0 (frame), op = {axis, hi}: c -/+ h -> box edge.
    wire ay = job ? op[3] : op[1];
    wire [2:0] s = op[2:0];
    wire [10:0] p1 = ay ? {1'b0, f[20:11]} : f[10:0], p2 = ay ? {1'b0, f[42:33]} : f[32:22];
    wire [10:0] c = ay ? {1'b0, cy} : cx, yc = ay ? {1'b0, ycy} : ycx, h = ay ? {1'b0, hh} : hw;
    wire [10:0] dd = ay ? {1'b0, dy} : dx;                       // Z17: smoothed centre of the axis
    wire tbig = tmp[12] ? ({1'b0, tmp[11:0]} < 13'd4096 - 13'd48) : (tmp[11:0] > 12'd48);   // |c - d| > 48: snap
    wire [12:0] hp = !hok ? {2'b0, c} : ay ? hpy : hpx;
    // job 0 (frame), Z17: op 0 / 2: t = c - d, op 1 / 3: d + t / 2 (x / y), op 4..7: d -/+ h -> box edge
    // job 1 (Z19): s0 yc = (p1 + p2) / 2, s1 h = p2 - yc, s2 t = yc - hp, s3 e = yc - prev, s4 yc = c + t, s5 yc = yc + e
    wire [10:0] prv = ay ? {1'b0, pyy} : pyx;
    wire [12:0] tsh = thalf ? {tmp[12], tmp[12:1]} : tmp;             // Z21: applied correction
    wire [10:0] A = !job ? ((op[2] || op[0]) ? dd : c) : (s <= 3'd1) ? p2 : (s == 3'd4) ? c : (s == 3'd7) ? h : yc;
    wire [10:0] B = !job ? (op[2] ? h : dd) : (s == 3'd0) ? p1 : (s == 3'd7) ? ho : yc;   // s 2..6: B13 (hp / prev / t / prev / e)
    wire [12:0] B13 = (job && s == 3'd4) ? tsh : (job && s == 3'd2) ? hp : (job && (s == 3'd3 || s == 3'd5)) ? {2'b0, prv} :
                      (job && s == 3'd6) ? ee : (!job && !op[2] && op[0]) ? {tmp[12], tmp[12:1]} : {2'b0, B};
    wire sub = job ? (s == 3'd1 || s == 3'd2 || s == 3'd3 || s == 3'd5) : !op[0];   // job 0: t = c - d, edges c - h (op even)
    wire rfarx = r[12] ? ({1'b0, r[11:0]} < 13'd4096 - FARX[12:0]) : (r[11:0] > FARX[11:0]);   // |t| > FARX
    wire rfarh = r[12] ? ({1'b0, r[11:0]} < 13'd4096 - FARH[12:0]) : (r[11:0] > FARH[11:0]);   // |t| > FARH
    wire rmst = r[12] ? ({1'b0, r[11:0]} > 13'd4096 - MST[12:0]) : (r[11:0] < MST[11:0]);      // |m| < MST
    wire esmall = ee[12] ? ({1'b0, ee[11:0]} > 13'd4096 - XMAX[12:0]) : (ee[11:0] < XMAX[11:0]);
    wire xdo = pv && esmall && (!trk || lock == 2'd2 || (bigt && mstill));   // Z21: running track only if it held still
    wire hsm = trk && lock != 2'd2;                                    // Z21: size mean while tracking
    wire [12:0] r = {2'b0, A} + (B13 ^ {13{sub}}) + {12'd0, sub};
    wire rfar = r[12] ? ({1'b0, r[11:0]} < 13'd4096 - FAR[12:0]) : (r[11:0] > FAR[11:0]);   // |r| > FAR
    wire rfarn = r[12] ? ({1'b0, r[11:0]} < 13'd4096 - FARN[12:0]) : (r[11:0] > FARN[11:0]); // |r| > FARN (no history)
    wire ge1280 = r[11] | (r[10] & (r[9] | r[8]));
    wire ge720 = r[11] | r[10] | (r[9] & (r[8] | (r[7] & r[6] & (r[5] | r[4]))));
    assign sx = ycx[10:6] == 5'd0 ? 11'd64 : (ycx[10] & (ycx[9] | ycx[8] | (ycx[7] & ycx[6]))) ? 11'd1212 : ycx;   // 64 .. <1216
    assign sy = ycy[9:6] == 4'd0 ? 10'd64 : (ycy[9] & (ycy[8] | (ycy[7] & (ycy[6] | ycy[5] | ycy[4])))) ? 10'd652 : ycy; // 64 .. <656
    assign entry = {8'd0, 1'b1, tv, 8'd1, 2'd3, 16'd32768, 1'b0, ey2, ex2, 1'b0, ey1, ex1};
    always @(posedge clk) if(hwe) hist[vid[7:1]] <= {gen, {2'b0, cx} - offx, {3'b0, cy} - offy};
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            kq<=1; vsq<=0; vsp<=0; scan<=0; chk<=0; go<=0; busy<=0; job<=0; dcd<=0; found<=0; trk<=0; tv<=0; far<=0; updq<=0; sk<=0; nh<=0; offx<=0; offy<=0; tx<=0; ty<=0;
            bmode<=0; seed<=0; drop<=0; status<=3'd5; rid_q<=0; age<=0; k<=0; kf<=0; miss<=0; op<=0; tmp<=0; gen<=0; pyx<=11'd640; pyy<=10'd360; pv<=0; bigt<=0; xap<=0; ee<=0; thalf<=0; mstill<=0; ho<=0;
            ycx<=11'd640; hw<=11'd32; ex1<=0; ex2<=0; ycy<=10'd360; hh<=10'd32; ey1<=0; ey2<=0; dx<=11'd640; dy<=10'd360;
        end else begin
            kq<=kst; vsq<=vs; updq<=upd; seed<=0; drop<=0; dcd<=0;
            if(kq && !kst && en) bmode<=~bmode;                          // KEY4 press (debounced in range_meter)
            if(up && on && trk && sk) sk<=0;                             // first update after a seed: not stored (hwe)
            // ---- sequencer
            if(busy) begin
                if(!job) begin
                    if(!op[2]) begin
                        if(!op[0]) tmp<=r;                                   // t = c - d
                        else if(op[1]) dy <= tbig ? cy : r[9:0];             // d + t / 2, or snap to c
                        else dx <= tbig ? cx : r[10:0];
                    end else case(op[1:0])
                        2'd0: ex1 <= r[12] ? 11'd0 : r[10:0];
                        2'd1: ex2 <= ge1280 ? 11'd1280 : r[10:0];
                        2'd2: ey1 <= r[12] ? 10'd0 : r[9:0];
                        default: ey2 <= ge720 ? 10'd720 : r[9:0];
                    endcase
                    op<=op+4'd1; if(op==4'd7) busy<=0;
                end else begin
                    case(s)
                        3'd0: begin ho<=h; if(ay) ycy<=r[10:1]; else ycx<=r[11:1]; end        // Z21: previous size kept
                        3'd1: if(ay) hh<=r[9:0]; else hw<=r[10:0];
                        3'd2: begin tmp<=r; far<=far | (hok && rfar); bigt <= hok && rfarx; thalf <= hok && !rfarh; end   // Z19: no history -> no correction
                        3'd3: begin ee<=r; if(ay) pyy<=ycy; else pyx<=ycx; end                 // Z19: YOLO step, prev <- this centre
                        3'd4: begin if(ay) begin ty<=tsh; ycy <= r[12] ? 10'd0 : |r[11:10] ? 10'd1023 : r[9:0]; end   // Z21: t or t / 2
                                    else begin tx<=tsh; ycx <= r[12] ? 11'd0 : r[11] ? 11'd2047 : r[10:0]; end end
                        3'd5: mstill <= rmst;                                                    // Z21: |c - hp| < MST
                        3'd6: if(xdo) begin xap<=1; far<=1;                                     // Z19: extrapolated seed
                                  if(ay) ycy <= r[12] ? 10'd0 : |r[11:10] ? 10'd1023 : r[9:0];
                                  else ycx <= r[12] ? 11'd0 : r[11] ? 11'd2047 : r[10:0]; end
                        default: if(hsm) begin if(ay) hh<=r[10:1]; else hw<=r[11:1]; end       // Z21: size mean
                    endcase
                    op <= op+4'd1;
                    if(op==4'd15) begin busy<=0; dcd<=1; nh<=!hok; pv<=1; end
                end
            end else if(vsp) begin vsp<=0; busy<=1; job<=0; op<=0; end
            else if(go) begin go<=0; busy<=1; job<=1; op<=0; far<=0; xap<=0; end
            // ---- results
            if(!on) begin
                if(trk) drop<=1;
                trk<=0; miss<=0; scan<=0; chk<=0; go<=0; dcd<=0; rid_q<=rid[7:0]; pv<=0;
            end else begin
                if(!scan && !chk && !go && !(busy && job) && !dcd && rid[7:0]!=rid_q) begin rid_q<=rid[7:0]; scan<=1; k<=0; found<=0; end
                if(scan) begin                                   // first observed bottle = highest confidence
                    if(!found && e[70] && e[71] && e[61:60]==2'd3) begin found<=1; kf<=k; end
                    if(k==2'd3) begin scan<=0; chk<=1; end else k<=k+2'd1;
                end
                if(chk) begin
                    chk<=0;
                    if(!recent) ;                                // stale result: ignore
                    else if(!found) begin
                        pv<=0;                                           // Z19: no consecutive bottle results
                        if(miss!=MISS_MAX[1:0] && lock!=2'd2) miss<=miss+2'd1; else if(trk) begin trk<=0; drop<=1; end
                    end else begin miss<=0; go<=1; end
                end
                if(dcd && (!trk || lock==2'd2 || far)) begin
                    seed<=1; trk<=1; sk<=1;
                    if(!trk || lock==2'd2 || xap) begin gen<=gen+3'd1; offx<=0; offy<=0; end  // fresh / extrapolated seed: new history generation
                    else begin offx<=offx+tx; offy<=offy+ty; end               // correction: move history with the track
                end
                if(vs && !vsq) begin
                    if(age!=AGE_MAX[7:0]) age<=age+8'd1; else if(trk) begin trk<=0; drop<=1; end
                end
                if(chk) age<=0;                                  // any new result
            end
            if(vs && !vsq) begin
                vsp<=1;
                tv <= trk && on;
                status <= !(trk && on) ? 3'd5 : lock==2'd2 ? 3'd4 : nh ? 3'd1 : 3'd0;
            end
        end
    end
endmodule
