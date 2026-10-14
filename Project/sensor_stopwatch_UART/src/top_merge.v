`timescale 1ns / 1ps

module top_merge (
    input clk,
    input reset,
    input btnL,
    input btnR,
    input btnU,
    input btnD,
    input [15:0] sw,
    input rx,
    input echo,
    output tx,
    output trigger,
    output [3:0] fnd_com,
    output [7:0] fnd_data,
    inout dht11_io

);
    wire w_btnL, w_btnR, w_btnU, w_btnD;  // wire button

    wire [7:0] w_uart_ctr_rxdata;
    wire w_uart_ctr_empty;  // from uart_ctr

    // from uart_ascii_decoder
    wire w_uart_run,
         w_uart_stop,
         w_uart_clear,
         w_uart_mode_sw,
         w_uart_sec_set,
         w_uart_min_set,
         w_uart_hour_set,
         w_uart_mode_w,
         w_uart_sr_start,
         w_uart_dht_start,
         w_uart_get_start;
    // from control_unit
    wire w_run, w_clear, w_mode_sw, w_option,  //stopwatch
    w_hour_set, w_min_set, w_sec_set, w_mode_watch,  //watch 
    w_sr_start, w_dht_start;  //sensor

    // wire watch datapath
    wire [6:0] w_watch_msec;
    wire [5:0] w_watch_sec, w_watch_min;
    wire [4:0] w_watch_hour;

    // wire stopwatch datapath
    wire [6:0] w_stopwatch_msec;
    wire [5:0] w_stopwatch_sec, w_stopwatch_min;
    wire [4:0] w_stopwatch_hour;

    // wire sensor
    wire [15:0] w_humidity, w_temperature;
    wire [8:0] w_distance;
    wire w_dht_done, w_dht_valid;
    wire w_sr_done;

    // data selector output
    wire [2:0] display_mode;
    wire [6:0] w_fnd_msec;
    wire [5:0] w_fnd_sec;
    wire [5:0] w_fnd_min;
    wire [4:0] w_fnd_hour;
    wire [13:0] top_selected_data;

    btn_debouncer U_BTN_DEBOUNCER_L (
        .clk  (clk),
        .reset(reset),
        .i_btn(btnL),
        .o_btn(w_btnL)
    );

    btn_debouncer U_BTN_DEBOUNCER_R (
        .clk  (clk),
        .reset(reset),
        .i_btn(btnR),
        .o_btn(w_btnR)
    );

    btn_debouncer U_BTN_DEBOUNCER_U (
        .clk  (clk),
        .reset(reset),
        .i_btn(btnU),
        .o_btn(w_btnU)
    );

    btn_debouncer U_BTN_DEBOUNCER_D (
        .clk  (clk),
        .reset(reset),
        .i_btn(btnD),
        .o_btn(w_btnD)
    );
    // UART RX controller
    uart_controller U_UART_CONTROLLER (
        .clk     (clk),
        .reset   (reset),
        .rx      (rx),
        .rx_pop  (~w_uart_ctr_empty),
        .rx_data (w_uart_ctr_rxdata),
        .rx_empty(w_uart_ctr_empty)
    );

    // UART TX sender
    uart_sender U_UART_SENDER (
        .clk          (clk),
        .reset        (reset),
        .tx_trigger   (w_uart_get_start),
        .selected_data(top_selected_data),
        .tx           (tx)
    );

    uart_ascii_decoder U_UART_ASCII_DECODER (
        .clk           (clk),
        .reset         (reset),
        .rx_data       (w_uart_ctr_rxdata),
        .rx_done       (~w_uart_ctr_empty),
        .uart_run      (w_uart_run),
        .uart_stop     (w_uart_stop),
        .uart_clear    (w_uart_clear),
        .uart_mode_sw  (w_uart_mode_sw),
        .uart_sec_set  (w_uart_sec_set),
        .uart_min_set  (w_uart_min_set),
        .uart_hour_set (w_uart_hour_set),
        .uart_mode_w   (w_uart_mode_w),
        .uart_sr_start (w_uart_sr_start),
        .uart_dht_start(w_uart_dht_start),
        .uart_get_start(w_uart_get_start)
    );

    control_unit U_CONTROL_UNIT (
        .clk             (clk),
        .reset           (reset),
        .btn_U           (w_btnU),
        .btn_D           (w_btnD),
        .btn_L           (w_btnL),
        .btn_R           (w_btnR),
        .i_sw_0          (sw[0]),
        .i_sw_1          (sw[1]),
        .i_sw_2          (sw[2]),
        .i_sw_3          (sw[3]),
        //uart
        .uart_run        (w_uart_run),
        .uart_stop       (w_uart_stop),
        .uart_clear      (w_uart_clear),
        .uart_mode_swatch(w_uart_mode_sw),
        .uart_sec_set    (w_uart_sec_set),
        .uart_min_set    (w_uart_min_set),
        .uart_hour_set   (w_uart_hour_set),
        .uart_mode_watch (w_uart_mode_w),
        .uart_sr_start   (w_uart_sr_start),
        .uart_dht_start  (w_uart_dht_start),
        //output
        .o_sr_start      (w_sr_start),
        .o_dht_start     (w_dht_start),
        .o_run           (w_run),
        .o_mode_swatch   (w_mode_sw),
        .o_clear         (w_clear),
        .o_option        (w_option),
        .o_hour_set      (w_hour_set),
        .o_min_set       (w_min_set),
        .o_sec_set       (w_sec_set),
        .o_mode_watch    (w_mode_watch)
    );

    watch_data_path U_WATCH_DATAPATH (
        .clk       (clk),
        .reset     (reset),
        .sec_set   (w_sec_set),
        .min_set   (w_min_set),
        .hour_set  (w_hour_set),
        .mode_watch(w_mode_watch),
        //output
        .msec_count(w_watch_msec),
        .sec_count (w_watch_sec),
        .min_count (w_watch_min),
        .hour_count(w_watch_hour)
    );

    stopwatch_data_path U_STOPWATCH_DATAPATH (
        .clk       (clk),
        .reset     (reset),
        .run       (w_run),
        .clear     (w_clear),
        .mode      (w_mode_sw),
        .option    (w_option),
        //output
        .msec_count(w_stopwatch_msec),
        .sec_count (w_stopwatch_sec),
        .min_count (w_stopwatch_min),
        .hour_count(w_stopwatch_hour)
    );

    dht11 U_DHT11 (
        .clk        (clk),
        .reset      (reset),
        .start      (w_dht_start),
        .humidity   (w_humidity),
        .temperature(w_temperature),
        .done       (w_dht_done),
        .valid      (w_dht_valid),
        .dht11_io   (dht11_io)
    );

    sr04_controller U_SR04_CONTROLLER (
        .clk     (clk),
        .reset   (reset),
        .start   (w_sr_start),
        .echo    (echo),
        .trigger (trigger),
        .done    (w_sr_done),
        .distance(w_distance)
    );

    data_selector U_DATA_SELECTOR (
        .clk  (clk),
        .reset(reset),
        .sw   (sw),

        .watch_msec(w_watch_msec),
        .watch_sec (w_watch_sec),
        .watch_min (w_watch_min),
        .watch_hour(w_watch_hour),

        .stopwatch_msec(w_stopwatch_msec),
        .stopwatch_sec (w_stopwatch_sec),
        .stopwatch_min (w_stopwatch_min),
        .stopwatch_hour(w_stopwatch_hour),

        .temperature(w_temperature),
        .humidity   (w_humidity),
        .distance   (w_distance),

        .display_mode (display_mode),
        .fnd_msec     (w_fnd_msec),
        .fnd_sec      (w_fnd_sec),
        .fnd_min      (w_fnd_min),
        .fnd_hour     (w_fnd_hour),
        .selected_data(top_selected_data)
    );

    fnd_controller U_FND_CONTROLLER (
        .clk         (clk),
        .reset       (reset),
        .msec        (w_fnd_msec),
        .sec         (w_fnd_sec),
        .min         (w_fnd_min),
        .hour        (w_fnd_hour),
        .humidity    (w_humidity),
        .temperature (w_temperature),
        .distance    (w_distance),
        .display_mode(display_mode),
        .fnd_com     (fnd_com),
        .fnd_data    (fnd_data)
    );

endmodule
