// SC520CS vendor full 1280x720 RAW10, no spatial crop or decimation.
// Four pixels per beat; source (0,0) BGGR phase follows vendor Lab1.
// CSI source cannot be backpressured. Blank cycles do not advance counters.
module sc520_raw10_crop (
    input wire clk, rst_n, frame_start, frame_end, valid,
    input wire [39:0] data,
    output reg [39:0] out_data,
    output reg out_valid, out_sof, out_eol,
    output reg frame_error
);
    reg [8:0] x;
    reg [9:0] y;
    reg active;
    wire [8:0] px = frame_start ? 9'd0 : x;
    wire [9:0] py = frame_start ? 10'd0 : y;
    wire take = valid && (active || frame_start);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            x<=0; y<=0; active<=0; frame_error<=0;
            out_data<=0; out_valid<=0; out_sof<=0; out_eol<=0;
        end else begin
            out_valid<=0; out_sof<=0; out_eol<=0;
            if (frame_start) begin x<=0; y<=0; active<=1; end
            if (take) begin
                if (py < 720) begin
                    if (px<320 && py<720) begin
                        out_data<=data; out_valid<=1;
                        out_sof<=px==0 && py==0;
                        out_eol<=px==319;
                    end
                    if (px==319) begin x<=0; y<=py+1'b1; end
                    else begin x<=px+1'b1; y<=py; end
                end else frame_error<=1;
            end
            if (frame_end) begin
                active<=0;
                if (!(take ? (py==719 && px==319) : (y==720 && x==0)))
                    frame_error<=1;
            end
        end
    end
endmodule
