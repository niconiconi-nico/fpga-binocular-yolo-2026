// One selected-eye point-effect datapath, not two simultaneous unused copies.
// Caller selects the displayed pane BEFORE computation. Pane transitions occur
// at x==0, where the existing horizontal edge definition is already invalid.
// Both original eye-valid flags and pair diagnostics are preserved unchanged.
module stereo_pair_selected1 #(parameter integer WIDTH=640,HEIGHT=360)(
 input wire clk,rst,de_i,local_valid_i,remote_valid_i,pair_ok_i,frame_start_i,
 input wire[3:0]mode_i,input wire[10:0]x_i,input wire[9:0]y_i,
 input wire[15:0]selected_i,
 output reg valid_o,missing_o,output reg[31:0]missing_count,
 output reg[3:0]mode_o,output reg[10:0]x_o,output reg[9:0]y_o,
 output reg[15:0]selected_o
);
 function automatic[7:0]luma(input[15:0]p);
  reg[15:0]r,g,b,s;begin
   r={8'd0,p[15:11],p[15:13]};g={8'd0,p[10:5],p[10:9]};b={8'd0,p[4:0],p[4:2]};
   // Exact unsigned77R+150G+29B+128, maximum65408 fits16bits.
   s=(r<<6)+(r<<3)+(r<<2)+r+(g<<7)+(g<<4)+(g<<2)+(g<<1)+(b<<4)+(b<<3)+(b<<2)+b+16'd128;
   luma=s[15:8];
  end
 endfunction
 function automatic[15:0]gray(input[7:0]v);gray={v[7:3],v[7:2],v[7:3]};endfunction
 function automatic[7:0]edge_strength(input[7:0]a,b);
  reg[7:0]d;begin d=a>b?a-b:b-a;edge_strength=d>=64?255:{d[5:0],2'b0};end
 endfunction
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
 function automatic[15:0]poster(input[15:0]p);poster={p[15:13],p[15:14],p[10:8],p[10:8],p[4:2],p[4:3]};endfunction
 function automatic[7:0]contrast(input[7:0]v);contrast=v<64?0:v>=192?255:((v-8'd64)<<1);endfunction
 function automatic[15:0]solar(input[15:0]p);solar={p[15]?~p[15:11]:p[15:11],p[10]?~p[10:5]:p[10:5],p[4]?~p[4:0]:p[4:0]};endfunction
 reg de1,good1,frame1;reg[3:0]mode1;reg[10:0]x1;reg[9:0]y1;
 reg[15:0]pixel1;reg[7:0]lum1;
 reg previous_valid;reg[10:0]previous_x;reg[9:0]previous_y;reg[7:0]previous_lum;
 wire adjacent=previous_valid&&!frame1&&x1!=0&&previous_y==y1&&previous_x+1'b1==x1;
 always @(posedge clk or posedge rst)begin
  if(rst)begin
   de1<=0;good1<=0;frame1<=0;mode1<=0;x1<=0;y1<=0;pixel1<=0;lum1<=0;
   previous_valid<=0;previous_x<=0;previous_y<=0;previous_lum<=0;
   valid_o<=0;missing_o<=0;missing_count<=0;mode_o<=0;x_o<=0;y_o<=0;selected_o<=0;
  end else begin
   de1<=de_i;good1<=de_i&&local_valid_i&&remote_valid_i&&pair_ok_i;
   frame1<=frame_start_i;mode1<=mode_i;x1<=x_i;y1<=y_i;pixel1<=selected_i;lum1<=luma(selected_i);
   valid_o<=good1;missing_o<=de1&&!good1;
   if(de1&&!good1&&missing_count!=32'hffffffff)missing_count<=missing_count+1'b1;
   mode_o<=mode1;x_o<=x1;y_o<=y1;
   previous_valid<=good1;previous_x<=x1;previous_y<=y1;previous_lum<=lum1;
   selected_o<=0;
   if(good1)case(mode1)
    1:selected_o<=gray(lum1);
    2:selected_o<=adjacent?gray(edge_strength(lum1,previous_lum)):16'd0;
    3:selected_o<=heat(lum1);
    4:selected_o<=poster(pixel1);
    5:selected_o<=gray(contrast(lum1));
    6:selected_o<=lum1>=128?16'hffff:16'd0;
    // CLAUDE UPPER_V1: 7 (mode 45 ALIGN grid) removed; never selected (pair_effect_mode excludes 45)
    8:selected_o<=solar(pixel1);
    default:selected_o<=pixel1;
   endcase
  end
 end
endmodule
