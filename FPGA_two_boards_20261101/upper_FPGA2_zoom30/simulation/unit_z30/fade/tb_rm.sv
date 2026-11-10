`timescale 1ns/1ps
// CLAUDE Z30 range_meter TEMPLATE (track_only, !rwin) RTL test: the real range_meter with the vision_core left window RAM
// model (4 byte lanes x 4096, camera-clock write, pixel-clock registered read) and a camera stream from frames.bin
// (grey uint8 1280x720 per frame, sent as R = G = B, 4 pixels per beat, pixel 0 in [95:72]). KEY4 long press at start =
// lock at pos 4 (640, 360). Every tracking result (target_update) is logged with the index of the frame its window was
// captured from (capture start = the camera-domain lon rise) -> compared with the exact model offline (check_rtl.py).
module tb_rm;
  parameter integer NFR=60, NUPD=40, BLANK=300000;
  reg cclk=0, pclk=0, rst_n=0; always #5 cclk=~cclk; always #6.6667 pclk=~pclk;
  reg l_valid=0, l_sof=0, l_eol=0; reg [95:0] l_data=0; reg key_n=1;
  wire w_we; wire [11:0] w_wa, waddr; wire [31:0] w_wd; reg [7:0] wq [0:3];
  wire [3:0] pos; wire [10:0] cx; wire [9:0] cy; wire [1:0] lock; wire tu, tg;
  range_meter #(.GRID_FILE("range_grid.hex"),.DEBOUNCE(4),.LONGPRESS(60),.MS_TICK(0)) dut(
    .cam_clk(cclk),.cam_rst_n(rst_n),.l_valid(l_valid),.l_sof(l_sof),.l_eol(l_eol),.l_data(l_data),
    .rx_clk(cclk),.rx_rst(!rst_n),.r_valid(1'b0),.r_addr(32'd0),.r_data(16'd0),
    .pclk(pclk),.prst_n(rst_n),.enable(1'b1),.key_n(key_n),.run(1'b1),.track_only(1'b1),
    .rwin(1'b0),.rwin_rx(1'b0),.seed(1'b0),.seed_x(11'd0),.seed_y(10'd0),.drop(1'b0),
    .waddr14(),.kst_o(),.moved(),.w_we(w_we),.w_wa(w_wa),.w_wd(w_wd),.waddr(waddr),.wq0(wq[0]),.wq1(wq[1]),.wq2(wq[2]),.wq3(wq[3]),
    .s_we(),.s_wa(),.s_wd(),.raddr(),.rq(8'd0),
    .pos(pos),.cx(cx),.cy(cy),.lock(lock),.status(),.z_bcd(),.d_bcd(),.d_tenth(),.results(),
    .target_update(tu),.target_good(tg),.ms(1'b0));
  reg [7:0] lmem [0:3][0:4095];
  integer k;
  always @(posedge cclk) if(w_we) for(k=0;k<4;k=k+1) lmem[k][w_wa] <= w_wd[31-8*k -: 8];
  always @(posedge pclk) for(k=0;k<4;k=k+1) wq[k] <= lmem[k][waddr];
  // frames
  reg [7:0] fr [0:1280*720-1];
  integer fd, fi=0, cap_frame=-1, x, y, r, nupd=0, logf;
  reg lon_d=0;
  always @(posedge cclk) begin lon_d <= dut.lon; if(dut.lon && !lon_d) cap_frame <= fi; end
  always @(posedge pclk) if(tu) begin
    $fdisplay(logf, "%0d %0d %0d %0d %0d", cap_frame, cx, cy, lock, tg);
    if(lock!=0) nupd = nupd + 1;
    if(nupd >= NUPD) begin $display("DONE updates=%0d last_frame=%0d", nupd, fi); $fclose(logf); $finish; end
  end
  initial begin repeat(60) @(posedge pclk); key_n = 0; repeat(200) @(posedge pclk); key_n = 1; end   // KEY4 long press = lock
  initial begin
    logf = $fopen("rtl_log.txt", "w");
    fd = $fopen("frames.bin", "rb"); if(!fd) $fatal(1, "frames.bin");
    repeat(20) @(posedge cclk); rst_n = 1;
    for(fi=0; fi<NFR; fi=fi+1) begin
      r = $fread(fr, fd); if(r != 1280*720) $fatal(1, "short frame %0d", fi);
      for(y=0; y<720; y=y+1) for(x=0; x<1280; x=x+4) begin
        @(negedge cclk);
        l_valid = 1; l_sof = (x==0 && y==0); l_eol = (x==1276);
        l_data = {{3{fr[y*1280+x]}}, {3{fr[y*1280+x+1]}}, {3{fr[y*1280+x+2]}}, {3{fr[y*1280+x+3]}}};
      end
      @(negedge cclk); l_valid = 0; l_sof = 0; l_eol = 0;
      repeat(BLANK) @(negedge cclk);                                  // vertical blanking
    end
    $display("END OF FRAMES updates=%0d", nupd); $fclose(logf); $finish;
  end
endmodule
