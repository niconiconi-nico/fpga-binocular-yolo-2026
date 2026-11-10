// Common asynchronous assertion, two receiving-clock edges for release.
// No claim about analog PLL reset pulse or vendor hard-IP recovery/removal.
module reset_domain_sync(input wire clk,async_reset,output wire reset);
    (* async_reg="true" *) reg [1:0] release_chain;
    always @(posedge clk or posedge async_reset)
        if(async_reset) release_chain<=2'b11;
        else release_chain<={release_chain[0],1'b0};
    assign reset=release_chain[1];
endmodule
