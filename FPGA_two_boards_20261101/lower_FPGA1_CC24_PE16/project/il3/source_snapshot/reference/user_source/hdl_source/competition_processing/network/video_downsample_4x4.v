// Select one RGB888 pixel from each 4 by 4 source-pixel area.
// The display timing is 1024 by 600, so this produces a deterministic
// 256 by 150 RGB888 stream for the Ethernet sender.
module video_downsample_4x4 (
    input  wire        I_clk,
    input  wire        I_rst_n,
    input  wire        I_video_de,
    input  wire        I_frame_start,
    input  wire [23:0] I_rgb888,
    output reg         O_pixel_valid,
    output reg         O_frame_start,
    output reg  [23:0] O_rgb888
);
    reg        S_de_d;
    reg        S_frame_pending;
    reg [11:0] S_x;
    reg [11:0] S_y;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            S_de_d          <= 1'b0;
            S_frame_pending  <= 1'b0;
            S_x              <= 12'd0;
            S_y              <= 12'd0;
            O_pixel_valid    <= 1'b0;
            O_frame_start    <= 1'b0;
            O_rgb888         <= 24'd0;
        end else begin
            S_de_d       <= I_video_de;
            O_pixel_valid <= 1'b0;
            O_frame_start <= 1'b0;

            if (I_frame_start)
                S_frame_pending <= 1'b1;

            if (I_video_de) begin
                // The VTC user pulse is aligned to the first active pixel.
                // Keeping a pending flag also handles an implementation that
                // places the pulse one cycle before data-enable.
                if (I_frame_start || S_frame_pending) begin
                    S_frame_pending <= 1'b0;
                    S_x             <= 12'd1;
                    S_y             <= 12'd0;
                    O_pixel_valid   <= 1'b1;
                    O_frame_start   <= 1'b1;
                    O_rgb888        <= I_rgb888;
                end else if (!S_de_d) begin
                    S_x <= 12'd1;
                    S_y <= S_y + 12'd1;
                    if (S_y[1:0] == 2'b11) begin
                        O_pixel_valid <= 1'b1;
                        O_rgb888      <= I_rgb888;
                    end
                end else begin
                    if ((S_x[1:0] == 2'b00) && (S_y[1:0] == 2'b00)) begin
                        O_pixel_valid <= 1'b1;
                        O_rgb888      <= I_rgb888;
                    end
                    S_x <= S_x + 12'd1;
                end
            end
        end
    end
endmodule
