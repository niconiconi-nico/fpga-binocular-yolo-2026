// Serializes actual detection-memory records for the uiudp_stack TX interface.
// The accelerator owns the records; this block reads them only after NMS done.
// One compact UDP reply is issued per record to avoid IP fragmentation.
module v5n_udp_detection_tx #(
    parameter integer INDEX_W = 9
) (
    input wire clk_i, input wire rst_ni,
    input wire start_i, input wire [31:0] frame_id_i,
    input wire [INDEX_W-1:0] detection_count_i,
    output reg [INDEX_W-1:0] detection_read_index_o,
    output reg detection_read_request_o, input wire detection_read_valid_i,
    input wire [1:0] detection_class_i, input wire [15:0] detection_confidence_q15_i,
    input wire signed [31:0] detection_x1_q16_i, input wire signed [31:0] detection_y1_q16_i,
    input wire signed [31:0] detection_x2_q16_i, input wire signed [31:0] detection_y2_q16_i,
    input wire udp_busy_i, output reg udp_request_o, output reg udp_valid_o,
    output reg [7:0] udp_data_o, output wire [15:0] udp_length_o,
    output reg busy_o, output reg done_o
);
    // Header is 16 B; each non-empty reply carries one 19 B record.  A zero
    // count still transmits the 16-byte completion header.
    localparam [15:0] REPLY_BYTES = 16'd35;
    localparam [2:0] ST_IDLE=0, ST_READ=1, ST_REQUEST=2, ST_SEND=3, ST_NEXT=4;
    reg [2:0] state_r; reg [5:0] byte_r;
    reg [31:0] frame_r; reg [INDEX_W-1:0] count_r;
    assign udp_length_o = (count_r==0)?16'd16:REPLY_BYTES;
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            state_r<=ST_IDLE; byte_r<=0; frame_r<=0; count_r<=0;
            detection_read_index_o<=0; detection_read_request_o<=0; udp_request_o<=0; udp_valid_o<=0;
            udp_data_o<=0; busy_o<=0; done_o<=0;
        end else begin
            detection_read_request_o<=0; udp_request_o<=0; udp_valid_o<=0; done_o<=0;
            case(state_r)
                ST_IDLE: if(start_i) begin
                    frame_r<=frame_id_i; count_r<=detection_count_i;
                    detection_read_index_o<=0; busy_o<=1;
                    if(detection_count_i==0) state_r<=ST_REQUEST;
                    else state_r<=ST_READ;
                end
                ST_READ: begin detection_read_request_o<=1'b1; if(detection_read_valid_i) state_r<=ST_REQUEST; end
                ST_REQUEST: if(!udp_busy_i) begin udp_request_o<=1; byte_r<=0; state_r<=ST_SEND; end
                ST_SEND: if(udp_busy_i) begin
                    udp_valid_o<=1;
                    case(byte_r)
                        0:udp_data_o<=8'h59; 1:udp_data_o<=8'h38; 2:udp_data_o<=8'h4e; 3:udp_data_o<=8'h33;
                        4:udp_data_o<=8'd1; 5:udp_data_o<=8'd2; 6:udp_data_o<=8'd0; 7:udp_data_o<=8'd0;
                        8:udp_data_o<=frame_r[7:0]; 9:udp_data_o<=frame_r[15:8]; 10:udp_data_o<=frame_r[23:16]; 11:udp_data_o<=frame_r[31:24];
                        12:udp_data_o<=detection_read_index_o[7:0]; 13:udp_data_o<={{7{1'b0}},detection_read_index_o[INDEX_W-1]};
                        14:udp_data_o<=count_r[7:0]; 15:udp_data_o<={{7{1'b0}},count_r[INDEX_W-1]};
                        16:udp_data_o<={6'd0,detection_class_i};
                        17:udp_data_o<=detection_confidence_q15_i[7:0]; 18:udp_data_o<=detection_confidence_q15_i[15:8];
                        19:udp_data_o<=detection_x1_q16_i[7:0]; 20:udp_data_o<=detection_x1_q16_i[15:8]; 21:udp_data_o<=detection_x1_q16_i[23:16]; 22:udp_data_o<=detection_x1_q16_i[31:24];
                        23:udp_data_o<=detection_y1_q16_i[7:0]; 24:udp_data_o<=detection_y1_q16_i[15:8]; 25:udp_data_o<=detection_y1_q16_i[23:16]; 26:udp_data_o<=detection_y1_q16_i[31:24];
                        27:udp_data_o<=detection_x2_q16_i[7:0]; 28:udp_data_o<=detection_x2_q16_i[15:8]; 29:udp_data_o<=detection_x2_q16_i[23:16]; 30:udp_data_o<=detection_x2_q16_i[31:24];
                        31:udp_data_o<=detection_y2_q16_i[7:0]; 32:udp_data_o<=detection_y2_q16_i[15:8]; 33:udp_data_o<=detection_y2_q16_i[23:16];
                        default:udp_data_o<=detection_y2_q16_i[31:24];
                    endcase
                    if(byte_r+1>=udp_length_o) state_r<=ST_NEXT; else byte_r<=byte_r+1'b1;
                end
                ST_NEXT: begin
                    if(detection_read_index_o+1>=count_r) begin busy_o<=0; done_o<=1; state_r<=ST_IDLE; end
                    else begin detection_read_index_o<=detection_read_index_o+1'b1; state_r<=ST_READ; end
                end
                default: state_r<=ST_IDLE;
            endcase
        end
    end
endmodule
