// physical_friendly_v1 fixed-role synchronous feature ERAM.
// IFM A/B: halo writes only; executor reads only. OFM: executor writes only,
// writer reads only. No destination bank selector or IFM/OFM data crossbar.
module v5n_feature_tile_store_physical_friendly_eram #(
    parameter integer TILE_BYTES=16384,
    parameter integer ADDR_W=14
)(
    input wire clk_i,input wire compute_active_i,input wire source_bank_i,
    input wire [ADDR_W-1:0] source_addr_i,output wire [7:0] source_data_o,
    input wire destination_write_enable_i,
    input wire [ADDR_W-1:0] destination_write_addr_i,
    input wire [7:0] destination_write_data_i,
    input wire store_active_i,input wire [ADDR_W-1:0] store_read_addr_i,
    output wire [7:0] store_read_data_o,
    input wire dma_valid_i,output wire dma_ready_o,input wire dma_bank_i,
    input wire [ADDR_W-1:0] dma_addr_i,input wire [7:0] dma_data_i,
    output wire ownership_error_o
);
    assign ownership_error_o=compute_active_i && store_active_i;
    assign dma_ready_o=!(compute_active_i && source_bank_i==dma_bank_i) &&
                       !ownership_error_o;
    wire [7:0] read_port[0:2];
    assign source_data_o=source_bank_i ? read_port[1] : read_port[0];
    assign store_read_data_o=read_port[2];
    genvar bank;
    generate for(bank=0;bank<3;bank=bank+1) begin:G_BANK
        wire do_compute_write;
        wire do_dma_write;
        wire [ADDR_W-1:0] read_addr,write_addr;
        wire [7:0] write_data;
        if(bank<2)begin:G_IFM
            assign read_addr=source_addr_i;
            assign write_addr=dma_addr_i;
            assign write_data=dma_data_i;
            assign do_compute_write=1'b0;
            assign do_dma_write=dma_valid_i && dma_ready_o && dma_bank_i==bank;
        end else begin:G_OFM
            assign read_addr=store_read_addr_i;
            assign write_addr=destination_write_addr_i;
            assign write_data=destination_write_data_i;
            assign do_compute_write=compute_active_i && !ownership_error_o &&
                                    destination_write_enable_i;
            assign do_dma_write=1'b0;
        end
        PH1P_LOGIC_ERAM #(
            .DATA_WIDTH_A(8),.DATA_WIDTH_B(8),.ADDR_WIDTH_A(ADDR_W),.ADDR_WIDTH_B(ADDR_W),
            .DATA_DEPTH_A(TILE_BYTES),.DATA_DEPTH_B(TILE_BYTES),.MODE("DP"),
            .REGMODE_A("NOREG"),.REGMODE_B("NOREG"),
            .WRITEMODE_A("READBEFOREWRITE"),.WRITEMODE_B("READBEFOREWRITE"),
            .CLKMODE("ASYNC"),.SSROVERCE("DISABLE"),.OREGSET_A("RESET"),.OREGSET_B("RESET"),
            .RESETMODE_A("ASYNC"),.RESETMODE_B("ASYNC"),
            .ASYNC_RESET_RELEASE_A("ASYNC"),.ASYNC_RESET_RELEASE_B("ASYNC"),
            .ECC_ENCODE("DISABLE"),.ECC_DECODE("DISABLE"),.IMPLEMENT("20K(FAST)"),
            .INIT_FILE("NONE"),.FILL_ALL("NONE")
        ) memory(
            .dia(8'd0),.addra(read_addr),.cea(1'b1),.ocea(1'b0),.clka(clk_i),
            .wea(1'b0),.rsta(1'b0),.bea(1'b0),.dib(write_data),.addrb(write_addr),
            .ceb(1'b1),.oceb(1'b0),.clkb(clk_i),.web(do_compute_write||do_dma_write),
            .rstb(1'b0),.beb(1'b0),.ecc_sbiterrinj(1'b0),.ecc_dbiterrinj(1'b0),
            .doa(read_port[bank]),.dob(),.ecc_sbiterr(),.ecc_dbiterr());
    end endgenerate
endmodule
