// Legacy <8I header, BE RGB565. Strict in-order first implementation.
// Malformed/duplicate/out-of-order packet invalidates its entire frame.
// Packet start/end refer to UDP payload, not Ethernet framing. No retransmit.
// Writer accepts one pixel / two UDP clocks. On memory stall drop the frame;
// downstream DDR FIFO must sustain this ingress rate. Publish waits for drain.
module video_udp_receiver #(
    parameter integer WIDTH=1280, HEIGHT=720,
    parameter integer PAYLOAD_BYTES=636
) (
    input wire clk, rst,
    input wire rx_valid, rx_start, rx_last, rx_abort,
    input wire [7:0] rx_data,
    input wire [15:0] rx_length,
    input wire back_available, input wire [1:0] back_bank,   // CLAUDE Z29: three banks
    output wire mem_valid,
    input wire mem_ready, mem_drained,
    output wire [1:0] mem_bank,
    output wire [31:0] mem_pixel_addr,
    output wire [15:0] mem_pixel_data,
    output reg frame_complete, frame_written,   // CLAUDE Z29B: frame_written = last datagram accepted (data complete)
    output reg [31:0] completed_id,
    output reg [31:0] rx_packets, bad_packets, dropped_packets,
    output reg [31:0] completed_frames, dropped_frames, frame_id_gap
);
    localparam integer FRAME_BYTES=WIDTH*HEIGHT*2;
    reg [31:0] hdr [0:7];
    reg [15:0] idx, length;
    reg in_packet, accepted, active, bad, await_drain, seen_id; reg [1:0] write_bank;
    reg [31:0] current_id, expected_offset, expected_packet, drain_id;
    reg [7:0] high_byte;
    reg [15:0] expected_payload;
    integer i;
    // No duplicate/replayed completed FID, nor resurrection of a failed FID.
    // Forward modulo32 FIDs accepted; half-range ambiguity is rejected.
    wire [31:0] id_delta=hdr[5]-current_id;
    wire new_frame = hdr[4]==0 && hdr[6]==0 &&
        (!seen_id || (id_delta!=0 && !id_delta[31]));
    wire [31:0] want_payload = (FRAME_BYTES-hdr[4] < PAYLOAD_BYTES) ?
                               FRAME_BYTES-hdr[4] : PAYLOAD_BYTES;
    wire header_ok = hdr[0]==32'haa0055ff && hdr[1]==WIDTH && hdr[2]==HEIGHT &&
        hdr[3]==FRAME_BYTES && hdr[4]<FRAME_BYTES && !hdr[4][0] &&
        hdr[7]=={16'd0,expected_payload} && hdr[7]!=0 && !hdr[7][0] &&
        {16'd0,length}==hdr[7]+32 && back_available &&   // Z29B: next frame may start while the last one drains
        (new_frame || (active && !bad && hdr[5]==current_id &&
                       hdr[4]==expected_offset && hdr[6]==expected_packet));
    assign mem_valid=rx_valid && in_packet && idx>=33 && idx[0] &&
                     accepted && !bad && back_available && idx<length;
    assign mem_bank=write_bank;
    assign mem_pixel_addr=(hdr[4]+{16'd0,idx}-33)>>1;
    assign mem_pixel_data={high_byte,rx_data};
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            for(i=0;i<8;i=i+1) hdr[i]<=0;
            idx<=0; length<=0; in_packet<=0; accepted<=0; active<=0; bad<=0;
            await_drain<=0; current_id<=0; expected_offset<=0; expected_packet<=0;
            seen_id<=0;write_bank<=1;
            high_byte<=0; expected_payload<=0; frame_complete<=0; frame_written<=0; completed_id<=0; drain_id<=0;
            rx_packets<=0; bad_packets<=0; dropped_packets<=0;
            completed_frames<=0; dropped_frames<=0; frame_id_gap<=0;
        end else begin
            frame_complete<=0; frame_written<=0;
            if (await_drain && mem_drained && !rx_abort) begin
                await_drain<=0; frame_complete<=1;
                completed_frames<=completed_frames+1; completed_id<=drain_id;
            end
            if (rx_abort) begin
                await_drain<=0;
                in_packet<=0; accepted<=0; bad_packets<=bad_packets+1;
                if (active && !bad) dropped_frames<=dropped_frames+1;
                bad<=1;
            end else if (rx_valid) begin
                if (rx_start) begin
                    rx_packets<=rx_packets+1; idx<=1; length<=rx_length;
                    in_packet<=1; accepted<=0;
                    hdr[0]<= {24'd0,rx_data};
                    for(i=1;i<8;i=i+1) hdr[i]<=0;
                    if (rx_last) begin
                        in_packet<=0; bad<=1; bad_packets<=bad_packets+1;
                        if (active && !bad) dropped_frames<=dropped_frames+1;
                    end
                    if (in_packet) begin
                        bad<=1; bad_packets<=bad_packets+1;
                        if (active && !bad) dropped_frames<=dropped_frames+1;
                    end
                end else if (in_packet) begin
                    idx<=idx+1;
                    if (idx<32) hdr[idx[4:2]][idx[1:0]*8 +: 8]<=rx_data;
                    // Offset is complete at byte19. Calculate its bounded
                    // expected payload ahead of header validation at byte32.
                    // Breaks offset-subtract -> header-valid -> counter-CE path.
                    if (idx==20) expected_payload<=want_payload[15:0];
                    if (idx==32) begin
                        accepted<=header_ok;
                        high_byte<=rx_data;
                        if (header_ok && new_frame) begin
                            if (active && !bad) dropped_frames<=dropped_frames+1;
                            if (hdr[5]!=current_id+1 && hdr[5]!=current_id)
                                frame_id_gap<=frame_id_gap+1;
                            active<=1; bad<=0; current_id<=hdr[5];seen_id<=1;
                            write_bank<=back_bank;
                            expected_offset<=0; expected_packet<=0;
                        end else if (!header_ok) begin
                            bad<=1; bad_packets<=bad_packets+1;
                            dropped_packets<=dropped_packets+1;
                            if (active && !bad) dropped_frames<=dropped_frames+1;
                        end
                    end else if (idx>=32 && !idx[0]) high_byte<=rx_data;
                    if (mem_valid && !mem_ready) begin
                        bad<=1; accepted<=0;
                        bad_packets<=bad_packets+1; dropped_packets<=dropped_packets+1;
                        if (active && !bad) dropped_frames<=dropped_frames+1;
                    end
                    if (rx_last) begin
                        in_packet<=0;
                        if (idx<32) begin
                            bad<=1; bad_packets<=bad_packets+1;
                            dropped_packets<=dropped_packets+1;
                            if (active && !bad) dropped_frames<=dropped_frames+1;
                        end else if (accepted && !bad && idx==length-1 &&
                            idx==hdr[7]+31 && (!mem_valid || mem_ready)) begin
                            expected_offset<=hdr[4]+hdr[7];
                            expected_packet<=hdr[6]+1;
                            if (hdr[4]+hdr[7]==FRAME_BYTES) begin await_drain<=1; drain_id<=current_id; active<=0; frame_written<=1; end
                        end else if (accepted && !bad) begin
                            bad<=1; bad_packets<=bad_packets+1;
                            if (active) dropped_frames<=dropped_frames+1;
                        end
                    end
                end
            end
        end
    end
endmodule
