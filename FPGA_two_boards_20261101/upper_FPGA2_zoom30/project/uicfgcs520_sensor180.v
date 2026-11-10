`timescale 1ns / 1ps

module uicfgcs520_sensor180 #(
    parameter integer CLK_DIV = 16'd239
) (
    input  wire        I_clk,
    input  wire        I_rst_n,
    input  wire        I_ae_req,
    input  wire [15:0] I_ae,
    input  wire [15:0] I_ag,
    output wire        O_cam_scl,
    inout  wire        IO_cam_sda,
    output reg         O_cfg_done,
    output reg         O_ae_cfg_done,
    output reg  [15:0] O_sensor_id,
    output reg         O_sensor_id_ok,
    output reg         O_iic_error
);
    localparam [7:0] CAM_ID = 8'h6c;

    localparam [4:0] ST_IDH_REQ  = 4'd0;
    localparam [4:0] ST_IDH_BUSY = 4'd1;
    localparam [4:0] ST_IDH_DONE = 4'd2;
    localparam [4:0] ST_IDL_REQ  = 4'd3;
    localparam [4:0] ST_IDL_BUSY = 4'd4;
    localparam [4:0] ST_IDL_DONE = 4'd5;
    localparam [4:0] ST_CHECK_ID = 4'd6;
    localparam [4:0] ST_IDLE     = 4'd7;
    localparam [4:0] ST_WR_REQ   = 4'd8;
    localparam [4:0] ST_WR_BUSY  = 4'd9;
    localparam [4:0] ST_WR_DONE  = 4'd10;
    localparam [4:0] ST_ERROR    = 4'd11;
    localparam [4:0] ST_RESET_WAIT = 4'd12;
    localparam integer RESET_WAIT_CYCLES = 119048; // 5 ms at 23.809524 MHz

    reg  [4:0]  state;
    localparam [4:0] ST_ROT_REQ=13, ST_ROT_BUSY=14, ST_ROT_DONE=15;
    reg [1:0] rotate_phase; // read original, write preserved OR66, verify
    reg [7:0] rotate_original, rotate_expected, rotate_readback;
    reg rotate_verified;
    reg         iic_req;
    reg         iic_mode;
    reg  [7:0]  wr_cnt;
    reg  [7:0]  rd_cnt;
    reg  [31:0] wr_data;
    reg  [8:0]  reg_index;
    reg  [16:0] reset_wait_cnt;
    reg         ae_table_active;
    wire        iic_busy;
    wire        iic_bus_error;
    wire [7:0]  rd_data;

    wire [23:0] init_reg_data;
    wire [8:0]  init_reg_size;
    wire [23:0] ae_reg_data;
    wire [8:0]  ae_reg_size;
    wire [23:0] gain_value;
    wire [23:0] selected_reg_data = ae_table_active ? ae_reg_data : init_reg_data;
    wire [8:0]  selected_reg_size = ae_table_active ? ae_reg_size : init_reg_size;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            rotate_phase<=0;rotate_original<=0;rotate_expected<=0;
            rotate_readback<=0;rotate_verified<=0;
            state            <= ST_IDH_REQ;
            iic_req          <= 1'b0;
            iic_mode         <= 1'b1;
            wr_cnt           <= 8'd3;
            rd_cnt           <= 8'd1;
            wr_data          <= 32'd0;
            reg_index        <= 9'd0;
            reset_wait_cnt   <= 17'd0;
            ae_table_active  <= 1'b0;
            O_cfg_done       <= 1'b0;
            O_ae_cfg_done    <= 1'b0;
            O_sensor_id      <= 16'd0;
            O_sensor_id_ok   <= 1'b0;
            O_iic_error      <= 1'b0;
        end else begin
            if (iic_bus_error)
                O_iic_error <= 1'b1;

            case (state)
                ST_IDH_REQ: if (!iic_busy) begin
                    wr_data <= {8'h00, 8'h07, 8'h31, CAM_ID};
                    wr_cnt <= 8'd3;
                    rd_cnt <= 8'd1;
                    iic_mode <= 1'b1;
                    iic_req <= 1'b1;
                    state <= ST_IDH_BUSY;
                end
                ST_IDH_BUSY: if (iic_busy) begin
                    iic_req <= 1'b0;
                    state <= ST_IDH_DONE;
                end
                ST_IDH_DONE: if (!iic_busy) begin
                    O_sensor_id[15:8] <= rd_data;
                    state <= ST_IDL_REQ;
                end
                ST_IDL_REQ: if (!iic_busy) begin
                    wr_data <= {8'h00, 8'h08, 8'h31, CAM_ID};
                    wr_cnt <= 8'd3;
                    rd_cnt <= 8'd1;
                    iic_mode <= 1'b1;
                    iic_req <= 1'b1;
                    state <= ST_IDL_BUSY;
                end
                ST_IDL_BUSY: if (iic_busy) begin
                    iic_req <= 1'b0;
                    state <= ST_IDL_DONE;
                end
                ST_IDL_DONE: if (!iic_busy) begin
                    O_sensor_id[7:0] <= rd_data;
                    state <= ST_CHECK_ID;
                end
                ST_CHECK_ID: begin
                    if ((O_sensor_id == 16'hee4b) ||
                        (O_sensor_id == 16'h9e4b)) begin
                        O_sensor_id_ok <= 1'b1;
                        reg_index <= 9'd0;
                        ae_table_active <= 1'b0;
                        state <= ST_IDLE;
                    end else begin
                        state <= ST_ERROR;
                    end
                end
                ST_IDLE: begin
                    if (!O_cfg_done) begin
                        if (reg_index == init_reg_size) begin
                            O_cfg_done <= 1'b1;
                            O_ae_cfg_done <= 1'b1;
                        end else if(reg_index==9'd164 && !rotate_verified) begin
                            rotate_phase<=0;state<=ST_ROT_REQ;
                        end else begin
                            state <= ST_WR_REQ;
                        end
                    end else if (ae_table_active) begin
                        if (reg_index == ae_reg_size) begin
                            ae_table_active <= 1'b0;
                            O_ae_cfg_done <= 1'b1;
                        end else begin
                            state <= ST_WR_REQ;
                        end
                    end else if (I_ae_req) begin
                        ae_table_active <= 1'b1;
                        O_ae_cfg_done <= 1'b0;
                        reg_index <= 9'd0;
                    end
                end
                ST_WR_REQ: if (!iic_busy) begin
                    wr_data[7:0]   <= CAM_ID;
                    wr_data[15:8]  <= selected_reg_data[23:16];
                    wr_data[23:16] <= selected_reg_data[15:8];
                    wr_data[31:24] <= selected_reg_data[7:0];
                    wr_cnt <= 8'd4;
                    rd_cnt <= 8'd0;
                    iic_mode <= 1'b0;
                    iic_req <= 1'b1;
                    state <= ST_WR_BUSY;
                end
                ST_WR_BUSY: if (iic_busy) begin
                    iic_req <= 1'b0;
                    state <= ST_WR_DONE;
                end
                ST_WR_DONE: if (!iic_busy) begin
                    reg_index <= reg_index + 1'b1;
                    if (!ae_table_active && (reg_index == 9'd0)) begin
                        reset_wait_cnt <= 17'd0;
                        state <= ST_RESET_WAIT;
                    end else begin
                        state <= ST_IDLE;
                    end
                end
                ST_RESET_WAIT: begin
                    if (reset_wait_cnt == RESET_WAIT_CYCLES - 1) begin
                        state <= ST_IDLE;
                    end else begin
                        reset_wait_cnt <= reset_wait_cnt + 1'b1;
                    end
                end
                ST_ROT_REQ: if(!iic_busy) begin
                    wr_data<={rotate_expected,8'h21,8'h32,CAM_ID};
                    wr_cnt<=rotate_phase==1 ? 8'd4 : 8'd3;
                    rd_cnt<=rotate_phase==1 ? 8'd0 : 8'd1;
                    iic_mode<=rotate_phase!=1;
                    iic_req<=1;state<=ST_ROT_BUSY;
                end
                ST_ROT_BUSY: if(iic_busy) begin iic_req<=0;state<=ST_ROT_DONE;end
                ST_ROT_DONE: if(!iic_busy) begin
                    if(O_iic_error || iic_bus_error) begin
                        O_iic_error<=1;state<=ST_ERROR;
                    end else if(rotate_phase==0) begin
                        rotate_original<=rd_data;rotate_expected<=rd_data | 8'h66;
                        rotate_phase<=1;state<=ST_ROT_REQ;
                    end else if(rotate_phase==1) begin
                        rotate_phase<=2;state<=ST_ROT_REQ;
                    end else begin
                        rotate_readback<=rd_data;
                        if(rd_data==rotate_expected) begin rotate_verified<=1;state<=ST_IDLE;end
                        else begin O_iic_error<=1;state<=ST_ERROR;end
                    end
                end
                ST_ERROR: begin
                    iic_req <= 1'b0;
                    O_cfg_done <= 1'b0;
                    O_ae_cfg_done <= 1'b0;
                end
                default: state <= ST_ERROR;
            endcase
        end
    end

    // The original CFG changes these fields on parent rising edges, exactly
    // when uii2c's generated SCL may rise. Actual routed hold was -2.612ns.
    // Transfer the stable transaction bundle at the opposite parent edge.
    // uii2c and its external SCL/SDA timing/table are unchanged.
    reg [31:0] phase_wr_data;
    reg [7:0] phase_wr_cnt,phase_rd_cnt;
    reg phase_req,phase_mode;
    always @(negedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            phase_wr_data<=0;phase_wr_cnt<=0;phase_rd_cnt<=0;
            phase_req<=0;phase_mode<=0;
        end else begin
            phase_wr_data<=wr_data;phase_wr_cnt<=wr_cnt;phase_rd_cnt<=rd_cnt;
            phase_req<=iic_req;phase_mode<=iic_mode;
        end
    end

    // Actual Route5: parent-rising reset release races generated-SCL edges.
    // Assert asynchronously, release ONLY at opposite parent edge, >=21ns
    // before either internal SCL transition. Divider/CFG/table/data unchanged.
    reg i2c_phase_reset_n;
    always @(negedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) i2c_phase_reset_n<=1'b0;
        else i2c_phase_reset_n<=1'b1;
    end

    uii2c #(
        .WMEN_LEN(4),
        .RMEN_LEN(1),
        .CLK_DIV(CLK_DIV)
    ) u_i2c (
        .I_clk(I_clk),
        .I_rstn(i2c_phase_reset_n),
        .O_iic_scl(O_cam_scl),
        .IO_iic_sda(IO_cam_sda),
        .I_wr_data(phase_wr_data),
        .I_wr_cnt(phase_wr_cnt),
        .O_rd_data(rd_data),
        .I_rd_cnt(phase_rd_cnt),
        .I_iic_req(phase_req),
        .I_iic_mode(phase_mode),
        .O_iic_busy(iic_busy),
        .O_iic_bus_error(iic_bus_error),
        .IO_iic_sda_dg()
    );

    // SC520CS true 1280x720@60 mode.  This test keeps the factory 0x89 table
    // but clears register 0x3222 to verify Free-run operation.
    uics520reg_720p60 u_init_regs (
        .REG_INDEX(reg_index),
        .REG_DATA(init_reg_data),
        .REG_SIZE(init_reg_size)
    );

    SC520GainTbl u_gain (
        .I_AG(I_ag),
        .O(gain_value)
    );

    uics520regAE u_ae_regs (
        .REG_INDEX(reg_index),
        .REG_DATA(ae_reg_data),
        .REG_SIZE(ae_reg_size),
        .I_AE(I_ae),
        .I_AG(gain_value)
    );
endmodule
