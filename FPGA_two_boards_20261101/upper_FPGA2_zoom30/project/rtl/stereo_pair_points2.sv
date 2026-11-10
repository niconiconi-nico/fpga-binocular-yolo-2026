// Independent follow-on prototype. NOT connected to the running repair input.
// Input pair_ok means a frozen, row-tag-validated display pair, NOT synchronized
// exposure or rectification. Difference/overlay are never called metric depth.
module stereo_pair_points1 #(parameter integer WIDTH=640,HEIGHT=360)(
 input wire clk,rst,de_i,local_valid_i,remote_valid_i,pair_ok_i,frame_start_i,
 input wire[3:0]mode_i,input wire[10:0]x_i,input wire[9:0]y_i,
 input wire[15:0]local_i,remote_i,
 output reg valid_o,missing_o,output reg[31:0]missing_count,
 output reg[3:0]mode_o,output reg[10:0]x_o,output reg[9:0]y_o,
 output reg[15:0]local_o,remote_o
);
 function automatic[7:0]luma(input[15:0]p);
  reg[7:0]r,g,b;reg[15:0]sum;begin
   r={p[15:11],p[15:13]};g={p[10:5],p[10:9]};b={p[4:0],p[4:2]};
   sum=16'd77*r+16'd150*g+16'd29*b+16'd128;luma=sum[15:8];
  end
 endfunction
 function automatic[15:0]gray(input[7:0]v);gray={v[7:3],v[7:2],v[7:3]};endfunction
 function automatic[7:0]absolute_difference(input[7:0]a,b);absolute_difference=a>b?a-b:b-a;endfunction
 function automatic[7:0]edge_strength(input[7:0]a,b);
  reg[7:0]d;begin d=absolute_difference(a,b);edge_strength=d>=64?255:{d[5:0],2'b0};end
 endfunction
 function automatic[15:0]blend(input[15:0]a,b);
  reg[5:0]r,bv;reg[6:0]g;begin
   r={1'b0,a[15:11]}+{1'b0,b[15:11]}+1'b1;
   g={1'b0,a[10:5]}+{1'b0,b[10:5]}+1'b1;
   bv={1'b0,a[4:0]}+{1'b0,b[4:0]}+1'b1;blend={r[5:1],g[6:1],bv[5:1]};
  end
 endfunction
 reg de1,good1,frame1;reg[3:0]mode1;reg[10:0]x1;reg[9:0]y1;
 reg[15:0]left1,right1;reg[7:0]yl1,yr1;
 reg previous_valid;reg[10:0]previous_x;reg[9:0]previous_y;reg[7:0]previous_l,previous_r;
 wire adjacent=previous_valid&&!frame1&&x1!=0&&previous_y==y1&&previous_x+1'b1==x1;
 // Human-selected non-mixing modes: each output depends on its own eye only.
 // Cameras have real disparity and independent exposure; cross-eye blend,
 // red/cyan, difference and checker were NOT temporal DDR ghosts.
 function automatic[15:0]heat(input[7:0]v);
  reg[7:0]r,g,b,t;begin
   t={v[5:0],v[5:4]};r=0;g=0;b=0;
   case(v[7:6])
    0:begin g=t;b=255;end
    1:begin g=255;b=255-t;end
    2:begin r=t;g=255;end
    3:begin r=255;g=255-t;end
   endcase
   heat={r[7:3],g[7:2],b[7:3]};
  end
 endfunction
 function automatic[15:0]poster(input[15:0]p);
  poster={p[15:13],p[15:14],p[10:8],p[10:8],p[4:2],p[4:3]};
 endfunction
 function automatic[7:0]contrast(input[7:0]v);
  contrast=v<64?0:v>=192?255:((v-8'd64)<<1);
 endfunction
 function automatic[15:0]solar(input[15:0]p);
  solar={p[15]?~p[15:11]:p[15:11],p[10]?~p[10:5]:p[10:5],p[4]?~p[4:0]:p[4:0]};
 endfunction
 always @(posedge clk or posedge rst)begin
  if(rst)begin
   de1<=0;good1<=0;frame1<=0;mode1<=0;x1<=0;y1<=0;left1<=0;right1<=0;yl1<=0;yr1<=0;
   previous_valid<=0;previous_x<=0;previous_y<=0;previous_l<=0;previous_r<=0;
   valid_o<=0;missing_o<=0;missing_count<=0;mode_o<=0;x_o<=0;y_o<=0;local_o<=0;remote_o<=0;
  end else begin
   de1<=de_i;good1<=de_i&&local_valid_i&&remote_valid_i&&pair_ok_i;
   frame1<=frame_start_i;mode1<=mode_i;x1<=x_i;y1<=y_i;left1<=local_i;right1<=remote_i;
   yl1<=luma(local_i);yr1<=luma(remote_i);
   valid_o<=good1;missing_o<=de1&&!good1;
   if(de1&&!good1&&missing_count!=32'hffffffff)missing_count<=missing_count+1'b1;
   mode_o<=mode1;x_o<=x1;y_o<=y1;
   previous_valid<=good1;previous_x<=x1;previous_y<=y1;previous_l<=yl1;previous_r<=yr1;
   local_o<=0;remote_o<=0;
   if(good1)case(mode1)
    1:begin local_o<=gray(yl1);remote_o<=gray(yr1);end
    2:begin local_o<=adjacent?gray(edge_strength(yl1,previous_l)):16'd0;remote_o<=adjacent?gray(edge_strength(yr1,previous_r)):16'd0;end
    3:begin local_o<=heat(yl1);remote_o<=heat(yr1);end
    4:begin local_o<=poster(left1);remote_o<=poster(right1);end
    5:begin local_o<=gray(contrast(yl1));remote_o<=gray(contrast(yr1));end
    6:begin local_o<=yl1>=128?16'hffff:16'd0;remote_o<=yr1>=128?16'hffff:16'd0;end
    7:begin
     local_o<=left1;remote_o<=right1;
     if(y1[4:0]==0)begin local_o<=16'h07e0;remote_o<=16'h07e0;end
     if(x1==WIDTH/2||y1==HEIGHT/2)begin local_o<=16'hf800;remote_o<=16'hf800;end
    end
    8:begin local_o<=solar(left1);remote_o<=solar(right1);end
    default:begin local_o<=left1;remote_o<=right1;end
   endcase
  end
 end
endmodule
