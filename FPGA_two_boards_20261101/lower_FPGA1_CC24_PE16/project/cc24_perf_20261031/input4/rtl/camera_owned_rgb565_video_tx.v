// RGB565 video packetizer for the official PH1P uiudp_stack application TX
// interface. The extra FIFO bit marks the first sampled pixel of a source
// frame, so a UDP frame always begins at an HDMI frame boundary.
module camera_owned_rgb565_video_tx #(
    parameter [31:0] IMAGE_WIDTH          = 32'd1024,
    parameter [31:0] IMAGE_HEIGHT         = 32'd600,
    parameter [15:0] PACKET_DATA_BYTES    = 16'd636,
    parameter integer FIFO_ADDR_WIDTH_W   = 13
) (
    input  wire       I_rst,
    input  wire       I_enable,
    // Same-domain stable owned frame ID. Producer MUST wait O_frame_complete
    // before changing this ID or starting another source frame.
    input wire [31:0] I_source_frame_id,
    output reg O_frame_complete,
    input  wire       I_video_clk,
    input  wire       I_pixel_valid,
    input  wire       I_frame_start,
    input  wire [15:0] I_pixel_rgb565,
    input  wire       I_udp_clk,
    input  wire       I_W_udp_busy,
    output wire       O_W_udp_req,
    output wire       O_W_udp_valid,
    output wire [7:0] O_W_udp_data,
    output wire [15:0] O_W_udp_len,
    output wire       O_fifo_full,
    output wire       O_fifo_empty,
    output wire [FIFO_ADDR_WIDTH_W:0] O_fifo_rdusedw,
    output reg [31:0] O_dropped_pixels,
    output reg [31:0] O_frame_sequence,
    output reg [31:0] O_packet_sequence,
    output reg [31:0] O_frame_offset,
    output wire       O_tx_active
);
    localparam [31:0] FRAME_BYTES = IMAGE_WIDTH * IMAGE_HEIGHT * 32'd2;
    localparam [15:0] HEADER_BYTES = 16'd32;
    localparam [15:0] FIRST_PACKET_DATA_BYTES =
        (FRAME_BYTES >= {16'd0, PACKET_DATA_BYTES}) ?
        PACKET_DATA_BYTES : FRAME_BYTES[15:0];
    localparam FIRST_PACKET_ENDS_FRAME =
        (FRAME_BYTES <= {16'd0, PACKET_DATA_BYTES});
    // A non-final packet must also reserve the first pixel of its successor.
    // A final packet only needs the pixels following the cached first word.
    localparam [15:0] FIRST_PACKET_FIFO_PIXELS =
        (FIRST_PACKET_DATA_BYTES >> 1) -
        (FIRST_PACKET_ENDS_FRAME ? 16'd1 : 16'd0);
    localparam [15:0] FULL_PACKET_FIFO_PIXELS =
        (PACKET_DATA_BYTES >> 1);
    localparam [2:0] ST_SEEK_FRAME = 3'd0;
    localparam [2:0] ST_IDLE       = 3'd1;
    localparam [2:0] ST_REQUEST    = 3'd2;
    localparam [2:0] ST_HEADER     = 3'd3;
    localparam [2:0] ST_DATA       = 3'd4;
    localparam [2:0] ST_WAIT_DONE  = 3'd5;

    reg [2:0]  S_state;
    reg [5:0]  S_header_index;
    // Counts payload bytes, rather than pixels.  The UDP application
    // interface consumes exactly one byte on each valid clock.
    reg [15:0] S_data_index;
    reg [15:0] S_packet_data_bytes;
    reg        S_current_packet_ends_frame;
    reg        S_byte_select;
    reg        S_pixel_word_valid;
    reg [16:0] S_pixel_word;
    reg        S_prefetch_valid;
    reg [16:0] S_prefetch_word;
    // Packet metadata is prepared before ST_IDLE.  This keeps the 125-MHz
    // request decision to one FIFO-count comparison instead of placing the
    // frame-byte subtraction and final-packet calculation on the same path.
    reg [31:0] S_remaining_bytes;
    reg [15:0] S_packet_start_fifo_pixels;
    wire [16:0] S_fifo_dout;
    wire        S_fifo_we;
    wire        S_fifo_re;
    wire [FIFO_ADDR_WIDTH_W-1:0] S_fifo_rdusedw;

    // Store the marker and pixel in the same FIFO word. The first source
    // pixel is cached in the UDP domain; the remaining packet pixels come
    // directly from subsequent FIFO words.
    udp_pkg_buf #(
        .DATA_WIDTH_W (17),
        .DATA_WIDTH_R (17),
        .ADDR_WIDTH_W (FIFO_ADDR_WIDTH_W),
        .ADDR_WIDTH_R (FIFO_ADDR_WIDTH_W),
        .SHOW_AHEAD_EN(1'b1),
        .OUTREG_EN    ("NOREG")
    ) u_video_fifo (
        .rst       (I_rst),
        .clkw      (I_video_clk),
        .clkr      (I_udp_clk),
        .we        (S_fifo_we),
        .di        ({I_frame_start, I_pixel_rgb565}),
        .re        (S_fifo_re),
        .dout      (S_fifo_dout),
        .valid     (),
        .full_flag (O_fifo_full),
        .empty_flag(O_fifo_empty),
        .afull     (),
        .aempty    (),
        .wrusedw   (),
        .rdusedw   (S_fifo_rdusedw)
    );

    // Camera-only CDC correction: never use PHY25M enable combinationally
    // at the video FIFO write port or at125M packet FSM. Reset asserts
    // asynchronously; readiness releases independently in both domains.
    (* async_reg = "true" *) reg [1:0] video_enable_sync;
    (* async_reg = "true" *) reg [1:0] udp_enable_sync;
    always @(posedge I_video_clk or posedge I_rst)
        if(I_rst) video_enable_sync<=2'b00;
        else video_enable_sync<={video_enable_sync[0],I_enable};
    always @(posedge I_udp_clk or posedge I_rst)
        if(I_rst) udp_enable_sync<=2'b00;
        else udp_enable_sync<={udp_enable_sync[0],I_enable};
    assign S_fifo_we = video_enable_sync[1] && I_pixel_valid && !O_fifo_full;
    assign O_fifo_rdusedw = {1'b0, S_fifo_rdusedw};

    always @(posedge I_video_clk or posedge I_rst) begin
        if (I_rst)
            O_dropped_pixels <= 32'd0;
        else if (video_enable_sync[1] && I_pixel_valid && O_fifo_full)
            O_dropped_pixels <= O_dropped_pixels + 32'd1;
    end

    function [7:0] F_header_byte;
        input [5:0]  I_index;
        input [31:0] I_frame_sequence;
        input [31:0] I_packet_sequence;
        input [31:0] I_frame_offset;
        input [15:0] I_packet_data_bytes;
        begin
            case (I_index)
                6'd0:  F_header_byte = 8'hff;
                6'd1:  F_header_byte = 8'h55;
                6'd2:  F_header_byte = 8'h00;
                6'd3:  F_header_byte = 8'haa;
                6'd4:  F_header_byte = IMAGE_WIDTH[7:0];
                6'd5:  F_header_byte = IMAGE_WIDTH[15:8];
                6'd6:  F_header_byte = IMAGE_WIDTH[23:16];
                6'd7:  F_header_byte = IMAGE_WIDTH[31:24];
                6'd8:  F_header_byte = IMAGE_HEIGHT[7:0];
                6'd9:  F_header_byte = IMAGE_HEIGHT[15:8];
                6'd10: F_header_byte = IMAGE_HEIGHT[23:16];
                6'd11: F_header_byte = IMAGE_HEIGHT[31:24];
                6'd12: F_header_byte = FRAME_BYTES[7:0];
                6'd13: F_header_byte = FRAME_BYTES[15:8];
                6'd14: F_header_byte = FRAME_BYTES[23:16];
                6'd15: F_header_byte = FRAME_BYTES[31:24];
                6'd16: F_header_byte = I_frame_offset[7:0];
                6'd17: F_header_byte = I_frame_offset[15:8];
                6'd18: F_header_byte = I_frame_offset[23:16];
                6'd19: F_header_byte = I_frame_offset[31:24];
                6'd20: F_header_byte = I_frame_sequence[7:0];
                6'd21: F_header_byte = I_frame_sequence[15:8];
                6'd22: F_header_byte = I_frame_sequence[23:16];
                6'd23: F_header_byte = I_frame_sequence[31:24];
                6'd24: F_header_byte = I_packet_sequence[7:0];
                6'd25: F_header_byte = I_packet_sequence[15:8];
                6'd26: F_header_byte = I_packet_sequence[23:16];
                6'd27: F_header_byte = I_packet_sequence[31:24];
                6'd28: F_header_byte = I_packet_data_bytes[7:0];
                6'd29: F_header_byte = I_packet_data_bytes[15:8];
                default: F_header_byte = 8'd0;
            endcase
        end
    endfunction

    assign O_W_udp_req   = (S_state == ST_REQUEST);
    assign O_W_udp_valid = (S_state == ST_HEADER) || (S_state == ST_DATA);
    assign O_W_udp_len   = S_packet_data_bytes + HEADER_BYTES;
    assign O_tx_active   = (S_state != ST_SEEK_FRAME) && (S_state != ST_IDLE);

    // The FIFO is show-ahead: dout is the current head before a read advances
    // its pointer.  A data-phase read caches that next head in the prefetch
    // register while the current word emits its high byte; the low-byte phase
    // then makes the prefetch word current.
    assign S_fifo_re = udp_enable_sync[1] && !O_fifo_empty && !S_prefetch_valid &&
        ((S_state == ST_SEEK_FRAME) ||
         // Pop the next word only after the first byte of the current word
         // has been issued.  A final packet does not prefetch into the next
         // frame; all other packets retain one cached word for the next one.
         ((S_state == ST_DATA) && S_pixel_word_valid && !S_byte_select &&
          ((S_data_index + 16'd2 < S_packet_data_bytes) ||
           !S_current_packet_ends_frame)));

    assign O_W_udp_data = (S_state == ST_HEADER) ?
        F_header_byte(S_header_index, O_frame_sequence, O_packet_sequence,
                      O_frame_offset, S_packet_data_bytes) :
        (S_state == ST_DATA) ?
            (S_byte_select ? S_pixel_word[7:0] : S_pixel_word[15:8]) :
        8'd0;

    always @(posedge I_udp_clk or posedge I_rst) begin
        if (I_rst) begin
            S_state                     <= ST_SEEK_FRAME;
            S_header_index              <= 6'd0;
            S_data_index                <= 16'd0;
            S_packet_data_bytes         <= 16'd0;
            S_current_packet_ends_frame <= 1'b0;
            S_byte_select               <= 1'b0;
            S_pixel_word_valid          <= 1'b0;
            S_pixel_word                <= 17'd0;
            S_prefetch_valid            <= 1'b0;
            S_prefetch_word             <= 17'd0;
            S_remaining_bytes           <= FRAME_BYTES;
            S_packet_start_fifo_pixels  <= FIRST_PACKET_FIFO_PIXELS;
            O_frame_sequence            <= 32'd0;
            O_frame_complete            <= 1'b0;
            O_packet_sequence           <= 32'd0;
            O_frame_offset              <= 32'd0;
        end else begin
            O_frame_complete <= 1'b0;
            if (S_fifo_re && (S_state == ST_SEEK_FRAME)) begin
                // udp_pkg_buf is configured in show-ahead mode.  Its dout is
                // the current FIFO head before the read pointer advances, so
                // acquire it in this same clock edge.  Waiting a cycle here
                // would observe the next FIFO word and discard the frame
                // marker together with the first source pixel.
                S_pixel_word       <= S_fifo_dout;
                S_pixel_word_valid <= S_fifo_dout[16];
                if (S_fifo_dout[16]) begin
                    O_frame_sequence <= I_source_frame_id;
                    S_byte_select               <= 1'b0;
                    S_remaining_bytes           <= FRAME_BYTES;
                    S_packet_data_bytes         <= FIRST_PACKET_DATA_BYTES;
                    S_current_packet_ends_frame <= FIRST_PACKET_ENDS_FRAME;
                    S_packet_start_fifo_pixels  <= FIRST_PACKET_FIFO_PIXELS;
                    S_state                     <= ST_IDLE;
                end
            end else if (S_fifo_re) begin
                S_prefetch_word  <= S_fifo_dout;
                S_prefetch_valid <= 1'b1;
            end

            case (S_state)
                // Discard stale pixels until a source-frame marker is read.
                ST_SEEK_FRAME: begin
                    if (!S_fifo_re)
                        S_pixel_word_valid <= 1'b0;
                end

                ST_IDLE: begin
                    // The cached first pixel is outside the FIFO count.
                    if (udp_enable_sync[1] && !I_W_udp_busy && S_pixel_word_valid &&
                        (O_fifo_rdusedw >= S_packet_start_fifo_pixels)) begin
                        S_header_index <= 6'd0;
                        S_data_index   <= 16'd0;
                        S_byte_select  <= 1'b0;
                        S_state        <= ST_REQUEST;
                    end
                end

                ST_REQUEST: begin
                    if (I_W_udp_busy)
                        S_state <= ST_HEADER;
                end

                ST_HEADER: begin
                    if (S_header_index == 6'd31) begin
                        S_header_index <= 6'd0;
                        S_data_index   <= 16'd0;
                        S_byte_select  <= 1'b0;
                        S_state        <= ST_DATA;
                    end else begin
                        S_header_index <= S_header_index + 6'd1;
                    end
                end

                ST_DATA: begin
                    if (!S_byte_select) begin
                        // First byte of RGB565 is the high-order byte from the
                        // FIFO word. The source writes {frame_start, rgb565}.
                        S_byte_select <= 1'b1;
                        S_data_index  <= S_data_index + 16'd1;
                    end else begin
                        // The second byte completes one pixel. S_data_index is
                        // a byte offset, so the terminal comparison is made
                        // after precisely PACKET_DATA_BYTES valid cycles.
                        S_byte_select <= 1'b0;
                        // The data-phase FIFO read was issued while sending
                        // this word's high byte.  Move the saved next word
                        // into the current register only after its low byte
                        // has been presented.
                        if (S_prefetch_valid) begin
                            S_pixel_word       <= S_prefetch_word;
                            S_pixel_word_valid <= 1'b1;
                            S_prefetch_valid   <= 1'b0;
                        end
                        if (S_data_index == (S_packet_data_bytes - 16'd1)) begin
                            S_data_index <= 16'd0;
                            S_state      <= ST_WAIT_DONE;
                            if (S_current_packet_ends_frame) begin
                                S_remaining_bytes <= 32'd0;
                                O_frame_offset    <= 32'd0;
                                O_packet_sequence <= 32'd0;
                                // Retain physical source ID through final packet.
                            end else begin
                                S_remaining_bytes <= S_remaining_bytes -
                                    {16'd0, S_packet_data_bytes};
                                O_frame_offset    <= O_frame_offset + S_packet_data_bytes;
                                O_packet_sequence <= O_packet_sequence + 32'd1;
                            end
                        end else begin
                            S_data_index <= S_data_index + 16'd1;
                        end
                    end
                end

                ST_WAIT_DONE: begin
                    if (!I_W_udp_busy) begin
                        if (S_current_packet_ends_frame)begin
                            O_frame_complete <= 1'b1;
                            S_state <= ST_SEEK_FRAME;
                        end
                        else begin
                            // S_remaining_bytes was reduced when the previous
                            // packet completed.  Register the next packet's
                            // metadata here, one cycle before ST_IDLE uses it.
                            if (S_remaining_bytes <=
                                {16'd0, PACKET_DATA_BYTES}) begin
                                S_packet_data_bytes <= S_remaining_bytes[15:0];
                                S_current_packet_ends_frame <= 1'b1;
                                S_packet_start_fifo_pixels <=
                                    (S_remaining_bytes[15:0] >> 1) - 16'd1;
                            end else begin
                                S_packet_data_bytes <= PACKET_DATA_BYTES;
                                S_current_packet_ends_frame <= 1'b0;
                                S_packet_start_fifo_pixels <=
                                    FULL_PACKET_FIFO_PIXELS;
                            end
                            S_state <= ST_IDLE;
                        end
                    end
                end

                default: S_state <= ST_SEEK_FRAME;
            endcase
        end
    end
endmodule
