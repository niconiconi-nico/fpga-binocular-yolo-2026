`timescale 1ns/1ps
// CLAUDE Z29 receive-ownership test: remote_media_ingress5 (real checked_media_ethernet_rx3 / video_udp_receiver /
// frame_publish_cdc3 or cdc4) fed with real Ethernet/IPv4/UDP video datagrams (vectors.txt, 64x36 RGB565, 18 x 256 B per
// frame), time-scaled board situation: sender frame period TSEND with the link busy 76.5 % of it (45 fps, 699 Mbps on the
// board), display safe boundary every TDISP = TSEND * 45 / 60 (HDMI 60 Hz). DDR model: writes land in memory immediately,
// drained DRAIN ns after the last write of a frame.
// Checks: no write into the bank the display holds; every frame the display takes is complete and exact; the displayed
// bank stays intact until the next take. Reports frames sent / completed (published) / taken by the display.
module tbo;
  parameter real TSEND=66636.0, DRAIN=2000.0, TDISP=49977.0;   // default: 45 fps sender vs 60 Hz display
  parameter integer PACED=0, PEND_LAST=0;   // PEND_LAST: drain flag set by the last pixel (z29b stereo_raw_memory1)   // 1: the frame's packets are spread evenly over TSEND (else back-to-back burst)
  localparam integer N=64*36;
  reg clk=0, pclk=0, rst=1; always #4 clk=~clk; always #6.6667 pclk=~pclk;
  reg gv=0, ge=0; reg [7:0] gd=0; reg drained=1, boundary=0;
  wire mv, fv, available; wire [1:0] mb, fb; wire [31:0] ma, fid, cc; wire [15:0] md;
  remote_media_ingress5 #(.WIDTH(64),.HEIGHT(36),.PAYLOAD_BYTES(256)) dut(.rx_clk(clk),.pixel_clk(pclk),.rst(rst),
    .gmii_valid(gv),.gmii_error(ge),.gmii_data(gd),
    .mem_valid(mv),.mem_bank(mb),.mem_ready(1'b1),.mem_drained(drained),
    .mem_pixel_addr(ma),.mem_pixel_data(md),.display_safe_boundary(boundary),
    .front_valid(fv),.front_bank(fb),.front_id(fid),.complete_count(cc),
    .bad_network_packets(),.bad_video_packets(),.write_available(available));
  reg [15:0] memory [0:3*N-1];
  integer errors=0, writes=0, k;
  function automatic [15:0] pattern(input integer index, input integer id); pattern=(index*37+id*257)&65535; endfunction
  // DDR model + front protection
  real last_write=0.0; reg wrote=0;
  always @(posedge clk) if(!rst && mv) begin
    if(ma>=N) begin errors=errors+1; $display("BAD address %0d", ma); end
    if(fv && mb==fb) begin errors=errors+1; if(errors<10) $display("BAD write into displayed bank %0d (fid %0d) at %0t", fb, fid, $time); end
    memory[mb*N+ma] <= md; writes=writes+1;
    if(PEND_LAST ? ma==N-1 : ma==0) drained=0;
    if(ma==N-1) begin last_write=$realtime; wrote=1; end
  end
  always @(posedge clk) if(wrote && $realtime-last_write>=DRAIN) begin drained=1; wrote=0; end
  // display: safe boundary every TDISP; check the taken frame and that the held one stayed intact
  integer taken=0, last_fid=-1, held_bank=-1, held_fid=-1, bad_img;
  task automatic check_bank(input integer b, input integer id, input [8*16-1:0] what);
    begin bad_img=0; for(k=0;k<N;k=k+1) if(memory[b*N+k]!==pattern(k,id)) bad_img=bad_img+1;
      if(bad_img) begin errors=errors+1; $display("BAD %0s bank %0d fid %0d: %0d pixels wrong", what, b, id, bad_img); end end
  endtask
  initial begin
    #1000;
    forever begin
      #(TDISP);
      if(held_bank>=0) check_bank(held_bank, held_fid, "held");
      @(negedge pclk); boundary=1; @(negedge pclk); boundary=0; repeat(2) @(negedge pclk);
      if(fv && fid!=last_fid) begin
        taken=taken+1; last_fid=fid; held_bank=fb; held_fid=fid; check_bank(fb, fid, "taken");
      end
    end
  end
  // sender
  integer f, s, v, j, len, nf, np, p, sent=0; reg [8*2-1:0] tag;
  initial begin
    repeat(10) @(negedge clk); rst=0; repeat(20) @(negedge clk);
    f=$fopen("vectors.txt","r"); if(!f) $fatal(1,"missing vectors");
    while(!$feof(f)) begin
      s=$fscanf(f,"F %d %d\n",nf,np); if(s!=2) break;
      while($realtime < nf*TSEND) @(negedge clk);
      for(p=0;p<np;p=p+1) begin
        s=$fscanf(f,"%d",len);
        for(j=0;j<len;j=j+1) begin s=$fscanf(f,"%h",v); @(negedge clk); gv=1; gd=v; end
        @(negedge clk); gv=0; repeat(11) @(negedge clk);
        if(PACED) while($realtime < nf*TSEND + (p+1)*TSEND/np) @(negedge clk);
        s=$fscanf(f,"\n");
      end
      sent=sent+1;
    end
    #(3*TSEND);
    $display("FINAL CDC=%0s PACED=%0d TSEND=%0.0f TDISP=%0.0f DRAIN=%0.0f sent=%0d completed=%0d taken_by_display=%0d (rate %0.1f%% of sent) errors=%0d %s",
      `CDCNAME, PACED, TSEND, TDISP, DRAIN, sent, cc, taken, 100.0*taken/sent, errors, errors==0 ? "PASS" : "FAIL");
    $finish;
  end
endmodule
