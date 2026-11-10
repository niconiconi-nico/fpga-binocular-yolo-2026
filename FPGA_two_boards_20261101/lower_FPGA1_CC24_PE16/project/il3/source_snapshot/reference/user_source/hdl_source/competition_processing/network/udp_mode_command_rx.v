// UDP mode command parser for the PH1P uiudp_stack receive interface.
// Commands are exactly two payload bytes, big-endian:
//   00 00..3F : select unified image-processing mode 0..63
//   00 FF     : select the next mode
//   00 FE     : toggle automatic demonstration
module udp_mode_command_rx #(
    parameter [7:0] MAX_MODE = 8'd63
) (
    input  wire       I_clk,
    input  wire       I_rst,
    input  wire       I_udp_valid,
    input  wire [7:0] I_udp_data,
    input  wire [15:0] I_udp_len,

    output reg        O_mode_set_valid,
    output reg  [7:0] O_mode_set,
    output reg        O_mode_set_toggle,
    output reg        O_mode_next,
    output reg        O_mode_next_toggle,
    output reg        O_auto_demo_enable,
    output reg        O_auto_demo_toggle,
    output reg        O_command_error
);
    reg       S_in_packet;
    reg       S_accept_packet;
    reg [1:0] S_byte_index;
    reg [7:0] S_command_msb;

    always @(posedge I_clk or posedge I_rst) begin
        if (I_rst) begin
            S_in_packet          <= 1'b0;
            S_accept_packet      <= 1'b0;
            S_byte_index         <= 2'd0;
            S_command_msb        <= 8'd0;
            O_mode_set_valid     <= 1'b0;
            O_mode_set           <= 8'd0;
            O_mode_set_toggle    <= 1'b0;
            O_mode_next          <= 1'b0;
            O_mode_next_toggle   <= 1'b0;
            O_auto_demo_enable   <= 1'b0;
            O_auto_demo_toggle   <= 1'b0;
            O_command_error      <= 1'b0;
        end else begin
            // These are local one-clock indications.  The toggle outputs are
            // the signals intended for the destination-clock CDC module.
            O_mode_set_valid <= 1'b0;
            O_mode_next      <= 1'b0;
            O_command_error  <= 1'b0;

            if (!I_udp_valid) begin
                S_in_packet     <= 1'b0;
                S_accept_packet <= 1'b0;
                S_byte_index    <= 2'd0;
            end else if (!S_in_packet) begin
                S_in_packet     <= 1'b1;
                S_byte_index    <= 2'd1;
                S_command_msb   <= I_udp_data;
                S_accept_packet <= (I_udp_len == 16'd2);
            end else if (S_byte_index == 2'd1) begin
                S_byte_index <= 2'd2;
                if (!S_accept_packet || (S_command_msb != 8'h00)) begin
                    O_command_error <= 1'b1;
                end else if (I_udp_data <= MAX_MODE) begin
                    O_mode_set        <= I_udp_data;
                    O_mode_set_valid  <= 1'b1;
                    O_mode_set_toggle <= ~O_mode_set_toggle;
                end else if (I_udp_data == 8'hff) begin
                    O_mode_next        <= 1'b1;
                    O_mode_next_toggle <= ~O_mode_next_toggle;
                end else if (I_udp_data == 8'hfe) begin
                    O_auto_demo_enable <= ~O_auto_demo_enable;
                    O_auto_demo_toggle <= ~O_auto_demo_toggle;
                end else begin
                    O_command_error <= 1'b1;
                end
            end
        end
    end
endmodule
