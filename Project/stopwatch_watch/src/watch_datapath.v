`timescale 1ns / 1ps
module watch_datapath #(
    parameter MSEC_WIDTH = 7,
    SEC_WIDTH = 6,
    MIN_WIDTH = 6,
    HOUR_WIDTH = 5
) (
    input                   clk,
    input                   reset,
    input                   mode,
    input                   secmove,
    input                   minmove,
    input                   hourmove,
    input                   def,
    output [MSEC_WIDTH-1:0] msec,
    output [ SEC_WIDTH-1:0] sec,
    output [ MIN_WIDTH-1:0] min,
    output [HOUR_WIDTH-1:0] hour,
    output                  o_def
);
    assign o_def = def;
    wire w_tick_100hz, w_tick_sec, w_tick_min, w_tick_hour; //o_tick from bot to top

    tick_gen_100hz U_TICK_GEN_100hz (
        .clk(clk),
        .reset(reset),
        .o_tick(w_tick_100hz)
    );

    time_counter #(
        .BIT_WIDTH(7),
        .TIMES(100)
    ) U_MSEC_COUNTER (
        .clk       (clk),
        .reset     (reset),
        .i_tick    (w_tick_100hz),
        .i_watch   (1'b0),
        .i_mode    (1'b0),
        .i_def     (1'b0),
        .time_count(msec),
        .o_tick    (w_tick_sec)
    );

    time_counter #(
        .BIT_WIDTH(6),
        .TIMES(60)
    ) U_SEC_COUNTER (
        .clk       (clk),
        .reset     (reset),
        .i_tick    (w_tick_sec),
        .i_watch   (secmove),
        .i_mode    (mode),
        .i_def     (def),
        .time_count(sec),
        .o_tick    (w_tick_min)
    );

    time_counter #(
        .BIT_WIDTH(6),
        .TIMES(60)
    ) U_MIN_COUNTER (
        .clk       (clk),
        .reset     (reset),
        .i_tick    (w_tick_min),
        .i_watch   (minmove),
        .i_mode    (mode),
        .i_def     (def),
        .time_count(min),
        .o_tick    (w_tick_hour)
    );

    time_counter #(
        .BIT_WIDTH(5),
        .TIMES(24)
    ) U_HOUR_COUNTER (
        .clk       (clk),
        .reset     (reset),
        .i_tick    (w_tick_hour),
        .i_watch   (hourmove),
        .i_mode    (mode),
        .i_def     (def),
        .time_count(hour),
        .o_tick    ()
    );
endmodule

module time_counter #(
    parameter BIT_WIDTH = 7,
    TIMES = 100
) (
    input                      clk,
    input                      reset,
    input                      i_tick,
    input                      i_watch,
    input                      i_mode,
    input                      i_def,
    output     [BIT_WIDTH-1:0] time_count,
    output reg                 o_tick
);
    reg [$clog2(TIMES)-1 : 0] counter_reg;
    assign time_count = counter_reg;

    always @(posedge clk, posedge reset) begin
        if (reset) begin
            counter_reg <= 0;
            o_tick <= 1'b0;
        end else begin
            if (~(i_def) && i_watch) begin
                if (!i_mode) begin
                    if (counter_reg == (TIMES - 1)) counter_reg <= 0;
                    else counter_reg <= counter_reg + 1;
                end else begin
                    if (counter_reg == 0) counter_reg <= (TIMES - 1);
                    else counter_reg <= counter_reg - 1;
                end
            end
            if (i_tick) begin
                counter_reg <= counter_reg + 1;
                if (counter_reg == (TIMES - 1)) begin
                    counter_reg <= 0;
                    o_tick <= 1'b1;
                end
            end else begin
                o_tick <= 1'b0;
            end
        end
    end
endmodule

module tick_gen_100hz (
    input clk,
    input reset,
    output reg o_tick
);
    parameter F_COUNT = 1_000_000;  // 100MHz -> 100Hz
    reg [$clog2(F_COUNT)-1:0] counter_reg;

    always @(posedge clk, posedge reset) begin
        if (reset) begin
            counter_reg <= 0;
            o_tick      <= 0;
        end else begin
            counter_reg <= counter_reg + 1;
            if (counter_reg == F_COUNT - 1) begin
                counter_reg <= 0;
                o_tick      <= 1'b1;
            end else begin
                o_tick <= 1'b0;
            end
        end
    end
endmodule
