`timescale 1ns/1ps
// CLAUDE Z25 LATENCY system test: camera model (frame start + 115200 ordered native writes per frame into a bank chosen
// like video_in: next bank, never the bank the reader holds) -> local_native_commit1 (z25) -> stereo_raw_reader1 (z25,
// real row-0 selection with a DDR read model) -> latency_meter1. Independent reference: the testbench knows the frame
// written into every bank and its frame-start time; at every row-0 selection it records true latency, newest frame and
// displayed frame. Checks: meter mean of each 16-selection group vs true mean (|err| <= 0.15 ms), and every BCD result
// (LAT / CAP / DISP) vs the reference of the selection that produced it.
module tbl;
  parameter real FPER=16666.7;       // camera frame period (us)
  parameter real WD=800.0;           // frame start -> first bank write (us)
  parameter real WT=14500.0;         // write duration (us)
  parameter integer STEREO=0, NGRP=6, DBG=0;
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
  latency_meter1 #(.TICK(7500)) m(.cam_clk(cclk),.cam_rst_n(!rst),.cam_sof(sofp),.clk(pclk),.rst_n(!rst),.sof_g(sofg),
    .sel_tg(seltg),.sel_idx(selidx),.ok(ok),.lat_bcd(latb),.cap_bcd(capb),.dsp_bcd(dspb));
  // reference at every row-0 selection (same condition as the reader's req_first capture)
  real rl [0:4095]; integer rcap [0:4095], rdsp [0:4095]; integer ns=0;
  always @(posedge dclk) if(!rdr.dr && rdr.qs2!=rdr.ack && !rdr.active && !rdr.done && rdr.req_first) begin
    rl[ns] = ($realtime - tsof[bank_frame[rdr.chosen_bank]%4096]) / 1000000.0; rcap[ns] = nsof % 10000; rdsp[ns] = bank_frame[rdr.chosen_bank] % 10000;
    ns = ns + 1;
  end
  function integer bcd2i(input [15:0] b); bcd2i = b[15:12]*1000 + b[11:8]*100 + b[7:4]*10 + b[3:0]; endfunction
  // meter results: the double dabble started by selection s (meter's own count) finishes with ph 2 -> 0
  integer ms=0, bad=0, nchk=0, ngrp=0; real gm, emax=0, e; integer i;
  reg busyd=0; integer mg=0, gs=0;
  always @(posedge pclk) begin                           // BCD results (no delay: old values at the go edge)
    busyd <= m.busy;
    if(m.go) begin ms = ms + 1; mg = m.mok ? m.mean : -1; end
    if(m.go && DBG && ms>=20 && ms<40) $display("SEL %0d meter %0.1f true %0.3f pidx %0d dn %0d", ms-1, m.lat/10.0, rl[ms-1], m.pidx, m.dn);
    if(busyd && !m.busy && ms > 1) begin                 // BCD of selection ms-1, started at its go with mean mg
      nchk = nchk + 1;
      if(bcd2i(capb) != rcap[ms-1] || bcd2i(dspb) != rdsp[ms-1] || (mg >= 0 && mg <= 999 && bcd2i({4'd0, latb}) != mg) || ok != (mg >= 0 && mg <= 999)) begin
        bad = bad + 1; if(bad < 10) $display("BAD BCD sel %0d cap %0d/%0d disp %0d/%0d lat %h mean %0d ok %0d", ms-1, bcd2i(capb), rcap[ms-1], bcd2i(dspb), rdsp[ms-1], latb, mg, ok);
      end
    end
  end
  always @(posedge pclk) if(m.go) begin gs = gs + 1; if(m.mc==4'd15 && gs >= 16) begin   // own count (no race with ms): group closes
    gm = 0; for(i=gs-16;i<gs;i=i+1) gm = gm + rl[i]; gm = gm / 16.0;
    #1; e = m.mean/10.0 - gm; if(e<0) e=-e; if(e>emax) emax=e;
    ngrp = ngrp + 1;
    $display("GROUP %0d sel %0d..%0d mean meter %0.1f ms  true %0.3f ms  (single %0.2f .. %0.2f)  CAP %0d DISP %0d", ngrp, gs-16, gs-1, m.mean/10.0, gm, rl[gs-16], rl[gs-1], rcap[gs-1], rdsp[gs-1]);
    if(e > 0.15) begin bad=bad+1; $display("  BAD mean error %0.3f", e); end
    if(ngrp==NGRP) begin
      $display("FINAL FPER=%0.1f WD=%0.0f WT=%0.0f STEREO=%0d groups=%0d bcd_checks=%0d max_mean_err=%0.3f ms bad=%0d perr=%0d cerr=%0d missed=%0d %s",
               FPER, WD, WT, STEREO, ngrp, nchk, emax, bad, perr, cerr, missed, (bad==0 && nchk>50) ? "PASS" : "FAIL");
      $finish;
    end
  end end
  initial begin repeat(20) @(posedge pclk); rst=0; end
  initial begin #2000000000; $display("TIMEOUT"); $finish; end
endmodule
