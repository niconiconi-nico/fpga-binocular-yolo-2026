// Read-only, windowed feature-tensor dump for board accuracy debug.
// Existing packet types 1..4 are unchanged.  Type 5 replies contain a
// 26-byte header followed by at most PAYLOAD_BYTES raw HWC tensor bytes.
module v5n_udp_tensor_dump_tx #(
    parameter integer ADDR_W = 32,
    parameter integer PAYLOAD_BYTES = 64
) (
    input wire clk_i, input wire rst_ni,
    input wire start_i, input wire [7:0] layer_i, input wire [31:0] frame_id_i,
    input wire [ADDR_W-1:0] tensor_base_i, input wire [31:0] tensor_size_i,
    input wire [31:0] request_offset_i, input wire [31:0] request_count_i,
    output reg read_start_o, output reg [ADDR_W-1:0] read_address_o,
    output reg [ADDR_W-1:0] read_count_o, input wire read_ready_i,
    input wire read_done_i, input wire read_data_valid_i,
    input wire [ADDR_W-1:0] read_data_offset_i, input wire signed [7:0] read_data_i,
    input wire udp_busy_i, output reg udp_request_o, output reg udp_valid_o,
    output reg [7:0] udp_data_o, output wire [15:0] udp_length_o,
    output reg busy_o, output reg done_o, output reg error_o
);
    localparam [2:0] ST_IDLE=0, ST_READ_START=1, ST_READ_WAIT=2,
                     ST_REQUEST=3, ST_SEND=4, ST_NEXT=5, ST_DONE=6;
    localparam integer HEADER_BYTES = 26;
    reg [2:0] state_r;
    reg [7:0] layer_r;
    reg [31:0] frame_r, tensor_size_r, window_offset_r, window_count_r;
    reg [31:0] packet_offset_r;
    reg [15:0] packet_index_r, packet_count_r, chunk_bytes_r, tx_byte_r, data_index_r;
    reg [7:0] payload_r [0:PAYLOAD_BYTES-1];
    integer i;

    wire [31:0] next_packet_offset_w = packet_offset_r + chunk_bytes_r;
    wire [31:0] remaining_w = window_count_r - next_packet_offset_w;
    wire [31:0] absolute_offset_w = window_offset_r + packet_offset_r;
    wire [15:0] next_chunk_w = (remaining_w > PAYLOAD_BYTES) ? PAYLOAD_BYTES : remaining_w[15:0];
    assign udp_length_o = HEADER_BYTES + chunk_bytes_r;

    always @* begin
        if (data_index_r < HEADER_BYTES) begin
            case (data_index_r)
                0:udp_data_o=8'h59; 1:udp_data_o=8'h38; 2:udp_data_o=8'h4e; 3:udp_data_o=8'h33;
                4:udp_data_o=8'd1; 5:udp_data_o=8'd5; 6:udp_data_o=layer_r; 7:udp_data_o=8'd0;
                8:udp_data_o=frame_r[7:0]; 9:udp_data_o=frame_r[15:8];
                10:udp_data_o=frame_r[23:16]; 11:udp_data_o=frame_r[31:24];
                12:udp_data_o=packet_index_r[7:0]; 13:udp_data_o=packet_index_r[15:8];
                14:udp_data_o=packet_count_r[7:0]; 15:udp_data_o=packet_count_r[15:8];
                16:udp_data_o=absolute_offset_w[7:0];
                17:udp_data_o=absolute_offset_w[15:8];
                18:udp_data_o=absolute_offset_w[23:16];
                19:udp_data_o=absolute_offset_w[31:24];
                20:udp_data_o=tensor_size_r[7:0]; 21:udp_data_o=tensor_size_r[15:8];
                22:udp_data_o=tensor_size_r[23:16]; 23:udp_data_o=tensor_size_r[31:24];
                24:udp_data_o=chunk_bytes_r[7:0]; default:udp_data_o=chunk_bytes_r[15:8];
            endcase
        end else udp_data_o = payload_r[data_index_r-HEADER_BYTES];
    end

    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            state_r<=ST_IDLE; layer_r<=0; frame_r<=0; tensor_size_r<=0;
            window_offset_r<=0; window_count_r<=0; packet_offset_r<=0;
            packet_index_r<=0; packet_count_r<=0; chunk_bytes_r<=0; tx_byte_r<=0; data_index_r<=0;
            read_start_o<=0; read_address_o<=0; read_count_o<=0;
            udp_request_o<=0; udp_valid_o<=0; busy_o<=0; done_o<=0; error_o<=0;
            for(i=0;i<PAYLOAD_BYTES;i=i+1) payload_r[i]<=0;
        end else begin
            read_start_o<=0; udp_request_o<=0; udp_valid_o<=0; done_o<=0;
            case(state_r)
                ST_IDLE: if(start_i) begin
                    layer_r<=layer_i; frame_r<=frame_id_i; tensor_size_r<=tensor_size_i;
                    window_offset_r<=request_offset_i; window_count_r<=request_count_i;
                    packet_offset_r<=0; packet_index_r<=0;
                    packet_count_r<=(request_count_i+PAYLOAD_BYTES-1)/PAYLOAD_BYTES;
                    chunk_bytes_r<=(request_count_i>PAYLOAD_BYTES)?PAYLOAD_BYTES:request_count_i[15:0];
                    busy_o<=1; error_o<=0;
                    if(request_count_i==0 || request_offset_i>=tensor_size_i ||
                       request_count_i>tensor_size_i-request_offset_i) begin error_o<=1; state_r<=ST_DONE; end
                    else state_r<=ST_READ_START;
                end
                ST_READ_START: if(read_ready_i) begin
                    read_address_o<=tensor_base_i+window_offset_r+packet_offset_r;
                    read_count_o<=chunk_bytes_r; read_start_o<=1; state_r<=ST_READ_WAIT;
                end
                ST_READ_WAIT: begin
                    if(read_data_valid_i && read_data_offset_i<PAYLOAD_BYTES)
                        payload_r[read_data_offset_i]<=read_data_i;
                    if(read_done_i) state_r<=ST_REQUEST;
                end
                ST_REQUEST: if(!udp_busy_i) begin udp_request_o<=1; tx_byte_r<=0; data_index_r<=0; state_r<=ST_SEND; end
                ST_SEND: if(udp_busy_i) begin
                    udp_valid_o<=1; data_index_r<=tx_byte_r;
                    if(tx_byte_r+1>=udp_length_o) state_r<=ST_NEXT;
                    else tx_byte_r<=tx_byte_r+1'b1;
                end
                ST_NEXT: begin
                    if(packet_offset_r+chunk_bytes_r>=window_count_r) state_r<=ST_DONE;
                    else begin
                        packet_offset_r<=packet_offset_r+chunk_bytes_r;
                        packet_index_r<=packet_index_r+1'b1;
                        chunk_bytes_r<=next_chunk_w;
                        state_r<=ST_READ_START;
                    end
                end
                ST_DONE: begin busy_o<=0; done_o<=1; state_r<=ST_IDLE; end
                default: begin error_o<=1; state_r<=ST_DONE; end
            endcase
        end
    end
endmodule
