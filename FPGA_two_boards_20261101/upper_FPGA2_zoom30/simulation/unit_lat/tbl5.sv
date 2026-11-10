`timescale 1ns/1ps
// CLAUDE Z28C MONITOR system test (tbl2 + latency_meter5: BCD time base, 10-frame mean, 1 s windows; net_rate_meter2). Base: CLAUDE Z25 LATENCY system test: camera model (frame start + 115200 ordered native writes per frame into a bank chosen
// like video_in: next bank, never the bank the reader holds) -> local_native_commit1 (z25) -> stereo_raw_reader1 (z25,
// real row-0 selection with a DDR read model) -> latency_meter1. Independent reference: the testbench knows the frame
// written into every bank and its frame-start time; at every row-0 selection it records true latency, newest frame and
// displayed frame. Checks: meter mean of each 16-selection group vs true mean (|err| <= 0.15 ms), and every BCD result
// (LAT / CAP / DISP) vs the reference of the selection that produced it.
module tbl;
  parameter real FPER=16666.7;       // camera frame period (us)
  parameter real WD=800.0;           // frame start -> first bank write (us)
  parameter real WT=14500.0;         // write duration (us)
  parameter integer STEREO=0, NGRP=40, DBG=0, PXR=77, FPX=921600;   // window ticks, px probability /256, px per UDP frame
  reg pclk=0, dclk=0, cclk=0, rst=1; always #6.6667 pclk=~pclk; always #5 dclk=~dclk; always #6 cclk=~cclk;
  integer hc=0, vc=0;
  wire de = hc<1280 && vc<720, vsy = vc>=725 && vc<730;
  reg [10:0] x=0; reg [9:0] y=0;
  always @(posedge pclk) if(hc==1649) begin hc<=0; vc<= vc==749 ? 0 : vc+1; end else hc<=hc+1;
  always @(*) begin x = (hc<1280) ? hc[10:0] : 11'd0; y = (vc<720) ? vc[9:0] : 10'd720 + (vc-720); end
  // DDR read model
  wire arvalid; wire [24:0] araddr; reg rvalid=0; reg [127:0] rdata=0;
  reg [24:0] q [0:255]; integer qh=0, qt=0, cnt=0;
  always @(posedge dclk) begin
    rvalid <= 0;
    if(arvalid) begin q[qt%256] <= araddr; qt <= qt+1; end
    cnt <= cnt+1;
    if(qh != qt && cnt[1:0]==0) begin rvalid <= 1; rdata <= {8{q[qh%256][15:0]}}; qh <= qh+1; end
  end
  // camera: frame start (camera clock pulse) and ordered writes (DDR clock)
  reg sofp=0; real tsof [0:4095]; integer nsof=0;
  reg wact=0; reg [24:0] wbase=0; integer wcnt=0; reg acc=0; reg [24:0] waddr=0;
  integer bank_frame [0:3]; integer wbank=0, wframe=0; wire [1:0] latest; wire hold; wire [1:0] hb;
  initial begin bank_frame[0]=0; bank_frame[1]=0; bank_frame[2]=0; bank_frame[3]=0; end
  initial begin
    #20000;
    forever begin
      @(posedge cclk); sofp<=1; nsof=nsof+1; tsof[nsof%4096]=$realtime; @(posedge cclk); sofp<=0;
      fork begin : wr
        integer k, nb; real t0;
        k = nsof; t0 = $realtime;
        #(WD*1000.0);
        nb = (latest + 1) % 4; if(hold && nb==hb) nb=(nb+1)%4;
        wbank = nb; wframe = k; bank_frame[nb] = k;
        @(posedge dclk); wbase <= (nb==0) ? 25'd0 : (nb==1) ? 25'd7000000 : (nb==2) ? 25'd14000000 : 25'd21000000; wcnt <= 0; wact <= 1;
      end join_none
      #(FPER*1000.0 - 12);
    end
  end
  // 115200 writes spread over WT
  integer wgap; initial wgap = $rtoi(WT*1000.0/10.0/115200.0);
  integer wdiv=0;
  always @(posedge dclk) begin
    acc <= 0;
    if(wact) begin
      if(wdiv>=wgap-1) begin wdiv<=0; acc<=1; waddr<=wbase+25'(wcnt*8); wcnt<=wcnt+1; if(wcnt==115199) wact<=0; end
      else wdiv<=wdiv+1;
    end
  end
  // DUT chain
  wire [3:0] valid; wire [127:0] epochs; wire cerr; wire [7:0] bsofs; wire [1:0] sofg; wire seltg; wire [1:0] selidx;
  local_native_commit1 commit(dclk, rst, acc, 1'b0, waddr, valid, epochs, cerr, latest, sofg, bsofs);
  wire [15:0] lp, rp; wire [23:0] lrgb; wire lv, rv, sb, perr; wire [31:0] missed;
  stereo_raw_reader1 rdr(.pixel_clk(pclk),.ddr_clk(dclk),.rst(rst),.calibrated(1'b1),.frame_vs(vsy),.stereo_mode_i(STEREO!=0),.x(x),.y(y),.de(de),
    .local_bank(latest),.local_valid_banks(valid),.local_epochs(epochs),.remote_valid(1'b0),.remote_bank(1'b0),.remote_id(32'd0),
    .local_pixel(lp),.remote_pixel(rp),.local_rgb888(lrgb),.local_pixel_valid(lv),.remote_pixel_valid(rv),
    .arvalid(arvalid),.arready(1'b1),.araddr(araddr),.rvalid(rvalid),.rdata(rdata),.local_hold(hold),.held_local_bank(hb),
    .safe_boundary(sb),.missed_lines(missed),.protocol_error(perr),.remote_full_i(1'b0),.pair_mode_i(1'b0),
    .zoom_i(1'b0),.zstep_i(19'd65536),.local_sofs(bsofs),.sel_tg(seltg),.sel_idx(selidx));
  wire ok; wire [11:0] latb; wire [15:0] capb, dspb;
  wire [1:0] lagv; wire utg, ftg; wire [7:0] showf, udpf; wire [15:0] mbpsv;
  latency_meter5 #(.TICK(7500)) m(.cam_clk(cclk),.cam_rst_n(!rst),.cam_sof(sofp),.clk(pclk),.rst_n(!rst),.sof_g(sofg),
    .sel_tg(seltg),.sel_idx(selidx),.unit_tg(utg),.frame_tg(ftg),.ok(ok),.lat_bcd(latb),.cap_bcd(capb),.dsp_bcd(dspb),.lag(lagv),
    .show_fps(showf),.udp_fps(udpf),.mbps(mbpsv));
  // rx clock 125 MHz: random accepted video pixels (PXR/256 per clock) and a complete-frame pulse every FPX pixels
  reg rxclk=0; always #4 rxclk=~rxclk;
  reg px=0, frm=0; reg [31:0] lf=32'h1; integer fpx=0;
  always @(posedge rxclk) begin
    lf <= {lf[30:0], lf[31]^lf[21]^lf[1]^lf[0]};
    px <= !rst && lf[7:0] < PXR;
    frm <= 0; if(px) begin if(fpx==FPX-1) begin fpx<=0; frm<=1; end else fpx<=fpx+1; end
  end
  net_rate_meter2 netm(.clk(rxclk),.rst(rst),.px(px),.frame(frm),.unit_tg(utg),.frame_tg(ftg));
  // reference at every row-0 selection (same condition as the reader's req_first capture)
  real rl [0:4095]; integer rcap [0:4095], rdsp [0:4095]; integer ns=0;
  always @(posedge dclk) if(!rdr.dr && rdr.qs2!=rdr.ack && !rdr.active && !rdr.done && rdr.req_first) begin
    rl[ns] = ($realtime - tsof[bank_frame[rdr.chosen_bank]%4096]) / 1000000.0; rcap[ns] = nsof % 10000; rdsp[ns] = bank_frame[rdr.chosen_bank] % 10000;
    ns = ns + 1;
  end
  function integer bcd2i(input [15:0] b); bcd2i = b[15:12]*1000 + b[11:8]*100 + b[7:4]*10 + b[3:0]; endfunction
  // Z28C meter: one update per 10 selections (group closed by the selection with mc==9), outputs valid one clock later
  integer gs=0, gcl=-1, bad=0, nchk=0, ngrp=0, nlag=0; real gm, emax=0, e, mv; integer i;
  always @(posedge pclk) begin
    if(m.go) begin gs = gs + 1; if(ok != (ngrp>0)) begin bad=bad+1; $display("BAD ok %0d before/after first group", ok); end end
    if(m.go && m.mc==4'd9) begin
      gcl = gs - 1; #1;
      ngrp = ngrp + 1; nchk = nchk + 1;
      gm = 0; for(i=gcl-9;i<=gcl;i=i+1) gm = gm + rl[i]; gm = gm / 10.0;
      mv = bcd2i({4'd0, latb}) / 10.0; e = mv - gm; if(e<0) e=-e; if(e>emax) emax=e;
      $display("GROUP %0d sel %0d..%0d LAT %0.1f ms (BCD %h) true %0.3f ms  CAP %0d/%0d DISP %0d/%0d LAG %0d ok %0d", ngrp, gcl-9, gcl, mv, latb, gm, bcd2i(capb), rcap[gcl], bcd2i(dspb), rdsp[gcl], lagv, ok);
      if(lagv != (rcap[gcl] - rdsp[gcl] + 10000) % 10000) begin bad=bad+1; $display("  BAD LAG %0d", lagv); end else nlag = nlag + 1;
      if(e > 0.15 || !ok || bcd2i(capb) != rcap[gcl] || bcd2i(dspb) != rdsp[gcl] || gcl != 10*ngrp-1) begin bad=bad+1; $display("  BAD"); end
      if(ngrp==NGRP) begin
        $display("FINAL FPER=%0.1f WD=%0.0f WT=%0.0f STEREO=%0d groups=%0d checks=%0d lag=%0d windows=%0d net_windows=%0d max_mean_err=%0.3f ms bad=%0d perr=%0d cerr=%0d missed=%0d %s",
                 FPER, WD, WT, STEREO, ngrp, nchk, nlag, nwin, nnet, emax, bad, perr, cerr, missed, (bad==0 && nchk==NGRP && nlag==NGRP && nwin>=3 && nnet>=3) ? "PASS" : "FAIL");
        $finish;
      end
    end
  end
  // ---- 1 s statistics reference (window = meter sec pulse). Events within the synchronizer delay of a boundary may fall
  // into the neighbouring window: per window +-1, running totals +-1. Hold registers = counts of the closed window.
  function integer b2i2(input [7:0] b); b2i2 = b[7:4]*10 + b[3:0]; endfunction
  integer rshow=0, tshow=0, mshow=0, nwin=0, wdiff, nlast=-1;
  integer tpx=0, runit=0, tunit=0, munit=0, rfr=0, tfr=0, mfr=0;
  always @(posedge dclk) if(!rdr.dr && rdr.qs2!=rdr.ack && !rdr.active && !rdr.done && rdr.req_first && ns>0)
    if(bank_frame[rdr.chosen_bank] % 10000 != nlast) begin if(nlast>=0) rshow = rshow + 1; nlast = bank_frame[rdr.chosen_bank] % 10000; end
  always @(posedge rxclk) begin if(px) begin tpx = tpx + 1; if(tpx % 6250 == 0) runit = runit + 1; end if(frm) rfr = rfr + 1; end
  reg [7:0] psf, pnf; reg [15:0] pnb;
  always @(posedge pclk) if(m.sec) begin
    nwin = nwin + 1; psf = m.sf; pnf = m.nf; pnb = m.nb;
    tshow = tshow + rshow; mshow = mshow + b2i2(m.sf); tunit = tunit + runit; munit = munit + bcd2i(m.nb); tfr = tfr + rfr; mfr = mfr + b2i2(m.nf);
    $display("WIN %0d SHOW %0d/%0d UDP %0d/%0d MBPS(units) %0d/%0d  totals %0d/%0d %0d/%0d %0d/%0d", nwin, b2i2(m.sf), rshow, b2i2(m.nf), rfr,
             bcd2i(m.nb), runit, mshow, tshow, mfr, tfr, munit, tunit);
    wdiff = b2i2(m.sf) - rshow; if(wdiff>1 || wdiff<-1) begin bad=bad+1; $display("  BAD SHOW"); end
    wdiff = b2i2(m.nf) - rfr; if(wdiff>1 || wdiff<-1) begin bad=bad+1; $display("  BAD UDP"); end
    wdiff = bcd2i(m.nb) - runit; if(wdiff>1 || wdiff<-1) begin bad=bad+1; $display("  BAD MBPS"); end
    wdiff = mshow - tshow; if(wdiff>1 || wdiff<-1) begin bad=bad+1; $display("  BAD SHOW total"); end
    wdiff = mfr - tfr; if(wdiff>1 || wdiff<-1) begin bad=bad+1; $display("  BAD UDP total"); end
    wdiff = munit - tunit; if(wdiff>1 || wdiff<-1) begin bad=bad+1; $display("  BAD MBPS total"); end
    rshow = 0; runit = 0; rfr = 0;
    #1 if(showf != psf || udpf != pnf || mbpsv != pnb) begin bad=bad+1; $display("  BAD hold"); end
  end
  integer nnet=0; always @(posedge pclk) if(m.sec) nnet = nnet + 1;
  initial begin repeat(20) @(posedge pclk); rst=0; end
  initial begin #2000000000; #2000000000; #2000000000; #2000000000; $display("TIMEOUT"); $finish; end
endmodule
