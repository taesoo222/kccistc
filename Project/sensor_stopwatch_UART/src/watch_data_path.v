`timescale 1ns / 1ps

module watch_data_path #(
    parameter MSEC_WIDTH = 7,
    SEC_WIDTH = 6,
    MIN_WIDTH = 6,
    HOUR_WIDTH = 5
) (
    input                     clk,
    input                     reset,
    input                     sec_set,
    input                     min_set,
    input                     hour_set,
    input                     mode_watch,
    output [MSEC_WIDTH-1 : 0] msec_count,
    output [ SEC_WIDTH-1 : 0] sec_count,
    output [ MIN_WIDTH-1 : 0] min_count,
    output [HOUR_WIDTH-1 : 0] hour_count
);
    wire w_tick_100hz, w_tick_sec, w_tick_min, w_tick_hour;

    tick_gen_100hz U_TICK_GEN_100hz (
        .clk(clk),
        .reset(reset),
        .o_tick(w_tick_100hz)
    );
    time_counter #(
        .BIT_WIDTH(MSEC_WIDTH),
        .TIMES(100)
    ) U_MSEC_COUNTER (
        .clk        (clk),
        .reset      (reset),
        .i_tick     (w_tick_100hz),
        .i_watch_set(1'b0),
        .i_mode     (1'b0),
        .time_count (msec_count),
        .o_tick     (w_tick_sec)
    );
    time_counter #(
        .BIT_WIDTH(SEC_WIDTH),
        .TIMES(60)
    ) U_SEC_COUNTER (
        .clk        (clk),
        .reset      (reset),
        .i_tick     (w_tick_sec),
        .i_watch_set(sec_set),
        .i_mode     (mode_watch),
        .time_count (sec_count),
        .o_tick     (w_tick_min)
    );
    time_counter #(
        .BIT_WIDTH(MIN_WIDTH),
        .TIMES(60)
    ) U_MIN_COUNTER (
        .clk        (clk),
        .reset      (reset),
        .i_tick     (w_tick_min),
        .i_watch_set(min_set),
        .i_mode     (mode_watch),
        .time_count (min_count),
        .o_tick     (w_tick_hour)
    );
    time_counter #(
        .BIT_WIDTH(HOUR_WIDTH),
        .TIMES(24)
    ) U_HOUR_COUNTER (
        .clk        (clk),
        .reset      (reset),
        .i_tick     (w_tick_hour),
        .i_watch_set(hour_set),
        .i_mode     (mode_watch),
        .time_count (hour_count),
        .o_tick     ()
    );
endmodule

module tick_gen_100hz (
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

module time_counter #(
    parameter BIT_WIDTH = 7,
    TIMES = 100
) (
    input                     clk,
    input                     reset,
    input                     i_watch_set,
    input                     i_mode,
    input                     i_tick,
    output [BIT_WIDTH -1 : 0] time_count,
    output                    o_tick
);
    reg [$clog2(TIMES)-1:0] count_reg;
    reg tick_reg;

    assign o_tick = tick_reg;
    assign time_count = count_reg;

    always @(posedge clk, posedge reset) begin
        if (reset) begin
            count_reg <= 1'b0;
            tick_reg  <= 1'b0;
        end else begin
            if (i_watch_set) begin
                if (!i_mode) begin
                    if (count_reg == (TIMES - 1)) count_reg <= 0;
                    else count_reg <= count_reg + 1;
                end else begin
                    if (count_reg == 0) count_reg <= (TIMES - 1);
                    else count_reg <= count_reg - 1;
                end
            end
            if (i_tick) begin
                count_reg <= count_reg + 1;
                if (count_reg == (TIMES - 1)) begin
                    count_reg <= 1'b0;
                    tick_reg  <= 1'b1;
                end
            end else begin
                tick_reg <= 1'b0;
            end
        end
    end
endmodule
