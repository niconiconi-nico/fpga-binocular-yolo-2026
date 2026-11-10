// False-colour luma visualization, NOT a physical temperature measurement.
function automatic [23:0] heat_palette(input [7:0] y);
 reg [7:0] t;begin
  t={y[5:0],y[5:4]};
  case(y[7:6])
   0:heat_palette={8'd0,t,8'hff};
   1:heat_palette={8'd0,8'hff,8'hff-t};
   2:heat_palette={t,8'hff,8'd0};
   3:heat_palette={8'hff,8'hff-t,8'd0};
  endcase
 end
endfunction
function automatic [7:0] poster_channel(input [7:0] c);
 poster_channel={c[7:5],c[7:5],c[7:6]};
endfunction
function automatic [23:0] poster_rgb(input [23:0] p);
 poster_rgb={poster_channel(p[23:16]),poster_channel(p[15:8]),poster_channel(p[7:0])};
endfunction
function automatic [7:0] solar_channel(input [7:0] c);
 solar_channel=c[7]?8'hff-c:c;
endfunction
function automatic [23:0] sepia_rgb(input [23:0] p);
 reg [17:0] r,g,b;begin
  r=18'd101*p[23:16]+18'd197*p[15:8]+18'd48*p[7:0];
  g=18'd89*p[23:16]+18'd176*p[15:8]+18'd43*p[7:0];
  b=18'd70*p[23:16]+18'd137*p[15:8]+18'd34*p[7:0];
  sepia_rgb={r[17:8]>255?8'hff:r[15:8],g[17:8]>255?8'hff:g[15:8],b[17:8]>255?8'hff:b[15:8]};
 end
endfunction
