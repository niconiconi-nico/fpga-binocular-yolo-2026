// The reference code_main_algorithm_pipeline's final passthrough registers,
// without its optional algorithms. Same first-active-pixel marker alignment.
module camera_video_scanout (
    input wire pix_clk,rst_n,in_hs,in_vs,in_de,
    input wire [23:0] in_rgb888,
    output reg out_hs,out_vs,out_de,out_frame_start,
    output reg [23:0] out_rgb888,
    output wire [7:0] active_mode
);
    reg frame_armed;
    assign active_mode=8'd0;
    always @(posedge pix_clk or negedge rst_n) begin
        if(!rst_n) begin
            out_hs<=0;out_vs<=0;out_de<=0;out_frame_start<=0;out_rgb888<=0;frame_armed<=1;
        end else begin
            out_hs<=in_hs;out_vs<=in_vs;out_de<=in_de;
            out_rgb888<=in_de?in_rgb888:24'd0;
            out_frame_start<=0;
            if(in_vs)frame_armed<=1;
            if(in_de&&frame_armed)begin out_frame_start<=1;frame_armed<=0;end
        end
    end
endmodule
