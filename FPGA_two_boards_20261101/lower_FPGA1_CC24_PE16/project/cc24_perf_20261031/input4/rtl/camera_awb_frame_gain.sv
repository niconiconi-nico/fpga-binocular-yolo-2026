// CC9 colour stage (replaces the CC8 light AWB; same ports / instance as il3 ENABLE_AWB=1).
// Calibrated against a 24-patch ColorChecker on the board video (pc_upper/camera_yolo_demo/colorcal):
// CC8 measured a black pedestal of ~21.5 codes that the AWB gains coloured (purple shadows),
// linear (gamma 1.0) output and ~0.17x reference chroma.
// Per 8-bit channel, 4 pixels per beat (R=[23:16] G=[15:8] B=[7:0] per 24-bit pixel):
//   s1 xb  = max(c - BL_c, 0)                     per-channel black level BEFORE white balance
//          CC11: CC10 on the board clipped blue shadows (single BL=21); a CC8+CC10 two-capture fit on the
//          chart greys gave R ~3 and B ~4-5 codes below G -> BL_R/G/B = 18/22/17.
//   s2 lin = min(1023, (xb * gain_c) >> 6)       gain Q8 (G fixed 256); R/B 8x10 multiplies (8 DSP, as CC8)
//          gains in use are latched at the input SOF; frame f's statistics are applied from frame f+2.
//          10-bit linear (936 = white at unity gain)
//   s3 t   = TONE[lin]                            1024x8 sRGB tone ROM in ERAM (TONE_FILE)
//   s4 Y   = (tR + 2 tG + tB) >> 2
//   s5 out = clip(Y + (((t - Y) * S) >>> 2))      S = S_NUM (Y >= DARK_Y) else S_DARK, shift-add constants
// CALNY2 (2026-10-24, measured on the board with the CAL1c statistics, see CLAUDE_HANDOFF/CALNY_COLOUR_CAL_NO_YOLO.md):
//   BL_R/G/B = 16/16/16 from a capped-lens dark frame (pre-BLC 15.82/15.75/15.59, spatially flat; 18/22/17 over-subtracted G
//   -> purple shadows). Lens colour shading (two white flat fields, pattern fixed to the lens: R/G up to +49%, B/G +28% at
//   the edges) is corrected per beat: corr_c = 256 - ((CX_c*(bx-BX0_c)^2 + CY_c*(y-Y0_c)^2) >> 20) (Q8, bx = beat, y = line),
//   folded into the R/B gain of s2: geff_c = (gain_c * corr_c) >> 8 (registered with s1). Saturation 9/4 (Y >= DARK_Y) and
//   7/4 (dark). Highlight clamp: a pixel with any pre-BLC channel >= HL_TH is output white (LSC lowers R/B at the edges and
//   would otherwise tint sensor-clipped highlights). Grey-world statistics see the corrected lin values.
// CC21 (2026-10-24): corr_c = LUT_c[(CX_c*(bx-BX0_c)^2 + CY_c*(y-Y0_c)^2) >> 20] (see camera_lsc_q8), refitted to the same flats.
// CC22: refit on a diffuser flat + per-column offset (lens left/right asymmetry): corr_c = LUT_c[idx] - OXM_c[bx >> 3]; AWB dead band 1/256.
// CC23: chroma noise reduction (CC22 board video: chroma noise std 10-11 codes vs luma 3; the left eye runs CC12 with S 7/4).
//   Per beat the chroma sums s_c = sum_4px (t_c - Y) (c = R, B, 11-bit signed) are filtered H = [1 2 2 2 1] over the beats of
//   the same line (ends replicated, computed 2 beats late) and folded into a 320-entry line memory
//   M[k] = (((H + 4) >>> 3) + M[k] + 1) >>> 1. A line's output uses M[k] as read BEFORE that line's update (IIR chroma of
//   lines y-1, y-2, ... weights 1/2, 1/4, ...), so no luma delay is needed and the 5-clock latency is unchanged:
//   out = clip(Y_px + ((S * V_c) >>> 4)), V_G = (6 - V_R - V_B) >>> 1 (V = 4x pixel chroma; luma per pixel unchanged).
//   Golden: colorcal/cc23_model.py (measured on 24 CC22 board frames: chroma noise R-Y 10.4 -> 3.0, B-Y 11.3 -> 3.3).
// CC24 (CC23 TD: camera clock SWNS -1.368 ns on the CC22 path LSC state -> LUT -> R/B gain DSP -> geff, slack +0.105 in CC22;
//   routed 20,482 Slice): (1) camera_lsc_q8 registers corr, computed from the NEXT state (SOF beat: constant), so the gain
//   multiply starts at a register; (2) chroma NR without the right-edge flush: the update for beat k (H centred on k-2,
//   left end replicated) is written to M[k], the output of beat k reads M[min(k+2, NB-1)] (same centring; the last 2 beats
//   of a line reuse beat NB-3's chroma), the old value for the update is the read of beat k-2. Write side moved to s4.
//   Golden: colorcal/cc24_model.py.
// Bit-exact Python model: pc_upper/camera_yolo_demo/colorcal/cc24_model.py (cc23_model.py for CC23, calny2_model.py + cc22_model.P for CC22, cc9_model.py for CC9..CC18).
// AWB: closed-loop grey world on lane-0 LINEAR samples (pedestal removed); excludes clipped (>=1000)
// and dark (R+G+B < 48) samples; 0/1/2/8 Q8 steps per frame, gains 64..1023 (same law as CC8; CC22 dead band 1/256).
// CC10: multiply+clamp merged into one stage, saturation constants as explicit shift-adds (CC9 mapped
// them to 10 DSPs); tdata/tvalid/tlast/tuser are delayed by the same 5 clocks (native stream contract kept).
module camera_awb_frame_gain #(
    parameter integer IMG_HEIGHT=720, IMG_WIDTH=1280,
    parameter integer BL_R=16, BL_G=16, BL_B=16, DARK_Y=40,  // CALNY2: dark-frame black level; saturation 9/4 / 7/4 shift-adds
    // CC22 lens shading (diffuser flat on the lens, pc_upper/camera_yolo_demo/colorcal/cc22_lsc_fit.py + cc22_lsc_fit2.py
    // -> cc22_lsc.json): corr = LUT[elliptic index] - OXM[bx>>3]; LUT entry i at bits [9i+8:9i], OXM column j at [5j+4:5j]
    parameter integer LSC_BX0_R=195, LSC_Y0_R=410, LSC_CX_R=2789, LSC_CY_R=167,
    parameter [1151:0] LSC_LUT_R=1152'h56ab55aad56ab55aad56ab55aad56ab55aad56ab55aae572b95cae572b95caf57abd60b0582c160b058ac562b2592cd66b35a2d168b45aad56cb65badd6eb85cae574ba5daf178bd5f2f97ebf6030584c261b118ac56331d90c864b2996cb663359ace6733da0d068b49a6d46a355acd76c365b4db6e375bcdf70385c6e47339dd0ea75bb5def0793d1ecf87d3f5ff00,
    parameter [199:0] LSC_OXM_R=200'h635cf7bdce6b58c5a9273106108000004432190a52d6b5ad4a,
    parameter integer LSC_BX0_B=180, LSC_Y0_B=380, LSC_CX_B=3387, LSC_CY_B=169,
    parameter [1151:0] LSC_LUT_B=1152'h5fafd7ebf5fafd7ebf5fafd7ebf5fafd7ebf5fafd7ebf5fafd7ebf5fafd7ebf5fafd7ebf6030180c06030180c060b0582c160b0584c26130984c261b0d86c36231188c562b158cc66331d8ec86432192c964b2994cb65b3198cd66b399ccf67b41a0d169349a6d46a355aad66bb61b2da6db71bade6f381c2e271b91cae673ba5d4eb76bb9e0f179bd5eef87d3f5ff00,
    parameter [199:0] LSC_OXM_B=200'h18c6318c84294c73a107398c529062084000000110c85298e8,
    parameter integer HL_TH=250,
    parameter TONE_FILE="cc9_tone_lut.hex"
)(
    input wire I_clk,I_rst_n,I_tlast,I_tuser,I_tvalid,
    input wire [95:0] I_tdata,
    output wire I_tready,
    output wire O_tlast,O_tuser,O_tvalid,
    output wire [95:0] O_tdata,
    input wire O_tready,
    output wire [9:0] dbg_gain_r_o, dbg_gain_b_o   // CAL1: AWB gains in use (observation only)
);
    localparam integer SB=28;               // 230400 * 3069 < 2^28
    localparam [9:0] GMIN=10'd64, GMAX=10'd1023;
    assign I_tready=O_tready;
    assign dbg_gain_r_o=gu_r; assign dbg_gain_b_o=gu_b;

    reg [9:0] gain_r,gain_b;              // next gains (control law state)
    reg [9:0] gu_r,gu_b;                  // gains in use: latched at the input SOF -> one gain pair per frame
    reg [5:1] v,u,l;                        // control pipeline
    reg [7:0]  xb [0:11];                   // s1
    reg [9:0]  lin[0:11];                   // s2
    wire [7:0] t4 [0:11];                   // s3 (ROM registered output)
    reg [7:0]  t5 [0:11];                   // s4
    reg [7:0]  y5 [0:3];
    reg [95:0] d6;                          // s5
    wire [17:0] m [0:11];                   // s2 product (combinational into the clamp)
    wire [8:0] corr_r,corr_b;               // LSC factor (Q8) of the input beat
    wire [9:0] gsel_r=I_tuser ? gain_r : gu_r, gsel_b=I_tuser ? gain_b : gu_b;   // the SOF beat already uses the new gains
    wire [18:0] gp_r=gsel_r*corr_r, gp_b=gsel_b*corr_b;
    reg [9:0] geff_r,geff_b;                // s1: per-beat R/B gain including LSC
    reg [3:0] hl1,hl2,hl3,hl4;              // highlight flags, aligned with s5
    // CC23/CC24 chroma NR
    localparam [8:0] NBM=IMG_WIDTH/4-1;    // last beat of a line (319)
    reg [8:0] k2;                           // beat index in the line of the beat at s2
    reg [8:0] ka3,ka4;                      // the same index carried with s3/s4
    wire [8:0] ra=(k2>=NBM-9'd1) ? NBM : k2+9'd2;   // CC24: read M[min(k+2, NB-1)]
    (* ram_style="bram" *) reg [21:0] nrm [0:319];   // line memory {V_R[21:11], V_B[10:0]}, signed
    reg [21:0] nrd;                         // read value, aligned with s3 (ERAM output register)
    reg [21:0] nv4;                         // carried to s4 for the update
    reg signed [9:0] p9 [0:2], p7 [0:2];    // s4: (9*V)>>>4 and (7*V)>>>4 for R, G, B
    reg signed [10:0] wr [0:4], wb [0:4];   // window of beat sums of the line (index 4 newest)
    reg [21:0] dl0,dl1,dl2;                 // values read for the last 3 beats (dl2 = read of beat k-2 = old M[k])
    reg pend; reg [8:0] pa;                 // update of M[pa] pending
    wire signed [10:0] vr3=nrd[21:11], vb3=nrd[10:0];
    wire signed [11:0] vgs=12'sd6-vr3-vb3;
    wire signed [10:0] vg3=vgs>>>1;
    wire [9:0] st_r=t5[2]+t5[5]+t5[8]+t5[11], st_b=t5[0]+t5[3]+t5[6]+t5[9], st_y=y5[0]+y5[1]+y5[2]+y5[3];
    wire signed [10:0] cs_r=$signed({1'b0,st_r})-$signed({1'b0,st_y}), cs_b=$signed({1'b0,st_b})-$signed({1'b0,st_y});
    wire [21:0] nwd={nr_upd(wr[0],wr[1],wr[2],wr[3],wr[4],dl2[21:11]),nr_upd(wb[0],wb[1],wb[2],wb[3],wb[4],dl2[10:0])};
    camera_lsc_q8 #(.BX0(LSC_BX0_R),.Y0(LSC_Y0_R),.CX(LSC_CX_R),.CY(LSC_CY_R),.LUT(LSC_LUT_R),.OXM(LSC_OXM_R)) u_lsc_r(.clk(I_clk),.rst_n(I_rst_n),
        .tvalid(I_tvalid),.tuser(I_tuser),.tlast(I_tlast),.corr(corr_r));
    camera_lsc_q8 #(.BX0(LSC_BX0_B),.Y0(LSC_Y0_B),.CX(LSC_CX_B),.CY(LSC_CY_B),.LUT(LSC_LUT_B),.OXM(LSC_OXM_B)) u_lsc_b(.clk(I_clk),.rst_n(I_rst_n),
        .tvalid(I_tvalid),.tuser(I_tuser),.tlast(I_tlast),.corr(corr_b));
    integer k;

    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            v<=0;u<=0;l<=0;d6<=0;gu_r<=10'd256;gu_b<=10'd256;geff_r<=10'd256;geff_b<=10'd256;hl1<=0;hl2<=0;hl3<=0;hl4<=0;
            for(k=0;k<12;k=k+1) begin xb[k]<=0;lin[k]<=0;t5[k]<=0; end
            for(k=0;k<4;k=k+1) y5[k]<=0;
            k2<=0;ka3<=0;ka4<=0;nv4<=0;
            for(k=0;k<3;k=k+1) begin p9[k]<=0;p7[k]<=0; end
        end else begin
            v<={v[4:1],I_tvalid}; u<={u[4:1],I_tuser}; l<={l[4:1],I_tlast};
            if(I_tuser) begin gu_r<=gain_r; gu_b<=gain_b; end
            geff_r<=gp_r[17:8]; geff_b<=gp_b[17:8];
            for(k=0;k<4;k=k+1)
                hl1[k]<=(I_tdata[24*k+16 +: 8]>=HL_TH) || (I_tdata[24*k+8 +: 8]>=HL_TH) || (I_tdata[24*k +: 8]>=HL_TH);
            hl2<=hl1; hl3<=hl2; hl4<=hl3;
            for(k=0;k<12;k=k+1) begin
                xb[k] <= I_tdata[8*k +: 8] > blv(k) ? I_tdata[8*k +: 8] - blv(k) : 8'd0;
                // channel index k%3: 0=B, 1=G, 2=R within each 24-bit pixel
                lin[k]<= |m[k][17:16] ? 10'd1023 : m[k][15:6];
                t5[k] <= t4[k];
            end
            for(k=0;k<4;k=k+1) begin
                y5[k] <= ({2'd0,t4[3*k+2]} + {1'd0,t4[3*k+1],1'b0} + {2'd0,t4[3*k]}) >> 2;
                d6[24*k+16 +: 8] <= hl4[k] ? 8'd255 : nrout(y5[k], p9[0], p7[0]);
                d6[24*k+8  +: 8] <= hl4[k] ? 8'd255 : nrout(y5[k], p9[1], p7[1]);
                d6[24*k    +: 8] <= hl4[k] ? 8'd255 : nrout(y5[k], p9[2], p7[2]);
            end
            // CC23: beat index at s2 (counts valid beats, tlast ends a line)
            if(v[2]) k2 <= l[2] ? 9'd0 : k2+9'd1;
            ka3<=k2; ka4<=ka3; nv4<=nrd;
            p9[0]<=s9(vr3); p7[0]<=s7(vr3); p9[1]<=s9(vg3); p7[1]<=s7(vg3); p9[2]<=s9(vb3); p7[2]<=s7(vb3);
        end
    end

    function [7:0] blv; input integer bi;  // byte bi: 0=B 1=G 2=R (per pixel)
        blv = (bi%3==2) ? BL_R[7:0] : (bi%3==1) ? BL_G[7:0] : BL_B[7:0];
    endfunction

    // CC23 saturation on the filtered chroma (V = 4x pixel chroma): shift-add constants, S_NUM=9 -> 8V+V, S_DARK=7 -> 8V-V
    function signed [9:0] s9; input signed [10:0] x; reg signed [14:0] p; begin p = {x,3'b0}; p = p + x; s9 = p >>> 4; end endfunction
    function signed [9:0] s7; input signed [10:0] x; reg signed [14:0] p; begin p = {x,3'b0}; p = p - x; s7 = p >>> 4; end endfunction
    function [7:0] nrout; input [7:0] y; input signed [9:0] a9, a7;
        reg signed [10:0] s;
        begin
            s = $signed({3'b0,y}) + ((y >= DARK_Y) ? a9 : a7);
            nrout = s < 0 ? 8'd0 : s > 255 ? 8'd255 : s[7:0];
        end
    endfunction
    // M update: (((a0 + 2a1 + 2a2 + 2a3 + a4 + 4) >>> 3) + v + 1) >>> 1
    function signed [10:0] nr_upd; input signed [10:0] a0,a1,a2,a3,a4,vin;
        reg signed [13:0] h; reg signed [11:0] q;
        begin
            h = a1; h = h + a2; h = h + a3; h = h <<< 1; h = h + a0; h = h + a4; h = h + 14'sd4;
            q = h >>> 3; q = q + vin; q = q + 12'sd1;
            nr_upd = q >>> 1;
        end
    endfunction

    // CC24 line memory: one write (update) port, one registered read port. M[k] is read by beats k-2, k-1 (clamp) and k of
    // a line at s2 and written by beat k of the same line at s4->s5 (later); never the same address in one clock.
    always @(posedge I_clk) begin
        nrd <= nrm[ra];
        if(pend) nrm[pa] <= nwd;
    end
    integer j;
    initial for(j=0;j<320;j=j+1) nrm[j]=22'd0;
    // write side at s4: beat sums (combinational from t5/y5) enter the window; beat k >= 2 updates M[k]
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            dl0<=0;dl1<=0;dl2<=0;pend<=0;pa<=0;
            for(j=0;j<5;j=j+1) begin wr[j]<=0;wb[j]<=0; end
        end else begin
            pend<=v[4] && ka4>=9'd2;
            if(v[4]) begin
                pa<=ka4;
                if(ka4==9'd0) for(j=0;j<5;j=j+1) begin wr[j]<=cs_r; wb[j]<=cs_b; end
                else begin for(j=0;j<4;j=j+1) begin wr[j]<=wr[j+1]; wb[j]<=wb[j+1]; end wr[4]<=cs_r; wb[4]<=cs_b; end
                dl0<=nv4; dl1<=dl0; dl2<=dl1;
            end
        end
    end
    genvar r;
    generate for(r=0;r<12;r=r+1) begin:G_MUL
        assign m[r] = (r%3==1) ? {2'd0,xb[r],8'd0} : xb[r] * ((r%3==2) ? geff_r : geff_b);
    end endgenerate
    generate for(r=0;r<6;r=r+1) begin:G_TONE
        cc9_tone_rom2 #(.TONE_FILE(TONE_FILE)) u_rom(.clk(I_clk),.a0(lin[2*r]),.a1(lin[2*r+1]),.q0(t4[2*r]),.q1(t4[2*r+1]));
    end endgenerate

    assign O_tdata=d6; assign O_tvalid=v[5]; assign O_tuser=u[5]; assign O_tlast=l[5];

    // closed-loop statistics on lane-0 linear values (stage 2, aligned with v[2]/u[2])
    wire [9:0] sr=lin[2], sg=lin[1], sb=lin[0];
    wire [11:0] ssum={2'd0,sr}+{2'd0,sg}+{2'd0,sb};
    wire usable=v[2] && sr<10'd1000 && sg<10'd1000 && sb<10'd1000 && ssum>=12'd48;
    reg [SB-1:0] acc_r,acc_g,acc_b,snap_r,snap_g,snap_b;
    reg [17:0] acc_n;
    reg snap_ok;
    reg [1:0] upd;
    reg [3:0] step_r,step_b; reg dn_r,dn_b;
    function [3:0] step_of; input [SB:0] diff; input [SB-1:0] base;
        begin
            step_of = diff > (base>>3) ? 4'd8 : diff > (base>>5) ? 4'd2 : diff > (base>>8) ? 4'd1 : 4'd0;   // CC22: dead band 1/256 (was 1/128: the loop climbs from 256 and stopped up to 0.78% short -> green)
        end
    endfunction
    function [9:0] move; input [9:0] g; input [3:0] s; input dn;
        reg [10:0] t;
        begin
            if(dn) move = (g < GMIN + s) ? GMIN : g - s;
            else begin t = {1'b0,g} + s; move = (t > GMAX) ? GMAX : t[9:0]; end
        end
    endfunction
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            acc_r<=0;acc_g<=0;acc_b<=0;acc_n<=0;snap_r<=0;snap_g<=0;snap_b<=0;snap_ok<=0;upd<=0;
            step_r<=0;step_b<=0;dn_r<=0;dn_b<=0;gain_r<=10'd256;gain_b<=10'd256;
        end else begin
            if(u[2]) begin
                snap_r<=acc_r;snap_g<=acc_g;snap_b<=acc_b;snap_ok<=acc_n>=18'd2048;upd<=2'd1;
                // the SOF beat itself is the first sample of the new frame
                acc_r<=usable ? sr : 0;acc_g<=usable ? sg : 0;acc_b<=usable ? sb : 0;acc_n<={17'd0,usable};
            end else if(usable && acc_n!=18'h3ffff) begin
                acc_r<=acc_r+sr;acc_g<=acc_g+sg;acc_b<=acc_b+sb;acc_n<=acc_n+1'b1;
            end
            if(upd==2'd1) begin
                dn_r<=snap_r>snap_g; dn_b<=snap_b>snap_g;
                step_r<=snap_ok ? step_of(snap_r>snap_g ? snap_r-snap_g : snap_g-snap_r, snap_g) : 4'd0;
                step_b<=snap_ok ? step_of(snap_b>snap_g ? snap_b-snap_g : snap_g-snap_b, snap_g) : 4'd0;
                upd<=2'd2;
            end else if(upd==2'd2) begin
                gain_r<=move(gain_r,step_r,dn_r); gain_b<=move(gain_b,step_b,dn_b); upd<=2'd0;
            end
        end
    end
endmodule

// 1024 x 8 tone ROM, two registered read ports (one ERAM per instance expected).
module cc9_tone_rom2 #(parameter TONE_FILE="cc9_tone_lut.hex")(
    input wire clk, input wire [9:0] a0,a1, output reg [7:0] q0,q1
);
    (* ram_style="bram" *) reg [7:0] rom [0:1023];
    initial $readmemh(TONE_FILE, rom);
    always @(posedge clk) begin q0<=rom[a0]; q1<=rom[a1]; end
endmodule

// CALNY2 lens-shading factor of the CURRENT input beat, Q8 (256 = 1.0):
//   corr = 256 - ((CX*(bx-BX0)^2 + CY*(y-Y0)^2) >> 20), bx = beat in line (tlast ends a line), y = line (tuser = line 0).
// The squares are kept as exact running sums (A += D, D += 2C per step), so no multiplier is needed.
// CALNY3 (area): same values bit for bit, narrower registers. For the 1280x720 stream (320 beats x 720 lines) and the
// default constants: CX*(bx-BX0)^2 + CY*(y-Y0)^2 <= 125,658,975 < 2^27, |DX| <= 961,261 < 2^20, |DY| <= 180,620 < 2^18,
// so A is 27 bits unsigned, DX 21 / DY 19 bits signed; term = A[26:20] <= 119, corr >= 137 (no clamp needed).
// x restarts on tlast only (every ISP line ends with tlast); y restarts on tuser (the SOF beat reads AY0 directly).
// CC21: corr = LUT[A[26:20]] instead of 256 - A[26:20]. The quadratic under-corrected the middle ring (R/G +14%) and
// over-corrected the corners (R/G -11%, green corners on the board); the measured shading flattens towards the edges,
// which a free 1-D profile over the same elliptic index follows. CC21 constants: A <= 134,124,425 < 2^27,
// |DX| <= 1,225,824 < 2^21 -> DX widened to 22 bits signed, |DY| <= 159,624 < 2^18 (19 bits as before).
// CC22: minus a per-column offset OXM[bx>>3] (40 columns of 8 beats, 5-bit magnitude, offsets <= 0 so corr <= 256 and the
// 10-bit geff cannot overflow); bx counts beats exactly like ax (reset on tlast). Constants: A <= 134,142,400 < 2^27,
// |DX| <= 1,215,933 < 2^21, |DY| <= 136,773 < 2^18; LUT - OXM >= 158.
module camera_lsc_q8 #(parameter integer BX0=195, Y0=410, CX=2789, CY=167, parameter [1151:0] LUT={128{9'd256}},
                       parameter [199:0] OXM=200'd0)(
    input wire clk, rst_n, tvalid, tuser, tlast, output wire [8:0] corr
);
    localparam [26:0] AX0=CX*BX0*BX0, AY0=CY*Y0*Y0;
    localparam signed [21:0] DX0=CX*(1-2*BX0);
    localparam signed [18:0] DY0=CY*(1-2*Y0);
    localparam [21:0] CX2=2*CX;
    localparam [18:0] CY2=2*CY;
    reg [26:0] ax,ay;
    reg [8:0] bx;
    reg signed [21:0] dx;
    reg signed [18:0] dy;
    wire [26:0] ay_c=tuser ? AY0 : ay;
    // CC24: corr of the NEXT valid beat, registered (same value as LUT[(ax+ay_c)[26:20]] - OXM[bx>>3] of that beat).
    // A SOF beat always follows a tlast (ax = AX0, bx = 0) and reads ay = AY0: its factor is the constant c_sof.
    wire [26:0] ax_n=tlast ? AX0 : ax+{{5{dx[21]}},dx};
    wire [26:0] ay_n=tlast ? ay_c+{{8{dy[18]}},dy} : ay_c;
    wire [8:0] bx_n=tlast ? 9'd0 : bx+9'd1;
    wire [26:0] sum_n=ax_n+ay_n, sum_sof=AX0+AY0;
    wire [8:0] c_sof=LUT[sum_sof[26:20]*9 +: 9]-{4'd0,OXM[4:0]};
    reg [8:0] corr_q;
    assign corr=tuser ? c_sof : corr_q;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) corr_q<=c_sof;
        else if(tvalid) corr_q<=LUT[sum_n[26:20]*9 +: 9]-{4'd0,OXM[bx_n[8:3]*5 +: 5]};
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin ax<=AX0; dx<=DX0; ay<=AY0; dy<=DY0; bx<=9'd0; end
        else if(tvalid) begin
            if(tlast) begin ax<=AX0; dx<=DX0; bx<=9'd0; ay<=ay_c+{{8{dy[18]}},dy}; dy<=dy+CY2; end
            else begin ax<=ax+{{5{dx[21]}},dx}; dx<=dx+CX2; bx<=bx+9'd1; if(tuser) begin ay<=AY0; dy<=DY0; end end
        end
    end
endmodule
