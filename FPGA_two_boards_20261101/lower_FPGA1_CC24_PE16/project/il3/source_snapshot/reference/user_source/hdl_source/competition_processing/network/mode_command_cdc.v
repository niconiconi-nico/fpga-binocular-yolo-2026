// Transfers the low-rate UDP control events into the image-processing clock
// domain.  Source data must remain stable until the next event; this is true
// for udp_mode_command_rx, whose mode and auto-demo registers are retained.
module mode_command_cdc (
    input  wire       I_src_mode_set_toggle,
    input  wire [7:0] I_src_mode_set,
    input  wire       I_src_mode_next_toggle,
    input  wire       I_src_auto_demo_toggle,
    input  wire       I_src_auto_demo_enable,

    input  wire       I_dst_clk,
    input  wire       I_dst_rst_n,
    output reg        O_mode_set_valid,
    output reg  [7:0] O_mode_set,
    output reg        O_manual_next,
    output reg        O_auto_demo_enable
);
    (* ASYNC_REG = "TRUE" *) reg S_mode_set_toggle_meta;
    (* ASYNC_REG = "TRUE" *) reg S_mode_set_toggle_sync;
    reg S_mode_set_toggle_pipe;
    reg S_mode_set_toggle_seen;

    (* ASYNC_REG = "TRUE" *) reg S_mode_next_toggle_meta;
    (* ASYNC_REG = "TRUE" *) reg S_mode_next_toggle_sync;
    reg S_mode_next_toggle_pipe;
    reg S_mode_next_toggle_seen;

    (* ASYNC_REG = "TRUE" *) reg S_auto_toggle_meta;
    (* ASYNC_REG = "TRUE" *) reg S_auto_toggle_sync;
    reg S_auto_toggle_pipe;
    reg S_auto_toggle_seen;

    (* ASYNC_REG = "TRUE" *) reg [7:0] S_mode_set_meta;
    reg [7:0] S_mode_set_sync;
    reg [7:0] S_mode_set_pipe;

    (* ASYNC_REG = "TRUE" *) reg S_auto_enable_meta;
    reg S_auto_enable_sync;
    reg S_auto_enable_pipe;

    always @(posedge I_dst_clk or negedge I_dst_rst_n) begin
        if (!I_dst_rst_n) begin
            S_mode_set_toggle_meta  <= 1'b0;
            S_mode_set_toggle_sync  <= 1'b0;
            S_mode_set_toggle_pipe  <= 1'b0;
            S_mode_set_toggle_seen  <= 1'b0;
            S_mode_next_toggle_meta <= 1'b0;
            S_mode_next_toggle_sync <= 1'b0;
            S_mode_next_toggle_pipe <= 1'b0;
            S_mode_next_toggle_seen <= 1'b0;
            S_auto_toggle_meta      <= 1'b0;
            S_auto_toggle_sync      <= 1'b0;
            S_auto_toggle_pipe      <= 1'b0;
            S_auto_toggle_seen      <= 1'b0;
            S_mode_set_meta         <= 8'd0;
            S_mode_set_sync         <= 8'd0;
            S_mode_set_pipe         <= 8'd0;
            S_auto_enable_meta      <= 1'b0;
            S_auto_enable_sync      <= 1'b0;
            S_auto_enable_pipe      <= 1'b0;
            O_mode_set_valid        <= 1'b0;
            O_mode_set              <= 8'd0;
            O_manual_next           <= 1'b0;
            O_auto_demo_enable      <= 1'b0;
        end else begin
            S_mode_set_toggle_meta  <= I_src_mode_set_toggle;
            S_mode_set_toggle_sync  <= S_mode_set_toggle_meta;
            S_mode_set_toggle_pipe  <= S_mode_set_toggle_sync;
            S_mode_next_toggle_meta <= I_src_mode_next_toggle;
            S_mode_next_toggle_sync <= S_mode_next_toggle_meta;
            S_mode_next_toggle_pipe <= S_mode_next_toggle_sync;
            S_auto_toggle_meta      <= I_src_auto_demo_toggle;
            S_auto_toggle_sync      <= S_auto_toggle_meta;
            S_auto_toggle_pipe      <= S_auto_toggle_sync;

            S_mode_set_meta    <= I_src_mode_set;
            S_mode_set_sync    <= S_mode_set_meta;
            S_mode_set_pipe    <= S_mode_set_sync;
            S_auto_enable_meta <= I_src_auto_demo_enable;
            S_auto_enable_sync <= S_auto_enable_meta;
            S_auto_enable_pipe <= S_auto_enable_sync;

            O_mode_set_valid <= 1'b0;
            O_manual_next    <= 1'b0;

            if (S_mode_set_toggle_pipe != S_mode_set_toggle_seen) begin
                S_mode_set_toggle_seen <= S_mode_set_toggle_pipe;
                O_mode_set             <= S_mode_set_pipe;
                O_mode_set_valid       <= 1'b1;
            end

            if (S_mode_next_toggle_pipe != S_mode_next_toggle_seen) begin
                S_mode_next_toggle_seen <= S_mode_next_toggle_pipe;
                O_manual_next           <= 1'b1;
            end

            if (S_auto_toggle_pipe != S_auto_toggle_seen) begin
                S_auto_toggle_seen <= S_auto_toggle_pipe;
                O_auto_demo_enable <= S_auto_enable_pipe;
            end
        end
    end
endmodule
