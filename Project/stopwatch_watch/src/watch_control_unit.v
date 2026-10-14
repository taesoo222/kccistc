`timescale 1ns / 1ps
module watch_control_unit (
    input clk,
    input reset,
    input i_min,  //btn_U
    input i_mode,  //btn_D
    input i_hour,  //btn_L
    input i_sec,  //btn_R
    input i_sw_2,
    input i_sw_1,
    output o_default,
    output o_min,
    output o_mode,
    output o_hour,
    output o_sec
);
    parameter DEFAULT = 3'b000; 
    parameter SET = 3'b001;
    parameter MIN = 3'b010;
    parameter MODE = 3'b011;
    parameter HOUR = 3'b100;
    parameter SEC = 3'b101;

    reg [2:0] c_state, n_state;
    reg default_reg, default_next;
    reg min_reg, min_next;
    reg mode_reg, mode_next;
    reg hour_reg, hour_next;
    reg sec_reg, sec_next;

    assign o_default = default_reg;
    assign o_min = min_reg;
    assign o_mode = mode_reg;
    assign o_hour = hour_reg;
    assign o_sec = sec_reg;

    wire i_sw = i_sw_2 & i_sw_1;

    // state register
    always @(posedge clk, posedge reset) begin
        if (reset) begin
            c_state     <= DEFAULT;
            default_reg <= 1'b0;
            min_reg     <= 1'b0;
            mode_reg    <= 1'b0;
            hour_reg    <= 1'b0;
            sec_reg     <= 1'b0;
        end else begin
            c_state     <= n_state;
            default_reg <= default_next;
            min_reg     <= min_next;
            mode_reg    <= mode_next;
            hour_reg    <= hour_next;
            sec_reg     <= sec_next;
        end
    end

    // next CL
    always @(*) begin
        n_state      = c_state;
        default_next = default_reg;
        min_next     = min_reg;
        mode_next    = mode_reg;
        hour_next    = hour_reg;
        sec_next     = sec_reg;
        case (c_state)
            DEFAULT: begin
                default_next = 1'b1;
                min_next     = 1'b0;
                hour_next    = 1'b0;
                sec_next     = 1'b0;
                if (i_sw) n_state = SET;
                else n_state = c_state;
            end
            SET: begin
                default_next = 1'b0;
                min_next = 1'b0;
                hour_next = 1'b0;
                sec_next = 1'b0;
                if (!i_sw) n_state = DEFAULT;
                else if (i_min) n_state = MIN;
                else if (i_mode) n_state = MODE;
                else if (i_hour) n_state = HOUR;
                else if (i_sec) n_state = SEC;
                else n_state = c_state;
            end
            MIN: begin
                min_next = 1'b1;
                n_state  = SET;
            end
            MODE: begin
                mode_next = ~mode_reg;
                n_state   = SET;
            end
            HOUR: begin
                hour_next = 1'b1;
                n_state   = SET;
            end
            SEC: begin
                sec_next = 1'b1;
                n_state  = SET;
            end
        endcase
    end
endmodule