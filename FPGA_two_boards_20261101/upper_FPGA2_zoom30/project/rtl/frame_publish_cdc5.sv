// CLAUDE Z29B (2026-11-01): three-bank ownership with the DDR drain overlapped by the next frame (cdc4 + drain stage).
// Board: the lower board sends 45.08 frames/s; with two banks (cdc3) the upper board completed ~24/s. Simulation: cdc4
// (three banks) reaches the full rate only if the next frame's first datagram comes later than the DDR drain of the
// previous one (evenly paced datagrams leave ~2 us); here the writer gets a new bank when a frame's DATA is complete
// (written), the frame is published when its DDR writes are committed (publish = receiver frame_complete).
// Roles: D = bank the display took (last acknowledged publish), P = published, not yet acknowledged (outst),
// R = written, waiting for drain / for the acknowledge of P (rv, rdone), W = bank being written (wv = a free bank exists).
// The receiver may start a frame only while wr_available (W valid); all roles are distinct banks.
// Handshake as cdc3 / cdc4: req toggles with a held published_bank / published_id, the display side takes them at its safe
// boundary and returns ack. Never consume a synchronizer first stage in logic.
module frame_publish_cdc5 (
    input wire wr_clk, rd_clk, rst,
    input wire written,                                 // last datagram of a frame accepted (its data is in the write path)
    input wire publish,                                 // that frame's DDR writes are committed
    input wire [31:0] publish_frame_id,                 // held by the receiver until its next frame_complete
    output wire wr_available,
    output wire [1:0] wr_bank,
    input wire rd_safe_boundary,
    output reg [1:0] rd_bank,
    output reg rd_valid,
    output reg [31:0] rd_frame_id
);
    reg req, ack, outst, rv, rdone, wv;
    reg [1:0] published_bank, disp, rb, wb;
    reg [31:0] published_id;
    wire wr_reset,rd_reset;
    reset_domain_sync wr_release(wr_clk,rst,wr_reset);
    reset_domain_sync rd_release(rd_clk,rst,rd_reset);
    (* async_reg = "true" *) reg ack_s1, ack_s2, req_s1, req_s2;
    wire acked = outst && req == ack_s2;                 // the display took published_bank
    assign wr_available = wv;
    assign wr_bank = wb;
    reg [1:0] nD, nP, nR, nW; reg nout, nrv, nrd, nwv, go;
    always @(*) begin
        nD = disp; nP = published_bank; nR = rb; nW = wb; nout = outst; nrv = rv; nrd = rdone; nwv = wv; go = 1'b0;
        if (written) begin nR = wb; nrv = 1'b1; nrd = 1'b0; nwv = 1'b0; end
        if (publish) nrd = 1'b1;
        if (acked) begin nD = published_bank; nout = 1'b0; end
        if (nrv && nrd && !nout) begin nP = nR; nout = 1'b1; nrv = 1'b0; nrd = 1'b0; go = 1'b1; end
        if (!nwv) begin
            if (!nout && !nrv) begin nW = (nD==2'd0) ? 2'd1 : 2'd0; nwv = 1'b1; end
            else if (nout && !nrv) begin nW = 2'd3 - nD - nP; nwv = 1'b1; end
            else if (!nout && nrv) begin nW = 2'd3 - nD - nR; nwv = 1'b1; end
        end
    end
    always @(posedge wr_clk or posedge wr_reset) begin
        if (wr_reset) begin
            req <= 0; outst <= 0; rv <= 0; rdone <= 0; wv <= 1; published_bank <= 0; disp <= 0; rb <= 0; wb <= 1;
            published_id <= 0; ack_s1 <= 0; ack_s2 <= 0;
        end else begin
            ack_s1 <= ack; ack_s2 <= ack_s1;
            disp <= nD; published_bank <= nP; rb <= nR; wb <= nW; outst <= nout; rv <= nrv; rdone <= nrd; wv <= nwv;
            if (go) begin req <= ~req; published_id <= publish_frame_id; end
        end
    end
    always @(posedge rd_clk or posedge rd_reset) begin
        if (rd_reset) begin
            req_s1 <= 0; req_s2 <= 0; ack <= 0;
            rd_bank <= 0; rd_valid <= 0; rd_frame_id <= 0;
        end else begin
            req_s1 <= req; req_s2 <= req_s1;
            if (rd_safe_boundary && req_s2 != ack) begin
                rd_bank <= published_bank; rd_frame_id <= published_id;
                rd_valid <= 1; ack <= req_s2;
            end
        end
    end
endmodule
