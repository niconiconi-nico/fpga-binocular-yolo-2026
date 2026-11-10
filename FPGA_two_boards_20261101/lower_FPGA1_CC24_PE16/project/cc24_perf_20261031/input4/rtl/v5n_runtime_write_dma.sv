// One-byte-at-a-time external-memory writer for runtime output-tile drains.
// Completion follows accepted DDR write responses, never a transfer counter
// alone. The producer holds a byte until source_ready_o is asserted.
module v5n_runtime_write_dma #(
    parameter integer ADDR_W = 32
) (
    input wire clk_i, input wire rst_ni,
    input wire start_i, input wire [ADDR_W-1:0] destination_byte_address_i,
    input wire [ADDR_W-1:0] byte_count_i,
    output wire busy_o, output reg done_o, output reg error_o,
    input wire source_valid_i, output wire source_ready_o,
    input wire signed [7:0] source_data_i, input wire source_last_i,
    output wire memory_valid_o, input wire memory_ready_i,
    output wire memory_write_o, output wire [ADDR_W-1:0] memory_raw_byte_address_o,
    output wire signed [7:0] memory_write_data_o,
    input wire memory_response_valid_i, output wire memory_response_ready_o,
    input wire memory_response_error_i, input wire memory_response_is_write_i
);
    localparam [1:0] ST_IDLE = 2'd0, ST_SOURCE = 2'd1, ST_ISSUE = 2'd2, ST_WAIT = 2'd3;
    reg [1:0] state_r;
    reg [ADDR_W-1:0] address_r, remaining_r;
    reg signed [7:0] data_r;
    reg last_r;
    assign busy_o = (state_r != ST_IDLE);
    assign source_ready_o = (state_r == ST_SOURCE);
    assign memory_valid_o = (state_r == ST_ISSUE);
    assign memory_write_o = 1'b1;
    assign memory_raw_byte_address_o = address_r;
    assign memory_write_data_o = data_r;
    assign memory_response_ready_o = (state_r == ST_WAIT);
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            state_r <= ST_IDLE; address_r <= 0; remaining_r <= 0; data_r <= 0; last_r <= 0; done_o <= 0; error_o <= 0;
        end else begin
            done_o <= 1'b0;
            case (state_r)
                ST_IDLE: if (start_i) begin
                    error_o <= 1'b0; address_r <= destination_byte_address_i; remaining_r <= byte_count_i;
                    if (byte_count_i == 0) done_o <= 1'b1; else state_r <= ST_SOURCE;
                end
                ST_SOURCE: if (source_valid_i) begin
                    data_r <= source_data_i; last_r <= source_last_i; state_r <= ST_ISSUE;
                end
                ST_ISSUE: if (memory_ready_i) state_r <= ST_WAIT;
                ST_WAIT: if (memory_response_valid_i) begin
                    if (memory_response_error_i || !memory_response_is_write_i || (last_r != (remaining_r == 1))) begin
                        error_o <= 1'b1; state_r <= ST_IDLE;
                    end else if (remaining_r == 1) begin
                        done_o <= 1'b1; state_r <= ST_IDLE;
                    end else begin
                        address_r <= address_r + 1'b1; remaining_r <= remaining_r - 1'b1; state_r <= ST_SOURCE;
                    end
                end
                default: state_r <= ST_IDLE;
            endcase
        end
    end
endmodule
