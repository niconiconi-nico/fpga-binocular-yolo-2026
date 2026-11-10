// CLAUDE MERGE (2026-10-27): COLOR 49, colour target detection on the displayed camera stream (pixel clock).
// Pixels of the target colour (KEY4 short press cycles RED / GREEN / BLUE) are counted per 32x32-pixel cell in blob_engine;
// at the start of vertical sync the blob selection runs (cells with >= CELL_TH pixels, grown from the strongest cell).
// Colour tests on 8-bit RGB: the target channel above a floor and above both others by a margin (chroma, not brightness).
// CLAUDE Z8C: KDEB = 1 -> key_n is the already debounced KEY4 level (range_meter kst, shared); the local debouncer is unused.
module color_cells #(parameter integer DEBOUNCE=1500000, CELL_TH=96, KDEB=0)(
    input wire clk, rst_n, en, key_n,
    input wire hs_i, vs_i, de_i, input wire [23:0] rgb_i,
    output reg inc, output reg [9:0] inc_cell, output reg bstart, output reg [1:0] csel
);
    reg [10:0] x; reg [9:0] y; reg pd, vsd;
    (* async_reg="true" *) reg k1, k2; reg kst; reg [20:0] kcnt;
    wire [7:0] r = rgb_i[23:16], g = rgb_i[15:8], b = rgb_i[7:0];
    // CLAUDE Z17 (board: the washed-out left view left a red mouse at r - g ~ 34, r - b ~ 14 -> NONE): margins over both other
    // channels lowered (red 45 / 45 -> 24 / 16, green 30 / 20 -> 20 / 14, blue 30 / 15 -> 20 / 12), floors 90 / 70 -> 64 / 56.
    // CLAUDE Z18 (board, exposure fixed: red mouse C EF 60 50, the box also took the hand): red margin scales with r,
    // r - g >= r/4 + 32 and r - b >= r/8 + 16 (mouse 239/96/80 and its shade pass; skin ~ 230/170/150, r - g 60 < 89, fails)
    wire hit_r = r > 8'd64 && {1'b0, r} >= {1'b0, g} + {3'd0, r[7:2]} + 9'd32 && {1'b0, r} >= {1'b0, b} + {4'd0, r[7:3]} + 9'd16;
    wire hit_g = g > 8'd56 && {1'b0, g} >= {1'b0, r} + 9'd20 && {1'b0, g} >= {1'b0, b} + 9'd14;
    wire hit_b = b > 8'd56 && {1'b0, b} >= {1'b0, r} + 9'd20 && {1'b0, b} >= {1'b0, g} + 9'd12;
    wire hit = (csel == 2'd0) ? hit_r : (csel == 2'd1) ? hit_g : hit_b;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin x<=0; y<=0; pd<=0; vsd<=0; inc<=0; inc_cell<=0; bstart<=0; csel<=0; k1<=1; k2<=1; kst<=1; kcnt<=0; end
        else begin
            pd<=de_i; vsd<=vs_i;
            if(de_i) x<=x+1'b1; else x<=0;
            if(vs_i) y<=0; else if(pd && !de_i) y<=y+1'b1;
            inc <= en && de_i && hit && x < 11'd1280 && y < 10'd720;
            inc_cell <= {y[9:5], 5'd0} + {2'd0, y[9:5], 3'd0} + {4'd0, x[10:5]};
            bstart <= en && vs_i && !vsd;
            k1<=key_n; k2<=k1;
            if(KDEB) begin kst<=key_n; if(kst && !key_n && en) csel <= (csel==2'd2) ? 2'd0 : csel+2'd1; end
            else if(k2==kst) kcnt<=0;
            else if(kcnt==DEBOUNCE[20:0]) begin kst<=k2; kcnt<=0; if(!k2 && en) csel <= (csel==2'd2) ? 2'd0 : csel+2'd1; end
            else kcnt<=kcnt+21'd1;
        end
    end
endmodule
