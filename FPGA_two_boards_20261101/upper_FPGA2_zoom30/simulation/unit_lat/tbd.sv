`timescale 1ns/1ps
// CLAUDE Z25 LATENCY panel render: mono_display6 (z25) frame with fixed latency values -> top 24 rows x 360 px dumped as
// hex RGB per line (converted to PNG outside). MODE = external mode id; OK = lat_ok.
module tbd;
  parameter integer MODE=37, OK=1;
  reg clk=0, rst_n=0; always #5 clk=~clk;
  integer hc=0, vc=0;
  wire de = hc<1280 && vc<720, vs = vc>=725 && vc<730, hs = hc>=1390 && hc<1430;
  always @(posedge clk) if(hc==1649) begin hc<=0; vc<= vc==749 ? 0 : vc+1; end else hc<=hc+1;
  wire [23:0] rgb_i = {hc[7:0], vc[7:0], 8'h40};
  wire ho, vo, deo; wire [23:0] rgb_o;
  mono_display6 #(.ENABLE_TEMPLATE(0)) mono(.clk(clk),.rst_n(rst_n),.key_n(3'b111),.capture_key_n(1'b1),.external_mode_i(8'(MODE)),.diag_flags_i(13'd0),
    .hs_i(hs),.vs_i(vs),.de_i(de),.rgb_i(rgb_i),.hs_o(ho),.vs_o(vo),.de_o(deo),.rgb_o(rgb_o),
    .active_mode_o(),.requested_mode_o(),.det_found_o(),.det_x_o(),.det_y_o(),.det_score_o(),.det_status_o(),.det_epoch_o(),
    .lat_ok(OK!=0),.lat_bcd(12'h334),.cap_bcd(16'h0125),.dsp_bcd(16'h0123));
  integer f, ox=0, oy=0, frame=0; reg vod=0, ded=0;
  initial f = $fopen("panel.hex", "w");
  always @(posedge clk) begin
    vod<=vo; ded<=deo;
    if(vo && !vod) begin frame<=frame+1; oy<=0; end
    if(deo) ox<=ox+1; else ox<=0;
    if(ded && !deo) oy<=oy+1;
    if(frame==2 && deo && oy<24 && ox<360) begin $fwrite(f, "%06h ", rgb_o); if(ox==359) $fwrite(f, "\n"); end
    if(frame==3) begin $fclose(f); $finish; end
  end
  initial begin repeat(10) @(posedge clk); rst_n=1; end
endmodule
