// Shared physical-memory service for the fixed YOLOv8n deployment.
//
// There is exactly one DDR byte adapter below this module.  UDP/image ingress
// and every execution transfer (image, parameters, feature tensors and output
// tensors) are serialized onto that adapter.  Compute operators receive only
// the exec_* streaming interface, so they cannot become independent DDR
// masters.
module v5n_shared_feature_memory_service #(
    parameter integer ADDR_W = 32,
    parameter integer DATA_W = 128,
    parameter integer WORD_LSB_W = 4,
    parameter integer FIXED_SPLIT_VIEWS = 0,
    parameter integer WRITE_LINE_ENABLE = 0
) (
    input wire clk_i, input wire rst_ni,

    // Image ingress.  A caller must retain its byte until ingress_ready_o.
    input wire ingress_valid_i, output wire ingress_ready_o,
    input wire [ADDR_W-1:0] ingress_address_i, input wire signed [7:0] ingress_data_i,
    output reg ingress_error_o,

    // Per-byte request/response port used only through
    // v5n_operator_memory_bridge.  It is intentionally not a DDR port.
    input wire operator_memory_valid_i, output wire operator_memory_ready_o,
    input wire operator_memory_write_i, input wire [ADDR_W-1:0] operator_memory_address_i,
    input wire signed [7:0] operator_memory_write_data_i,
    input wire operator_memory_write_line_i,
    input wire [DATA_W-1:0] operator_memory_write_line_data_i,
    output wire operator_memory_response_valid_o, input wire operator_memory_response_ready_i,
    output wire operator_memory_response_error_o, output wire operator_memory_response_is_write_o,
    output wire signed [7:0] operator_memory_read_data_o,
    output wire operator_read_line_valid_o,
    output wire [ADDR_W-1:0] operator_read_line_address_o,
    output wire [DATA_W-1:0] operator_read_line_data_o,
    output wire operator_line_invalidate_o,

    // Sole execution-client transfer port.  Absolute addresses select image,
    // weights, bias, requant, LUT, feature or detection-memory regions.
    input wire read_start_i, input wire [ADDR_W-1:0] read_address_i, input wire [ADDR_W-1:0] read_count_i,
    output wire read_ready_o, output wire read_busy_o, output wire read_done_o,
    output wire read_data_valid_o, input wire read_data_ready_i,
    output wire [ADDR_W-1:0] read_data_offset_o, output wire signed [7:0] read_data_o, output wire read_data_last_o,
    input wire write_start_i, input wire [ADDR_W-1:0] write_address_i, input wire [ADDR_W-1:0] write_count_i,
    output wire write_ready_o, output wire write_busy_o, output wire write_done_o,
    input wire write_data_valid_i, output wire write_data_ready_o,
    input wire signed [7:0] write_data_i, input wire write_data_last_i,
    output wire exec_error_o,

    // The only external-memory port for this subsystem.
    output wire ddr_req_valid_o, input wire ddr_req_ready_i, output wire ddr_req_write_o,
    output wire [ADDR_W-WORD_LSB_W-1:0] ddr_req_word_address_o,
    output wire [DATA_W-1:0] ddr_req_write_data_o, output wire [DATA_W/8-1:0] ddr_req_write_strobe_o,
    input wire ddr_read_valid_i, output wire ddr_read_ready_o, input wire [DATA_W-1:0] ddr_read_data_i,
    output wire [1:0] debug_owner_o,output wire [1:0] debug_adapter_state_o
);
    localparam [1:0] OWNER_INGRESS = 2'd0, OWNER_OPERATOR = 2'd1, OWNER_EXEC = 2'd2;
    reg [1:0] owner_r;
    assign debug_owner_o=owner_r;
    wire exec_memory_valid_w, exec_memory_ready_w, exec_memory_write_w;
    wire [ADDR_W-1:0] exec_memory_address_w;
    wire signed [7:0] exec_memory_write_data_w;
    wire exec_response_valid_w, exec_response_ready_w, exec_response_error_w, exec_response_is_write_w;
    wire signed [7:0] exec_response_data_w;
    wire adapter_ready_w, adapter_response_valid_w, adapter_response_ready_w, adapter_response_error_w, adapter_response_write_w;
    wire signed [7:0] adapter_response_data_w;
    wire adapter_read_line_valid_w;
    assign operator_read_line_valid_o = adapter_read_line_valid_w && owner_r == OWNER_OPERATOR;
    // Any physical writer invalidates consumer-local read lines. In particular,
    // ingress/parameter upload cannot leave a stale line across frames.
    wire select_exec_w = !ingress_valid_i && !operator_memory_valid_i && exec_memory_valid_w;
    wire select_ingress_w = ingress_valid_i;
    wire select_operator_w = !ingress_valid_i && operator_memory_valid_i;
    wire adapter_valid_w = select_ingress_w || select_operator_w || select_exec_w;
    wire adapter_write_w = select_ingress_w ? 1'b1 : (select_operator_w ? operator_memory_write_i : exec_memory_write_w);
    assign operator_line_invalidate_o = adapter_valid_w && adapter_ready_w && adapter_write_w;
    wire [ADDR_W-1:0] adapter_address_w = select_ingress_w ? ingress_address_i : (select_operator_w ? operator_memory_address_i : exec_memory_address_w);
    wire signed [7:0] adapter_write_data_w = select_ingress_w ? ingress_data_i : (select_operator_w ? operator_memory_write_data_i : exec_memory_write_data_w);
    wire adapter_write_line_w=(WRITE_LINE_ENABLE!=0)&&select_operator_w&&operator_memory_write_line_i;

    assign ingress_ready_o = adapter_ready_w && select_ingress_w;
    assign operator_memory_ready_o = adapter_ready_w && select_operator_w;
    assign exec_memory_ready_w = adapter_ready_w && select_exec_w;
    assign operator_memory_response_valid_o = adapter_response_valid_w && owner_r == OWNER_OPERATOR;
    assign operator_memory_response_error_o = adapter_response_error_w;
    assign operator_memory_response_is_write_o = adapter_response_write_w;
    assign operator_memory_read_data_o = adapter_response_data_w;
    assign exec_response_valid_w = adapter_response_valid_w && owner_r == OWNER_EXEC;
    assign exec_response_error_w = adapter_response_error_w;
    assign exec_response_is_write_w = adapter_response_write_w;
    assign exec_response_data_w = adapter_response_data_w;
    // Ingress completion needs no upstream response channel; consume it here.
    assign adapter_response_ready_w = (owner_r == OWNER_EXEC) ? exec_response_ready_w :
                                      (owner_r == OWNER_OPERATOR) ? operator_memory_response_ready_i : adapter_response_valid_w;

    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin owner_r <= OWNER_INGRESS; ingress_error_o <= 1'b0; end
        else begin
            if (adapter_ready_w && adapter_valid_w)
                owner_r <= select_exec_w ? OWNER_EXEC : (select_operator_w ? OWNER_OPERATOR : OWNER_INGRESS);
            if (adapter_response_valid_w && adapter_response_ready_w) begin
                if (owner_r == OWNER_INGRESS && adapter_response_error_w) ingress_error_o <= 1'b1;
                owner_r <= OWNER_INGRESS;
            end
        end
    end

    v5n_runtime_tile_service #(.ADDR_W(ADDR_W)) transfer_service (
        .clk_i(clk_i), .rst_ni(rst_ni),
        .read_start_i(read_start_i), .read_source_address_i(read_address_i), .read_byte_count_i(read_count_i),
        .read_ready_o(read_ready_o), .read_busy_o(read_busy_o), .read_done_o(read_done_o),
        .read_sink_valid_o(read_data_valid_o), .read_sink_ready_i(read_data_ready_i), .read_sink_offset_o(read_data_offset_o), .read_sink_data_o(read_data_o), .read_sink_last_o(read_data_last_o),
        .write_start_i(write_start_i), .write_destination_address_i(write_address_i), .write_byte_count_i(write_count_i),
        .write_ready_o(write_ready_o), .write_busy_o(write_busy_o), .write_done_o(write_done_o),
        .write_source_valid_i(write_data_valid_i), .write_source_ready_o(write_data_ready_o), .write_source_data_i(write_data_i), .write_source_last_i(write_data_last_i),
        .error_o(exec_error_o), .memory_valid_o(exec_memory_valid_w), .memory_ready_i(exec_memory_ready_w), .memory_write_o(exec_memory_write_w),
        .memory_raw_byte_address_o(exec_memory_address_w), .memory_write_data_o(exec_memory_write_data_w),
        .memory_response_valid_i(exec_response_valid_w), .memory_response_ready_o(exec_response_ready_w), .memory_response_error_i(exec_response_error_w), .memory_response_is_write_i(exec_response_is_write_w), .memory_read_data_i(exec_response_data_w)
    );
    v5n_tensor_memory_adapter #(.ADDR_W(ADDR_W), .DATA_W(DATA_W), .WORD_LSB_W(WORD_LSB_W), .FIXED_SPLIT_VIEWS(FIXED_SPLIT_VIEWS),.WRITE_LINE_ENABLE(WRITE_LINE_ENABLE)) byte_adapter (
        .client_write_line_i(adapter_write_line_w),.client_write_line_data_i(operator_memory_write_line_data_i),
        .read_line_valid_o(adapter_read_line_valid_w),
        .read_line_byte_address_o(operator_read_line_address_o),
        .read_line_data_o(operator_read_line_data_o),
        .clk_i(clk_i), .rst_ni(rst_ni), .client_valid_i(adapter_valid_w), .client_ready_o(adapter_ready_w), .client_write_i(adapter_write_w), .client_use_hwc_i(1'b0),
        .client_raw_byte_address_i(adapter_address_w), .client_tensor_base_i({ADDR_W{1'b0}}), .client_tensor_height_i(10'd0), .client_tensor_width_i(10'd0), .client_tensor_channels_i(10'd0), .client_y_i(10'd0), .client_x_i(10'd0), .client_channel_i(10'd0), .client_write_data_i(adapter_write_data_w),
        .client_response_valid_o(adapter_response_valid_w), .client_response_ready_i(adapter_response_ready_w), .client_response_is_write_o(adapter_response_write_w), .client_response_error_o(adapter_response_error_w), .client_read_data_o(adapter_response_data_w),
        .ddr_req_valid_o(ddr_req_valid_o), .ddr_req_ready_i(ddr_req_ready_i), .ddr_req_write_o(ddr_req_write_o), .ddr_req_word_address_o(ddr_req_word_address_o), .ddr_req_write_data_o(ddr_req_write_data_o), .ddr_req_write_strobe_o(ddr_req_write_strobe_o), .ddr_read_valid_i(ddr_read_valid_i), .ddr_read_ready_o(ddr_read_ready_o), .ddr_read_data_i(ddr_read_data_i),.state_o(debug_adapter_state_o)
    );
endmodule
