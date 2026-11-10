// CLAUDE ZOOM (2026-10-28): mode 51 zoom factor (pixel clock).
//   z (Q8, 64 = 0.25x .. 256 = 1.00x .. 1024 = 4.00x). ZOOM6: below 1x the whole frame shrinks (black border).
//   KEY4 short press (released before HOLD): 0.25 -> 0.50 -> 0.75 -> 1.00 -> 1.50 -> ... -> 4.00 -> 0.25.
//   KEY4 held > HOLD (~0.3 s): z changes by max(1, z/64) per frame (~1.6 %, even pace), ping-pong between 0.25x and 4.00x
//   (end to end ~3 s at 60 Hz); release keeps the factor.
//   Leaving the mode keeps z (re-entering resumes); zoom_en only in mode 51.
//   zstep = 65536 / zoom = 2^24 / z (16384 .. 262144) by a restoring division after each change (no multiplier).
//   zn: zoom x 100 = z * 100 / 256 (shift-add); vision_osd converts it to x.xx (BCD converter shared with DEPTH, Z10).
// CLAUDE Z8C: KDEB = 1 -> key_n is the already debounced KEY4 level (range_meter kst, shared); the local debouncer is unused.
// CLAUDE Z11 AREA: MS_TICK = 1 -> hold detection counts the shared 1 ms tick (HOLD_MS, 9-bit instead of 25-bit).
module zoom_ctrl #(parameter integer DEBOUNCE=1500000, HOLD=22000000, KDEB=0, MS_TICK=0, HOLD_MS=293)(
    input wire clk, rst_n, en, key_n, vs, ms,
    output wire zoom_en, output reg [18:0] zstep, output reg [9:0] zn   // CLAUDE Z10: zn = zoom x 100 (BCD in vision_osd)
);
    localparam integer HD = MS_TICK ? HOLD_MS : HOLD; wire hstep = MS_TICK ? ms : 1'b1;
    (* async_reg="true" *) reg k1, k2; reg kst; reg [20:0] kcnt; reg [$clog2(HD+1)-1:0] hcnt; reg held, dir, vsd;
    reg [10:0] z;
    assign zoom_en = en;
    wire rel = KDEB ? (key_n && !kst) : (k2 != kst) && (kcnt == DEBOUNCE[20:0]) && k2;    // debounced release
    wire [10:0] zr = (z[10:6] == 5'd0) ? 11'd1 : {6'd0, z[10:6]}; // hold step max(1, z/64)
    wire [10:0] zs = (z < 11'd256) ? 11'd64 : 11'd128;           // short-press step 0.25x below 1x, 0.50x above
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin k1<=1; k2<=1; kst<=1; kcnt<=0; hcnt<=0; held<=0; dir<=1; vsd<=0; z<=11'd256; end
        else begin
            k1<=key_n; k2<=k1; vsd<=vs;
            if(KDEB) kst<=key_n;
            else if(k2==kst) kcnt<=0;
            else if(kcnt==DEBOUNCE[20:0]) begin kst<=k2; kcnt<=0; end
            else kcnt<=kcnt+21'd1;
            // hold detection; a release always clears held (it takes priority over the hold counter)
            if(rel) begin held<=0; hcnt<=0; end
            else if(!kst) begin if(hcnt != HD) begin if(hstep) hcnt<=hcnt+1'b1; end else held<=1; end
            else hcnt<=0;
            if(en && rel && !held)                                           // short press: next step, wrap
                z <= (z + zs > 11'd1024) ? 11'd64 : z + zs;
            else if(en && held && !kst && vs && !vsd) begin                  // hold: ramp, reverse at the ends
                if(dir) begin if(z + zr >= 11'd1024) begin z<=11'd1024; dir<=0; end else z<=z+zr; end
                else    begin if(z <= 11'd64 + zr)   begin z<=11'd64;   dir<=1; end else z<=z-zr; end
            end
        end
    end
    // zstep = 2^24 / z (restarted whenever z changes)
    reg [10:0] zq; reg [4:0] dc; reg [24:0] rem; reg [18:0] quo; reg dbusy;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin zq<=11'd256; dc<=0; rem<=0; quo<=0; dbusy<=0; end
        else if(!dbusy) begin if(z != zq) begin zq<=z; rem<=25'd0; quo<=0; dc<=5'd25; dbusy<=1; end end
        else begin                                                // long division of 2^24 (bit 24 set) by zq
            if({rem[23:0], (dc == 5'd25)} >= {14'd0, zq}) begin rem <= {rem[23:0], (dc == 5'd25)} - {14'd0, zq}; quo <= {quo[17:0], 1'b1}; end
            else begin rem <= {rem[23:0], (dc == 5'd25)}; quo <= {quo[17:0], 1'b0}; end
            if(dc == 5'd1) begin dbusy<=0; end
            dc <= dc - 5'd1;
        end
    end
    always @(posedge clk or negedge rst_n) if(!rst_n) zstep <= 19'd65536; else if(!dbusy && z == zq && zq != 11'd256) zstep <= quo; else if(zq == 11'd256 && !dbusy) zstep <= 19'd65536;
    // zoom x.xx in BCD: n = z * 100 / 256 (100 = 64 + 32 + 4), 25..400
    wire [17:0] z100 = {1'b0, z, 6'd0} + {2'd0, z, 5'd0} + {5'd0, z, 2'd0};
    wire [9:0] n = z100[17:8];
    always @(posedge clk) zn <= n;
endmodule
