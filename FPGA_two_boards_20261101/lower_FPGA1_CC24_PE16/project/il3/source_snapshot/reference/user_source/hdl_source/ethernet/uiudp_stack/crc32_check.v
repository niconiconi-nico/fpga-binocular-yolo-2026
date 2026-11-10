`timescale 1ns/1ps
// Exact complemented internal CRC state; exported CRC and all cycles unchanged.
module crc32_check(
    input wire reset, clk, CRC32_en, CRC32_init,
    input wire [7:0] data,
    output wire [31:0] CRC_data
);
    reg [31:0] CRC_inverse;
    wire [31:0] CRC_temp;
    assign CRC_temp = ~CRC_inverse;
    wire [7:0] feedback;
    wire [31:0] crc_next;
    assign CRC_data = CRC_temp;
    assign feedback = CRC_temp[31:24] ^ {data[0],data[1],data[2],data[3],data[4],data[5],data[6],data[7]};
    assign crc_next[0] = feedback[0] ^ feedback[6];
    assign crc_next[1] = feedback[1] ^ feedback[7] ^ feedback[0] ^ feedback[6];
    assign crc_next[2] = feedback[2] ^ feedback[1] ^ feedback[7] ^ feedback[0] ^ feedback[6];
    assign crc_next[3] = feedback[3] ^ feedback[2] ^ feedback[1] ^ feedback[7];
    assign crc_next[4] = feedback[4] ^ feedback[3] ^ feedback[2] ^ feedback[0] ^ feedback[6];
    assign crc_next[5] = feedback[5] ^ feedback[4] ^ feedback[3] ^ feedback[1] ^ feedback[7] ^ feedback[0] ^ feedback[6];
    assign crc_next[6] = feedback[6] ^ feedback[5] ^ feedback[4] ^ feedback[2] ^ feedback[1] ^ feedback[7];
    assign crc_next[7] = feedback[7] ^ feedback[5] ^ feedback[3] ^ feedback[2] ^ feedback[0];
    assign crc_next[8] = CRC_temp[0] ^ feedback[4] ^ feedback[3] ^ feedback[1] ^ feedback[0];
    assign crc_next[9] = CRC_temp[1] ^ feedback[5] ^ feedback[4] ^ feedback[2] ^ feedback[1];
    assign crc_next[10] = CRC_temp[2] ^ feedback[5] ^ feedback[3] ^ feedback[2] ^ feedback[0];
    assign crc_next[11] = CRC_temp[3] ^ feedback[4] ^ feedback[3] ^ feedback[1] ^ feedback[0];
    assign crc_next[12] = CRC_temp[4] ^ feedback[5] ^ feedback[4] ^ feedback[2] ^ feedback[1] ^ feedback[0] ^ feedback[6];
    assign crc_next[13] = CRC_temp[5] ^ feedback[6] ^ feedback[5] ^ feedback[3] ^ feedback[2] ^ feedback[1] ^ feedback[7];
    assign crc_next[14] = CRC_temp[6] ^ feedback[7] ^ feedback[6] ^ feedback[4] ^ feedback[3] ^ feedback[2];
    assign crc_next[15] = CRC_temp[7] ^ feedback[7] ^ feedback[5] ^ feedback[4] ^ feedback[3];
    assign crc_next[16] = CRC_temp[8] ^ feedback[5] ^ feedback[4] ^ feedback[0];
    assign crc_next[17] = CRC_temp[9] ^ feedback[6] ^ feedback[5] ^ feedback[1];
    assign crc_next[18] = CRC_temp[10] ^ feedback[7] ^ feedback[6] ^ feedback[2];
    assign crc_next[19] = CRC_temp[11] ^ feedback[7] ^ feedback[3];
    assign crc_next[20] = CRC_temp[12] ^ feedback[4];
    assign crc_next[21] = CRC_temp[13] ^ feedback[5];
    assign crc_next[22] = CRC_temp[14] ^ feedback[0];
    assign crc_next[23] = CRC_temp[15] ^ feedback[1] ^ feedback[0] ^ feedback[6];
    assign crc_next[24] = CRC_temp[16] ^ feedback[2] ^ feedback[1] ^ feedback[7];
    assign crc_next[25] = CRC_temp[17] ^ feedback[3] ^ feedback[2];
    assign crc_next[26] = CRC_temp[18] ^ feedback[4] ^ feedback[3] ^ feedback[0] ^ feedback[6];
    assign crc_next[27] = CRC_temp[19] ^ feedback[5] ^ feedback[4] ^ feedback[1] ^ feedback[7];
    assign crc_next[28] = CRC_temp[20] ^ feedback[6] ^ feedback[5] ^ feedback[2];
    assign crc_next[29] = CRC_temp[21] ^ feedback[7] ^ feedback[6] ^ feedback[3];
    assign crc_next[30] = CRC_temp[22] ^ feedback[7] ^ feedback[4];
    assign crc_next[31] = CRC_temp[23] ^ feedback[5];
    always @(posedge clk or posedge reset)
        if (reset) CRC_inverse <= 32'h00000000;
        else if (CRC32_init) CRC_inverse <= 32'h00000000;
        else if (CRC32_en) CRC_inverse <= ~crc_next;
endmodule
