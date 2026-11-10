// PH1P ERAM-backed two-bank feature tile store.
//
// Compute must use distinct source/destination banks, as required by the
// existing ping-pong tile contract. Port A reads the source tile and port B
// writes the destination tile. A destination read is permitted while that
// bank is not being written; transaction scheduling must otherwise bypass it.
// This explicit primitive replaces the former 16 KiB byte arrays that TD
// implemented as distributed RAM LUTs.
module v5n_feature_tile_store_eram #(
    parameter integer TILE_BYTES = 16384,
    parameter integer ADDR_W = 14
) (
    input wire clk_i, input wire compute_active_i,
    input wire source_bank_i, input wire [ADDR_W-1:0] source_addr_i, output wire [7:0] source_data_o,
    input wire destination_bank_i, input wire [ADDR_W-1:0] destination_read_addr_i, output wire [7:0] destination_read_data_o,
    input wire destination_write_enable_i, input wire [ADDR_W-1:0] destination_write_addr_i, input wire [7:0] destination_write_data_i,
    input wire dma_valid_i, output wire dma_ready_o, input wire dma_bank_i, input wire [ADDR_W-1:0] dma_addr_i, input wire [7:0] dma_data_i
);
    wire [7:0] bank0_porta, bank0_portb, bank1_porta, bank1_portb;
    wire bank0_write = (!compute_active_i && dma_valid_i && !dma_bank_i) ||
                       (compute_active_i && destination_write_enable_i && !destination_bank_i);
    wire bank1_write = (!compute_active_i && dma_valid_i && dma_bank_i) ||
                       (compute_active_i && destination_write_enable_i && destination_bank_i);
    wire [ADDR_W-1:0] bank0_waddr = !compute_active_i ? dma_addr_i : destination_write_addr_i;
    wire [ADDR_W-1:0] bank1_waddr = !compute_active_i ? dma_addr_i : destination_write_addr_i;
    wire [7:0] write_data = !compute_active_i ? dma_data_i : destination_write_data_i;
    // The scheduler keeps source and destination in opposite banks during a
    // compute tile. This selects two independent true-dual-port macro ports.
    wire [ADDR_W-1:0] bank0_raddr = source_bank_i ? destination_read_addr_i : source_addr_i;
    wire [ADDR_W-1:0] bank1_raddr = source_bank_i ? source_addr_i : destination_read_addr_i;
    assign dma_ready_o = !compute_active_i;
    assign source_data_o = source_bank_i ? bank1_porta : bank0_porta;
    assign destination_read_data_o = destination_bank_i ? bank1_porta : bank0_porta;

    PH1P_LOGIC_ERAM #(
        .DATA_WIDTH_A(8), .DATA_WIDTH_B(8), .ADDR_WIDTH_A(ADDR_W), .ADDR_WIDTH_B(ADDR_W),
        .DATA_DEPTH_A(TILE_BYTES), .DATA_DEPTH_B(TILE_BYTES), .MODE("DP"),
        .REGMODE_A("NOREG"), .REGMODE_B("NOREG"), .WRITEMODE_A("READBEFOREWRITE"), .WRITEMODE_B("READBEFOREWRITE"),
        .CLKMODE("ASYNC"), .SSROVERCE("DISABLE"), .OREGSET_A("RESET"), .OREGSET_B("RESET"),
        .RESETMODE_A("ASYNC"), .RESETMODE_B("ASYNC"), .ASYNC_RESET_RELEASE_A("ASYNC"), .ASYNC_RESET_RELEASE_B("ASYNC"),
        .ECC_ENCODE("DISABLE"), .ECC_DECODE("DISABLE"), .IMPLEMENT("20K(FAST)"), .INIT_FILE("NONE"), .FILL_ALL("NONE")
    ) bank0 (.dia(8'd0), .addra(bank0_raddr), .cea(1'b1), .ocea(1'b0), .clka(clk_i), .wea(1'b0), .rsta(1'b0), .bea(1'b0),
             .dib(write_data), .addrb(bank0_waddr), .ceb(1'b1), .oceb(1'b0), .clkb(clk_i), .web(bank0_write), .rstb(1'b0), .beb(1'b0),
             .ecc_sbiterrinj(1'b0), .ecc_dbiterrinj(1'b0), .doa(bank0_porta), .dob(bank0_portb), .ecc_sbiterr(), .ecc_dbiterr());
    PH1P_LOGIC_ERAM #(
        .DATA_WIDTH_A(8), .DATA_WIDTH_B(8), .ADDR_WIDTH_A(ADDR_W), .ADDR_WIDTH_B(ADDR_W),
        .DATA_DEPTH_A(TILE_BYTES), .DATA_DEPTH_B(TILE_BYTES), .MODE("DP"),
        .REGMODE_A("NOREG"), .REGMODE_B("NOREG"), .WRITEMODE_A("READBEFOREWRITE"), .WRITEMODE_B("READBEFOREWRITE"),
        .CLKMODE("ASYNC"), .SSROVERCE("DISABLE"), .OREGSET_A("RESET"), .OREGSET_B("RESET"),
        .RESETMODE_A("ASYNC"), .RESETMODE_B("ASYNC"), .ASYNC_RESET_RELEASE_A("ASYNC"), .ASYNC_RESET_RELEASE_B("ASYNC"),
        .ECC_ENCODE("DISABLE"), .ECC_DECODE("DISABLE"), .IMPLEMENT("20K(FAST)"), .INIT_FILE("NONE"), .FILL_ALL("NONE")
    ) bank1 (.dia(8'd0), .addra(bank1_raddr), .cea(1'b1), .ocea(1'b0), .clka(clk_i), .wea(1'b0), .rsta(1'b0), .bea(1'b0),
             .dib(write_data), .addrb(bank1_waddr), .ceb(1'b1), .oceb(1'b0), .clkb(clk_i), .web(bank1_write), .rstb(1'b0), .beb(1'b0),
             .ecc_sbiterrinj(1'b0), .ecc_dbiterrinj(1'b0), .doa(bank1_porta), .dob(bank1_portb), .ecc_sbiterr(), .ecc_dbiterr());
endmodule
