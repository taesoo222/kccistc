`timescale 1ns / 1ps

module sr04_controller (
    input        clk,
    input        reset,
    input        start,
    input        echo,
    output       trigger,
    output       done,
    output [8:0] distance
);
    localparam [2:0] IDLE = 0, START = 1, WAIT = 2, COUNT = 3, DISTANCE = 4;
    reg [2:0] n_state, c_state;
    reg run_stop, clear;
    reg trigger_reg, trigger_next;
    reg done_reg, done_next;
    reg [$clog2(58)-1:0] counter_reg, counter_next;
    reg [8:0] distcnt_reg, distcnt_next;
    reg [8:0] distance_reg, distance_next;

    wire w_tick_us;

    assign distance = distance_reg;
    assign trigger = trigger_reg;
    assign done = done_reg;

    tick_us_SR04 U_TICK_US_SR04 (
        .clk       (clk),
        .reset     (reset),
        .i_run_stop(run_stop),
        .clear     (clear),
        .o_tick_us (w_tick_us)
    );

    // fsm control_unit
    always @(posedge clk, posedge reset) begin
        if (reset) begin
            c_state      <= IDLE;
            trigger_reg  <= 0;
            done_reg     <= 0;
            counter_reg  <= 0;
            distcnt_reg  <= 0;
            distance_reg <= 0;
        end else begin
            c_state      <= n_state;
            trigger_reg  <= trigger_next;
            done_reg     <= done_next;
            counter_reg  <= counter_next;
            distcnt_reg  <= distcnt_next;
            distance_reg <= distance_next;
        end
    end

    // next,output
    always @(*) begin
        n_state       = c_state;
        counter_next  = counter_reg;
        run_stop      = 0;
        clear         = 0;
        trigger_next  = trigger_reg;
        done_next     = 0;
        distcnt_next  = distcnt_reg;
        distance_next = distance_reg;
        case (c_state)
            IDLE: begin
                run_stop = 0;
                clear    = 1;
                if (start) begin
                    n_state      = START;
                    counter_next = 0;
                end
            end
            START: begin
                run_stop = 1;
                clear    = 0;
                trigger_next = 1;
                distcnt_next = 0;
                if (w_tick_us) begin
                    counter_next = counter_reg + 1;
                end
                if (counter_reg == 11) begin
                    n_state = WAIT;
                end
            end
            WAIT: begin
                run_stop = 1;
                trigger_next = 0;
                counter_next = 0;
                distcnt_next = 0;
                if (echo) n_state = COUNT;
            end
            COUNT: begin
                run_stop = 1;
                if (!echo) begin
                    done_next = 1;
                    n_state   = DISTANCE;
                end else begin
                    if (w_tick_us) begin
                        if (counter_reg == 57) begin
                            counter_next = 0;
                            distcnt_next = distcnt_reg + 1;
                        end else counter_next = counter_reg + 1;
                    end
                    if (distcnt_reg > (400 - 1)) begin
                        n_state = IDLE;
                    end
                end
            end
            DISTANCE: begin
                distance_next = distcnt_reg;
                counter_next = 0;
                n_state = IDLE;
            end
        endcase
    end
endmodule

module tick_us_SR04 (
    input  clk,
    input  reset,
    input  i_run_stop,
    input  clear,
    output o_tick_us
);
    parameter TICK_COUNT = 100;
    reg [$clog2(TICK_COUNT)-1:0] count_reg;
    reg tick_us_reg;

    assign o_tick_us = tick_us_reg;

    always @(posedge clk, posedge reset) begin
        if (reset | clear) begin
            count_reg   <= 0;
            tick_us_reg <= 0;
        end else begin
            if (i_run_stop) begin
                count_reg <= count_reg + 1;
                if (count_reg == (TICK_COUNT - 1)) begin
                    tick_us_reg <= 1;
                    count_reg   <= 0;
                end else begin
                    tick_us_reg <= 0;
                end
            end
        end
    end

endmodule

