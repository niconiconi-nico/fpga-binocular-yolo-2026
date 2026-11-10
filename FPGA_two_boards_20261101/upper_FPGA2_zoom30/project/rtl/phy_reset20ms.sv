// Documented YT8511 RESET_N minimum is10ms (local datasheet PDF p22).
// Use20ms of25MHz clocks, not the reference's10.00004ms nominal borderline.
// Asynchronous PLL-lock-loss assertion works even when the clock stops.
// Release is synchronized, then counted; optional settle interval is20ms.
// Physical board rail/clock-tolerance verification remains separate.
module phy_reset20ms #(
    parameter integer CLK_HZ=25000000,
    parameter integer LOW_CYCLES=(CLK_HZ+49)/50,
    parameter integer SETTLE_CYCLES=(CLK_HZ+49)/50
)(
    input wire clk,pll_locked,
    output reg reset_n,output reg ready
);
    wire reset;
    reset_domain_sync release_reset(clk,!pll_locked,reset);
    localparam integer MAX_CYCLES=LOW_CYCLES>SETTLE_CYCLES ? LOW_CYCLES : SETTLE_CYCLES;
    localparam integer CW=$clog2(MAX_CYCLES+1);
    reg [CW-1:0] count;
    reg [1:0] phase;
    always @(posedge clk or posedge reset) begin
        if(reset) begin reset_n<=0;ready<=0;count<=0;phase<=0;end
        else case(phase)
            0: if(count==LOW_CYCLES-1) begin reset_n<=1;count<=0;phase<=1;end
               else count<=count+1'b1;
            1: if(count==SETTLE_CYCLES-1) begin ready<=1;count<=0;phase<=2;end
               else count<=count+1'b1;
            default:;
        endcase
    end
endmodule
