// A2 v5 PROTOTYPE: 25200 position-major multi-label candidates, strict IoU0.6.
// Input order defines stable equal-score tie order. No model/score alteration.
// Class-aware stable integer-only NMS engine.
//
// Candidate order is class-major then position-major. Score ordering and the
// exact strict Q16 IoU test (intersection*10 > union*7) are unchanged. The
// suppress path is explicitly pipelined as capture -> geometry -> areas ->
// compare, replacing its former cross-module 19-level combinational path.
module v5n_integer_nms_context #(
    parameter integer MAX_CANDIDATES = 25200,
    parameter integer INDEX_W = 15,
    parameter integer MAX_DETECTIONS = 300
) (
    input wire clk_i, input wire rst_ni, input wire start_i,
    output wire ready_o, output reg busy_o, output reg complete_o,
    input wire [INDEX_W-1:0] candidate_count_i,
    input wire [15:0] score_threshold_q15_i,
    input wire [8:0] max_detections_i,
    output wire [INDEX_W-1:0] candidate_index_o,
    output wire candidate_request_o,
    input wire candidate_valid_i,
    input wire [15:0] candidate_score_q15_i,
    input wire [1:0] candidate_class_i,
    input wire signed [4*32-1:0] candidate_box_q16_i,
    output reg selected_valid_o,
    output reg signed [4*32-1:0] selected_box_q16_o,
    output reg [15:0] selected_score_q15_o,
    output reg [1:0] selected_class_o,
    output reg [INDEX_W-1:0] selected_candidate_index_o,
    output reg [8:0] selected_count_o,
    output wire context_req_valid,input wire context_req_ready,
    output wire[2:0]context_mode,output wire[511:0]context_words,
    input wire context_rsp_valid,output wire context_rsp_ready,
    input wire[31:0]context_rsp_data,input wire[2:0]context_rsp_index,
    input wire context_rsp_last,context_rsp_error,output reg arithmetic_error_o

);
    localparam [2:0] ST_IDLE          = 3'd0;
    localparam [2:0] ST_CLEAR         = 3'd1;
    localparam [2:0] ST_FIND          = 3'd2;
    localparam [2:0] ST_EMIT          = 3'd3;
    localparam [3:0] ST_SUPPRESS_LOAD = 4'd4;
    localparam [3:0] ST_SUPPRESS_GEOM = 4'd5;
    localparam [3:0] ST_SUPPRESS_AREA_I = 4'd6;
    localparam [3:0] ST_SUPPRESS_AREA_C = 4'd7;
    localparam [3:0] ST_SUPPRESS_AREA_S = 4'd8;
    localparam [3:0] ST_SUPPRESS_CMP    = 4'd9;
    localparam [3:0] ST_SUPPRESS_WRITE  = 4'd10;
    // PH1P ERAM has a synchronous array read even in NOREG mode.  Prime the
    // best-index byte for one cycle before ST_EMIT performs its read/modify/
    // write; otherwise the last scan byte is written at the best-index
    // address and previously selected/suppressed flags are lost.
    localparam [3:0] ST_EMIT_PRIME      = 4'd11;
    localparam [3:0] ST_FIND_PRIME      = 4'd12;

    reg [3:0] state_r;
    reg [INDEX_W-1:0] scan_index_r;
    reg [11:0] clear_index_r;
    reg best_valid_r;
    reg [INDEX_W-1:0] best_index_r;
    reg [15:0] best_score_r;
    reg [1:0] best_class_r, selected_class_r, candidate_class_r;
    reg signed [4*32-1:0] best_box_r, selected_box_r, candidate_box_r;

    reg candidate_eligible_r, candidate_better_r, suppress_current_r, suppress_decision_r;
    assign context_req_valid=state_r==ST_SUPPRESS_GEOM;
    assign context_mode=3'd4;
    assign context_words={256'd0,selected_box_r,candidate_box_r};
    assign context_rsp_ready=state_r==ST_SUPPRESS_AREA_I;

    // Store eight suppression flags per byte in one ERAM.  The former
    // bit-addressed register array synthesized as an 8400:1 distributed-RAM
    // mux and was the dominant placement/fanout failure.  Both ports are
    // NOREG: port A supplies the current byte and port B performs either the
    // initial clear or an atomic set-bit update.  NMS ordering and predicates
    // are unchanged; only the physical storage implementation changes.
    wire [11:0] suppression_read_addr_w =
        ((state_r == ST_EMIT_PRIME) || (state_r == ST_EMIT)) ?
        (best_index_r >> 3) : (scan_index_r >> 3);
    wire [7:0] suppression_read_data_w;
    wire [2:0] suppression_read_bit_w =
        (state_r == ST_EMIT) ? best_index_r[2:0] : scan_index_r[2:0];
    wire suppression_flag_w = suppression_read_data_w[suppression_read_bit_w];
    wire suppression_clear_w = (state_r == ST_CLEAR);
    wire suppression_set_w = (state_r == ST_EMIT) ||
                             ((state_r == ST_SUPPRESS_WRITE) && suppress_decision_r);
    wire suppression_write_w = suppression_clear_w || suppression_set_w;
    wire [11:0] suppression_write_addr_w = suppression_clear_w ? clear_index_r : suppression_read_addr_w;
    wire [7:0] suppression_write_data_w = suppression_clear_w ? 8'd0 :
        (suppression_read_data_w | (8'b1 << suppression_read_bit_w));

    PH1P_LOGIC_ERAM #(
        .DATA_WIDTH_A(8), .DATA_WIDTH_B(8), .ADDR_WIDTH_A(12), .ADDR_WIDTH_B(12),
        .DATA_DEPTH_A((MAX_CANDIDATES+7)/8), .DATA_DEPTH_B((MAX_CANDIDATES+7)/8), .MODE("DP"),
        .REGMODE_A("NOREG"), .REGMODE_B("NOREG"),
        .WRITEMODE_A("READBEFOREWRITE"), .WRITEMODE_B("READBEFOREWRITE"),
        .CLKMODE("ASYNC"), .SSROVERCE("DISABLE"),
        .OREGSET_A("RESET"), .OREGSET_B("RESET"),
        .RESETMODE_A("ASYNC"), .RESETMODE_B("ASYNC"),
        .ASYNC_RESET_RELEASE_A("ASYNC"), .ASYNC_RESET_RELEASE_B("ASYNC"),
        .ECC_ENCODE("DISABLE"), .ECC_DECODE("DISABLE"),
        .IMPLEMENT("20K(FAST)"), .INIT_FILE("NONE"), .FILL_ALL("NONE")
    ) suppression_bitmap (
        .dia(8'd0), .addra(suppression_read_addr_w), .cea(1'b1), .ocea(1'b0),
        .clka(clk_i), .wea(1'b0), .rsta(1'b0), .bea(1'b0),
        .dib(suppression_write_data_w), .addrb(suppression_write_addr_w),
        .ceb(1'b1), .oceb(1'b0), .clkb(clk_i), .web(suppression_write_w),
        .rstb(1'b0), .beb(1'b0), .ecc_sbiterrinj(1'b0), .ecc_dbiterrinj(1'b0),
        .doa(suppression_read_data_w), .dob(), .ecc_sbiterr(), .ecc_dbiterr()
    );

    assign ready_o = !busy_o;
    assign candidate_index_o = scan_index_r;
    assign candidate_request_o = (state_r == ST_FIND) || (state_r == ST_SUPPRESS_LOAD);

    always @* begin
        candidate_eligible_r = (scan_index_r < candidate_count_i) && !suppression_flag_w &&
                               (candidate_score_q15_i >= score_threshold_q15_i);
        candidate_better_r = candidate_eligible_r && (!best_valid_r || candidate_score_q15_i > best_score_r);


    end

    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            state_r <= ST_IDLE;
            busy_o <= 0; complete_o <= 0; selected_valid_o <= 0;
            selected_box_q16_o <= 0; selected_score_q15_o <= 0; selected_class_o <= 0;
            selected_candidate_index_o <= 0; selected_count_o <= 0;
            scan_index_r <= 0; clear_index_r <= 0; best_valid_r <= 0;
            best_index_r <= 0; best_score_r <= 0; best_class_r <= 0; best_box_r <= 0;
            selected_class_r <= 0; selected_box_r <= 0; candidate_class_r <= 0; candidate_box_r <= 0;
            suppress_decision_r <= 0;
            arithmetic_error_o<=0;
        end else begin
            complete_o <= 0;
            selected_valid_o <= 0;
            case (state_r)
                ST_IDLE: begin
                    busy_o <= 0;
                    if (start_i) begin
                        selected_count_o <= 0;
                        if (candidate_count_i == 0 || candidate_count_i > MAX_CANDIDATES || max_detections_i == 0)
                            complete_o <= 1;
                        else begin
                            busy_o <= 1;
                            selected_count_o <= 0;
                            clear_index_r <= 0;
                            state_r <= ST_CLEAR;
                        end
                    end
                end
                ST_CLEAR: begin
                    if (clear_index_r + 1'b1 >= ((candidate_count_i + 3'd7) >> 3)) begin
                        scan_index_r <= 0;
                        best_valid_r <= 0;
                        state_r <= ST_FIND_PRIME;
                    end else clear_index_r <= clear_index_r + 1'b1;
                end
                ST_FIND_PRIME: begin
                    state_r <= ST_FIND;
                end
                ST_FIND: begin
                  if (candidate_valid_i) begin
                    if (candidate_better_r) begin
                        best_valid_r <= 1;
                        best_index_r <= scan_index_r;
                        best_score_r <= candidate_score_q15_i;
                        best_class_r <= candidate_class_i;
                        best_box_r <= candidate_box_q16_i;
                    end
                    if (scan_index_r + 1'b1 >= candidate_count_i) begin
                        if (candidate_better_r || best_valid_r) begin
                            if (candidate_better_r) begin
                                best_index_r <= scan_index_r;
                                best_score_r <= candidate_score_q15_i;
                                best_class_r <= candidate_class_i;
                                best_box_r <= candidate_box_q16_i;
                            end
                            state_r <= ST_EMIT_PRIME;
                        end else begin
                            busy_o <= 0;
                            complete_o <= 1;
                            state_r <= ST_IDLE;
                        end
                    end else begin
                        scan_index_r <= scan_index_r + 1'b1;
                        state_r <= ST_FIND_PRIME;
                    end
                  end
                end
                ST_EMIT_PRIME: begin
                    state_r <= ST_EMIT;
                end
                ST_EMIT: begin
                    selected_valid_o <= 1;
                    selected_box_q16_o <= best_box_r;
                    selected_score_q15_o <= best_score_r;
                    selected_class_o <= best_class_r;
                    selected_candidate_index_o <= best_index_r;
                    selected_class_r <= best_class_r;
                    selected_box_r <= best_box_r;
                    selected_count_o <= selected_count_o + 1'b1;
                    if (selected_count_o + 1'b1 >= max_detections_i) begin
                        busy_o <= 0;
                        complete_o <= 1;
                        state_r <= ST_IDLE;
                    end else begin
                        scan_index_r <= 0;
                        state_r <= ST_SUPPRESS_LOAD;
                    end
                end
                ST_SUPPRESS_LOAD: begin
                    if (candidate_valid_i) begin
                        candidate_class_r <= candidate_class_i;
                        candidate_box_r <= candidate_box_q16_i;
                        state_r <= ST_SUPPRESS_GEOM;
                    end
                end
                ST_SUPPRESS_GEOM:if(context_req_ready)state_r<=ST_SUPPRESS_AREA_I;
                ST_SUPPRESS_AREA_I:if(context_rsp_valid)begin
                  if(context_rsp_error||!context_rsp_last||context_rsp_index!=0)begin
                    arithmetic_error_o<=1;busy_o<=0;complete_o<=1;state_r<=ST_IDLE;
                  end else begin
                    suppress_decision_r<=(candidate_class_r==selected_class_r)&&context_rsp_data[0];
                    state_r<=ST_SUPPRESS_CMP;
                  end
                end
                ST_SUPPRESS_CMP:state_r<=ST_SUPPRESS_WRITE;
                ST_SUPPRESS_WRITE: begin
                    if (scan_index_r + 1'b1 >= candidate_count_i) begin
                        scan_index_r <= 0;
                        best_valid_r <= 0;
                        best_score_r <= 0;
                        state_r <= ST_FIND_PRIME;
                    end else begin
                        scan_index_r <= scan_index_r + 1'b1;
                        state_r <= ST_SUPPRESS_LOAD;
                    end
                end
                default: state_r <= ST_IDLE;
            endcase
        end
    end
endmodule
