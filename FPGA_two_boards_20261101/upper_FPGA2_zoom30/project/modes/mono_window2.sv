// One shared centered3x3 luma window and exact centre RGB. Three row banks
// avoid active read/write same-address collisions. No RAM reset/old-frame use.
module mono_window2 #(parameter integer WIDTH=1280,HEIGHT=720,HTOTAL=1650)(
 input wire clk,rst_n,vs_i,de_i,input wire [23:0] rgb_i,
 output reg valid_o,output reg [11:0] x_o,y_o,
 output reg [23:0] rgb_o,output reg [71:0] grey_o);
 reg vs_d,de_d;reg [11:0] ix,iy;reg [1:0] bank;
 reg flush_waiting,flushing;reg [11:0] wait_count,fx;
 wire boundary=vs_i&&!vs_d;
 wire fall=de_d&&!de_i;
 wire start_flush=flush_waiting&&wait_count==0;
 wire proc=de_i||fall||flushing||start_flush;
 wire [11:0] xx=de_i?ix:fall?WIDTH:flushing?fx:12'd0;
 wire [11:0] yy=(flushing||start_flush)?HEIGHT:iy;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin vs_d<=0;de_d<=0;ix<=0;iy<=0;bank<=0;flush_waiting<=0;flushing<=0;wait_count<=0;fx<=0;end
  else begin
   vs_d<=vs_i;de_d<=de_i;
   if(boundary)begin ix<=0;iy<=0;bank<=0;flush_waiting<=0;flushing<=0;fx<=0;end
   else begin
    if(de_i)ix<=ix+1'b1;
    if(fall)begin
     ix<=0;iy<=iy+1'b1;bank<=bank==2?0:bank+1'b1;
     if(iy==HEIGHT-1)begin flush_waiting<=1;wait_count<=HTOTAL-WIDTH-1;end
    end
    if(flush_waiting)begin
     if(wait_count!=0)wait_count<=wait_count-1'b1;
     else begin flush_waiting<=0;flushing<=1;fx<=1;end
    end
    if(flushing)begin if(fx==WIDTH)flushing<=0;else fx<=fx+1'b1;end
   end
  end
 end
 wire [23:0] q[0:2];
 genvar k;
 generate for(k=0;k<3;k=k+1)begin:rows
  reg [23:0] mem[0:WIDTH-1];reg [23:0] rq;
  always @(posedge clk)begin
   if(rst_n&&de_i&&bank==k)mem[ix]<=rgb_i;
   if(rst_n&&proc&&xx<WIDTH&&bank!=k)rq<=mem[xx];
  end
  assign q[k]=rq;
 end endgenerate
 reg pv;reg [11:0] px,py;reg [1:0] pb;reg [23:0] bottom;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin pv<=0;px<=0;py<=0;pb<=0;bottom<=0;end
  else begin pv<=proc&&!boundary;px<=xx;py<=yy;pb<=bank;bottom<=de_i?rgb_i:24'd0;end
 end
 wire [23:0] middle=(py>=1&&px<WIDTH)?(pb==0?q[2]:pb==1?q[0]:q[1]):24'd0;
 wire [23:0] top=(py>=2&&px<WIDTH)?(pb==0?q[1]:pb==1?q[2]:q[0]):24'd0;
 function automatic [7:0] luma(input [23:0] p);
  reg [15:0] r,g,b,s;begin r={8'd0,p[23:16]};g={8'd0,p[15:8]};b={8'd0,p[7:0]};
   s=(r<<6)+(r<<3)+(r<<2)+r+(g<<7)+(g<<4)+(g<<2)+(g<<1)+(b<<4)+(b<<3)+(b<<2)+b;
   luma=s[15:8];end
 endfunction
 reg [7:0] tl2,tl1,ml2,ml1,bl2,bl1;reg [23:0] previous_middle;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   valid_o<=0;x_o<=0;y_o<=0;rgb_o<=0;grey_o<=0;tl2<=0;tl1<=0;ml2<=0;ml1<=0;bl2<=0;bl1<=0;previous_middle<=0;
  end else begin
   valid_o<=pv&&px>=1&&px<=WIDTH&&py>=1&&py<=HEIGHT;
   if(pv)begin
    x_o<=px-1'b1;y_o<=py-1'b1;rgb_o<=previous_middle;
    grey_o<={luma(bottom),bl1,bl2,luma(middle),ml1,ml2,luma(top),tl1,tl2};
    if(px==0)begin tl2<=0;ml2<=0;bl2<=0;end
    else begin tl2<=tl1;ml2<=ml1;bl2<=bl1;end
    tl1<=luma(top);ml1<=luma(middle);bl1<=luma(bottom);previous_middle<=middle;
   end
  end
 end
endmodule
