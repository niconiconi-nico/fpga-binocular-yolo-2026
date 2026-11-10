// Independent, not connected to production. Readiness is not FIFO-empty:
// every accepted ingress request must have its real adapter completion.
// Result completion is supplied ONLY after graph/NMS/final-record physical ACK.
// This module does not arbitrate input buffers or make multi-frame FPS claims.
module v5n_ai_frame_commit_fence #(
    parameter integer ADDR_W=32
) (
    input wire clk_i, input wire rst_ni,
    input wire ingress_accept_i, input wire ingress_commit_i,
    input wire ingress_error_i, input wire ingress_empty_i,
    input wire frame_complete_i, input wire [31:0] frame_id_i,
    input wire [ADDR_W-1:0] frame_base_i,
    input wire parameters_ready_i, input wire ai_accept_ready_i,
    input wire graph_done_i, input wire graph_error_i,
    input wire nms_done_i, input wire result_committed_i,
    output wire frame_ready_o, output wire ai_start_o,
    output reg ai_owned_o, output reg ai_result_ready_o,
    output reg protocol_error_o,
    output reg [31:0] ai_frame_id_o, result_frame_id_o,
    output reg [ADDR_W-1:0] ai_frame_base_o,
    output reg [63:0] ai_start_tick_o, ai_result_tick_o,
    output reg [63:0] ai_latency_cycles_o
);
    reg ingress_pending_r, frame_pending_r;
    reg [31:0] pending_frame_id_r;
    reg [ADDR_W-1:0] pending_frame_base_r;
    reg [63:0] tick_r;
    // Single-outstanding adapter contract; completion is not DDR request-ready.
    assign frame_ready_o=frame_pending_r && ingress_empty_i &&
        !ingress_pending_r && !ingress_accept_i && !ingress_error_i &&
        parameters_ready_i && !ai_owned_o && !protocol_error_o;
    assign ai_start_o=frame_ready_o && ai_accept_ready_i;
    always @(posedge clk_i or negedge rst_ni) begin
        if(!rst_ni) begin
            ingress_pending_r<=0; frame_pending_r<=0; tick_r<=0;
            pending_frame_id_r<=0; pending_frame_base_r<=0;
            ai_owned_o<=0; ai_result_ready_o<=0; protocol_error_o<=0;
            ai_frame_id_o<=0; result_frame_id_o<=0; ai_frame_base_o<=0;
            ai_start_tick_o<=0; ai_result_tick_o<=0; ai_latency_cycles_o<=0;
        end else begin
            tick_r<=tick_r+1'b1; ai_result_ready_o<=0;
            case({ingress_accept_i,ingress_commit_i})
                2'b10: begin
                    if(ingress_pending_r) protocol_error_o<=1;
                    ingress_pending_r<=1;
                end
                2'b01: begin
                    if(!ingress_pending_r) protocol_error_o<=1;
                    ingress_pending_r<=0;
                end
                2'b11: begin
                    // A retiring old request may be replaced in this clock.
                    if(!ingress_pending_r) protocol_error_o<=1;
                    ingress_pending_r<=1;
                end
                default: begin end
            endcase
            if(frame_complete_i) begin
                if(ai_owned_o || frame_pending_r) protocol_error_o<=1;
                else begin
                    frame_pending_r<=1;
                    pending_frame_id_r<=frame_id_i;
                    pending_frame_base_r<=frame_base_i;
                end
            end
            if(ai_start_o) begin
                frame_pending_r<=0; ai_owned_o<=1;
                ai_frame_id_o<=pending_frame_id_r;
                ai_frame_base_o<=pending_frame_base_r;
                ai_start_tick_o<=tick_r;
            end
            if(graph_error_i && ai_owned_o) begin
                ai_owned_o<=0; protocol_error_o<=1;
            end
            if(graph_done_i) begin
                if(!ai_owned_o || !nms_done_i || !result_committed_i ||
                   ingress_pending_r || ingress_error_i || protocol_error_o)
                    protocol_error_o<=1;
                else begin
                    ai_result_ready_o<=1;
                    result_frame_id_o<=ai_frame_id_o;
                    ai_result_tick_o<=tick_r;
                    ai_latency_cycles_o<=tick_r-ai_start_tick_o;
                end
                ai_owned_o<=0;
            end
        end
    end
endmodule
