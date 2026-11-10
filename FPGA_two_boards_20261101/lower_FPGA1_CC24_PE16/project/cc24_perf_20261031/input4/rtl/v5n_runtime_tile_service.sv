// Serialized, descriptor-driven tile transport service. It arbitrates one
// shared tensor-memory-adapter client between a real DDR reader and writer.
// Cache storage is deliberately external: sinks/sources may connect to the
// frozen Feature ERAM or parameter ERAM banks without changing DMA semantics.
module v5n_runtime_tile_service #(
    parameter integer ADDR_W = 32
) (
    input wire clk_i, input wire rst_ni,
    input wire read_start_i, input wire [ADDR_W-1:0] read_source_address_i,
    input wire [ADDR_W-1:0] read_byte_count_i,
    output wire read_ready_o, output wire read_busy_o, output reg read_done_o,
    output wire read_sink_valid_o, input wire read_sink_ready_i,
    output wire [ADDR_W-1:0] read_sink_offset_o, output wire signed [7:0] read_sink_data_o,
    output wire read_sink_last_o,
    input wire write_start_i, input wire [ADDR_W-1:0] write_destination_address_i,
    input wire [ADDR_W-1:0] write_byte_count_i,
    output wire write_ready_o, output wire write_busy_o, output reg write_done_o,
    input wire write_source_valid_i, output wire write_source_ready_o,
    input wire signed [7:0] write_source_data_i, input wire write_source_last_i,
    output wire error_o,
    output wire memory_valid_o, input wire memory_ready_i, output wire memory_write_o,
    output wire [ADDR_W-1:0] memory_raw_byte_address_o, output wire signed [7:0] memory_write_data_o,
    input wire memory_response_valid_i, output wire memory_response_ready_o,
    input wire memory_response_error_i, input wire memory_response_is_write_i,
    input wire signed [7:0] memory_read_data_i
);
    localparam [2:0] ST_IDLE = 3'd0, ST_START_READ = 3'd1, ST_READ = 3'd2,
                     ST_START_WRITE = 3'd3, ST_WRITE = 3'd4, ST_FAIL = 3'd5;
    reg [2:0] state_r; reg read_start_r, write_start_r, error_r;
    reg [ADDR_W-1:0] read_address_r, read_count_r, write_address_r, write_count_r;
    wire reader_busy_w, reader_done_w, reader_error_w, reader_memory_valid_w, reader_memory_ready_w;
    wire [ADDR_W-1:0] reader_memory_address_w, reader_sink_offset_w;
    wire reader_response_ready_w, reader_sink_valid_w, reader_sink_last_w;
    wire signed [7:0] reader_sink_data_w;
    wire writer_busy_w, writer_done_w, writer_error_w, writer_memory_valid_w, writer_memory_ready_w;
    wire writer_memory_write_w, writer_response_ready_w, writer_source_ready_w;
    wire [ADDR_W-1:0] writer_memory_address_w;
    wire signed [7:0] writer_memory_data_w;

    v5n_runtime_read_dma reader (
        .clk_i(clk_i), .rst_ni(rst_ni), .start_i(read_start_r), .source_byte_address_i(read_address_r), .byte_count_i(read_count_r),
        .busy_o(reader_busy_w), .done_o(reader_done_w), .error_o(reader_error_w),
        .memory_valid_o(reader_memory_valid_w), .memory_ready_i(reader_memory_ready_w), .memory_raw_byte_address_o(reader_memory_address_w),
        .memory_response_valid_i(memory_response_valid_i), .memory_response_ready_o(reader_response_ready_w), .memory_response_error_i(memory_response_error_i), .memory_read_data_i(memory_read_data_i),
        .sink_valid_o(reader_sink_valid_w), .sink_ready_i(read_sink_ready_i), .sink_offset_o(reader_sink_offset_w), .sink_data_o(reader_sink_data_w), .sink_last_o(reader_sink_last_w)
    );
    v5n_runtime_write_dma writer (
        .clk_i(clk_i), .rst_ni(rst_ni), .start_i(write_start_r), .destination_byte_address_i(write_address_r), .byte_count_i(write_count_r),
        .busy_o(writer_busy_w), .done_o(writer_done_w), .error_o(writer_error_w), .source_valid_i(write_source_valid_i), .source_ready_o(writer_source_ready_w), .source_data_i(write_source_data_i), .source_last_i(write_source_last_i),
        .memory_valid_o(writer_memory_valid_w), .memory_ready_i(writer_memory_ready_w), .memory_write_o(writer_memory_write_w), .memory_raw_byte_address_o(writer_memory_address_w), .memory_write_data_o(writer_memory_data_w),
        .memory_response_valid_i(memory_response_valid_i), .memory_response_ready_o(writer_response_ready_w), .memory_response_error_i(memory_response_error_i), .memory_response_is_write_i(memory_response_is_write_i)
    );
    assign read_ready_o = (state_r == ST_IDLE);
    assign write_ready_o = (state_r == ST_IDLE) && !read_start_i;
    assign read_busy_o = (state_r == ST_START_READ) || (state_r == ST_READ) || reader_busy_w;
    assign write_busy_o = (state_r == ST_START_WRITE) || (state_r == ST_WRITE) || writer_busy_w;
    assign error_o = error_r || (state_r == ST_FAIL);
    assign read_sink_valid_o = reader_sink_valid_w; assign read_sink_offset_o = reader_sink_offset_w;
    assign read_sink_data_o = reader_sink_data_w; assign read_sink_last_o = reader_sink_last_w;
    assign write_source_ready_o = writer_source_ready_w;
    assign memory_valid_o = (state_r == ST_READ) ? reader_memory_valid_w : ((state_r == ST_WRITE) ? writer_memory_valid_w : 1'b0);
    assign memory_write_o = (state_r == ST_WRITE) ? writer_memory_write_w : 1'b0;
    assign memory_raw_byte_address_o = (state_r == ST_READ) ? reader_memory_address_w : writer_memory_address_w;
    assign memory_write_data_o = writer_memory_data_w;
    assign reader_memory_ready_w = (state_r == ST_READ) ? memory_ready_i : 1'b0;
    assign writer_memory_ready_w = (state_r == ST_WRITE) ? memory_ready_i : 1'b0;
    assign memory_response_ready_o = (state_r == ST_READ) ? reader_response_ready_w : ((state_r == ST_WRITE) ? writer_response_ready_w : 1'b0);
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin state_r <= ST_IDLE; read_start_r <= 0; write_start_r <= 0; error_r <= 0; read_done_o <= 0; write_done_o <= 0; read_address_r <= 0; read_count_r <= 0; write_address_r <= 0; write_count_r <= 0; end
        else begin
            read_start_r <= 0; write_start_r <= 0; read_done_o <= 0; write_done_o <= 0;
            case (state_r)
                ST_IDLE: begin
                    error_r <= 0;
                    if (read_start_i) begin read_address_r <= read_source_address_i; read_count_r <= read_byte_count_i; state_r <= ST_START_READ; end
                    else if (write_start_i) begin write_address_r <= write_destination_address_i; write_count_r <= write_byte_count_i; state_r <= ST_START_WRITE; end
                end
                ST_START_READ: begin read_start_r <= 1'b1; state_r <= ST_READ; end
                ST_READ: if (reader_error_w) begin error_r <= 1'b1; state_r <= ST_FAIL; end else if (reader_done_w) begin read_done_o <= 1'b1; state_r <= ST_IDLE; end
                ST_START_WRITE: begin write_start_r <= 1'b1; state_r <= ST_WRITE; end
                ST_WRITE: if (writer_error_w) begin error_r <= 1'b1; state_r <= ST_FAIL; end else if (writer_done_w) begin write_done_o <= 1'b1; state_r <= ST_IDLE; end
                default: state_r <= ST_FAIL;
            endcase
        end
    end
endmodule
