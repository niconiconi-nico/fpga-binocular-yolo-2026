// CLAUDE MERGE (2026-10-27): MOTION 50, frame difference on the Vision Core images (mode-exclusive with DEPTH / RANGE).
// depth_map captures the left view as 160x90 8x8-binned luma into the left image RAM and raises go; this block reads it
// (port shared through vision_core) together with the previous frame kept in the right image RAM:
//   pass 1: frame means (current, previous) -> global brightness compensation off = mean(cur) - mean(prev)
//   pass 2: per bin |cur - prev - off| > TH -> one hit in the 32x32-pixel cell (4x4 bins) of blob_engine; prev <= cur
// then blob_engine selects the moving blob (cells with >= CELL_TH hits, grown from the strongest cell). The first frame after
// entering the mode only fills the history (no detection). One RAM access per address slot (4 clocks), ~0.12 M clocks total.
module motion_cells #(parameter integer TH=18, CELL_TH=3)(
    input wire clk, rst_n, en,
    input wire go, output reg done,                               // from / to depth_map (left capture ready / analysis done)
    output reg [13:0] ma, input wire [7:0] lq, rq,                // image address (both RAMs), data (2-clock latency)
    output reg r_we, output reg [7:0] r_wd,                       // previous-frame update (right image RAM, pixel-clock port)
    output reg inc, output reg [9:0] inc_cell,                    // -> blob_engine
    output reg bstart, input wire bbusy, output reg valid_hist
);
    localparam [2:0] S_IDLE=0, S_P1=1, S_OFS=2, S_P2=3, S_BLOB=4, S_BW=5, S_DONE=6;
    reg [2:0] st; reg [1:0] ph; reg [7:0] bx; reg [6:0] by; reg [21:0] sc, sp; reg signed [8:0] off; reg goq;
    wire signed [23:0] sd = $signed({2'd0, sc}) - $signed({2'd0, sp});
    wire signed [23:0] ofs_raw = (sd >>> 14) + (sd >>> 17);       // ~ /14400
    wire signed [10:0] df = $signed({3'd0, lq}) - $signed({3'd0, rq}) - off;
    wire [9:0] adf = df[10] ? -df[9:0] : df[9:0];
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            st<=S_IDLE; ph<=0; bx<=0; by<=0; sc<=0; sp<=0; off<=0; goq<=0; done<=0; ma<=0; r_we<=0; r_wd<=0; inc<=0; inc_cell<=0;
            bstart<=0; valid_hist<=0;
        end else begin
            goq<=go; done<=0; r_we<=0; inc<=0; bstart<=0;
            if(!en) valid_hist<=0;
            case(st)
                S_IDLE: if(en && go && !goq) begin ma<=0; bx<=0; by<=0; ph<=0; sc<=0; sp<=0; st<=S_P1; end
                S_P1: begin                                       // slot: address held, data valid in phase 2
                    ph<=ph+2'd1;
                    if(ph==2'd2) begin sc<=sc+{14'd0, lq}; sp<=sp+{14'd0, rq}; end
                    if(ph==2'd3) begin if(ma==14'd14399) begin ma<=0; bx<=0; by<=0; st<=S_OFS; end else ma<=ma+14'd1; end
                end
                S_OFS: begin off <= (ofs_raw > 24'sd127) ? 9'sd127 : (ofs_raw < -24'sd127) ? -9'sd127 : ofs_raw[8:0]; ph<=0; st<=S_P2; end
                S_P2: begin
                    ph<=ph+2'd1;
                    if(ph==2'd2) begin
                        r_we<=1; r_wd<=lq;                         // history <- current (written in phase 3, same address)
                        if(valid_hist && adf > TH) begin inc<=1; inc_cell <= {by[6:2], 5'd0} + {2'd0, by[6:2], 3'd0} + {4'd0, bx[7:2]}; end
                    end
                    if(ph==2'd3) begin
                        if(bx==8'd159) begin bx<=0; by<=by+7'd1; end else bx<=bx+8'd1;
                        if(ma==14'd14399) st<=valid_hist ? S_BLOB : S_DONE; else ma<=ma+14'd1;
                    end
                end
                S_BLOB: begin bstart<=1; st<=S_BW; end
                S_BW: if(!bstart && !bbusy) st<=S_DONE;
                S_DONE: begin valid_hist<=1; done<=1; st<=S_IDLE; end
                default: st<=S_IDLE;
            endcase
        end
    end
endmodule
