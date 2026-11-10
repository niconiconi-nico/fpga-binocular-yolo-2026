// Independent SC520 experiment. Does not modify pixels, clocks, VTS or YOLO.
// SC520CS V1.6 pp19-22: half-line exposure 4..2*VTS-9; N+2 latency;
// analog gain 00/08/09/0b/0f/1f; group hold 3812=00 ... 30.
// Use original SC520GainTbl index 16..176 (1..32x total gain).
// Measurement is linear RAW10 green, before AWB, not display RGB/gamma.
module sc520_auto_exposure #(
    parameter integer FRAME_WORDS=230400,
    parameter integer EXP_MAX=1991,
    parameter integer GAIN_MAX=176,
    parameter integer SETTLE_FRAMES=4,
    parameter integer TIMEOUT_CYCLES=12000000
)(
    input wire pixel_clk, pixel_rst_n, raw_valid, raw_sof, raw_eol,
    input wire [39:0] raw_data,
    input wire cfg_clk, cfg_rst_n, cfg_done, ae_done, cfg_error,
    input wire hold,                                  // CLAUDE Z17 (upper board): AE lock level (any clock), no new command while set
    output reg ae_req,
    output wire [15:0] exposure, gain_index,
    output wire [15:0] applied_exposure, applied_gain_index,
    output reg fault,
    output reg [31:0] applied_transactions,
    output reg [27:0] measured_green_sum,
    output reg [18:0] measured_clipped,
    output reg measurement_pulse,
    output reg [31:0] measured_raw_sequence, command_raw_sequence
);
wire [3:0] settle;
localparam [15:0] MASK_exposure=EXP_MAX;
reg [15:0] enc_exposure;
assign exposure=enc_exposure ^ MASK_exposure;
localparam [15:0] MASK_gain_index=16;
reg [15:0] enc_gain_index;
assign gain_index=enc_gain_index ^ MASK_gain_index;
localparam [15:0] MASK_applied_exposure=EXP_MAX;
reg [15:0] enc_applied_exposure;
assign applied_exposure=enc_applied_exposure ^ MASK_applied_exposure;
localparam [15:0] MASK_applied_gain_index=16;
reg [15:0] enc_applied_gain_index;
assign applied_gain_index=enc_applied_gain_index ^ MASK_applied_gain_index;
localparam [3:0] MASK_settle=SETTLE_FRAMES;
reg [3:0] enc_settle;
assign settle=enc_settle ^ MASK_settle;
    localparam [27:0] LOW_SUM=FRAME_WORDS*256;
    localparam [27:0] HIGH_SUM=FRAME_WORDS*384;
    // Single-slot bundled-data mailbox. Payload is held until synchronized ACK.
    // Neither the sensor nor the streaming data path can be backpressured.
    reg [27:0] green_sum, held_sum;
    // Exact same 28-bit threshold results, published with the same mailbox
    // transaction. This moves only the comparison across the mailbox, not the
    // numerical policy, command cycle, payload statistics or ACK boundary.
    localparam MASK_held_dark=(28'd0<LOW_SUM);
    reg enc_held_dark, held_bright;
    wire held_dark=enc_held_dark ^ MASK_held_dark;
    reg [18:0] sample_count, clip_count, held_clip;
    reg active, row_odd, request_toggle;
    // RAW observation identity, not DDR committed video FID. First SOF is1.
    reg [31:0] raw_sequence,held_sequence;
    reg ack_toggle;
    (* async_reg="true" *) reg ack_meta, ack_sync;
    (* async_reg="true" *) reg req_meta, req_sync;
    (* async_reg="true" *) reg hold_meta, hold_sync;
    wire row_now=raw_sof ? 1'b0 : row_odd;
    wire [9:0] green=row_now ? raw_data[9:0] : raw_data[19:10];
    always @(posedge pixel_clk or negedge pixel_rst_n) begin
        if(!pixel_rst_n) begin
            green_sum<=0;sample_count<=0;clip_count<=0;active<=0;
            row_odd<=0;held_sum<=0;held_clip<=0;request_toggle<=0;
            enc_held_dark<=1'b0;held_bright<=(28'd0>HIGH_SUM);
            ack_meta<=0;ack_sync<=0;
            raw_sequence<=0;held_sequence<=0;
        end else begin
            ack_meta<=ack_toggle;ack_sync<=ack_meta;
            if(raw_sof) begin
                raw_sequence<=raw_sequence+1'b1;
                if(active && sample_count==FRAME_WORDS && request_toggle==ack_sync) begin
                    held_sum<=green_sum;held_clip<=clip_count;
                    enc_held_dark<=(green_sum<LOW_SUM) ^ MASK_held_dark;
                    held_bright<=(green_sum>HIGH_SUM);
                    held_sequence<=raw_sequence;
                    request_toggle<=~request_toggle;
                end
                active<=1;
                green_sum<=raw_valid ? {18'd0,green} : 28'd0;
                sample_count<=raw_valid ? 19'd1 : 19'd0;
                clip_count<=(raw_valid && green>=960) ? 19'd1 : 19'd0;
                row_odd<=raw_valid && raw_eol;
            end else if(active && raw_valid) begin
                // Saturate the count beyond a legal frame, so wrap cannot pass.
                if(sample_count<=FRAME_WORDS) sample_count<=sample_count+1'b1;
                if(sample_count<FRAME_WORDS) begin
                    green_sum<=green_sum+green;
                    if(green>=960)clip_count<=clip_count+1'b1;
                end
                if(raw_eol)row_odd<=~row_odd;
            end
        end
    end

    localparam [1:0] IDLE=0, WAIT_BUSY=1, WAIT_DONE=2, FAILED=3;
    reg [1:0] state;
    reg [23:0] timer_count;
    
    wire [15:0] exp_step=(exposure>>4)==0 ? 16'd1 : exposure>>4;
    wire [16:0] increased_exp={1'b0,exposure}+{1'b0,exp_step};
    wire [15:0] decreased_exp=exposure>exp_step+16'd4 ? exposure-exp_step : 16'd4;
    wire is_dark=held_dark;
    wire is_bright=held_bright;
    always @(posedge cfg_clk or negedge cfg_rst_n) begin
        if(!cfg_rst_n) begin
            req_meta<=0;req_sync<=0;ack_toggle<=0;ae_req<=0;hold_meta<=0;hold_sync<=0;
            enc_exposure <= (EXP_MAX) ^ MASK_exposure;enc_gain_index <= (16) ^ MASK_gain_index;
            // Initial values describe the immutable init table, not AE readback.
            enc_applied_exposure <= (EXP_MAX) ^ MASK_applied_exposure;enc_applied_gain_index <= (16) ^ MASK_applied_gain_index;
            fault<=0;applied_transactions<=0;state<=IDLE;timer_count<=0;
            measured_green_sum<=0;measured_clipped<=0;measurement_pulse<=0;
            measured_raw_sequence<=0;command_raw_sequence<=0;
            enc_settle <= (SETTLE_FRAMES) ^ MASK_settle;
        end else begin
            req_meta<=request_toggle;req_sync<=req_meta;hold_meta<=hold;hold_sync<=hold_meta;
            ae_req<=0;measurement_pulse<=0;
            if(req_sync!=ack_toggle) begin
                // Payload has already been stable for >=2 destination clocks.
                ack_toggle<=req_sync;
                measured_green_sum<=held_sum;measured_clipped<=held_clip;
                measured_raw_sequence<=held_sequence;
                measurement_pulse<=1;
                if(state==IDLE && cfg_done && ae_done && !cfg_error && !fault && !hold_sync) begin   // Z17: AE lock
                    if(settle!=0)enc_settle <= (settle-1'b1) ^ MASK_settle;
                    else if(is_dark && (exposure<EXP_MAX || gain_index<GAIN_MAX)) begin
                        if(exposure<EXP_MAX)
                            enc_exposure <= (increased_exp>EXP_MAX ? EXP_MAX : increased_exp[15:0]) ^ MASK_exposure;
                        else enc_gain_index <= (gain_index+2>GAIN_MAX ? GAIN_MAX : gain_index+2) ^ MASK_gain_index;
                        ae_req<=1;state<=WAIT_BUSY;
                        command_raw_sequence<=held_sequence;
                    end else if(is_bright && (gain_index>16 || exposure>4)) begin
                        if(gain_index>16)enc_gain_index <= (gain_index<18 ? 16 : gain_index-2) ^ MASK_gain_index;
                        else enc_exposure <= (decreased_exp) ^ MASK_exposure;
                        ae_req<=1;state<=WAIT_BUSY;
                        command_raw_sequence<=held_sequence;
                    end
                end
            end
            if(state==WAIT_BUSY || state==WAIT_DONE) begin
                // CLAUDE Z14 (upper board copy): no write timeout. It only raised the unconnected fault output and parked
                // the loop in FAILED; without it a write that never completes parks the loop in WAIT_* (no further command).
                if(state==WAIT_BUSY && !ae_done) begin
                    state<=WAIT_DONE;
                end else if(state==WAIT_DONE && ae_done) begin
                    // Successful full group write, not sensor readback confirmation.
                    enc_applied_exposure <= (exposure) ^ MASK_applied_exposure;enc_applied_gain_index <= (gain_index) ^ MASK_applied_gain_index;
                    applied_transactions<=applied_transactions+1'b1;
                    state<=IDLE;enc_settle <= (SETTLE_FRAMES) ^ MASK_settle;
                end
            end
            if(cfg_error) begin fault<=1;state<=FAILED;ae_req<=0;end
        end
    end
    // No queued commands or timeout retry. Reinitialization requires reset.
// synthesis translate_off
    initial begin
        if(FRAME_WORDS<1 || FRAME_WORDS>230400 || EXP_MAX<4 || EXP_MAX>1991 ||
           GAIN_MAX<16 || GAIN_MAX>176 || SETTLE_FRAMES<3 || SETTLE_FRAMES>15 ||
           TIMEOUT_CYCLES<2 || TIMEOUT_CYCLES>16777215)
            $fatal(1,"Unsupported SC520 AE bounds");
    end
// synthesis translate_on
endmodule
