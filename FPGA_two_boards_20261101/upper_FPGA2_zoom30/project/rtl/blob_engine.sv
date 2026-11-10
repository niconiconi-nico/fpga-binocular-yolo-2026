// CLAUDE MERGE (2026-10-27): cell statistics + target blob selection, shared by COLOR 49 and MOTION 50 (mode-exclusive).
// Grid 40 x 23 cells of 32 x 32 screen pixels (index cy*40 + cx). Clients add hits with inc (one per clock at most).
// Counts live in one ERAM (synchronous read): hits of consecutive increments to the same cell are summed in a register and
// written with a 3-clock read-modify-write when the cell changes (COLOR: >= 32 clocks per cell run, MOTION: >= 4 clocks
// between increments). start: flush the open run, seed = the cell with the most hits (>= th), grow the box by the active
// cells (>= th) within gap cells of it (repeated scans until stable, at most 8), publish the box and found, clear. ~10k clocks.
module blob_engine (
    input wire clk, rst_n,
    input wire inc, input wire [9:0] inc_cell,                    // count one hit in a cell
    input wire start, input wire [9:0] th, input wire [1:0] gap,     // gap: cells allowed between joined active cells + 1
    output reg busy, output reg found, output reg [5:0] bx0, bx1, output reg [4:0] by0, by1, output reg [7:0] runs
);
    reg [9:0] cnt [0:1023]; /* fehdl force_ram=1, ram_style="bram" */
    localparam [2:0] S_IDLE=0, S_FLUSH=1, S_SEED=2, S_GROW=3, S_CLR=4;
    reg [2:0] st; reg [9:0] i; reg [5:0] cx; reg [4:0] cy; reg vq; reg [5:0] cxq; reg [4:0] cyq; reg last;
    reg [9:0] best; reg [5:0] sx; reg [4:0] sy; reg chg; reg [3:0] pass;
    reg [5:0] gx0, gx1; reg [4:0] gy0, gy1;
    // open run and its read-modify-write
    reg av; reg [9:0] acell, an; reg [1:0] fs; reg [9:0] fcell, fn;
    wire [9:0] ra = (fs == 2'd1) ? fcell : i;
    reg [9:0] q;
    always @(posedge clk) q <= cnt[ra];
    wire [10:0] fsum = {1'b0, q} + {1'b0, fn};
    always @(posedge clk) begin
        if(fs == 2'd2) cnt[fcell] <= fsum[10] ? 10'h3ff : fsum[9:0];
        else if(st == S_CLR) cnt[i] <= 10'd0;
    end
    wire act = q >= th && q != 0;
    wire near = {1'b0, cxq} + {5'd0, gap} >= {1'b0, gx0} && {1'b0, cxq} <= {1'b0, gx1} + {5'd0, gap} &&
                {1'b0, cyq} + {4'd0, gap} >= {1'b0, gy0} && {1'b0, cyq} <= {1'b0, gy1} + {4'd0, gap};
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            st<=S_IDLE; busy<=0; found<=0; bx0<=0; bx1<=0; by0<=0; by1<=0; runs<=0; i<=0; cx<=0; cy<=0; vq<=0; cxq<=0; cyq<=0; last<=0;
            best<=0; sx<=0; sy<=0; chg<=0; pass<=0; gx0<=0; gx1<=0; gy0<=0; gy1<=0; av<=0; acell<=0; an<=0; fs<=0; fcell<=0; fn<=0;
        end else begin
            // read-modify-write of a closed run: fs 1 = address, 2 = write (data of the address in q)
            if(fs == 2'd1) fs<=2'd2; else if(fs == 2'd2) fs<=2'd0;
            if(st == S_IDLE && inc) begin
                if(av && inc_cell == acell) begin if(an != 10'h3ff) an<=an+10'd1; end
                else begin if(av) begin fcell<=acell; fn<=an; fs<=2'd1; end av<=1; acell<=inc_cell; an<=10'd1; end
            end
            // scan bookkeeping: q (cell i of the previous clock) is tagged with cxq / cyq
            vq <= (st == S_SEED || st == S_GROW) && fs == 2'd0; cxq<=cx; cyq<=cy; last <= (i == 10'd919);
            case(st)
                S_IDLE: if(start) begin busy<=1; st<=S_FLUSH; end
                S_FLUSH: if(fs == 2'd0) begin
                    if(av) begin fcell<=acell; fn<=an; fs<=2'd1; av<=0; end
                    else begin i<=0; cx<=0; cy<=0; best<=0; st<=S_SEED; end
                end
                S_SEED: begin
                    if(vq && act && q > best) begin best<=q; sx<=cxq; sy<=cyq; end
                    if(vq && last) begin
                        i<=0; cx<=0; cy<=0; chg<=0; pass<=0; vq<=0; last<=0;   // new pass: drop the stale tag
                        if(best != 0 || (act && q > best)) begin
                            st<=S_GROW;
                            gx0 <= (act && q > best) ? cxq : sx; gx1 <= (act && q > best) ? cxq : sx;
                            gy0 <= (act && q > best) ? cyq : sy; gy1 <= (act && q > best) ? cyq : sy;
                        end else begin found<=0; st<=S_CLR; end
                    end else if(i != 10'd919) begin i<=i+10'd1; if(cx == 6'd39) begin cx<=0; cy<=cy+5'd1; end else cx<=cx+6'd1; end
                end
                S_GROW: begin
                    if(vq && act && near && (cxq < gx0 || cxq > gx1 || cyq < gy0 || cyq > gy1)) begin
                        chg<=1; if(cxq < gx0) gx0<=cxq; if(cxq > gx1) gx1<=cxq; if(cyq < gy0) gy0<=cyq; if(cyq > gy1) gy1<=cyq;
                    end
                    if(vq && last) begin
                        i<=0; cx<=0; cy<=0; chg<=0; pass<=pass+4'd1; vq<=0; last<=0;
                        if(!chg || pass == 4'd7) begin found<=1; bx0<=gx0; bx1<=gx1; by0<=gy0; by1<=gy1; st<=S_CLR; end
                    end else if(i != 10'd919) begin i<=i+10'd1; if(cx == 6'd39) begin cx<=0; cy<=cy+5'd1; end else cx<=cx+6'd1; end
                end
                S_CLR: if(i == 10'd919) begin i<=0; busy<=0; runs<=runs+8'd1; st<=S_IDLE; end else i<=i+10'd1;
                default: st<=S_IDLE;
            endcase
        end
    end
endmodule
