// exhaustive check of latency_meter2 BCD functions binc / bsub against integer reference
module tbf;
  latency_meter2 m(.cam_clk(1'b0),.cam_rst_n(1'b0),.cam_sof(1'b0),.clk(1'b0),.rst_n(1'b0),.sof_g(),.sel_tg(1'b0),.sel_idx(2'd0),.ok(),.lat_bcd(),.cap_bcd(),.dsp_bcd());
  function [15:0] i2b(input integer v); i2b = {4'(v/1000), 4'((v/100)%10), 4'((v/10)%10), 4'(v%10)}; endfunction
  integer v, d, bad=0;
  initial begin
    for(v=0;v<10000;v=v+1) begin
      if(m.binc(i2b(v)) != i2b((v+1)%10000)) begin bad=bad+1; if(bad<5) $display("BAD inc %0d", v); end
      for(d=0;d<4;d=d+1) if(m.bsub(i2b(v), 2'(d)) != i2b((v-d+10000)%10000)) begin bad=bad+1; if(bad<5) $display("BAD sub %0d-%0d", v, d); end
    end
    $display("BCDFUNC bad=%0d %s", bad, bad==0 ? "PASS" : "FAIL"); $finish;
  end
endmodule
