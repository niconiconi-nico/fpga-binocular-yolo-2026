// Weight cache, unchanged signed8 coefficient bytes, full 16 KiB.
// NUM_PE=1: il3 scalar variant (one 16 KiB bank), byte-identical behaviour.
// NUM_PE=4 (CC2) / NUM_PE=8 (CC7): four 4 KiB / eight 2 KiB lane banks. The parameter loader writes Cout
// plane c into bank c[1:0] at bank-local offsets; every lane reads the same
// rolling term offset, so one cycle yields the four weights of one output
// group. Read latency stays ERAM read + one output register. The two INT8
// pairs are also emitted in the R10 PE2 packed form
//   {signed9(w1 - sign(w0)), {10{w0[7]}}, w0}  ==  w1*2^18 + w0  (27 bit)
// for the engine's exact two-lanes-per-DSP product.
module v5n_camera_paired_weight_cache #(
    parameter integer NUM_PE=1, TILE_BYTES=16384, ADDR_W=15, CHANNEL_W=10
)(
    input wire clk_i,rst_ni,compute_active_i,compute_bank_i,
    input wire [NUM_PE*ADDR_W-1:0] read_offset_i,
    output wire [NUM_PE*8-1:0] read_weight_o,
    output wire [((NUM_PE/2)>0 ? (NUM_PE/2)*27 : 1)-1:0] read_packed_weight_o,
    input wire [CHANNEL_W-1:0] active_channels_i,
    input wire load_begin_i,load_valid_i,output wire load_ready_o,
    input wire load_bank_i,input wire [3:0] load_lane_i,
    input wire [ADDR_W-1:0] load_offset_i,input wire [7:0] load_data_i,
    input wire load_last_i,output reg [1:0] bank_valid_o
);
    localparam integer BANK_BYTES=TILE_BYTES/NUM_PE;
    localparam integer BW=$clog2(BANK_BYTES);
    wire accept_w=load_valid_i&&load_ready_o;
    assign load_ready_o=!compute_active_i;
    wire [NUM_PE*8-1:0] bank_read;
    reg [NUM_PE*8-1:0] coefficient;
    assign read_weight_o=coefficient;
    always @(posedge clk_i or negedge rst_ni) begin
        if(!rst_ni) begin coefficient<=0;bank_valid_o<=0;end
        else begin
            if(compute_active_i) coefficient<=bank_read;
            if(load_begin_i) bank_valid_o<=0;
            if(accept_w&&load_last_i) bank_valid_o<=1;
        end
    end
    genvar b;
    generate
        for(b=0;b<NUM_PE;b=b+1) begin:G_BANK
            wire we_w=accept_w&&(NUM_PE==1 || load_lane_i==b);
            PH1P_LOGIC_ERAM #(
                .DATA_WIDTH_A(8),.DATA_WIDTH_B(8),.ADDR_WIDTH_A(BW),.ADDR_WIDTH_B(BW),
                .DATA_DEPTH_A(BANK_BYTES),.DATA_DEPTH_B(BANK_BYTES),.MODE("DP"),
                .REGMODE_A("NOREG"),.REGMODE_B("NOREG"),.WRITEMODE_A("READBEFOREWRITE"),
                .WRITEMODE_B("READBEFOREWRITE"),.CLKMODE("ASYNC"),.SSROVERCE("DISABLE"),
                .OREGSET_A("RESET"),.OREGSET_B("RESET"),.RESETMODE_A("ASYNC"),.RESETMODE_B("ASYNC"),
                .ASYNC_RESET_RELEASE_A("ASYNC"),.ASYNC_RESET_RELEASE_B("ASYNC"),
                .ECC_ENCODE("DISABLE"),.ECC_DECODE("DISABLE"),.IMPLEMENT("20K(FAST)"),
                .INIT_FILE("NONE"),.FILL_ALL("NONE")
            ) memory(
                .dia(load_data_i),.addra(load_offset_i[BW-1:0]),.cea(1'b1),.ocea(1'b0),
                .clka(clk_i),.wea(we_w),.rsta(1'b0),.bea(1'b0),
                .dib(8'd0),.addrb(read_offset_i[b*ADDR_W+:BW]),.ceb(1'b1),.oceb(1'b0),
                .clkb(clk_i),.web(1'b0),.rstb(1'b0),.beb(1'b0),
                .ecc_sbiterrinj(1'b0),.ecc_dbiterrinj(1'b0),.doa(),.dob(bank_read[b*8+:8]),
                .ecc_sbiterr(),.ecc_dbiterr());
        end
        if(NUM_PE>=2) begin:G_PACKED
            reg [(NUM_PE/2)*27-1:0] packed_r;
            assign read_packed_weight_o=packed_r;
            integer p;
            always @(posedge clk_i or negedge rst_ni) begin
                if(!rst_ni) packed_r<=0;
                else if(compute_active_i)
                    for(p=0;p<NUM_PE/2;p=p+1)
                        packed_r[p*27+:27]<={$signed({bank_read[(2*p+1)*8+7],bank_read[(2*p+1)*8+:8]})-
                                             $signed({8'd0,bank_read[2*p*8+7]}),
                                             {10{bank_read[2*p*8+7]}},bank_read[2*p*8+:8]};
            end
        end else begin:G_SCALAR
            // Unused by the existing odd-lane scalar multiplier; not a numerical lane.
            assign read_packed_weight_o=0;
        end
    endgenerate
`ifndef SYNTHESIS
    initial if(!((NUM_PE==1&&ADDR_W==15)||((NUM_PE==4||NUM_PE==8||NUM_PE==16)&&ADDR_W>=BW))||!((NUM_PE==16&&TILE_BYTES==32768)||(NUM_PE!=16&&TILE_BYTES==16384)))
        $fatal(1,"weight cache: PE16 requires 16x2 KiB; legacy PE1/4/8 requires 16 KiB");
    always @(posedge clk_i) if(rst_ni&&accept_w&&load_offset_i>=BANK_BYTES)
        $fatal(1,"weight load exceeded physical bank capacity");
    always @(posedge clk_i) if(rst_ni&&accept_w&&(load_lane_i>=NUM_PE||load_bank_i!=0))
        $fatal(1,"weight cache received illegal physical bank/lane");
`endif
endmodule
