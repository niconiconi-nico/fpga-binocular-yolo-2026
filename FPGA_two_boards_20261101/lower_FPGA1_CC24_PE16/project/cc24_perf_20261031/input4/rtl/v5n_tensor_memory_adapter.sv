// External DDR/SDRAM byte adapter for the independent real YOLOv8n graph.
//
// Feature tensors use byte-addressed signed INT8 HWC storage:
//   byte_address = tensor_base + ((y * tensor_width + x) * tensor_channels + c)
// Parameters and descriptor-related blobs use the same client port with
// client_use_hwc_i deasserted and client_raw_byte_address_i supplied directly.
//
// The external memory side is wide-line addressed.  A write uses exactly one
// byte strobe.  Reads retain the complete returned line, so later byte clients
// hitting the same line are answered locally without another external command.
// With DATA_W=128 this turns one PH1P DDR transaction into as many as sixteen
// sequential HWC bytes while preserving the scalar client ABI.
//
// Contract: DATA_W / 8 must be 2**WORD_LSB_W and external words are little
// endian (lane zero occupies data[7:0]).  There is deliberately no inferred
// full-frame RAM here: feature-map residency remains external DDR/SDRAM and
// tile caches are separate RTL blocks.
module v5n_tensor_memory_adapter #(
    parameter integer ADDR_W = 32,
    parameter integer SHAPE_W = 10,
    parameter integer DATA_W = 32,
    parameter integer WORD_LSB_W = 2,
    parameter integer FIXED_SPLIT_VIEWS = 0,
    parameter integer WRITE_LINE_ENABLE = 0
) (
    input  wire                                clk_i,
    input  wire                                rst_ni,

    // One generic tile/parameter client.  Hold valid until ready is observed.
    input  wire                                client_valid_i,
    output wire                                client_ready_o,
    input  wire                                client_write_i,
    input  wire                                client_use_hwc_i,
    input  wire [ADDR_W-1:0]                   client_raw_byte_address_i,
    input  wire [ADDR_W-1:0]                   client_tensor_base_i,
    input  wire [SHAPE_W-1:0]                  client_tensor_height_i,
    input  wire [SHAPE_W-1:0]                  client_tensor_width_i,
    input  wire [SHAPE_W-1:0]                  client_tensor_channels_i,
    input  wire [SHAPE_W-1:0]                  client_y_i,
    input  wire [SHAPE_W-1:0]                  client_x_i,
    input  wire [SHAPE_W-1:0]                  client_channel_i,
    input  wire signed [7:0]                   client_write_data_i,
    input wire client_write_line_i,
    input wire [DATA_W-1:0] client_write_line_data_i,
    output reg                                 client_response_valid_o,
    input  wire                                client_response_ready_i,
    output reg                                 client_response_is_write_o,
    output reg                                 client_response_error_o,
    output reg signed [7:0]                    client_read_data_o,

    // Word-addressed external DDR/SDRAM command and read-response interface.
    output wire                                ddr_req_valid_o,
    input  wire                                ddr_req_ready_i,
    output wire                                ddr_req_write_o,
    output wire [ADDR_W-WORD_LSB_W-1:0]        ddr_req_word_address_o,
    output reg  [DATA_W-1:0]                   ddr_req_write_data_o,
    output reg  [DATA_W/8-1:0]                 ddr_req_write_strobe_o,
    input  wire                                ddr_read_valid_i,
    output wire                                ddr_read_ready_o,
    input  wire [DATA_W-1:0]                   ddr_read_data_i,
    output wire [1:0]                          state_o,
    // Qualified physical read-line sideband, not a second DDR master.
    output wire read_line_valid_o,
    output wire [ADDR_W-1:0] read_line_byte_address_o,
    output wire [DATA_W-1:0] read_line_data_o
);
    localparam integer BYTE_LANES = DATA_W / 8;
    localparam [1:0] ST_IDLE = 2'd0;
    localparam [1:0] ST_ISSUE = 2'd1;
    localparam [1:0] ST_WAIT_READ = 2'd2;
    localparam [1:0] ST_RESPONSE = 2'd3;

    localparam [2:0] ST_VIEW_RESOLVE=3'd4, ST_VIEW_LOOKUP=3'd5;
    reg [2:0] state_r;
    assign state_o=state_r[1:0];
    wire view_hit_w;
    reg [ADDR_W-1:0] client_byte_address_r;
    wire [ADDR_W-1:0] view_logical_base_w,view_physical_base_w;
    wire [7:0] view_mask_w;
    reg [ADDR_W-1:0] view_offset_r,view_base_r;
    reg [7:0] view_mask_r;
    wire [ADDR_W-1:0] view_mask_extended_w={{(ADDR_W-8){1'b0}},view_mask_r};
    wire [ADDR_W-1:0] view_address_w=view_base_r+
        ((view_offset_r & ~view_mask_extended_w)<<1)+(view_offset_r & view_mask_extended_w);
    generate if (FIXED_SPLIT_VIEWS) begin: g_view_map
      v5n_split_view_map #(.ADDR_W(ADDR_W)) map (
        .logical_address_i(client_byte_address_r),.hit_o(view_hit_w),
        .logical_base_o(view_logical_base_w),.physical_base_o(view_physical_base_w),
        .channel_mask_o(view_mask_w));
    end else begin: g_no_view_map
      assign view_hit_w=0;
      assign view_logical_base_w=0;
      assign view_physical_base_w=0;
      assign view_mask_w=0;
    end endgenerate
    reg                            request_write_r;
    reg [ADDR_W-1:0]               request_byte_address_r;
    reg [WORD_LSB_W-1:0]           request_byte_lane_r;
    reg signed [7:0]               request_write_data_r;
    reg request_write_line_r;
    reg [DATA_W-1:0] request_write_line_data_r;
    wire client_write_line_w=(WRITE_LINE_ENABLE!=0)&&client_write_line_i;
    wire client_line_error_w=client_write_line_w&&
        (!client_write_i||DATA_W!=128||WORD_LSB_W!=4||
         client_byte_address_r[WORD_LSB_W-1:0]!=0);
    reg [DATA_W-1:0]               read_line_r;
    reg [ADDR_W-WORD_LSB_W-1:0]    read_line_tag_r;
    reg                            read_line_valid_r;
    assign read_line_valid_o = client_response_valid_o &&
        !client_response_is_write_o && !client_response_error_o &&
        read_line_valid_r &&
        read_line_tag_r == request_byte_address_r[ADDR_W-1:WORD_LSB_W];
    assign read_line_byte_address_o = request_byte_address_r;
    assign read_line_data_o = read_line_r;

    reg [ADDR_W-1:0] y_wide_r;
    reg [ADDR_W-1:0] x_wide_r;
    reg [ADDR_W-1:0] channel_wide_r;
    reg [ADDR_W-1:0] width_wide_r;
    reg [ADDR_W-1:0] channels_wide_r;
    wire client_hwc_in_bounds_w;

    assign client_hwc_in_bounds_w =
        (client_y_i < client_tensor_height_i) &&
        (client_x_i < client_tensor_width_i) &&
        (client_channel_i < client_tensor_channels_i);
    wire [ADDR_W-WORD_LSB_W-1:0] client_line_address_w =
        client_byte_address_r[ADDR_W-1:WORD_LSB_W];
    wire client_read_line_hit_w = read_line_valid_r &&
        (read_line_tag_r == client_line_address_w);

    // All operands are widened before the multiplies so a 320x320x1024 HWC
    // location is represented without a 10-bit intermediate overflow.
    always @* begin
        y_wide_r = client_y_i;
        x_wide_r = client_x_i;
        channel_wide_r = client_channel_i;
        width_wide_r = client_tensor_width_i;
        channels_wide_r = client_tensor_channels_i;
        if (client_use_hwc_i)
            client_byte_address_r = client_tensor_base_i +
                (((y_wide_r * width_wide_r) + x_wide_r) * channels_wide_r) +
                channel_wide_r;
        else
            client_byte_address_r = client_raw_byte_address_i;
    end

    assign client_ready_o = (state_r == ST_IDLE) && !client_response_valid_o;
    assign ddr_req_valid_o = (state_r == ST_ISSUE);
    assign ddr_req_write_o = request_write_r;
    assign ddr_req_word_address_o = request_byte_address_r[ADDR_W-1:WORD_LSB_W];
    assign ddr_read_ready_o = (state_r == ST_WAIT_READ) && !client_response_valid_o;

    // The byte lane is registered with its request, so all external command
    // signals stay stable while ddr_req_valid_o waits for ddr_req_ready_i.
    always @* begin
        ddr_req_write_data_o = {DATA_W{1'b0}};
        ddr_req_write_strobe_o = {BYTE_LANES{1'b0}};
        if (request_write_r) begin
            if(request_write_line_r)begin
                ddr_req_write_data_o=request_write_line_data_r;
                ddr_req_write_strobe_o={BYTE_LANES{1'b1}};
            end else begin
                ddr_req_write_data_o[request_byte_lane_r*8 +: 8] = request_write_data_r;
                ddr_req_write_strobe_o[request_byte_lane_r] = 1'b1;
            end
        end
    end

    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            state_r <= ST_IDLE;
            view_offset_r<=0;view_base_r<=0;view_mask_r<=0;
            request_write_r <= 1'b0;
            request_byte_address_r <= 0;
            request_byte_lane_r <= 0;
            request_write_data_r <= 0;
            request_write_line_r<=0;request_write_line_data_r<=0;
            read_line_r <= 0;
            read_line_tag_r <= 0;
            read_line_valid_r <= 1'b0;
            client_response_valid_o <= 1'b0;
            client_response_is_write_o <= 1'b0;
            client_response_error_o <= 1'b0;
            client_read_data_o <= 0;
        end else begin
            case (state_r)
                ST_IDLE: begin
                    if (client_valid_i && client_ready_o) begin
                        client_response_is_write_o <= client_write_i;
                        client_response_error_o <= 1'b0;
                        client_read_data_o <= 0;
                        if ((client_use_hwc_i && !client_hwc_in_bounds_w)||client_line_error_w) begin
                            // Invalid HWC coordinates never reach external
                            // memory; the client receives an explicit error.
                            client_response_valid_o <= 1'b1;
                            client_response_error_o <= 1'b1;
                            state_r <= ST_RESPONSE;
                        end else begin
                            request_write_r <= client_write_i;
                            request_byte_address_r <= client_byte_address_r;
                            request_byte_lane_r <= client_byte_address_r[WORD_LSB_W-1:0];
                            request_write_data_r <= client_write_data_i;
                            request_write_line_r<=client_write_line_w;
                            request_write_line_data_r<=client_write_line_data_i;
                            if (client_write_i) begin
                                // Writes and cached tags are physical addresses.
                                // Every DDR master is serialized by this service.
                                // Preserve a source line across unrelated output
                                // writes, but invalidate matching writes (including
                                // source updates read later through Split aliases).
                                if (client_line_address_w == read_line_tag_r)
                                    read_line_valid_r <= 1'b0;
                                state_r <= ST_ISSUE;
                            end else if (view_hit_w) begin
                                // Register view metadata; non-view requests
                                // retain the unchanged baseline fast path.
                                view_offset_r<=client_byte_address_r-view_logical_base_w;
                                view_base_r<=view_physical_base_w;
                                view_mask_r<=view_mask_w;
                                state_r<=ST_VIEW_RESOLVE;
                            end else if (client_read_line_hit_w) begin
                                client_response_valid_o <= 1'b1;
                                client_response_is_write_o <= 1'b0;
                                client_response_error_o <= 1'b0;
                                client_read_data_o <= $signed(
                                    read_line_r[client_byte_address_r[WORD_LSB_W-1:0]*8 +: 8]);
                                state_r <= ST_RESPONSE;
                            end else begin
                                state_r <= ST_ISSUE;
                            end
                        end
                    end
                end
                ST_VIEW_RESOLVE: begin
                    request_byte_address_r<=view_address_w;
                    request_byte_lane_r<=view_address_w[WORD_LSB_W-1:0];
                    state_r<=ST_VIEW_LOOKUP;
                end
                ST_VIEW_LOOKUP: begin
                    // Physical cache tags make source-write invalidation valid
                    // for alias reads too, including debug tensor dumps.
                    if (read_line_valid_r && read_line_tag_r==request_byte_address_r[ADDR_W-1:WORD_LSB_W]) begin
                        client_response_valid_o<=1;
                        client_read_data_o<=$signed(read_line_r[request_byte_lane_r*8 +: 8]);
                        state_r<=ST_RESPONSE;
                    end else state_r<=ST_ISSUE;
                end
                ST_ISSUE: begin
                    if (ddr_req_ready_i) begin
                        if (request_write_r) begin
                            // The DDR command handshake is the completion
                            // point for byte-strobed writes in this interface.
                            client_response_valid_o <= 1'b1;
                            client_response_is_write_o <= 1'b1;
                            client_response_error_o <= 1'b0;
                            client_read_data_o <= 0;
                            state_r <= ST_RESPONSE;
                        end else begin
                            state_r <= ST_WAIT_READ;
                        end
                    end
                end
                ST_WAIT_READ: begin
                    if (ddr_read_valid_i && ddr_read_ready_o) begin
                        read_line_r <= ddr_read_data_i;
                        read_line_tag_r <= request_byte_address_r[ADDR_W-1:WORD_LSB_W];
                        read_line_valid_r <= 1'b1;
                        client_response_valid_o <= 1'b1;
                        client_response_is_write_o <= 1'b0;
                        client_response_error_o <= 1'b0;
                        client_read_data_o <= $signed(
                            ddr_read_data_i[request_byte_lane_r*8 +: 8]);
                        state_r <= ST_RESPONSE;
                    end
                end
                ST_RESPONSE: begin
                    if (client_response_valid_o && client_response_ready_i) begin
                        client_response_valid_o <= 1'b0;
                        state_r <= ST_IDLE;
                    end
                end
                default: state_r <= ST_IDLE;
            endcase
        end
    end
endmodule
