`timescale 1ns / 1ps

module control_unit (
    input clk,
    input reset,
    input btn_U,             //btn_U s_watch: mode      //watch: min_set
    input btn_D,             //btn_D s_watch: option,   //watch: mode
    input btn_L,             //btn_L s_watch: run/stop, //watch: hour_set
    input btn_R,             //btn_R s_watch: clear,    //watch: sec_set
    input i_sw_0,
    input i_sw_1,
    input i_sw_2,
    input i_sw_3,
    //uart
    input uart_run,
    input uart_stop,
    input uart_clear,
    input uart_mode_swatch,
    input uart_sec_set,
    input uart_min_set,
    input uart_hour_set,
    input uart_mode_watch,
    input uart_sr_start,
    input uart_dht_start,
    output o_sr_start,
    output o_dht_start,
    output o_run,
    output o_mode_swatch,
    output o_clear,
    output o_hour_set,
    output o_min_set,
    output o_sec_set,
    output o_mode_watch
);
    parameter
            SET_WATCH   = 0,
                SW_STOP = 1,
                    RUN = 2,
                  CLEAR = 3,
            MODE_SWATCH = 4,
            OPTION      = 5,
            MIN         = 6,
            HOUR        = 7,
            SEC         = 8,
            MODE_WATCH  = 9,
            DHT_T_IDLE  = 10,
            DHT_H_IDLE  = 11,
            SR04_IDLE   = 12,
            DHT_T_START = 13,
            DHT_H_START = 14,
            SR04_START  = 15;

    reg [3:0] c_state, n_state;
    reg  //stopwatch
        run_reg,
        run_next,
        clear_reg,
        clear_next,
        mode_swatch_reg,
        mode_swatch_next;
    reg  //watch
        min_reg,
        min_next,
        hour_reg,
        hour_next,
        sec_reg,
        sec_next,
        mode_watch_reg,
        mode_watch_next;

    reg  //sensor
        dht_reg, dht_next, sr_reg, sr_next;

    assign o_run         = run_reg;
    assign o_mode_swatch = mode_swatch_reg;
    assign o_clear       = clear_reg;
    assign o_hour_set    = hour_reg;
    assign o_min_set     = min_reg;
    assign o_sec_set     = sec_reg;
    assign o_mode_watch  = mode_watch_reg;
    assign o_sr_start    = sr_reg;
    assign o_dht_start   = dht_reg;


    // state register
    always @(posedge clk, posedge reset) begin
        if (reset) begin
            c_state         <= SET_WATCH;
            run_reg         <= 1'b0;
            clear_reg       <= 1'b0;
            mode_swatch_reg <= 1'b0;
            min_reg         <= 1'b0;
            hour_reg        <= 1'b0;
            sec_reg         <= 1'b0;
            mode_watch_reg  <= 1'b0;
            sr_reg          <= 1'b0;
            dht_reg         <= 1'b0;
        end else begin
            c_state         <= n_state;
            run_reg         <= run_next;
            clear_reg       <= clear_next;
            mode_swatch_reg <= mode_swatch_next;
            min_reg         <= min_next;
            hour_reg        <= hour_next;
            sec_reg         <= sec_next;
            mode_watch_reg  <= mode_watch_next;
            sr_reg          <= sr_next;
            dht_reg         <= dht_next;
        end
    end

    //next CL
    always @(*) begin
        n_state          = c_state;
        run_next         = run_reg;
        clear_next       = clear_reg;
        mode_swatch_next = mode_swatch_reg;
        min_next         = min_reg;
        hour_next        = hour_reg;
        sec_next         = sec_reg;
        mode_watch_next  = mode_watch_reg;
        sr_next          = sr_reg;
        dht_next         = dht_reg;
        case (c_state)
            /////////////////watch/////////////////////
            SET_WATCH: begin
                run_next       = 1'b0;
                clear_next     = 1'b0;
                min_next       = 1'b0;
                hour_next      = 1'b0;
                sec_next       = 1'b0;
                sr_next        = 1'b0;
                dht_next       = 1'b0;
                if (i_sw_0) n_state = SW_STOP;
                else if (i_sw_1) n_state = DHT_T_IDLE;
                else if (i_sw_2) n_state = DHT_H_IDLE;
                else if (i_sw_3) n_state = SR04_IDLE;
                else if (btn_L || uart_hour_set) n_state = HOUR;
                else if (btn_R || uart_sec_set) n_state = SEC;
                else if (btn_U || uart_min_set) n_state = MIN;
                else if (btn_D || uart_mode_watch) n_state = MODE_WATCH;
                else n_state = c_state;
            end
            MIN: begin
                min_next = 1'b1;
                n_state  = SET_WATCH;
            end
            MODE_WATCH: begin
                mode_watch_next = ~mode_watch_reg;
                n_state = SET_WATCH;
            end
            HOUR: begin
                hour_next = 1'b1;
                n_state   = SET_WATCH;
            end
            SEC: begin
                sec_next = 1'b1;
                n_state  = SET_WATCH;
            end
            /////////////////stopwatch/////////////////////
            SW_STOP: begin
                run_next        = 1'b0;
                clear_next      = 1'b0;
                min_next        = 1'b0;
                hour_next       = 1'b0;
                sec_next        = 1'b0;
                mode_watch_next = 1'b0;
                sr_next         = 1'b0;
                dht_next        = 1'b0;
                if (!i_sw_0) n_state = SET_WATCH;
                else if (btn_R || uart_clear) n_state = CLEAR;
                else if (btn_L || uart_run) n_state = RUN;
                else if (btn_U || uart_mode_swatch) n_state = MODE_SWATCH;
                else if (btn_D) n_state = OPTION;
                else n_state = c_state;
            end
            RUN: begin
                run_next  = 1'b1;
                if (!i_sw_0) n_state = SET_WATCH;
                else if (btn_L || uart_stop) n_state = SW_STOP;
            end
            CLEAR: begin
                clear_next = 1'b1;
                n_state = SW_STOP;
            end
            MODE_SWATCH: begin
                mode_swatch_next = ~mode_swatch_reg;
                n_state = SW_STOP;
            end
            // not working
            OPTION: begin
                n_state = SW_STOP;
            end
            /////////////////sensor/////////////////////
            DHT_T_IDLE: begin
                dht_next = 0;
                if (!i_sw_1) n_state = SET_WATCH;
                else if (btn_L || uart_dht_start) n_state = DHT_T_START;
            end
            DHT_T_START: begin
                dht_next = 1;
                n_state  = DHT_T_IDLE;
            end
            DHT_H_IDLE: begin
                dht_next = 0;
                if (!i_sw_2) n_state = SET_WATCH;
                else if (btn_L || uart_dht_start) n_state = DHT_H_START;
            end
            DHT_H_START: begin
                dht_next = 1;
                n_state  = DHT_H_IDLE;
            end
            SR04_IDLE: begin
                sr_next = 0;
                if (!i_sw_3) n_state = SET_WATCH;
                else if (btn_L || uart_sr_start) n_state = SR04_START;
            end
            SR04_START: begin
                sr_next = 1;
                n_state = SR04_IDLE;
            end
        endcase
    end
endmodule
