// CLAUDE GIMBAL LITE (2026-10-30): the board22 (MONO_GIMBAL_20261029) gimbal chain, area-reduced for the full-mode build.
// Same control law, Emm FW fixed-frame protocol, state sequences and safety stops as board22 gimbal_pair / track_pid_pair /
// image_position_pid / emm_follow_axis / emm_axis / uart_8n1, cycle for cycle with the board22 parameters; changes are
// implementation only:
//   * every register sized to its proven range (encoder |raw| < 2^30 by the pos_good check, steps < 2^27, |request| <= 32,
//     PID terms from |error| <= 1280); the 42-bit temporaries share one 37-bit register; drift / progress / err keep only
//     their compare results; counters sized to their limits
//   * constant multiplies (x25, KP / KI / KD) as shift-add: no DSP
//   * emm_axis: command bytes generated from (op, index) instead of a 13-byte buffer (dir / rpm / pulses are stable during
//     a transaction), only reply bytes 2..6 kept (all the follower reads), stop_request / rx diagnostics / enabled /
//     center_known (unused in board22) removed, only the five ops the follower issues (1 EN, 4 STOP, 7 POS, 8 STATUS, 9 MOVE)
//   * target frame id 16 bits (wrap-safe compare, ids come from a per-result counter)
module gl_uart #(parameter integer CLK_HZ=75000000, BAUD=115200)(
    input wire clk, rst, tx_start, input wire [7:0] tx_byte, output reg tx, output wire tx_busy, output reg tx_done,
    input wire rx, output reg rx_valid, output reg [7:0] rx_byte, output reg rx_error);
    localparam integer DIV=(CLK_HZ+BAUD/2)/BAUD, W=$clog2(DIV);
    reg [W-1:0] tc, rc; reg [3:0] tb, rb; reg [9:0] ts; reg [7:0] rs; reg tactive; reg [1:0] rstate;
    (* async_reg="true" *) reg rx1, rx2;
    assign tx_busy = tactive;
    always @(posedge clk or posedge rst) begin
        if(rst) begin tx<=1; tactive<=0; tc<=0; tb<=0; ts<=10'h3ff; tx_done<=0; end
        else begin
            tx_done<=0;
            if(!tactive) begin
                tx<=1;
                if(tx_start) begin ts<={1'b1,tx_byte,1'b0}; tx<=0; tactive<=1; tc<=DIV-1; tb<=0; end
            end else if(tc!=0) tc<=tc-1'b1;
            else if(tb==9) begin tx<=1; tactive<=0; tx_done<=1; end
            else begin tb<=tb+1'b1; ts<={1'b1,ts[9:1]}; tx<=ts[1]; tc<=DIV-1; end
        end
    end
    always @(posedge clk or posedge rst) begin
        if(rst) begin rx1<=1; rx2<=1; rstate<=0; rc<=0; rb<=0; rs<=0; rx_valid<=0; rx_error<=0; rx_byte<=0; end
        else begin
            rx1<=rx; rx2<=rx1; rx_valid<=0; rx_error<=0;
            case(rstate)
                0: if(!rx2) begin rc<=DIV/2-1; rstate<=1; end
                1: if(rc!=0) rc<=rc-1'b1; else if(rx2) rstate<=0; else begin rstate<=2; rc<=DIV-1; rb<=0; end
                2: if(rc!=0) rc<=rc-1'b1; else begin rs[rb]<=rx2; rc<=DIV-1; if(rb==7) rstate<=3; else rb<=rb+1'b1; end
                3: if(rc!=0) rc<=rc-1'b1; else begin rstate<=0; if(rx2) begin rx_byte<=rs; rx_valid<=1; end else rx_error<=1; end
            endcase
        end
    end
endmodule

// Emm FW fixed frames: op 1 enable (F3 AB 01 00), 4 stop (FE 98 00), 7 position (36, 8-byte reply), 8 status (3A),
// 9 move (FD dir rpm acc pulses 01 00). Reply bytes 2..6 on reply[47:8] (board22 reply bit numbering).
module gl_emm #(parameter integer CLK_HZ=75000000, BAUD=115200, parameter [7:0] ADDRESS=8'd1, parameter integer REPLY_MS=50)(
    input wire clk, rst, cmd_valid, input wire [3:0] op, input wire dir, input wire [5:0] rpm, input wire [27:0] pulses,
    output wire busy, output reg done, output reg [7:0] result, output reg [47:8] reply, output reg [3:0] reply_len,
    output wire uart_tx, input wire uart_rx);
    localparam integer TURN=CLK_HZ/1000*2, TOUT=CLK_HZ/1000*REPLY_MS;
    reg [3:0] length, index, expected, received, aop; reg [1:0] state; reg [7:0] fcode;
    reg tx_start; wire tx_busy, tx_done, rx_valid, rx_error; wire [7:0] rx_byte;
    reg [$clog2(TOUT+1)-1:0] tcnt; reg [$clog2(TURN+1)-1:0] turn;
    reg receive_open, frame_ready, bad_frame, rx_fault; reg [47:8] cand;
    reg [7:0] cb;                                                  // command byte (aop, index)
    always @* begin
        cb = 8'h6b;
        if(index==0) cb = ADDRESS;
        else case(aop)
            4'd1: case(index) 1: cb=8'hf3; 2: cb=8'hab; 3: cb=8'h01; 4: cb=8'h00; default: cb=8'h6b; endcase
            4'd4: case(index) 1: cb=8'hfe; 2: cb=8'h98; 3: cb=8'h00; default: cb=8'h6b; endcase
            4'd7: cb = index==1 ? 8'h36 : 8'h6b;
            4'd8: cb = index==1 ? 8'h3a : 8'h6b;
            default: case(index)                                   // 9 move
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
            done<=0; tx_start<=0; if(turn!=0) turn<=turn-1'b1;
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
                    if(rx_fault || rx_error) begin state<=0; done<=1; result<=6; turn<=TURN; end
                    else if(frame_ready) begin state<=0; done<=1; turn<=TURN; reply<=cand; reply_len<=expected; result<=bad_frame?8'd6:8'd1; end
                    else if(tcnt>=TOUT-1 && !rx_valid) begin state<=0; done<=1; result<=5; turn<=TURN; end
                    else if(tcnt<TOUT) tcnt<=tcnt+1'b1;
                end
            endcase
        end
    end
endmodule

// emm_follow_axis (board22) with proven-range widths. RPM table / acceleration as board22 unless overridden.
module gl_axis #(parameter integer CLK_HZ=75000000, BAUD=115200, POLL_MS=3, MOVE_MS=4000,
                 R1=4, R2=12, R3=24, R4=40, T2=5, T3=13, T4=25)(
    input wire clk, rst, enable, move_valid, input wire signed [7:0] move_steps,
    output wire ready, output reg fault, output reg signed [15:0] position_steps,
    output wire tx, input wire rx, output wire ready_to_arm, output reg [7:0] fault_code,
    output reg [7:0] move_acks, output reg signed [7:0] last_move);
    localparam [4:0] OFF=0,EN_SEND=1,EN_WAIT=2,ST_SEND=3,ST_WAIT=4,POS_SEND=5,POS_WAIT=6,IDLE=7,MV_SEND=8,MV_WAIT=9,DELAY=10,
                     STOP_SEND=11,STOP_WAIT=12,FAULT=13,POS_DIFF=14,POS_SCALE=15,POS_MAG=16,POS_STEP=17,POS_ERR=18,POS_CHECK=19,
                     ARM_SCALE=20,ARM_ROUND=21,ABS_TARGET=22,ABS_MAG=23;
    localparam integer POLLC=CLK_HZ/1000*POLL_MS, MOVEC=CLK_HZ/1000*MOVE_MS;
    reg [4:0] state;
    reg active, prev_enable, prepared, moving, pending_move, work_request, hold_stop, command, direction, stable, arrived, neg;
    reg drift_ok, prog_big, err_ok;
    reg [3:0] op; reg [27:0] pulse_count; reg [$clog2(POLLC+1)-1:0] poll_count; reg [$clog2(MOVEC+1)-1:0] move_age;
    reg signed [30:0] origin, last_raw, progress_raw, raw_saved;
    reg signed [6:0] requested, latest_request;
    reg signed [28:0] target_steps, next_target;
    reg signed [26:0] origin_pulses; reg signed [27:0] steps;
    reg signed [36:0] t;                                           // origin*25 / diff, diff*25, |diff*25| / absolute target
    reg [5:0] move_rpm;
    wire busy, done; wire [7:0] result; wire [47:8] reply; wire [3:0] reply_len;
    wire ack = result==1 && reply_len==4 && reply[47:40]==2;
    wire state_good = result==1 && reply_len==4 && (reply[47:40]&8'h0d)==1;
    wire pos_good = result==1 && reply_len==8 && reply[47:40]<=1 && reply[39:8]<=32'h3fffffff;
    wire signed [30:0] raw = reply[47:40]==1 ? -$signed({1'b0,reply[37:8]}) : $signed({1'b0,reply[37:8]});
    wire signed [31:0] drift = raw_saved - last_raw, progress = raw_saved - progress_raw;
    wire signed [29:0] err = steps - target_steps;
    wire signed [36:0] x25 = (t <<< 4) + (t <<< 3) + t;
    wire signed [36:0] tn = -t;
    assign ready_to_arm = state==OFF && !busy && !enable && !fault;
    assign ready = active && prepared && enable && !fault;
    gl_emm #(.CLK_HZ(CLK_HZ),.BAUD(BAUD)) u_uart(.clk(clk),.rst(rst),.cmd_valid(command && (enable || op==4)),.op(op),.dir(direction),
        .rpm(move_rpm),.pulses(pulse_count),.busy(busy),.done(done),.result(result),.reply(reply),.reply_len(reply_len),
        .uart_tx(tx),.uart_rx(rx));
    task fail(input [7:0] code); begin fault<=1; fault_code<=code; active<=0; hold_stop<=0; state<=STOP_SEND; end endtask
    always @(posedge clk or posedge rst) begin
        if(rst) begin
            state<=OFF; active<=0; prev_enable<=0; prepared<=0; moving<=0; pending_move<=0; work_request<=0; hold_stop<=0;
            command<=0; op<=0; direction<=0; pulse_count<=0; poll_count<=0; move_age<=0; stable<=0; arrived<=0; neg<=0;
            drift_ok<=0; prog_big<=0; err_ok<=0; origin<=0; last_raw<=0; progress_raw<=0; raw_saved<=0; requested<=0; latest_request<=0;
            target_steps<=0; next_target<=0; origin_pulses<=0; steps<=0; t<=0; move_rpm<=R1[5:0];
            fault<=0; fault_code<=0; move_acks<=0; last_move<=0; position_steps<=0;
        end else begin
            command<=0; prev_enable<=enable;
            if(moving && move_age<MOVEC) move_age<=move_age+1'b1;
            if(active && (!enable || (moving && move_age>=MOVEC))) begin
                active<=0; hold_stop<=0; state<=STOP_SEND;
                if(enable) begin fault<=1; fault_code<=8'h71; end
            end else case(state)
                OFF: if(enable && !prev_enable) begin
                    active<=1; prepared<=0; moving<=0; stable<=0; fault<=0; fault_code<=0; move_acks<=0; last_move<=0;
                    pending_move<=0; work_request<=0; hold_stop<=0; state<=EN_SEND;
                end
                EN_SEND: if(!busy) begin command<=1; op<=1; state<=EN_WAIT; end
                EN_WAIT: if(done) begin if(ack) state<=ST_SEND; else fail({4'h1, result==1 ? 4'hf : result[3:0]}); end
                ST_SEND: if(!busy) begin command<=1; op<=8; state<=ST_WAIT; end
                ST_WAIT: if(done) begin if(state_good) begin arrived<=reply[41]; state<=POS_SEND; end else fail({4'h2, result==1 ? 4'hf : result[3:0]}); end
                POS_SEND: if(!busy) begin command<=1; op<=7; state<=POS_WAIT; end
                POS_WAIT: if(done) begin
                    if(!pos_good) fail({4'h3, result==1 ? 4'hf : result[3:0]});
                    else if(!prepared) begin
                        if(!arrived) fail(8'h41);
                        else begin origin<=raw; last_raw<=raw; progress_raw<=raw; position_steps<=0; target_steps<=0; t<=raw; state<=ARM_SCALE; end
                    end else begin raw_saved<=raw; work_request<=pending_move; requested<=latest_request; pending_move<=0; state<=POS_DIFF; end
                end
                ARM_SCALE: begin t<=x25; state<=ARM_ROUND; end
                ARM_ROUND: begin
                    origin_pulses <= t<0 ? -((tn+37'sd256)>>>9) : ((t+37'sd256)>>>9);
                    prepared<=1; poll_count<=0; state<=IDLE;
                end
                POS_DIFF: begin
                    t <= raw_saved - origin;
                    drift_ok <= drift<=6 && drift>=-6; prog_big <= progress>=20 || progress<=-20;
                    state<=POS_SCALE;
                end
                POS_SCALE: begin t<=x25; state<=POS_MAG; end
                POS_MAG: begin t <= t<0 ? tn : t; neg <= t<0; state<=POS_STEP; end
                POS_STEP: begin steps <= neg ? -((t+37'sd256)>>>9) : ((t+37'sd256)>>>9); state<=POS_ERR; end
                POS_ERR: begin err_ok <= err<=3 && err>=-3; next_target <= steps + requested; state<=POS_CHECK; end
                POS_CHECK: begin
                    position_steps <= steps>32767 ? 16'sh7fff : steps< -32768 ? 16'sh8000 : steps[15:0];
                    last_raw<=raw_saved; poll_count<=0;
                    if(prog_big) begin progress_raw<=raw_saved; move_age<=0; end
                    if(work_request) begin
                        work_request<=0;
                        if(requested==0) begin if(moving) begin hold_stop<=1; state<=STOP_SEND; end else state<=IDLE; end
                        else begin target_steps<=next_target; stable<=0; state<=ABS_TARGET; end
                    end else begin
                        if(moving && arrived && err_ok && drift_ok) begin if(stable) begin moving<=0; stable<=0; end else stable<=1; end
                        else stable<=0;
                        state<=IDLE;
                    end
                end
                ABS_TARGET: begin t <= origin_pulses + target_steps; state<=ABS_MAG; end
                ABS_MAG: begin
                    direction <= t<0; pulse_count <= t<0 ? tn[27:0] : t[27:0];
                    move_rpm <= (requested>=T4 || requested<=-T4) ? R4[5:0] : (requested>=T3 || requested<=-T3) ? R3[5:0] :
                                (requested>=T2 || requested<=-T2) ? R2[5:0] : R1[5:0];
                    state<=MV_SEND;
                end
                IDLE: begin
                    if(pending_move) state<=ST_SEND;
                    else if(moving) begin if(poll_count>=POLLC-1) begin poll_count<=0; state<=ST_SEND; end else poll_count<=poll_count+1'b1; end
                end
                MV_SEND: if(!busy) begin command<=1; op<=9; if(!moving) begin move_age<=0; progress_raw<=raw_saved; end moving<=1; state<=MV_WAIT; end
                MV_WAIT: if(done) begin
                    if(ack) begin move_acks<=move_acks+1'b1; last_move<=requested; poll_count<=0; state<=IDLE; end
                    else fail({4'h6, result==1 ? 4'hf : result[3:0]});
                end
                STOP_SEND: if(!busy) begin command<=1; op<=4; state<=STOP_WAIT; moving<=0; end
                STOP_WAIT: if(done) begin
                    if(!ack) begin fault<=1; active<=0; if(!fault) fault_code<={4'h8, result[3:0]}; state<=FAULT; end
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

// image_position_pid (board22), narrow terms, shift-add constant multiplies.
module gl_pid #(parameter integer KP_Q12=768, KI_Q12=1, KD_Q12=128, DEAD_PX=4, I_LIMIT=4096, MAX_STEP=32, REVERSE=0)(
    input wire clk, rst, enable, sample_tick, fresh, axis_ready, input wire signed [12:0] error_px,
    output reg command_valid, output reg signed [7:0] command_steps);
    function automatic signed [23:0] cmul(input signed [23:0] v, input integer k);
        integer i; begin cmul = 0; for(i=0; i<16; i=i+1) if(k[i]) cmul = cmul + (v <<< i); end
    endfunction
    reg [3:0] state; reg signed [12:0] previous_error, e; reg previous_valid, negative;
    reg signed [14:0] integral, ni; reg signed [13:0] deriv;
    reg signed [23:0] pterm, iterm, dterm, psum, effort, mag; reg signed [11:0] raw_step; reg signed [7:0] limited;
    wire signed [12:0] input_e = REVERSE ? -error_px : error_px;
    always @(posedge clk or posedge rst) begin
        if(rst) begin
            state<=0; command_valid<=0; command_steps<=0; integral<=0; previous_error<=0; previous_valid<=0;
            e<=0; ni<=0; deriv<=0; pterm<=0; iterm<=0; dterm<=0; psum<=0; effort<=0; mag<=0; raw_step<=0; limited<=0; negative<=0;
        end else begin
            command_valid<=0;
            if(!enable) begin state<=0; integral<=0; previous_error<=0; previous_valid<=0; command_steps<=0; end
            else case(state)
                0: if(sample_tick && fresh && axis_ready) begin
                    if(input_e<=DEAD_PX && input_e>=-DEAD_PX) begin integral<=0; previous_error<=0; previous_valid<=0; command_steps<=0; command_valid<=1; end
                    else begin e<=input_e; state<=1; end
                end
                1: begin ni<=integral+e; deriv <= previous_valid ? e-previous_error : 14'sd0; state<=2; end
                2: begin
                    if(ni>I_LIMIT) ni<=I_LIMIT; else if(ni< -I_LIMIT) ni<=-I_LIMIT;
                    pterm<=cmul(e, KP_Q12); dterm<=cmul(deriv, KD_Q12); state<=3;
                end
                3: begin
                    iterm<=cmul(ni, KI_Q12);
                    if(e>0 && dterm< -(pterm>>>1)) dterm<=-(pterm>>>1);
                    else if(e<0 && dterm> -(pterm>>>1)) dterm<=-(pterm>>>1);
                    state<=4;
                end
                4: begin psum<=pterm+iterm; state<=5; end
                5: begin effort<=psum+dterm; state<=6; end
                6: begin negative<=effort<0; mag <= effort<0 ? -effort : effort; state<=7; end
                7: begin raw_step <= negative ? -((mag+24'sd2048)>>>12) : ((mag+24'sd2048)>>>12); state<=8; end
                8: begin limited <= raw_step>MAX_STEP ? MAX_STEP : raw_step< -MAX_STEP ? -MAX_STEP : raw_step; state<=9; end
                9: state<=10;
                10: state<=11;
                11: begin
                    previous_error<=e; previous_valid<=1;
                    if(limited==raw_step || (raw_step>limited && e<0) || (raw_step<limited && e>0)) integral<=ni;
                    command_steps<=limited; command_valid<=1; state<=0;
                end
                default: begin state<=0; integral<=0; previous_valid<=0; command_steps<=0; end
            endcase
        end
    end
endmodule

// track_pid_pair + gimbal_pair (board22). mode_ok = a follow-capable mode with its target (board22: mode_template).
module gimbal_lite #(parameter integer CLK_HZ=75000000, BAUD=115200, CONTROL_MS=12, STALE_MS=500, POLL_MS=3,
                     KP_Q12=768, KI_Q12=1, KD_Q12=128, MAX_STEP=32, R1=4, R2=12, R3=24, R4=40)(
    input wire clk, rst, mode_ok, arm_pulse, stop_pulse, target_update, target_good,
    input wire [15:0] target_fid, input wire [10:0] cx, input wire [9:0] cy,
    input wire pitch_rx, yaw_rx, output wire pitch_tx, yaw_tx,
    output reg armed, output reg fault, output wire ready_to_arm, ready,
    output wire [7:0] pitch_code, yaw_code, output reg [3:0] control_code, output wire [7:0] pitch_acks, yaw_acks,
    output wire signed [7:0] pitch_last, yaw_last);
    localparam integer PERIOD=CLK_HZ/1000*CONTROL_MS, TTL=CLK_HZ/1000*STALE_MS;
    wire pr, yr, pf, yf, pv0, yv0, po, yo; wire signed [7:0] ps, ys;
    assign ready_to_arm = po && yo && !armed;
    assign ready = armed && pr && yr;
    reg [$clog2(TTL+1)-1:0] age; reg [$clog2(PERIOD)-1:0] timer; reg [15:0] last_fid; reg have_fid, pending_p, pending_y;
    reg [1:0] good_count; reg signed [12:0] ex, ey;
    wire [15:0] fid_delta = target_fid - last_fid;
    wire newer = !have_fid || (fid_delta!=0 && !fid_delta[15]);
    wire sample_ok = target_good && cx<1280 && cy<720;
    wire expired = age>=TTL;
    wire bad_now = target_update && newer && !sample_ok;
    wire safe = armed && mode_ok && !stop_pulse && !pf && !yf && !expired && !bad_now;
    wire tick = timer==PERIOD-1;
    wire consume_p = tick && safe && pending_p && good_count==3 && pr;
    wire consume_y = tick && safe && pending_y && good_count==3 && yr;
    wire pv = pv0 && safe, yv = yv0 && safe;
    gl_pid #(.KP_Q12(KP_Q12),.KI_Q12(KI_Q12),.KD_Q12(KD_Q12),.MAX_STEP(MAX_STEP),.REVERSE(1)) p(.clk(clk),.rst(rst),.enable(safe),
        .sample_tick(consume_p),.fresh(pending_p),.axis_ready(pr),.error_px(ey),.command_valid(pv0),.command_steps(ps));
    gl_pid #(.KP_Q12(KP_Q12),.KI_Q12(KI_Q12),.KD_Q12(KD_Q12),.MAX_STEP(MAX_STEP),.REVERSE(0)) y(.clk(clk),.rst(rst),.enable(safe),
        .sample_tick(consume_y),.fresh(pending_y),.axis_ready(yr),.error_px(ex),.command_valid(yv0),.command_steps(ys));
    gl_axis #(.CLK_HZ(CLK_HZ),.BAUD(BAUD),.POLL_MS(POLL_MS),.R1(R1),.R2(R2),.R3(R3),.R4(R4)) pitch(.clk(clk),.rst(rst),.enable(armed),
        .move_valid(pv),.move_steps(ps),.ready(pr),.fault(pf),.position_steps(),.tx(pitch_tx),.rx(pitch_rx),.ready_to_arm(po),
        .fault_code(pitch_code),.move_acks(pitch_acks),.last_move(pitch_last));
    gl_axis #(.CLK_HZ(CLK_HZ),.BAUD(BAUD),.POLL_MS(POLL_MS),.R1(R1),.R2(R2),.R3(R3),.R4(R4)) yaw(.clk(clk),.rst(rst),.enable(armed),
        .move_valid(yv),.move_steps(ys),.ready(yr),.fault(yf),.position_steps(),.tx(yaw_tx),.rx(yaw_rx),.ready_to_arm(yo),
        .fault_code(yaw_code),.move_acks(yaw_acks),.last_move(yaw_last));
    always @(posedge clk or posedge rst) begin
        if(rst) begin age<=TTL; timer<=0; last_fid<=0; have_fid<=0; pending_p<=0; pending_y<=0; good_count<=0; ex<=0; ey<=0; armed<=0; fault<=0; control_code<=0; end
        else begin
            timer <= tick ? 0 : timer+1'b1; if(age<TTL) age<=age+1'b1;
            if(consume_p) pending_p<=0;
            if(consume_y) pending_y<=0;
            if(!mode_ok) begin have_fid<=0; pending_p<=0; pending_y<=0; good_count<=0; age<=TTL; end
            else if(target_update && newer) begin
                have_fid<=1; last_fid<=target_fid;
                if(sample_ok) begin
                    age<=0; pending_p<=1; pending_y<=1; if(good_count<3) good_count<=good_count+1'b1;
                    ex <= $signed({2'd0,cx}) - 13'sd640; ey <= $signed({3'd0,cy}) - 13'sd360;
                end else begin pending_p<=0; pending_y<=0; good_count<=0; end
            end
            if(armed && (!mode_ok || stop_pulse || pf || yf || expired || bad_now)) begin
                armed<=0; fault<=1; pending_p<=0; pending_y<=0; good_count<=0;
                control_code <= stop_pulse ? 4'd1 : !mode_ok ? 4'd2 : pf ? 4'd3 : yf ? 4'd4 : expired ? 4'd5 : 4'd6;
            end else if(!armed && arm_pulse && po && yo && mode_ok && !stop_pulse && !pf && !yf && !expired && good_count==3 && !bad_now) begin
                armed<=1; fault<=0; control_code<=0; timer<=0;
            end
        end
    end
endmodule
