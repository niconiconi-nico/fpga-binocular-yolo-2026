// One clock domain only. CDC belongs in the physical DDR/camera adapters.
// committed_i MUST mean full valid frame + actual final write completion.
// No enqueue/FIFO-ready surrogate is accepted as frame publication.
module camera_frame_bank_owner (
    input wire clk, rst_n,
    input wire frame_begin_i, committed_i, rejected_i,
    input wire [31:0] camera_frame_id_i,
    output wire capture_accept_o,
    output wire [1:0] capture_bank_o,
    output reg capture_active_o,
    input wire yolo_acquire_i, yolo_release_i,
    input wire [31:0] yolo_release_id_i,
    output reg yolo_locked_o,
    output reg [1:0] yolo_bank_o,
    output reg [31:0] yolo_source_id_o,
    input wire video_acquire_i, video_release_i,
    input wire [31:0] video_release_id_i,
    output reg video_locked_o,
    output reg [1:0] video_bank_o,
    output reg [31:0] video_source_id_o,
    output reg latest_valid_o,
    output reg [31:0] committed_frames_o, skipped_frames_o,
    output reg release_error_o
);
    reg [1:0] capture_bank_r, latest_bank_r;
    reg [31:0] latest_id_r, capture_id_r;
    reg free_found;
    reg [1:0] free_bank;
    integer i;
    always @* begin
        free_found=0; free_bank=0;
        for(i=0;i<3;i=i+1) begin
            if(!free_found && (!latest_valid_o || latest_bank_r!=i) &&
               (!yolo_locked_o || yolo_bank_o!=i) &&
               (!video_locked_o || video_bank_o!=i)) begin
                free_found=1; free_bank=i;
            end
        end
    end
    assign capture_accept_o=frame_begin_i && !capture_active_o && free_found;
    assign capture_bank_o=capture_active_o ? capture_bank_r : free_bank;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            capture_active_o<=0;capture_bank_r<=0;latest_bank_r<=0;latest_id_r<=0;capture_id_r<=0;
            yolo_locked_o<=0;yolo_bank_o<=0;yolo_source_id_o<=0;
            video_locked_o<=0;video_bank_o<=0;video_source_id_o<=0;
            latest_valid_o<=0;committed_frames_o<=0;skipped_frames_o<=0;release_error_o<=0;
        end else begin
            release_error_o<=0;
            if(frame_begin_i) begin
                if(capture_accept_o) begin capture_active_o<=1;capture_bank_r<=free_bank;capture_id_r<=camera_frame_id_i;end
                else skipped_frames_o<=skipped_frames_o+1'b1;
            end
            if(capture_active_o && rejected_i) capture_active_o<=0;
            else if(capture_active_o && committed_i) begin
                capture_active_o<=0;latest_valid_o<=1;latest_bank_r<=capture_bank_r;
                latest_id_r<=capture_id_r;committed_frames_o<=committed_frames_o+1'b1;
            end
            // Acquire snapshots the prior complete frame even if a new commit
            // arrives on this edge. That bank was excluded from capture.
            if(yolo_acquire_i && !yolo_locked_o && latest_valid_o) begin
                yolo_locked_o<=1;yolo_bank_o<=latest_bank_r;yolo_source_id_o<=latest_id_r;
            end
            if(video_acquire_i && !video_locked_o && latest_valid_o) begin
                video_locked_o<=1;video_bank_o<=latest_bank_r;video_source_id_o<=latest_id_r;
            end
            if(yolo_release_i) begin
                if(yolo_locked_o && yolo_release_id_i==yolo_source_id_o) yolo_locked_o<=0;
                else release_error_o<=1;
            end
            if(video_release_i) begin
                if(video_locked_o && video_release_id_i==video_source_id_o) video_locked_o<=0;
                else release_error_o<=1;
            end
        end
    end
endmodule
