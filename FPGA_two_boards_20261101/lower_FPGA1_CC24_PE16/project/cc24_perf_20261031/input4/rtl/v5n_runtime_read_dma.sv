// One-byte-at-a-time external-memory reader for runtime parameter/tile loads.
// Every byte returned to the sink is obtained through the real memory-client
// request/response handshake; completion is impossible without all responses.
module v5n_runtime_read_dma #(
    parameter integer ADDR_W = 32
) (
    input wire clk_i, input wire rst_ni,
    input wire start_i, input wire [ADDR_W-1:0] source_byte_address_i,
    input wire [ADDR_W-1:0] byte_count_i,
    output wire busy_o, output reg done_o, output reg error_o,
    output wire memory_valid_o, input wire memory_ready_i,
    output wire [ADDR_W-1:0] memory_raw_byte_address_o,
    input wire memory_response_valid_i, output wire memory_response_ready_o,
    input wire memory_response_error_i, input wire signed [7:0] memory_read_data_i,
    output wire sink_valid_o, input wire sink_ready_i,
    output wire [ADDR_W-1:0] sink_offset_o, output wire signed [7:0] sink_data_o,
    output wire sink_last_o
);
    localparam [1:0] ST_IDLE = 2'd0, ST_ISSUE = 2'd1, ST_WAIT = 2'd2, ST_SINK = 2'd3;
    reg [1:0] state_r; reg [ADDR_W-1:0] address_r, remaining_r, offset_r;
    reg signed [7:0] data_r;
    assign busy_o = (state_r != ST_IDLE);
    assign memory_valid_o = (state_r == ST_ISSUE);
    assign memory_raw_byte_address_o = address_r;
    assign memory_response_ready_o = (state_r == ST_WAIT);
    assign sink_valid_o = (state_r == ST_SINK);
    assign sink_offset_o = offset_r;
    assign sink_data_o = data_r;
    assign sink_last_o = (remaining_r == 1);
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            state_r <= ST_IDLE; address_r <= 0; remaining_r <= 0; offset_r <= 0; data_r <= 0; done_o <= 0; error_o <= 0;
        end else begin
            done_o <= 1'b0;
            case (state_r)
                ST_IDLE: if (start_i) begin
                    error_o <= 1'b0; address_r <= source_byte_address_i; remaining_r <= byte_count_i; offset_r <= 0;
                    if (byte_count_i == 0) done_o <= 1'b1; else state_r <= ST_ISSUE;
                end
                ST_ISSUE: if (memory_ready_i) state_r <= ST_WAIT;
                ST_WAIT: if (memory_response_valid_i) begin
                    if (memory_response_error_i) begin error_o <= 1'b1; state_r <= ST_IDLE; end
                    else begin data_r <= memory_read_data_i; state_r <= ST_SINK; end
                end
                ST_SINK: if (sink_ready_i) begin
                    if (remaining_r == 1) begin done_o <= 1'b1; state_r <= ST_IDLE; end
                    else begin address_r <= address_r + 1'b1; offset_r <= offset_r + 1'b1; remaining_r <= remaining_r - 1'b1; state_r <= ST_ISSUE; end
                end
                default: state_r <= ST_IDLE;
            endcase
        end
    end
endmodule
