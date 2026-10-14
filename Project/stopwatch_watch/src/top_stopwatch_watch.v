`timescale 1ns / 1ps
module top_stopwatch_watch (
    input        clk,
    input        reset,
    input        btn_L,
    input        btn_R,
    input        btn_U,
    input        btn_D,
    input  [3:0] sw,
    output [3:0] fnd_com,
    output [7:0] fnd_data,
    output [3:0] led
);

    wire w_btn_L, w_btn_R, w_btn_U, w_btn_D;
    wire w_def, w_minmove, w_modemove, w_hourmove, w_secmove;
    wire led_15;
    wire [6:0] w_msec_watch, w_msec_sw, w_msec;
    wire [5:0] w_sec_watch, w_min_watch, w_sec_sw, w_min_sw, w_sec, w_min;
    wire [4:0] w_hour_watch, w_hour_sw, w_hour;
    wire s_ptr, s_active;
    wire w_run_stop, w_clear, w_mode, w_load;
    wire w_set_en, w_set_rise, w_disp_sel_o;
    wire [3:0] w_set_btn;
    wire       w_time_zero;
    wire [3:0] w_btn_sw = {w_btn_D, w_btn_U, w_btn_R, w_btn_L};
    wire       w_def_fnd;
    assign led[0]  = 1'b1;
    assign led[1]  = sw[1];
    assign led[2] = led_15;
    assign led[3]  = 1'b0;

    mux_8x4 U_MUX_8X4_WATCH_STOPWATCH (
        .msec_watch    (w_msec_watch),
        .sec_watch     (w_sec_watch),
        .min_watch     (w_min_watch),
        .hour_watch    (w_hour_watch),
        .msec_stopwatch(w_msec_sw),
        .sec_stopwatch (w_sec_sw),
        .min_stopwatch (w_min_sw),
        .hour_stopwatch(w_hour_sw),
        .sel           (sw[1]),
        .msec_sel      (w_msec),
        .sec_sel       (w_sec),
        .min_sel       (w_min),
        .hour_sel      (w_hour)
    );

    watch_control_unit U_WATCH_CONTROL_UNIT (
        .clk      (clk),
        .reset    (reset),
        .i_min    (w_btn_U),
        .i_mode   (w_btn_D),
        .i_hour   (w_btn_L),
        .i_sec    (w_btn_R),
        .i_sw_2   (sw[3]),
        .i_sw_1   (sw[1]),
        .o_default(w_def),
        .o_min    (w_minmove),
        .o_mode   (w_modemove),
        .o_hour   (w_hourmove),
        .o_sec    (w_secmove)
    );

    watch_datapath U_WATCH_DATAPATH (
        .clk     (clk),
        .reset   (reset),
        .def     (w_def),
        .mode    (w_modemove),
        .secmove (w_secmove),
        .minmove (w_minmove),
        .hourmove(w_hourmove),
        .msec    (w_msec_watch),
        .sec     (w_sec_watch),
        .min     (w_min_watch),
        .hour    (w_hour_watch),
        .o_def   (w_def_fnd)
    );

    stopwatch_datapath U_STOPWATCH_DATAPATH (
        .clk      (clk),
        .reset    (reset),
        .run_stop (w_run_stop),
        .clear    (w_clear),
        .mode     (w_mode),
        .load     (w_load),
        .set_en   (s_active),
        .set_rise (w_set_rise),
        .set_btn  (w_set_btn),
        .disp_sel (w_disp_sel_o),
        .field_ptr(s_ptr),
        .msec     (w_msec_sw),
        .sec      (w_sec_sw),
        .min      (w_min_sw),
        .hour     (w_hour_sw),
        .time_zero(w_time_zero)
    );

    stopwatch_control_unit U_STOPWATCH_CONTROL_UNIT (
        .clk        (clk),
        .reset      (reset),
        .i_en       (~sw[1]),
        .i_set_mode (sw[2]),
        .i_btn      (w_btn_sw),
        .i_disp_sel (sw[0]),
        .i_done     (w_time_zero),
        .o_run_stop (w_run_stop),
        .o_clear    (w_clear),
        .o_mode     (w_mode),
        .o_load     (w_load),
        .o_alarm_led(led_15),
        .o_set_en   (s_active),
        .o_set_rise (w_set_rise),
        .o_set_btn  (w_set_btn),
        .o_disp_sel (w_disp_sel_o)
    );

    fnd_controller U_FND_CONTROLLER (
        .clk         (clk),
        .reset       (reset),
        .msec        (w_msec),
        .sec         (w_sec),
        .min         (w_min),
        .hour        (w_hour),
        .display_mode(sw[0]),
        .fnd_com     (fnd_com),
        .fnd_data    (fnd_data),
        .set_mode    (s_active),
        .field_ptr   (s_ptr),
        .def         (sw[1] ? w_def_fnd : 1'b1)
    );

    btn_debounce U_BTN_DEBOUNCE_HOUR (
        .clk  (clk),
        .reset(reset),
        .i_btn(btn_L),
        .o_btn(w_btn_L)
    );
    btn_debounce U_BTN_DEBOUNCE_SEC (
        .clk  (clk),
        .reset(reset),
        .i_btn(btn_R),
        .o_btn(w_btn_R)
    );
    btn_debounce U_BTN_DEBOUNCE_MIN (
        .clk  (clk),
        .reset(reset),
        .i_btn(btn_U),
        .o_btn(w_btn_U)
    );
    btn_debounce U_BTN_DEBOUNCE_WATCHMODE (
        .clk  (clk),
        .reset(reset),
        .i_btn(btn_D),
        .o_btn(w_btn_D)
    );
endmodule

module mux_8x4 (
    input  [6:0] msec_watch,
    input  [5:0] sec_watch,
    input  [5:0] min_watch,
    input  [4:0] hour_watch,
    input  [6:0] msec_stopwatch,
    input  [5:0] sec_stopwatch,
    input  [5:0] min_stopwatch,
    input  [4:0] hour_stopwatch,
    input        sel,             //sw1
    output [6:0] msec_sel,
    output [5:0] sec_sel,
    output [5:0] min_sel,
    output [4:0] hour_sel
);
    assign msec_sel = (sel) ? msec_watch : msec_stopwatch;
    assign sec_sel  = (sel) ? sec_watch : sec_stopwatch;
    assign min_sel  = (sel) ? min_watch : min_stopwatch;
    assign hour_sel = (sel) ? hour_watch : hour_stopwatch;
endmodule

