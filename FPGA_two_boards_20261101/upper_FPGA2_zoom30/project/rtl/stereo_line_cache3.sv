// Eight logical row banks:2 cameras x4 banks, three-row prefetch lead.
// DDR writes128-bit beats; pixel side reads a block then selects one16-bit
// lane. Completion metadata is bundled with a two-FF toggle crossing.
// Producer may only refill a line bank after display has consumed that row;
// stereo_display_reader enforces alternating requests originating in pixel clk.
// CLAUDE Z28D (2026-11-01, area): the per-line frame ids are kept and compared on their low IDW=16 bits (was 32). Every
// line bank is refilled for each displayed frame, so a stored id is a few frames old at most; a false match needs an id
// difference that is a non-zero multiple of 65536 between the stored line and the wanted frame.
module stereo_line_cache3(
    input wire ddr_clk,pixel_clk,rst,
    input wire cache_write,cache_camera,input wire [1:0] cache_bank,input wire [7:0] cache_beat,
    input wire [127:0] cache_data,
    input wire line_done,input wire [1:0] done_bank,input wire [9:0] done_row,
    input wire [31:0] done_local_id,done_remote_id,
    input wire local_request,remote_request,input wire [9:0] wanted_row,
    input wire [10:0] local_x,remote_x,
    input wire [31:0] wanted_local_id,wanted_remote_id,
    output reg [15:0] local_pixel,remote_pixel,
    output reg [23:0] local_rgb888,
    output reg local_valid,remote_valid,
    input wire [9:0] diagnostic_row,
    output wire [3:0] diagnostic_known,diagnostic_row_match,
    output wire [3:0] diagnostic_local_id_match,diagnostic_remote_id_match
);
    // Concatenated bank bit avoids a read-time mux across independent RAMs.
    // Only addresses {bank,0..159} are used; holes are never made valid.
    // Exact vendor annotation syntax also used by udp_pkg_buf.v.
    reg [127:0] lmem[0:1023]; /* fehdl force_ram=1, ram_style="bram" */
    reg [127:0] rmem[0:1023]; /* fehdl force_ram=1, ram_style="bram" */
    reg [3:0] done_toggle;
    localparam integer IDW=16;
    reg [9:0] row_tag[0:3];reg [IDW-1:0] lid[0:3],rid[0:3];
    (* async_reg="true" *) reg [3:0] ds1,ds2;
    reg [3:0] seen,known;
    reg [9:0] pixel_row_tag[0:3];reg [IDW-1:0] pixel_lid[0:3],pixel_rid[0:3];
    wire [IDW-1:0] wlid=wanted_local_id[IDW-1:0],wrid=wanted_remote_id[IDW-1:0];
    reg [127:0] lword;reg[127:0] rword;reg [2:0] lx,rx;
    reg lv,rv;
    assign diagnostic_known=known;
    assign diagnostic_row_match={pixel_row_tag[3]==diagnostic_row,pixel_row_tag[2]==diagnostic_row,pixel_row_tag[1]==diagnostic_row,pixel_row_tag[0]==diagnostic_row};
    assign diagnostic_local_id_match={pixel_lid[3]==wlid,pixel_lid[2]==wlid,pixel_lid[1]==wlid,pixel_lid[0]==wlid};
    assign diagnostic_remote_id_match={pixel_rid[3]==wrid,pixel_rid[2]==wrid,pixel_rid[1]==wrid,pixel_rid[0]==wrid};
    wire ddr_reset,pixel_reset;
    reset_domain_sync ddr_release(ddr_clk,rst,ddr_reset);
    reset_domain_sync pixel_release(pixel_clk,rst,pixel_reset);
    integer b;
    always @(posedge ddr_clk) if(cache_write && cache_beat<160) begin
        if(!cache_camera) lmem[{cache_bank,cache_beat}]<=cache_data;
        if(cache_camera) rmem[{cache_bank,cache_beat}]<=cache_data[127:0];
    end
    always @(posedge ddr_clk or posedge ddr_reset) begin
        if(ddr_reset) begin
            done_toggle<=0;for(b=0;b<4;b=b+1) begin row_tag[b]<=0;lid[b]<=0;rid[b]<=0;end
        end else if(line_done) begin
            row_tag[done_bank]<=done_row;lid[done_bank]<=done_local_id[IDW-1:0];rid[done_bank]<=done_remote_id[IDW-1:0];
            done_toggle[done_bank]<=~done_toggle[done_bank];
        end
    end
    // RAM output registers deliberately have no reset; valid gates all data.
    always @(posedge pixel_clk) begin
        if(local_request && local_x<1280)
            lword<=lmem[{wanted_row[1:0],local_x[10:3]}];
        if(remote_request && remote_x<1280)
            rword<=rmem[{wanted_row[1:0],remote_x[10:3]}];
        lx<=local_x[2:0];rx<=remote_x[2:0];
        local_rgb888<={lword[lx*16+11+:5],lword[lx*16+13+:3],lword[lx*16+5+:6],lword[lx*16+9+:2],lword[lx*16+:5],lword[lx*16+2+:3]};
        local_pixel<=lword[lx*16+:16];
        remote_pixel<=rword[rx*16+:16];
    end
    always @(posedge pixel_clk or posedge pixel_reset) begin
        if(pixel_reset) begin
            ds1<=0;ds2<=0;seen<=0;known<=0;lv<=0;rv<=0;local_valid<=0;remote_valid<=0;
            for(b=0;b<4;b=b+1) begin pixel_row_tag[b]<=0;pixel_lid[b]<=0;pixel_rid[b]<=0;end
        end else begin
            ds1<=done_toggle;ds2<=ds1;
            for(b=0;b<4;b=b+1) if(ds2[b]!=seen[b]) begin
                seen[b]<=ds2[b];known[b]<=1;
                pixel_row_tag[b]<=row_tag[b];pixel_lid[b]<=lid[b];pixel_rid[b]<=rid[b];
            end
            lv<=local_request && local_x<1280 && known[wanted_row[1:0]] &&
                pixel_row_tag[wanted_row[1:0]]==wanted_row && pixel_lid[wanted_row[1:0]]==wlid;
            rv<=remote_request && remote_x<1280 && known[wanted_row[1:0]] &&
                pixel_row_tag[wanted_row[1:0]]==wanted_row && pixel_rid[wanted_row[1:0]]==wrid;
            local_valid<=lv;remote_valid<=rv;
        end
    end
endmodule
