// Entire ingress is in recovered GMII RX clock domain. The actual downstream
// asynchronous DDR FIFO must retain valid data until accepted and report drained
// only after physical controller write completion; FIFO-empty alone is NOT drain.
module remote_media_ingress5 #(
    parameter integer WIDTH=1280,HEIGHT=720,PAYLOAD_BYTES=636
)(
    input wire rx_clk,pixel_clk,rst,
    input wire gmii_valid,gmii_error,input wire [7:0] gmii_data,
    output wire mem_valid,output wire [1:0] mem_bank,input wire mem_ready,mem_drained,
    output wire [31:0] mem_pixel_addr,output wire [15:0] mem_pixel_data,
    input wire display_safe_boundary,
    output wire front_valid,output wire [1:0] front_bank,output wire [31:0] front_id,
    output wire [31:0] complete_count,bad_network_packets,bad_video_packets,
    output wire result_valid,result_start,result_last,output wire [7:0] result_data,
    output wire [15:0] result_length,output wire [1:0] result_format,
    output reg [31:0] result_packets,ignored_packets,
    output wire write_available,
    output wire received_frame_commit,output wire[31:0]received_frame_id
);
    wire uv,us,ul,reject,done,written;wire [1:0] wb;wire [7:0] ud;wire [15:0] len;
    wire [31:0] fid;wire [1:0] kind;wire [15:0] destination;
    wire rx_reset;
    reset_domain_sync receiver_release(rx_clk,rst,rx_reset);
    checked_media_ethernet_rx3 #(.MAX_PAYLOAD(PAYLOAD_BYTES+32)) network(
        .clk(rx_clk),.rst(rx_reset),.gmii_valid(gmii_valid),.gmii_error(gmii_error),
        .gmii_data(gmii_data),.udp_valid(uv),.udp_start(us),.udp_last(ul),
        .udp_data(ud),.udp_length(len),.udp_kind(kind),.udp_destination(destination),.udp_ready(1'b1),.rejected(reject),
        .good_packets(),.bad_packets(bad_network_packets),.overrun_packets());
    video_udp_receiver #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.PAYLOAD_BYTES(PAYLOAD_BYTES)) video(
        .clk(rx_clk),.rst(rx_reset),.rx_valid(uv&&kind==1),.rx_start(us&&kind==1),.rx_last(ul&&kind==1),
        .rx_abort(1'b0),.rx_data(ud),.rx_length(len),.back_available(write_available),
        .back_bank(wb),.mem_valid(mem_valid),.mem_ready(mem_ready),.mem_drained(mem_drained),
        .mem_bank(mem_bank),.mem_pixel_addr(mem_pixel_addr),.mem_pixel_data(mem_pixel_data),
        .frame_complete(done),.frame_written(written),.completed_id(fid),.rx_packets(),.bad_packets(bad_video_packets),
        .dropped_packets(),.completed_frames(complete_count),.dropped_frames(),.frame_id_gap());
    assign received_frame_commit=done;assign received_frame_id=fid;
    // Business classification is after complete Ethernet/IP/UDP validation.
    // Result bytes are separate, not complete/validated YOLO results yet.
    assign result_valid=uv&&(kind==2||kind==3);
    assign result_start=result_valid&&us;assign result_last=result_valid&&ul;
    assign result_data=ud;assign result_length=len;assign result_format=kind;
    always @(posedge rx_clk or posedge rx_reset)begin
     if(rx_reset)begin result_packets<=0;ignored_packets<=0;end
     else if(uv&&us)begin
      if(kind==2||kind==3)result_packets<=result_packets+1'b1;
      else if(kind==0)ignored_packets<=ignored_packets+1'b1;
     end
    end
    // Network rejection is a missing packet; the next offset/packet check drops
    // that incomplete frame. Do not cancel a fully received/draining good frame
    // merely because a later unrelated Ethernet packet is rejected.
    frame_publish_cdc5 ownership(   // CLAUDE Z29B: three banks, DDR drain overlapped by the next frame
        .written(written),.wr_clk(rx_clk),.rd_clk(pixel_clk),.rst(rst),
        .publish(done),.publish_frame_id(fid),.wr_available(write_available),.wr_bank(wb),
        .rd_safe_boundary(display_safe_boundary),.rd_bank(front_bank),
        .rd_valid(front_valid),.rd_frame_id(front_id));
endmodule
