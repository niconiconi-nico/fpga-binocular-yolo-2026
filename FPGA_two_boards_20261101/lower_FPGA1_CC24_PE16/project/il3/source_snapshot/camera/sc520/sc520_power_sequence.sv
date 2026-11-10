// Vendor J9 PWDNB active-low power-down. GOOD STA reports 24.074 MHz.
// Conservative counters meet 1 ms low + 5 ms settle up to 25 MHz.
module sc520_power_sequence #(
    parameter integer LOW_CYCLES=25000,
    parameter integer READY_CYCLES=150000
) (
    input wire clk, pll_locked,
    output wire pwdnb, i2c_ready
);
    reg [17:0] count;
    always @(posedge clk or negedge pll_locked)
        if (!pll_locked) count<=0;
        else if (count<READY_CYCLES) count<=count+1'b1;
    assign pwdnb=pll_locked && count>=LOW_CYCLES;
    assign i2c_ready=pll_locked && count>=READY_CYCLES;
endmodule
