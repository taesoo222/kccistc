`timescale 1ns / 1ps

module stopwatch_data_path #(
    parameter MSEC_WIDTH = 7,
    SEC_WIDTH = 6,
    MIN_WIDTH = 6,
    HOUR_WIDTH = 5
) (
    input                     clk,
    input                     reset,
    input                     run,
    input                     clear,
    input                     mode,
    output [MSEC_WIDTH-1 : 0] msec_count,
    output [ SEC_WIDTH-1 : 0] sec_count,
    output [ MIN_WIDTH-1 : 0] min_count,
    output [HOUR_WIDTH-1 : 0] hour_count
);
    wire w_tick_100hz, w_tick_sec, w_tick_min, w_tick_hour;

    tick_gen_100hz_stopwatch U_TICK_GEN_100hz (
        .clk(clk),
        .reset(reset),
        .o_tick(w_tick_100hz)
    );
    time_counter_stopwatch #(
        .BIT_WIDTH(MSEC_WIDTH),
        .TIMES(100)
    ) U_MSEC_COUNTER (
        .clk       (clk),
        .reset     (reset),
        .i_tick    (w_tick_100hz),
        .i_run     (run),
        .i_clear   (clear),
        .i_mode    (mode),
        .time_count(msec_count),
        .o_tick    (w_tick_sec)
    );
    time_counter_stopwatch #(
        .BIT_WIDTH(SEC_WIDTH),
        .TIMES(60)
    ) U_SEC_COUNTER (
        .clk       (clk),
        .reset     (reset),
        .i_tick    (w_tick_sec),
        .i_run     (run),
        .i_clear   (clear),
        .i_mode    (mode),
        .time_count(sec_count),
        .o_tick    (w_tick_min)
    );
    time_counter_stopwatch #(
        .BIT_WIDTH(MIN_WIDTH),
        .TIMES(60)
    ) U_MIN_COUNTER (
        .clk       (clk),
        .reset     (reset),
        .i_tick    (w_tick_min),
        .i_run     (run),
        .i_clear   (clear),
        .i_mode    (mode),
        .time_count(min_count),
        .o_tick    (w_tick_hour)
    );
    time_counter_stopwatch #(
        .BIT_WIDTH(HOUR_WIDTH),
        .TIMES(24)
    ) U_HOUR_COUNTER (
        .clk       (clk),
        .reset     (reset),
        .i_tick    (w_tick_hour),
        .i_run     (run),
        .i_clear   (clear),
        .i_mode    (mode),
        .time_count(hour_count),
        .o_tick    ()
    );
endmodule

module tick_gen_100hz_stopwatch (
    input  clk,
    input  reset,
    output o_tick
);
    parameter F_COUNT = 1_000_000;  //for 100hz(10ms) 

    reg tick_reg;
    reg [$clog2(F_COUNT)-1:0] count_reg;

    assign o_tick = tick_reg;

    always @(posedge clk, posedge reset) begin
        if (reset) begin
            count_reg <= 0;
            tick_reg  <= 0;
        end else begin
            if (count_reg == F_COUNT - 1) begin
                tick_reg  <= 1;
                count_reg <= 0;
            end else begin
                count_reg <= count_reg + 1;
                tick_reg  <= 0;
            end
        end
    end
endmodule

module time_counter_stopwatch #(
    parameter BIT_WIDTH = 7,
    TIMES = 100
) (
    input                     clk,
    input                     reset,
    input                     i_tick,
    input                     i_run,
    input                     i_clear,
    input                     i_mode,
    output [BIT_WIDTH -1 : 0] time_count,
    output                    o_tick
);
    reg [$clog2(TIMES)-1:0] count_reg;
    reg tick_reg;

    assign o_tick = tick_reg;
    assign time_count = count_reg;

    always @(posedge clk, posedge reset) begin
        if (reset || i_clear) begin
            count_reg <= 1'b0;
            tick_reg  <= 1'b0;
        end else begin
            tick_reg <= 1'b0;
            if (i_tick && i_run) begin
                if (!i_mode) begin
                    if (count_reg == (TIMES - 1)) begin
                        count_reg <= 1'b0;
                        tick_reg  <= 1'b1;
                    end else count_reg <= count_reg + 1;
                end else begin
                    if (count_reg == 0) begin
                        count_reg <= (TIMES - 1);
                        tick_reg  <= 1'b1;
                    end else count_reg <= count_reg - 1;
                end
            end
        end
    end
endmodule

