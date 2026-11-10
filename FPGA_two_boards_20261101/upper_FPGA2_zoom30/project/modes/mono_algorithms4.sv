// Shared arithmetic, four register stages. Spatial modes operate on luma.
// CLAUDE MERGE (2026-10-27): the six parallel 3x3 kernels (sum/mean, Gauss, Sobel-X, Laplace, sharpen, emboss) share one
// mode-programmed adder tree (coefficients -2..5 per tap); Sobel-Y keeps its own tree (Sobel magnitude needs both). /9 by a
// constant multiply (exact for sums <= 2295). Bit-identical outputs to the reference (unit_mono random test).
// CLAUDE Z10 AREA: KEEP[id] = 1 keeps mode id (all ones = the z9 behaviour); a dropped mode passes the camera image
// through and its kernel class / point function / divider is removed from the logic.
// CLAUDE Z14 (board: LAPLACE too dark): LAPLACE shows |4-neighbour Laplacian| x 4 (saturated at 255), was x 1.
module mono_algorithms4 #(parameter integer SECOND_STAGE=0, parameter [63:0] KEEP=64'hffff_ffff_ffff_ffff)(input wire clk,rst_n,valid_i,input wire [7:0] mode_i,
 input wire [11:0] x_i,y_i,input wire [23:0] rgb_i,input wire [71:0] grey_i,
 output reg valid_o,output reg [7:0] mode_o,output reg [11:0] x_o,y_o,output reg [23:0] rgb_o);
 `include "G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/modes/mode_catalog.vh"
 `include "G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/modes/legacy_point_functions.vh"
 `include "G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/modes/mono_style_functions.vh"
 localparam [63:0] KM = KEEP & MODE_KEEP;                      // Z10: reachable modes only (mode_tables.vh)
 wire [7:0] w0=grey_i[7:0],w1=grey_i[15:8],w2=grey_i[23:16],w3=grey_i[31:24],w4=grey_i[39:32],w5=grey_i[47:40],w6=grey_i[55:48],w7=grey_i[63:56],w8=grey_i[71:64];
 function automatic [7:0] bright(input [7:0] a);bright=a>223?255:a+8'd32;endfunction
 function automatic [23:0] point(input [7:0] m,input [23:0] p,input [7:0] g);
  begin if(SECOND_STAGE)point=p;else case(m)
   MODE_GRAY:point=KM[MODE_GRAY]?{g,g,g}:p;MODE_BINARY:point=KM[MODE_BINARY]?(g>=128?24'hffffff:24'd0):p;MODE_INVERT:point=KM[MODE_INVERT]?~p:p;
   MODE_RED:point=KM[MODE_RED]?{p[23:16],16'd0}:p;MODE_GREEN:point=KM[MODE_GREEN]?{8'd0,p[15:8],8'd0}:p;MODE_BLUE:point=KM[MODE_BLUE]?{16'd0,p[7:0]}:p;
   MODE_BRIGHT:point=KM[MODE_BRIGHT]?{bright(p[23:16]),bright(p[15:8]),bright(p[7:0])}:p;
   MODE_CONTRAST:point=KM[MODE_CONTRAST]?{F_contrast(p[23:16]),F_contrast(p[15:8]),F_contrast(p[7:0])}:p;
   // CLAUDE ZOOM5: MODE_SKIN / MODE_CHROMA are produced outside point() (row hysteresis, see sk_hit / ch_hit)
   MODE_HEATMAP:point=KM[MODE_HEATMAP]?heat_palette(g):p;
   MODE_POSTER:point=KM[MODE_POSTER]?poster_rgb(p):p;MODE_SEPIA:point=KM[MODE_SEPIA]?sepia_rgb(p):p;
   MODE_SOLAR:point=KM[MODE_SOLAR]?{solar_channel(p[23:16]),solar_channel(p[15:8]),solar_channel(p[7:0])}:p;
   default:point=p; // Gamma mode removed from compact hardware/menu.
  endcase end
 endfunction
 function automatic [23:0] sort3(input [7:0] a,b,c);
  reg [7:0] lo,hi,mid;begin lo=a<b?a:b;hi=a<b?b:a;
   if(c<lo)begin mid=lo;lo=c;end else if(c>hi)begin mid=hi;hi=c;end else mid=c;
   sort3={hi,mid,lo};end
 endfunction
 function automatic [7:0] median3(input [7:0] a,b,c);reg [23:0] s;begin s=sort3(a,b,c);median3=s[15:8];end endfunction
 // CLAUDE ZOOM5 (2026-10-28, board: washed-out camera image, streaky skin mask): 25 SKIN / 26 CHROMA with row hysteresis
 // (enter threshold strict, stay threshold loose, reset at x = 0) and a saturation boost of the kept pixels (2c - grey).
 //   SKIN  : enter R>60, R-G>=10, R-B>=16, G>=B-4, R-G<=90; stay R>50, R-G>=5, R-B>=9, G>=B-8, R-G<=100.
 //           skin -> vivid colour, else grey / 2.
 //   CHROMA: colour splash, saturation (max-min) enter > 28, stay > 16 -> vivid colour, else grey.
 function automatic [7:0] vivid1(input [7:0] c, input [7:0] g);reg signed [10:0] v;begin
  v=$signed({3'd0,c,1'b0})-$signed({3'd0,g});vivid1=v<0?8'd0:v>255?8'd255:v[7:0];end endfunction
 function automatic [23:0] vivid(input [23:0] p, input [7:0] g);vivid={vivid1(p[23:16],g),vivid1(p[15:8],g),vivid1(p[7:0],g)};endfunction
 wire [7:0] cr=rgb_i[23:16], cg=rgb_i[15:8], cb=rgb_i[7:0];
 wire [8:0] crg={1'b0,cr}-{1'b0,cg}, crb={1'b0,cr}-{1'b0,cb};               // valid when cr >= cg / cb
 // CLAUDE Z17 (board: streaky SKIN, pink / grey false hits): per-pixel test without row hysteresis (the hysteresis smeared
 // hits along the row); skin = R > 80, G > 40, B > 20, R - G 12..110, R - B >= 20, G >= B (orange hue: pink and grey have B >= G).
 wire sk_enter=cr>8'd80 && cg>8'd40 && cb>8'd20 && cr>=cg && cr>=cb && crg>=9'd12 && crg<=9'd110 && crb>=9'd20 && cg>=cb;
 wire sk_stay =cr>8'd50 && cr>=cg && cr>=cb && crg>=9'd5  && crb>=9'd9  && {1'b0,cg}+9'd8>={1'b0,cb} && crg<=9'd100;
 wire [7:0] csat=max3(cr,cg,cb)-min3(cr,cg,cb);
 reg sk_st, ch_st;
 wire sk_hit=sk_enter;                                         // Z17: no row hysteresis
 wire ch_hit=csat>8'd22;                                       // Z17 CHROMA: per pixel (no row hysteresis), saturation > 22
 always @(posedge clk or negedge rst_n) if(!rst_n) begin sk_st<=0; ch_st<=0; end else if(valid_i) begin sk_st<=sk_hit; ch_st<=ch_hit; end
 function automatic [7:0] min3(input [7:0] a,b,c);reg [7:0] q;begin q=a<b?a:b;min3=q<c?q:c;end endfunction
 function automatic [7:0] max3(input [7:0] a,b,c);reg [7:0] q;begin q=a>b?a:b;max3=q>c?q:c;end endfunction
 function automatic [7:0] clip(input signed [12:0] a);begin clip=a<0?0:a>255?255:a[7:0];end endfunction
 function automatic [7:0] absclip(input signed [12:0] a);reg signed [12:0] v;begin v=a<0?-a:a;absclip=v>255?255:v[7:0];end endfunction
 localparam KSUM_EN = KM[MODE_MEAN];                          // Z17: ADAPTIVE no longer uses the 3x3 mean
 // CLAUDE Z17 (board: 3x3 ADAPTIVE showed almost nothing, e.g. on a checkerboard): block adaptive threshold over a window
 // larger than the features. Luma is summed per 32 x 32 block (40 columns, one 32-line band at a time, running sum per
 // column in a small distributed RAM); at the band end the block mean is stored. The threshold of a pixel is the mean of
 // the 4 blocks of the last finished band at columns c - 1 .. c + 2 (128 x 32 px, edges replicated); the pixel is black
 // when darker than it by more than 8, else white.
 reg [17:0] bacc [0:39]; reg [7:0] bmean [0:39]; reg [17:0] brun;
 wire [5:0] bcol = x_i[10:5];
 wire [17:0] bsum = ((x_i[4:0]==5'd0) ? ((y_i[4:0]==5'd0) ? 18'd0 : bacc[bcol]) : brun) + {10'd0, w4};
 always @(posedge clk) if(KM[MODE_ADAPTIVE] && valid_i && x_i < 12'd1280 && y_i < 12'd720) begin
  brun <= bsum;
  if(x_i[4:0]==5'd31) begin if(y_i[4:0]==5'd31) bmean[bcol] <= bsum[17:10]; else bacc[bcol] <= bsum; end
 end
 // CLAUDE Z18: GAMMA (id 10, was unreachable) back as a per-channel table (gamma_value of legacy_point_functions.vh) in
 // block RAM: two ROM copies (3 reads per pixel, 2 ports each), address = camera pixel of stage a, result aligned to stage c.
 wire [23:0] gmq; reg [23:0] gmb, gmc;
 generate if(!SECOND_STAGE && KM[MODE_GAMMA]) begin : g_gamma
  (* ram_style="bram" *) reg [7:0] grom0 [0:255]; (* ram_style="bram" *) reg [7:0] grom1 [0:255];
  initial begin $readmemh("G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/modes/gamma_lut.hex", grom0); $readmemh("G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30/modes/gamma_lut.hex", grom1); end
  reg [7:0] q2, q1, q0;
  always @(posedge clk) begin q2 <= grom0[rgb_i[23:16]]; q1 <= grom0[rgb_i[15:8]]; q0 <= grom1[rgb_i[7:0]]; end
  assign gmq = {q2, q1, q0};
 end else begin : g_nogamma assign gmq = 24'd0; end endgenerate
 always @(posedge clk) begin gmb <= gmq; gmc <= gmb; end
 reg [7:0] ga,gb,gc;
 reg va,vb,vc;reg [7:0] ma,mb,mc;reg [11:0] xa,ya,xb,yb,xc,yc;
 // window sum fetched serially through one bmean read port (4 parallel reads made TD copy the RAM 4 times): during
 // block k (input x 32k+9 .. 32k+12) the 4 means for block k+1 (block 0 of the next line during block 39) are added,
 // latched at 32k+13 and taken over when stage b enters block k+1
 reg [9:0] wacc, wnext, bwin;
 wire [5:0] btg = (bcol>=6'd39) ? 6'd0 : bcol + 6'd1;
 wire [6:0] bsx = {1'b0,btg} + {2'd0,x_i[4:0]} - 7'd10;         // x 9..12 -> target - 1 .. target + 2
 wire [5:0] bra = bsx[6] ? 6'd0 : (bsx[5:0]>6'd39) ? 6'd39 : bsx[5:0];
 always @(posedge clk) if(KM[MODE_ADAPTIVE] && valid_i && x_i < 12'd1280) begin
  if(x_i[4:0]==5'd8) wacc <= 10'd0;
  else if(x_i[4:0]>=5'd9 && x_i[4:0]<=5'd12) wacc <= wacc + {2'd0, bmean[bra]};
  else if(x_i[4:0]==5'd13) wnext <= wacc;
 end
 always @(posedge clk) if(KM[MODE_ADAPTIVE] && vb && xb[4:0]==5'd0) bwin <= wnext;
 wire [7:0] bmc = bwin[9:2];                                    // window mean (4 blocks) for the stage-c pixel
 reg [23:0] pa,pb,pc,ra0,ra1,ra2;
 reg erodea,dilatea,erodeb,dilateb,erodec,dilatec;
 // kernel classes of the shared tree
 localparam [2:0] K_SUM=0,K_GAUSS=1,K_GX=2,K_LAP=3,K_SHARP=4,K_EMB=5,K_DIAG=6;
 function automatic [2:0] kclass(input [7:0] m);
  case(m) MODE_GAUSS:kclass=K_GAUSS;MODE_LAPLACE:kclass=KM[MODE_LAPLACE]?K_LAP:K_GX;MODE_SHARPEN:kclass=KM[MODE_SHARPEN]?K_SHARP:K_GX;
   MODE_EMBOSS:kclass=KM[MODE_EMBOSS]?K_EMB:K_GX;MODE_DIAG:kclass=KM[MODE_DIAG]?K_DIAG:K_GX;
   MODE_SOBEL_X,MODE_SOBEL,MODE_EDGE,MODE_EDGE_RGB,MODE_SKETCH,MODE_CARTOON:kclass=K_GX;default:kclass=KSUM_EN?K_SUM:K_GX;endcase
 endfunction
 // coefficient of tap t (w0..w8 = rows top..bottom, columns left..right) for kernel class k: -2,-1,0,1,2,4,5
 function automatic signed [3:0] coef(input [2:0] k,input integer t);
  case(k)
   K_GAUSS:coef=(t==4)?4'sd4:(t==1||t==3||t==5||t==7)?4'sd2:4'sd1;
   K_GX:coef=(t==2||t==8)?4'sd1:(t==5)?4'sd2:(t==0||t==6)?-4'sd1:(t==3)?-4'sd2:4'sd0;
   K_LAP:coef=(t==4)?4'sd4:(t==1||t==3||t==5||t==7)?-4'sd1:4'sd0;
   K_SHARP:coef=(t==4)?4'sd5:(t==1||t==3||t==5||t==7)?-4'sd1:4'sd0;
   K_EMB:coef=(t==0)?-4'sd2:(t==1||t==3)?-4'sd1:(t==4||t==5||t==7)?4'sd1:(t==8)?4'sd2:4'sd0;
   K_DIAG:coef=(t==2)?4'sd2:(t==1||t==5)?4'sd1:(t==3||t==7)?-4'sd1:(t==6)?-4'sd2:4'sd0;   // Z18: Sobel 45 degrees
   default:coef=4'sd1;
  endcase
 endfunction
 function automatic signed [12:0] term(input [7:0] w,input signed [3:0] c);
  reg signed [12:0] v;begin v=$signed({5'd0,w});
   case(c) 4'sd1:term=v;4'sd2:term=v<<<1;4'sd4:term=v<<<2;4'sd5:term=(v<<<2)+v;-4'sd1:term=-v;-4'sd2:term=-(v<<<1);default:term=13'sd0;endcase end
 endfunction
 wire [2:0] ki=kclass(mode_i);
 wire signed [12:0] tree_n=term(w0,coef(ki,0))+term(w1,coef(ki,1))+term(w2,coef(ki,2))+term(w3,coef(ki,3))+term(w4,coef(ki,4))+
  term(w5,coef(ki,5))+term(w6,coef(ki,6))+term(w7,coef(ki,7))+term(w8,coef(ki,8))+((ki==K_EMB)?13'sd128:13'sd0);
 reg signed [12:0] treea,gya;reg [2:0] ka,kb;
 reg [7:0] kvb,gyb,medlo,medmid,medhi;
 reg [7:0] kvc,gyc,medianc,magc,edgec;
 wire [24:0] div9=treea[11:0]*13'd7282;                         // floor(s / 9) for s <= 2295
 wire [8:0] magnitude={1'b0,kvb}+{1'b0,gyb};
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   ga<=0;gb<=0;gc<=0;va<=0;vb<=0;vc<=0;valid_o<=0;ma<=1;mb<=1;mc<=1;mode_o<=1;xa<=0;ya<=0;xb<=0;yb<=0;xc<=0;yc<=0;x_o<=0;y_o<=0;
   erodea<=0;dilatea<=0;erodeb<=0;dilateb<=0;erodec<=0;dilatec<=0;
   pa<=0;pb<=0;pc<=0;rgb_o<=0;ra0<=0;ra1<=0;ra2<=0;treea<=0;gya<=0;ka<=0;kb<=0;
   kvb<=0;gyb<=0;medlo<=0;medmid<=0;medhi<=0;kvc<=0;gyc<=0;medianc<=0;magc<=0;edgec<=0;
  end else begin
   ga<=w4;gb<=ga;gc<=gb;
   va<=valid_i;ma<=mode_i;xa<=x_i;ya<=y_i;
   pa<=(KM[MODE_SKIN]&&mode_i==MODE_SKIN)?(sk_hit?vivid(rgb_i,w4):{1'b0,w4[7:1],1'b0,w4[7:1],1'b0,w4[7:1]}):
       (KM[MODE_CHROMA]&&mode_i==MODE_CHROMA)?(ch_hit?vivid(rgb_i,w4):{w4,w4,w4}):point(mode_i,rgb_i,w4);
   erodea<=&{w0[7],w1[7],w2[7],w3[7],w4[7],w5[7],w6[7],w7[7],w8[7]};
   dilatea<=|{w0[7],w1[7],w2[7],w3[7],w4[7],w5[7],w6[7],w7[7],w8[7]};
   treea<=tree_n;ka<=ki;
   gya<=$signed({5'd0,w6})+($signed({5'd0,w7})<<<1)+$signed({5'd0,w8})-$signed({5'd0,w0})-($signed({5'd0,w1})<<<1)-$signed({5'd0,w2});
   ra0<=sort3(w0,w1,w2);ra1<=sort3(w3,w4,w5);ra2<=sort3(w6,w7,w8);
   vb<=va;mb<=ma;xb<=xa;yb<=ya;pb<=pa;
   erodeb<=erodea;dilateb<=dilatea;kb<=ka;gyb<=absclip(gya);
   case(ka) K_SUM:kvb<=KSUM_EN?div9[23:16]:8'd0;K_GAUSS:kvb<=treea[11:4];K_GX,K_DIAG:kvb<=absclip(treea);K_LAP:kvb<=absclip(treea<<<2);default:kvb<=clip(treea);endcase
   medlo<=max3(ra0[7:0],ra1[7:0],ra2[7:0]);medmid<=median3(ra0[15:8],ra1[15:8],ra2[15:8]);medhi<=min3(ra0[23:16],ra1[23:16],ra2[23:16]);
   vc<=vb;mc<=mb;xc<=xb;yc<=yb;pc<=pb;
   erodec<=erodeb;dilatec<=dilateb;
   kvc<=kvb;gyc<=gyb;medianc<=median3(medlo,medmid,medhi);
   magc<=magnitude>255?255:magnitude[7:0];edgec<=magnitude>=128?255:0;
   valid_o<=vc;mode_o<=mc;x_o<=xc;y_o<=yc;
   if(SECOND_STAGE)begin
    case(mc) MODE_OPEN:rgb_o<=dilatec?24'hffffff:24'd0;MODE_CLOSE:rgb_o<=erodec?24'hffffff:24'd0;default:rgb_o<=pc;endcase
   end else case(mc)
    MODE_EDGE_RGB:rgb_o<=KM[MODE_EDGE_RGB]?(edgec==255?24'h00ff00:pc):pc;
    MODE_ADAPTIVE:rgb_o<=KM[MODE_ADAPTIVE]?(({1'b0,gc}+9'd8>={1'b0,bmc})?24'hffffff:24'd0):pc;   // Z17: block adaptive threshold
    MODE_SKETCH:rgb_o<=KM[MODE_SKETCH]?{3{8'hff-magc}}:pc;
    MODE_CARTOON:rgb_o<=KM[MODE_CARTOON]?(magc>=96?24'd0:poster_rgb(pc)):pc;
    MODE_ERODE:rgb_o<=KM[MODE_ERODE]?(erodec?24'hffffff:24'd0):pc;
    MODE_DILATE:rgb_o<=KM[MODE_DILATE]?(dilatec?24'hffffff:24'd0):pc;
    MODE_EMBOSS:rgb_o<=KM[MODE_EMBOSS]?{kvc,kvc,kvc}:pc;
    MODE_MEAN:rgb_o<=KM[MODE_MEAN]?{kvc,kvc,kvc}:pc;MODE_GAUSS:rgb_o<=KM[MODE_GAUSS]?{kvc,kvc,kvc}:pc;
    MODE_SHARPEN:rgb_o<=KM[MODE_SHARPEN]?{kvc,kvc,kvc}:pc;MODE_LAPLACE:rgb_o<=KM[MODE_LAPLACE]?{kvc,kvc,kvc}:pc;MODE_SOBEL_X:rgb_o<=KM[MODE_SOBEL_X]?{kvc,kvc,kvc}:pc;
    MODE_SOBEL_Y:rgb_o<=KM[MODE_SOBEL_Y]?{gyc,gyc,gyc}:pc;MODE_SOBEL:rgb_o<=KM[MODE_SOBEL]?{magc,magc,magc}:pc;MODE_EDGE:rgb_o<=KM[MODE_EDGE]?{edgec,edgec,edgec}:pc;
    MODE_DIAG:rgb_o<=KM[MODE_DIAG]?{kvc,kvc,kvc}:pc;                        // Z18: DIAG EDGE
    MODE_GAMMA:rgb_o<=KM[MODE_GAMMA]?gmc:pc;                                // Z18: GAMMA (ERAM table)
    default:rgb_o<=pc;
   endcase
  end
 end
endmodule
