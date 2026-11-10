`timescale 1ns / 1ns
// Derived from MiLianKe uii2c revision 1.1 (2022/12/23), Copyright (c)
// MiLianKe, all rights reserved. Original reference remains immutable.
// Camera branch adaptation: preserve divider, wire timing, state/byte math
// and reset behavior; replace divided-clock FFs with parent-clock enables.
module uii2c #(
    parameter integer WMEN_LEN = 0,
    parameter integer RMEN_LEN = 0,
    parameter integer CLK_DIV = 499
)(
    input wire I_clk, input wire I_rstn,
    output reg O_iic_scl = 1'b0, inout wire IO_iic_sda,
    input wire [WMEN_LEN*8-1:0] I_wr_data, input wire [7:0] I_wr_cnt,
    output reg [RMEN_LEN*8-1:0] O_rd_data = 0,
    input wire [7:0] I_rd_cnt, input wire I_iic_req, input wire I_iic_mode,
    output reg O_iic_busy = 1'b0, output reg O_iic_bus_error,
    output reg IO_iic_sda_dg
);
    localparam IDLE=0, START=1, W_WAIT=2, W_ACK=3,
               R_WAIT=4, R_ACK=5, STOP1=6, STOP2=7;
    localparam SCL_DIV=CLK_DIV/2, OFFSET=SCL_DIV-SCL_DIV/4;
    reg [2:0] IIC_S=0;
    reg [15:0] clkdiv=0;
    reg scl_r=1, sda_o=0, scl_clk=0;
    reg [7:0] sda_r=0, sda_i_r=0, wcnt=0, rcnt=0;
    reg [2:0] bcnt=0;
    reg rd_req=0;
    wire sda_i=IO_iic_sda;
    // These selects describe the original divider's NEXT edge, using old
    // divider values, so all enabled FFs consume the original pre-edge state.
    wire scl_rise_ce=(clkdiv>=SCL_DIV) && !scl_clk;
    wire scl_fall_ce=(clkdiv>=SCL_DIV) && scl_clk;
    assign IO_iic_sda=(sda_o==1'b0) ? 1'b0 : 1'bz;
    always @(posedge I_clk)
        if(clkdiv<SCL_DIV) clkdiv<=clkdiv+1'b1;
        else begin clkdiv<=0; scl_clk<=!scl_clk; end
    always @(posedge I_clk)
        O_iic_scl<=(clkdiv==OFFSET) ? scl_r : O_iic_scl;
    always @(posedge I_clk) IO_iic_sda_dg<=sda_i;
    always @(*)
        if(IIC_S==IDLE || IIC_S==STOP1 || IIC_S==STOP2) scl_r<=1;
        else scl_r<=scl_clk;
    always @(*)
        if(IIC_S==START || IIC_S==STOP1 || (IIC_S==R_ACK && rcnt!=I_rd_cnt)) sda_o<=0;
        else if(IIC_S==W_WAIT) sda_o<=sda_r[7];
        else sda_o<=1;
    always @(posedge I_clk) if(scl_rise_ce) begin
        if(IIC_S==W_ACK || IIC_S==START) begin
            sda_r<=I_wr_data[wcnt*8 +: 8];
            if(rd_req) sda_r<={I_wr_data[7:1],1'b1};
        end else if(IIC_S==W_WAIT) sda_r<={sda_r[6:0],1'b1};
    end
    always @(posedge I_clk) if(scl_fall_ce) begin
        if(IIC_S==R_WAIT) sda_i_r<={sda_i_r[6:0],sda_i};
        else if(IIC_S==R_ACK) O_rd_data[(rcnt-1'b1)*8 +: 8]<=sda_i_r;
        else if(IIC_S==IDLE) sda_i_r<=0;
    end
    always @(posedge I_clk or negedge I_rstn)
        if(!I_rstn) O_iic_busy<=0;
        else if(scl_rise_ce) begin
            if(I_iic_req || rd_req || O_iic_bus_error) O_iic_busy<=1;
            else if(IIC_S==IDLE) O_iic_busy<=0;
        end
    always @(posedge I_clk or negedge I_rstn)
        if(!I_rstn) O_iic_bus_error<=0;
        else if(scl_fall_ce) begin
            if(IIC_S==W_ACK && sda_i==1'b1) O_iic_bus_error<=1;
            else if(I_iic_req==0) O_iic_bus_error<=0;
        end
    always @(posedge I_clk or negedge I_rstn)
        if(!I_rstn) begin wcnt<=0; rcnt<=0; rd_req<=0; IIC_S<=IDLE; end
        else if(scl_rise_ce) begin
            case(IIC_S)
                IDLE: if(I_iic_req || rd_req) IIC_S<=START;
                      else begin wcnt<=0; rcnt<=0; end
                START: begin bcnt<=7; IIC_S<=W_WAIT; end
                W_WAIT: if(bcnt>0) bcnt<=bcnt-1'b1;
                        else begin wcnt<=wcnt+1'b1; IIC_S<=W_ACK; end
                W_ACK: begin
                    if(wcnt<I_wr_cnt) begin bcnt<=7; IIC_S<=W_WAIT; end
                    else if(I_rd_cnt>0) begin
                        if(!rd_req && I_iic_mode) begin rd_req<=1; IIC_S<=IDLE; end
                        else IIC_S<=R_WAIT;
                        bcnt<=7;
                    end else IIC_S<=STOP1;
                end
                R_WAIT: begin
                    rd_req<=0; bcnt<=bcnt-1'b1;
                    if(bcnt==0) begin rcnt<=(rcnt<I_rd_cnt) ? rcnt+1'b1 : rcnt; IIC_S<=R_ACK; end
                end
                R_ACK: begin bcnt<=7; IIC_S<=(rcnt<I_rd_cnt) ? R_WAIT : STOP1; end
                STOP1: begin rd_req<=0; IIC_S<=STOP2; end
                STOP2: IIC_S<=IDLE;
                default: IIC_S<=IDLE;
            endcase
        end
endmodule
