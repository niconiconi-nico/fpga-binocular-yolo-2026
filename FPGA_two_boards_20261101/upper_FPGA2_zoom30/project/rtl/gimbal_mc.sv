// CLAUDE GIMBAL MC (2026-10-30): board22 (MONO_GIMBAL_20261029) gimbal chain, time-multiplexed for the full-mode build
// (gimbal_lite = 2815 LUT in the z10 synthesis; the 42-bit board22 datapath and two PIDs did not fit).
// Same control law, Emm FW fixed frames, arming / stop / fault behaviour and codes as board22; implementation:
//   * gm_calc: ONE 40-bit add / shift unit with a 32 x 40 distributed-RAM register file executes, as short step sequences,
//     every arithmetic job of both axes: ARM (origin, origin pulses = round(origin * 25 / 512)), POS (encoder -> steps,
//     arrival / drift / progress tests, next target), ABS (absolute FD target, direction, magnitude) and the PID of both
//     axes (board22 image_position_pid: deadband, integral clamp, D cap at half P, round(effort / 4096), +-MAX_STEP limit,
//     conditional integration). Multiplications by constants as shift + add (KP = 2^KP_A + 2^KP_B, KD = 2^KD_S, KI = 1),
//     no DSP, no divider. Jobs take 10 .. 80 clocks (< 1.1 us); requests are queued (fixed priority).
//   * one shared 1 ms tick for the slow timers (emm turnaround 2..3 ms, reply timeout 50 ms, poll POLL_MS - 1 .. POLL_MS,
//     no-progress 4 s, target age, control period): board22 counted clocks; the tick moves each deadline by < 1 ms.
//   * gm_emm / gm_axis: board22 emm_axis / emm_follow_axis protocol state machines per axis (independent UARTs).
module gm_emm #(parameter integer CLK_HZ=75000000, BAUD=115200, parameter [7:0] ADDRESS=8'd1, parameter integer REPLY_MS=50)(
    input wire clk, rst, ms, cmd_valid, input wire [3:0] op, input wire dir, input wire [5:0] rpm, input wire [27:0] pulses,
    output wire busy, output reg done, output reg [3:0] result, output reg [47:8] reply, output reg [3:0] reply_len,
    output wire uart_tx, input wire uart_rx);
    reg [3:0] length, index, expected, received, aop; reg [1:0] state; reg [7:0] fcode;
    reg tx_start; wire tx_busy, tx_done, rx_valid, rx_error; wire [7:0] rx_byte;
    reg [5:0] tcnt; reg [1:0] turn;
    reg receive_open, frame_ready, bad_frame, rx_fault; reg [47:8] cand;
    reg [7:0] cb;
    always @* begin
        cb = 8'h6b;
        if(index==0) cb = ADDRESS;
        else case(aop)
            4'd1: case(index) 1: cb=8'hf3; 2: cb=8'hab; 3: cb=8'h01; 4: cb=8'h00; default: cb=8'h6b; endcase
            4'd4: case(index) 1: cb=8'hfe; 2: cb=8'h98; 3: cb=8'h00; default: cb=8'h6b; endcase
            4'd7: cb = index==1 ? 8'h36 : 8'h6b;
            4'd8: cb = index==1 ? 8'h3a : 8'h6b;
            default: case(index)
                1: cb=8'hfd; 2: cb={7'd0,dir}; 3: cb=8'h00; 4: cb={2'd0,rpm}; 5: cb=8'd220;
                6: cb={4'd0,pulses[27:24]}; 7: cb=pulses[23:16]; 8: cb=pulses[15:8]; 9: cb=pulses[7:0];
                10: cb=8'h01; 11: cb=8'h00; default: cb=8'h6b;
            endcase
        endcase
    end
    gl_uart #(.CLK_HZ(CLK_HZ),.BAUD(BAUD)) uart(clk, rst, tx_start, cb, uart_tx, tx_busy, tx_done, uart_rx, rx_valid, rx_byte, rx_error);
    assign busy = state!=0 || turn!=0;
    always @(posedge clk or posedge rst) begin
        if(rst) begin
            state<=0; length<=0; index<=0; expected<=4; received<=0; fcode<=0; aop<=0; done<=0; result<=0; reply<=0; reply_len<=0;
            tx_start<=0; tcnt<=0; turn<=0; receive_open<=0; frame_ready<=0; bad_frame<=0; rx_fault<=0; cand<=0;
        end else begin
            done<=0; tx_start<=0; if(turn!=0 && ms) turn<=turn-1'b1;
            if(state!=0) begin
                if(rx_error && receive_open) rx_fault<=1;
                if(rx_valid && receive_open && !frame_ready) begin
                    if(received==0) begin if(rx_byte==ADDRESS) begin cand<=0; received<=1; end end
                    else if(received==1 && rx_byte!=fcode) begin received <= rx_byte==ADDRESS ? 4'd1 : 4'd0; cand<=0; end
                    else begin
                        case(received) 2: cand[47:40]<=rx_byte; 3: cand[39:32]<=rx_byte; 4: cand[31:24]<=rx_byte;
                                       5: cand[23:16]<=rx_byte; 6: cand[15:8]<=rx_byte; default: ; endcase
                        received<=received+1'b1;
                        if(received==expected-1) begin frame_ready<=1; bad_frame<=rx_byte!=8'h6b; end
                    end
                end
            end
            case(state)
                0: if(turn==0 && cmd_valid) begin
                    index<=0; reply<=0; reply_len<=0; received<=0; tcnt<=0; receive_open<=0; frame_ready<=0; bad_frame<=0; rx_fault<=0;
                    cand<=0; expected<=4; result<=1; state<=1; aop<=op;
                    case(op)
                        4'd1: begin fcode<=8'hf3; length<=6; end
                        4'd4: begin fcode<=8'hfe; length<=5; end
                        4'd7: begin fcode<=8'h36; length<=3; expected<=8; end
                        4'd8: begin fcode<=8'h3a; length<=3; end
                        4'd9: begin fcode<=8'hfd; length<=13; end
                        default: begin state<=0; done<=1; result<=3; end
                    endcase
                end
                1: if(!tx_busy) begin tx_start<=1; state<=2; if(index==length-1) receive_open<=1; end
                2: if(tx_done) begin if(index==length-1) begin state<=3; tcnt<=0; end else begin index<=index+1'b1; state<=1; end end
                default: begin
                    if(rx_fault || rx_error) begin state<=0; done<=1; result<=6; turn<=3; end
                    else if(frame_ready) begin state<=0; done<=1; turn<=3; reply<=cand; reply_len<=expected; result<=bad_frame?4'd6:4'd1; end
                    else if(tcnt>REPLY_MS && !rx_valid) begin state<=0; done<=1; result<=5; turn<=3; end
                    else if(ms && tcnt<=REPLY_MS) tcnt<=tcnt+1'b1;
                end
            endcase
        end
    end
endmodule

// emm_follow_axis protocol state machine; the arithmetic runs as gm_calc jobs (job 0 ARM, 1 POS, 2 ABS).
module gm_axis #(parameter integer CLK_HZ=75000000, BAUD=115200, POLL_MS=3, MOVE_MS=4000,
                 R1=4, R2=12, R3=24, R4=40, T2=5, T3=13, T4=25)(
    input wire clk, rst, ms, enable, move_valid, input wire signed [7:0] move_steps,
    output wire ready, output reg fault, output wire tx, input wire rx, output wire ready_to_arm, output reg [7:0] fault_code,
    output reg [7:0] move_acks, output reg signed [7:0] last_move,
    output reg job_req, output reg [1:0] job, output reg setprog, input wire job_done, err_ok, drift_ok, prog_big,
    input wire pul_we, pul_dir, input wire [27:0] pul_mag, output wire signed [30:0] raw, output reg signed [6:0] requested);
    localparam [4:0] OFF=0,EN_SEND=1,EN_WAIT=2,ST_SEND=3,ST_WAIT=4,POS_SEND=5,POS_WAIT=6,IDLE=7,MV_SEND=8,MV_WAIT=9,
                     STOP_SEND=11,STOP_WAIT=12,FAULT=13,C_ARM=14,C_POS=15,C_ABS=16;
    reg [4:0] state;
    reg active, prev_enable, prepared, moving, pending_move, work_request, hold_stop, command, direction, stable, arrived;
    reg [3:0] op; reg [27:0] pulse_count; reg [1:0] poll_count; reg [11:0] move_age; reg signed [6:0] latest_request; reg [5:0] move_rpm;
    wire busy, done; wire [3:0] result; wire [47:8] reply; wire [3:0] reply_len;
    wire ack = result==1 && reply_len==4 && reply[47:40]==2;
    wire state_good = result==1 && reply_len==4 && (reply[47:40]&8'h0d)==1;
    wire pos_good = result==1 && reply_len==8 && reply[47:40]<=1 && reply[39:38]==2'd0;
    assign raw = reply[47:40]==1 ? -$signed({1'b0,reply[37:8]}) : $signed({1'b0,reply[37:8]});
    assign ready_to_arm = state==OFF && !busy && !enable && !fault;
    assign ready = active && prepared && enable && !fault;
    gm_emm #(.CLK_HZ(CLK_HZ),.BAUD(BAUD)) u_uart(.clk(clk),.rst(rst),.ms(ms),.cmd_valid(command && (enable || op==4)),.op(op),.dir(direction),
        .rpm(move_rpm),.pulses(pulse_count),.busy(busy),.done(done),.result(result),.reply(reply),.reply_len(reply_len),
        .uart_tx(tx),.uart_rx(rx));
    task fail(input [7:0] code); begin fault<=1; fault_code<=code; active<=0; hold_stop<=0; state<=STOP_SEND; end endtask
    always @(posedge clk or posedge rst) begin
        if(rst) begin
            state<=OFF; active<=0; prev_enable<=0; prepared<=0; moving<=0; pending_move<=0; work_request<=0; hold_stop<=0;
            command<=0; op<=0; direction<=0; pulse_count<=0; poll_count<=0; move_age<=0; stable<=0; arrived<=0;
            requested<=0; latest_request<=0; move_rpm<=R1[5:0]; job_req<=0; job<=0; setprog<=0;
            fault<=0; fault_code<=0; move_acks<=0; last_move<=0;
        end else begin
            command<=0; prev_enable<=enable; job_req<=0;
            if(pul_we) begin direction<=pul_dir; pulse_count<=pul_mag; end
            if(moving && ms && move_age!=MOVE_MS[11:0]) move_age<=move_age+1'b1;
            if(active && (!enable || (moving && move_age==MOVE_MS[11:0]))) begin
                active<=0; hold_stop<=0; state<=STOP_SEND;
                if(enable) begin fault<=1; fault_code<=8'h71; end
            end else case(state)
                OFF: if(enable && !prev_enable) begin
                    active<=1; prepared<=0; moving<=0; stable<=0; fault<=0; fault_code<=0; move_acks<=0; last_move<=0;
                    pending_move<=0; work_request<=0; hold_stop<=0; state<=EN_SEND;
                end
                EN_SEND: if(!busy) begin command<=1; op<=1; state<=EN_WAIT; end
                EN_WAIT: if(done) begin if(ack) state<=ST_SEND; else fail({4'h1, result==1 ? 4'hf : result}); end
                ST_SEND: if(!busy) begin command<=1; op<=8; state<=ST_WAIT; end
                ST_WAIT: if(done) begin if(state_good) begin arrived<=reply[41]; state<=POS_SEND; end else fail({4'h2, result==1 ? 4'hf : result}); end
                POS_SEND: if(!busy) begin command<=1; op<=7; state<=POS_WAIT; end
                POS_WAIT: if(done) begin
                    if(!pos_good) fail({4'h3, result==1 ? 4'hf : result});
                    else if(!prepared) begin
                        if(!arrived) fail(8'h41);
                        else begin job_req<=1; job<=2'd0; state<=C_ARM; end
                    end else begin work_request<=pending_move; requested<=latest_request; pending_move<=0; job_req<=1; job<=2'd1; state<=C_POS; end
                end
                C_ARM: if(job_done) begin prepared<=1; poll_count<=0; state<=IDLE; end
                C_POS: if(job_done) begin
                    poll_count<=0;
                    if(prog_big) move_age<=0;
                    if(work_request) begin
                        work_request<=0;
                        if(requested==0) begin if(moving) begin hold_stop<=1; state<=STOP_SEND; end else state<=IDLE; end
                        else begin stable<=0; job_req<=1; job<=2'd2; setprog<=!moving; state<=C_ABS; end
                    end else begin
                        if(moving && arrived && err_ok && drift_ok) begin if(stable) begin moving<=0; stable<=0; end else stable<=1; end
                        else stable<=0;
                        state<=IDLE;
                    end
                end
                C_ABS: if(job_done) begin
                    move_rpm <= (requested>=T4 || requested<=-T4) ? R4[5:0] : (requested>=T3 || requested<=-T3) ? R3[5:0] :
                                (requested>=T2 || requested<=-T2) ? R2[5:0] : R1[5:0];
                    state<=MV_SEND;
                end
                IDLE: begin
                    if(pending_move) state<=ST_SEND;
                    else if(moving) begin if(poll_count>=POLL_MS-1 && ms) begin poll_count<=0; state<=ST_SEND; end else if(ms) poll_count<=poll_count+1'b1; end
                end
                MV_SEND: if(!busy) begin command<=1; op<=9; if(!moving) move_age<=0; moving<=1; state<=MV_WAIT; end
                MV_WAIT: if(done) begin
                    if(ack) begin move_acks<=move_acks+1'b1; last_move<=requested; poll_count<=0; state<=IDLE; end
                    else fail({4'h6, result==1 ? 4'hf : result});
                end
                STOP_SEND: if(!busy) begin command<=1; op<=4; state<=STOP_WAIT; moving<=0; end
                STOP_WAIT: if(done) begin
                    if(!ack) begin fault<=1; active<=0; if(!fault) fault_code<={4'h8, result}; state<=FAULT; end
                    else if(hold_stop && active && enable && !fault) begin hold_stop<=0; poll_count<=0; state<=IDLE; end
                    else begin prepared<=0; state<=FAULT; end
                end
                FAULT: if(!enable) begin state<=OFF; fault<=0; end
                default: fail(8'hff);
            endcase
            if(move_valid && ready) begin
                if(move_steps>32 || move_steps< -32) fail(8'h53);
                else begin latest_request<=move_steps[6:0]; pending_move<=1; end
            end
        end
    end
endmodule

// Shared arithmetic unit. Register file per axis a (address {a, r}).
module gm_calc #(parameter integer KP_A=9, KP_B=8, KD_S=7, DEAD_PX=4, I_LIMIT=4096, MAX_STEP=32)(
    input wire clk, rst, safe,
    input wire [1:0] areq, input wire [1:0] ajob0, ajob1, input wire [1:0] asetprog,
    input wire signed [30:0] raw0, raw1, input wire signed [6:0] req0, req1,
    output reg [1:0] adone, output reg err_ok, drift_ok, prog_big,
    output reg [1:0] pul_we, output reg pul_dir, output reg [27:0] pul_mag,
    input wire [1:0] preq, input wire signed [12:0] e0, e1,
    output reg [1:0] cmd_valid, output reg signed [7:0] cmd0, cmd1);
    localparam [3:0] ORG=0, LAST=1, PROG=2, RAWS=3, TGT=4, OPUL=5, STEPS=6, NEXT=7, INTEG=8, PREV=9, T=10, U=11, PE=12, NI=13, PT=14, H=15;
    localparam [1:0] J_ARM=0, J_POS=1, J_ABS=2, J_PID=3;
    // immediate sources
    localparam [3:0] I_ZERO=0, I_RAW=1, I_REQ=2, I_E=3, I_256=4, I_2048=5, I_ILIM=6, I_NILIM=7, I_ILIM1N=8, I_MAX=9, I_NMAX=10, I_MAX1N=11;
    reg signed [39:0] rf [0:31];
    reg signed [39:0] acc; reg [6:0] step; reg [1:0] jt; reg ax, busy, N, C, CH, CL, sp; reg [3:0] rep;
    reg [1:0] pa, pp; reg [1:0] jlat0, jlat1; reg [1:0] splat; reg signed [12:0] el0, el1; reg [1:0] Z, PV;
    // ---- per-step control (combinational)
    reg [3:0] rr, wr_r; reg [3:0] isel; reg ysel_imm, yinv, cin, xzero, accw, rfw, shl, shr;
    wire signed [39:0] q = rf[{ax, rr}];
    wire signed [30:0] rawx = ax ? raw1 : raw0; wire signed [6:0] reqx = ax ? req1 : req0; wire signed [12:0] ex = ax ? el1 : el0;
    reg signed [39:0] imm;
    always @* case(isel)
        I_RAW: imm = rawx; I_REQ: imm = reqx; I_E: imm = ex;
        I_256: imm = 40'sd256; I_2048: imm = 40'sd2048; I_ILIM: imm = I_LIMIT; I_NILIM: imm = -I_LIMIT; I_ILIM1N: imm = -(I_LIMIT+1);
        I_MAX: imm = MAX_STEP; I_NMAX: imm = -MAX_STEP; I_MAX1N: imm = -(MAX_STEP+1); default: imm = 40'sd0;
    endcase
    wire signed [39:0] yv0 = ysel_imm ? imm : q;
    wire signed [39:0] sum = (xzero ? 40'sd0 : acc) + (yinv ? ~yv0 : yv0) + {39'd0, cin};
    wire hi0 = acc[39:5] == 35'd0, hi1 = &acc[39:5];
    function absle(input [4:0] k); absle = (hi0 && acc[4:0] <= k) || (hi1 && acc[4:0] >= 5'd0 - k); endfunction   // |acc| <= k < 32
    wire eneg = ex[12], epos = !ex[12] && ex!=0;
    wire ein = ex <= DEAD_PX && ex >= -DEAD_PX;
    localparam integer KP2 = (KP_B >= 0) ? 1 : 0;
    // step table. Fields: rr (read reg), isel / ysel_imm (Y = imm or q), yinv, cin, xzero (X = 0 / acc), accw (acc <= sum),
    // shl / shr (acc <<= 1 / >>>= 1, rep times), rfw / wr_r (rf <= acc)
    task automatic S_LD(input [3:0] r); begin rr=r; xzero=1; accw=1; end endtask
    task automatic S_LDI(input [3:0] i); begin isel=i; ysel_imm=1; xzero=1; accw=1; end endtask
    task automatic S_ADD(input [3:0] r); begin rr=r; accw=1; end endtask
    task automatic S_SUB(input [3:0] r); begin rr=r; yinv=1; cin=1; accw=1; end endtask
    task automatic S_ADDI(input [3:0] i); begin isel=i; ysel_imm=1; accw=1; end endtask
    task automatic S_NEG; begin rr=4'd0; isel=I_ZERO; ysel_imm=1; xzero=0; end endtask
    task automatic S_ST(input [3:0] r); begin wr_r=r; rfw=1; end endtask
    always @* begin
        rr=T; wr_r=T; isel=I_ZERO; ysel_imm=0; yinv=0; cin=0; xzero=0; accw=0; rfw=0; shl=0; shr=0;
        case(jt)
            J_ARM: case(step)
                0: S_LDI(I_RAW);  1: S_ST(ORG);  2: S_ST(LAST);  3: S_ST(PROG);  4: S_ST(T);
                5: shl=1;         6: S_ST(U);    7: shl=1;       8: S_ADD(U);    9: S_ADD(T);       // shl: 3 then 1 (rep)
                10: ;             11: ;                                 // 10: N <= sign, 11 / 14: negate if N
                12: S_ADDI(I_256); 13: shr=1;    14: ;           15: S_ST(OPUL);  16: S_LDI(I_ZERO); 17: S_ST(TGT);
                default: ;
            endcase
            J_POS: case(step)
                0: S_LDI(I_RAW);  1: S_ST(RAWS); 2: S_SUB(LAST); 3: S_LD(RAWS);   4: S_SUB(PROG);   5: S_LD(RAWS);
                6: S_SUB(ORG);    7: S_ST(T);    8: shl=1;       9: S_ST(U);      10: shl=1;        11: S_ADD(U);
                12: S_ADD(T);     13: ;          14: ;           15: S_ADDI(I_256); 16: shr=1;      17: ;
                18: S_ST(STEPS);  19: S_SUB(TGT); 20: S_LD(STEPS); 21: S_ADDI(I_REQ); 22: S_ST(NEXT); 23: S_LD(RAWS);
                24: S_ST(LAST);   25: if(prog_big) S_ST(PROG);
                default: ;
            endcase
            J_ABS: case(step)
                0: S_LD(NEXT);    1: S_ST(TGT);  2: S_ADD(OPUL); 3: ;             4: ;              5: if(sp) S_LD(RAWS);
                6: if(sp) S_ST(PROG);
                default: ;
            endcase
            default: case(step)                                  // J_PID
                0: S_LDI(I_E);    1: S_ST(PE);   2: begin rr=INTEG; if(Z[ax]) begin ysel_imm=1; isel=I_ZERO; end accw=1; end
                3: begin isel=I_ILIM1N; ysel_imm=1; end          // C = acc > I_LIMIT
                4: if(C) S_LDI(I_ILIM);
                5: begin isel=I_ILIM; ysel_imm=1; end            // C = acc < -I_LIMIT
                6: if(C) S_LDI(I_NILIM);
                7: S_ST(NI);
                8: if(PV[ax]) S_LD(PE); else S_LDI(I_ZERO);
                9: if(PV[ax]) S_SUB(PREV);
                10: shl=1;                                       // KD_S times
                11: S_ST(T);  12: S_LD(PE);  13: shl=1;  14: S_ST(U);  15: shl=1;  16: if(KP2) S_ADD(U);
                17: S_ST(PT); 18: shr=1;
                19: ;                                            // negate (N forced at 18): H = -(pterm >>> 1)
                20: S_ST(H);  21: S_LD(T);
                22: begin rr=H; yinv=1; cin=1; end               // C = acc - H < 0
                23: if(C && epos) S_LD(H);
                24: begin rr=H; yinv=1; end                      // C = acc - H - 1 >= 0  (acc > H)
                25: if(C && eneg) S_LD(H);
                26: S_ST(T);  27: S_LD(PT);  28: S_ADD(NI);  29: S_ADD(T);
                30: ;         31: ;          32: S_ADDI(I_2048);  33: shr=1;  34: ;
                35: begin isel=I_MAX1N; ysel_imm=1; end          // C = acc > MAX
                36: if(C) S_LDI(I_MAX);
                37: begin isel=I_MAX; ysel_imm=1; end            // C = acc < -MAX
                38: if(C) S_LDI(I_NMAX);
                39: S_LD(NI);
                40: if(!(CH && !eneg) && !(CL && !epos)) S_ST(INTEG);
                41: S_LD(PE); 42: S_ST(PREV);
                default: ;
            endcase
        endcase
    end
    // negation steps (N set): acc <= 0 - acc  = ~acc + 1 (dedicated, not through the step table)
    wire neg_step = (jt==J_ARM && (step==11 || step==14)) || (jt==J_POS && (step==14 || step==17)) || (jt==J_ABS && step==4) ||
                    (jt==J_PID && (step==19 || step==31 || step==34));
    wire set_n = (jt==J_ARM && step==10) || (jt==J_POS && step==13) || (jt==J_ABS && step==3) || (jt==J_PID && step==30);
    wire [3:0] nrep = (jt==J_ARM) ? (step==5 ? 4'd3 : step==7 ? 4'd1 : 4'd9) : (jt==J_POS) ? (step==8 ? 4'd3 : step==10 ? 4'd1 : 4'd9) :
                      (step==10 ? KD_S[3:0] : step==13 ? (KP2 ? KP_B[3:0] : KP_A[3:0]) : step==15 ? (KP2 ? KP_A[3:0]-KP_B[3:0] : 4'd0) : step==18 ? 4'd1 : 4'd12);
    wire last_step = (jt==J_ARM && step==17) || (jt==J_POS && step==25) || (jt==J_ABS && step==6) || (jt==J_PID && step==42);
    always @(posedge clk) if(busy && rfw) rf[{ax, wr_r}] <= acc;
    always @(posedge clk or posedge rst) begin
        if(rst) begin
            acc<=0; step<=0; jt<=0; ax<=0; busy<=0; N<=0; C<=0; CH<=0; CL<=0; sp<=0; rep<=0; pa<=0; pp<=0; jlat0<=0; jlat1<=0; splat<=0;
            el0<=0; el1<=0; Z<=2'b11; PV<=0; adone<=0; err_ok<=0; drift_ok<=0; prog_big<=0; pul_we<=0; pul_dir<=0; pul_mag<=0;
            cmd_valid<=0; cmd0<=0; cmd1<=0;
        end else begin
            adone<=0; pul_we<=0; cmd_valid<=0;
            if(areq[0]) begin pa[0]<=1; jlat0<=ajob0; splat[0]<=asetprog[0]; end
            if(areq[1]) begin pa[1]<=1; jlat1<=ajob1; splat[1]<=asetprog[1]; end
            if(!safe) begin pp<=0; Z<=2'b11; PV<=0; end
            else begin
                if(preq[0]) begin pp[0]<=1; el0<=e0; end
                if(preq[1]) begin pp[1]<=1; el1<=e1; end
            end
            if(!busy) begin
                step<=0; rep<=0;
                if(pp[0] && safe) begin busy<=1; jt<=J_PID; ax<=0; pp[0]<=0; end
                else if(pp[1] && safe) begin busy<=1; jt<=J_PID; ax<=1; pp[1]<=0; end
                else if(pa[0]) begin busy<=1; jt<=jlat0; ax<=0; sp<=splat[0]; pa[0]<=0; end
                else if(pa[1]) begin busy<=1; jt<=jlat1; ax<=1; sp<=splat[1]; pa[1]<=0; end
            end else begin
                // accumulator
                if(shl || shr) begin
                    acc <= shl ? acc <<< 1 : acc >>> 1;
                end else if(neg_step) begin
                    if(N) acc <= ~acc + 40'sd1;
                end else if(accw) acc <= sum;
                if(set_n) N <= acc[39];
                // compares (sum without writing acc)
                if(jt==J_PID && (step==3 || step==35)) C <= !sum[39];
                if(jt==J_PID && (step==5 || step==37 || step==22)) C <= sum[39];
                if(jt==J_PID && step==24) C <= !sum[39];
                if(jt==J_PID && step==35) CH <= !sum[39];
                if(jt==J_PID && step==37) CL <= sum[39];
                if(jt==J_PID && step==18) N <= 1'b1;             // 19: negate (pterm >>> 1)
                // flags of POS
                if(jt==J_POS && step==3) drift_ok <= absle(5'd6);
                if(jt==J_POS && step==5) prog_big <= !absle(5'd19);
                if(jt==J_POS && step==20) err_ok <= absle(5'd3);
                // outputs
                if(jt==J_ABS && step==5) begin pul_we[ax]<=1; pul_dir<=N; pul_mag<=acc[27:0]; end
                if(jt==J_PID && step==39) begin cmd_valid[ax]<=safe; if(ax) cmd1<=acc[7:0]; else cmd0<=acc[7:0]; end
                if(jt==J_PID && step==42 && safe) begin PV[ax]<=1; if(!(CH && !eneg) && !(CL && !epos)) Z[ax]<=0; end
                // deadband: command 0, integral / previous error cleared
                if(jt==J_PID && step==0 && ein) begin cmd_valid[ax]<=safe; if(ax) cmd1<=0; else cmd0<=0; Z[ax]<=1; PV[ax]<=0; busy<=0; end
                // sequencing (shift steps repeat nrep times; an nrep of 0 skips)
                else if((shl || shr) && rep+4'd1 < nrep) rep<=rep+4'd1;
                else begin
                    rep<=0;
                    if(last_step) begin busy<=0; if(jt!=J_PID) adone[ax]<=1; end
                    else if(jt==J_PID && (step==9 && KD_S==0)) step<=step+7'd2;   // KD = 1: no shift step
                    else if(jt==J_PID && step==13 && !KP2) step<=7'd17;           // KP = 2^KP_A: no second term
                    else step<=step+7'd1;
                end
            end
        end
    end
endmodule

// track_pid_pair + gimbal_pair (board22) on gm_calc / gm_axis.
module gimbal_mc #(parameter integer CLK_HZ=75000000, BAUD=115200, CONTROL_MS=12, STALE_MS=500, POLL_MS=3,
                   KP_A=9, KP_B=8, KD_S=7, MAX_STEP=32, R1=4, R2=12, R3=24, R4=40)(
    input wire clk, rst, mode_sel, mode_ok, arm_pulse, stop_pulse, target_update, target_good,
    input wire [15:0] target_fid, input wire [10:0] cx, input wire [9:0] cy,
    input wire pitch_rx, yaw_rx, output wire pitch_tx, yaw_tx,
    output reg armed, output reg fault, output wire ready_to_arm, ready,
    output wire [7:0] pitch_code, yaw_code, output reg [3:0] control_code, output wire [7:0] pitch_acks, yaw_acks,
    output wire signed [7:0] pitch_last, yaw_last, output wire ms_o);   // ms_o: shared 1 ms tick (Z11: key timers)
    localparam integer MSC = CLK_HZ/1000;
    reg [$clog2(MSC)-1:0] msc; reg ms;
    always @(posedge clk or posedge rst) if(rst) begin msc<=0; ms<=0; end else begin ms <= msc==MSC-1; msc <= msc==MSC-1 ? 0 : msc+1'b1; end
    assign ms_o = ms;
    wire pr, yr, pf, yf, po, yo;
    assign ready_to_arm = po && yo && !armed;
    assign ready = armed && pr && yr;
    reg [$clog2(STALE_MS+1)-1:0] age; reg [$clog2(CONTROL_MS)-1:0] timer; reg [15:0] last_fid; reg have_fid, pending_p, pending_y;
    reg [1:0] good_count; reg signed [12:0] ex, ey;
    wire [15:0] fid_delta = target_fid - last_fid;
    wire newer = !have_fid || (fid_delta!=0 && !fid_delta[15]);
    wire sample_ok = target_good && cx<1280 && cy<720;
    wire expired = age==STALE_MS;
    wire bad_now = target_update && newer && !sample_ok;
    wire safe = armed && mode_ok && !stop_pulse && !pf && !yf && !expired && !bad_now;
    wire tick = ms && timer==CONTROL_MS-1;
    wire consume_p = tick && safe && pending_p && good_count==3 && pr;
    wire consume_y = tick && safe && pending_y && good_count==3 && yr;
    // calc <-> axes
    wire [1:0] areq, adone, pul_we; wire [1:0] job0, job1, setp; wire err_ok, drift_ok, prog_big, pul_dir; wire [27:0] pul_mag;
    wire signed [30:0] raw0, raw1; wire signed [6:0] req0, req1; wire [1:0] cmdv; wire signed [7:0] cmd0, cmd1;
    gm_calc #(.KP_A(KP_A),.KP_B(KP_B),.KD_S(KD_S),.MAX_STEP(MAX_STEP)) calc(.clk(clk),.rst(rst),.safe(safe),
        .areq(areq),.ajob0(job0),.ajob1(job1),.asetprog(setp),.raw0(raw0),.raw1(raw1),.req0(req0),.req1(req1),
        .adone(adone),.err_ok(err_ok),.drift_ok(drift_ok),.prog_big(prog_big),.pul_we(pul_we),.pul_dir(pul_dir),.pul_mag(pul_mag),
        .preq({consume_y, consume_p}),.e0(-ey),.e1(ex),.cmd_valid(cmdv),.cmd0(cmd0),.cmd1(cmd1));
    gm_axis #(.CLK_HZ(CLK_HZ),.BAUD(BAUD),.POLL_MS(POLL_MS),.R1(R1),.R2(R2),.R3(R3),.R4(R4)) pitch(.clk(clk),.rst(rst),.ms(ms),.enable(armed),
        .move_valid(cmdv[0] && safe),.move_steps(cmd0),.ready(pr),.fault(pf),.tx(pitch_tx),.rx(pitch_rx),.ready_to_arm(po),.fault_code(pitch_code),
        .move_acks(pitch_acks),.last_move(pitch_last),.job_req(areq[0]),.job(job0),.setprog(setp[0]),.job_done(adone[0]),
        .err_ok(err_ok),.drift_ok(drift_ok),.prog_big(prog_big),.pul_we(pul_we[0]),.pul_dir(pul_dir),.pul_mag(pul_mag),.raw(raw0),.requested(req0));
    gm_axis #(.CLK_HZ(CLK_HZ),.BAUD(BAUD),.POLL_MS(POLL_MS),.R1(R1),.R2(R2),.R3(R3),.R4(R4)) yaw(.clk(clk),.rst(rst),.ms(ms),.enable(armed),
        .move_valid(cmdv[1] && safe),.move_steps(cmd1),.ready(yr),.fault(yf),.tx(yaw_tx),.rx(yaw_rx),.ready_to_arm(yo),.fault_code(yaw_code),
        .move_acks(yaw_acks),.last_move(yaw_last),.job_req(areq[1]),.job(job1),.setprog(setp[1]),.job_done(adone[1]),
        .err_ok(err_ok),.drift_ok(drift_ok),.prog_big(prog_big),.pul_we(pul_we[1]),.pul_dir(pul_dir),.pul_mag(pul_mag),.raw(raw1),.requested(req1));
    always @(posedge clk or posedge rst) begin
        if(rst) begin age<=STALE_MS; timer<=0; last_fid<=0; have_fid<=0; pending_p<=0; pending_y<=0; good_count<=0; ex<=0; ey<=0; armed<=0; fault<=0; control_code<=0; end
        else begin
            if(ms) timer <= timer==CONTROL_MS-1 ? 0 : timer+1'b1;
            if(ms && age!=STALE_MS) age<=age+1'b1;
            if(consume_p) pending_p<=0;
            if(consume_y) pending_y<=0;
            if(expired) good_count<=0;                                  // Z18: after a stale hold, 3 good samples again
            if(!mode_ok) begin have_fid<=0; pending_p<=0; pending_y<=0; good_count<=0; age<=STALE_MS; end
            else if(target_update && newer) begin
                have_fid<=1; last_fid<=target_fid;
                if(sample_ok) begin
                    age<=0; pending_p<=1; pending_y<=1; if(good_count<3) good_count<=good_count+1'b1;
                    ex <= $signed({2'd0,cx}) - 13'sd640; ey <= $signed({3'd0,cy}) - 13'sd360;
                end else begin pending_p<=0; pending_y<=0; good_count<=0; end
            end
            // CLAUDE Z18 (board: the gimbal stopped for good after a short track loss): a lost lock (!mode_ok), a stale
            // target (expired) or a bad sample only hold the gimbal (safe = 0, no move, 3 good samples to resume); it is
            // disarmed only by leaving the follow mode (mode_sel), the stop key or an axis fault.
            if(armed && (!mode_sel || stop_pulse || pf || yf)) begin
                armed<=0; fault<=1; pending_p<=0; pending_y<=0; good_count<=0;
                control_code <= stop_pulse ? 4'd1 : !mode_sel ? 4'd2 : pf ? 4'd3 : 4'd4;
            end else if(!armed && arm_pulse && po && yo && mode_ok && !stop_pulse && !pf && !yf && !expired && good_count==3 && !bad_now) begin
                armed<=1; fault<=0; control_code<=0; timer<=0;
            end
        end
    end
endmodule
