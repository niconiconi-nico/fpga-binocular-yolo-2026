// Fixed 1280-pixel rows; same vendor mode and latency, depth 512, not 2048.
// This .v wrapper deliberately uses Verilog-compatible simulation checks.
`timescale 1ns/1ps
module blk_mem_gen_awb_delay_signal (
    output [95:0] doa,
    input [95:0] dia,
    input [10:0] addra,
    input wea,clka,
    output [95:0] dob,
    input [10:0] addrb,
    input clkb,
    input [95:0] dib,
    input web
);
    ram_f84573da5ab5 #(
        .DATA_WIDTH_A(96),.ADDR_WIDTH_A(9),.DATA_DEPTH_A(512),
        .DATA_WIDTH_B(96),.ADDR_WIDTH_B(9),.DATA_DEPTH_B(512),
        .REGMODE_A("NOREG"),.REGMODE_B("NOREG"),
        .WRITEMODE_A("NORMAL"),.WRITEMODE_B("READBEFOREWRITE"),
        .RESETMODE_A("ASYNC"),.RESETMODE_B("ASYNC"),
        .INIT_FILE("NONE"),.FILL_ALL("NONE")
    ) ram_f84573da5ab5_Inst (
        .doa(doa),.dia(dia),.addra(addra[8:0]),.wea(wea),.clka(clka),
        .dob(dob),.dib(dib),.addrb(addrb[8:0]),.web(web),.clkb(clkb)
    );
    // synthesis translate_off
    always @(posedge clka) if((^addra !== 1'bx) && addra >= 320) begin
        $display("LINE320_ADDRESS_FAILURE write=%0d",addra); $finish;
    end
    always @(posedge clkb) if((^addrb !== 1'bx) && addrb >= 320) begin
        $display("LINE320_ADDRESS_FAILURE read=%0d",addrb); $finish;
    end
    // synthesis translate_on
endmodule
