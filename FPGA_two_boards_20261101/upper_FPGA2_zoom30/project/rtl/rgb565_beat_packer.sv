// Same producer domain, eight adjacent RGB565 pixels per128-bit DDR beat.
// Orphan pixels from a rejected frame never cause a beat to be published.
// First pixel at an aligned address replaces any previous partial beat.
module rgb565_beat_packer #(
    parameter integer FRAME_PIXELS=1280*720
)(
    input wire clk,rst,
    input wire pixel_valid, input wire [1:0] pixel_bank,
    input wire [31:0] pixel_address,input wire [15:0] pixel_data,
    output wire pixel_ready,
    output reg beat_valid,input wire beat_ready,
    output reg [1:0] beat_bank,output reg [31:0] beat_pixel_address,
    output reg [127:0] beat_data,output reg beat_frame_last,
    output reg [31:0] rejected_pixels
);
    reg [127:0] assembly;
    reg [31:0] expected_address;
    reg assembling;reg [1:0] bank;   // CLAUDE Z29: three receive banks
    wire slot_free=!beat_valid || beat_ready;
    assign pixel_ready=slot_free;
    always @(posedge clk or posedge rst) begin
        if(rst) begin
            beat_valid<=0;beat_bank<=0;beat_pixel_address<=0;beat_data<=0;
            beat_frame_last<=0;assembly<=0;expected_address<=0;
            assembling<=0;bank<=0;rejected_pixels<=0;
        end else begin
            if(beat_valid && beat_ready) beat_valid<=0;
            if(pixel_valid && pixel_ready) begin
                if(pixel_address>=FRAME_PIXELS) begin
                    assembling<=0;rejected_pixels<=rejected_pixels+1'b1;
                end else if(pixel_address[2:0]==0) begin
                    assembly<={112'd0,pixel_data};expected_address<=pixel_address+1;
                    bank<=pixel_bank;assembling<=1;
                end else if(assembling && pixel_bank==bank && pixel_address==expected_address) begin
                    assembly[pixel_address[2:0]*16 +:16]<=pixel_data;
                    expected_address<=pixel_address+1'b1;
                    if(pixel_address[2:0]==7) begin
                        beat_valid<=1;beat_bank<=bank;
                        beat_pixel_address<={pixel_address[31:3],3'b000};
                        beat_data<={pixel_data,assembly[111:0]};
                        beat_frame_last<=pixel_address==FRAME_PIXELS-1;
                        assembling<=0;
                    end
                end else begin assembling<=0;rejected_pixels<=rejected_pixels+1'b1; end
            end
        end
    end
endmodule
