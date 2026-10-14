`timescale 1ns / 1ps

module uart_ascii_decoder (
    input        clk,
    input        reset,
    input  [7:0] rx_data,
    input        rx_done,
    output       uart_run,
    output       uart_stop,
    output       uart_clear,
    output       uart_mode_sw,
    output       uart_sec_set,
    output       uart_min_set,
    output       uart_hour_set,
    output       uart_mode_w,
    output       uart_sr_start,
    output       uart_dht_start,
    output       uart_get_start
);
    localparam [2:0] IDLE  = 0,
                     SLASH = 1,
                     GET_G = 2,
                     GET_E = 3,
                     DHT_D = 4,
                     DHT_H = 5,
                     SR_S  = 6;

    reg [2:0] c_state, n_state;
    reg
        run_reg,
        stop_reg,
        clear_reg,
        mode_sw_reg,
        sec_set_reg,
        min_set_reg,
        hour_set_reg,
        mode_w_reg,
        sr_start_reg,
        dht_start_reg,
        get_start_reg;

    assign uart_run       = run_reg;
    assign uart_stop      = stop_reg;
    assign uart_clear     = clear_reg;
    assign uart_mode_sw   = mode_sw_reg;
    assign uart_sec_set   = sec_set_reg;
    assign uart_min_set   = min_set_reg;
    assign uart_hour_set  = hour_set_reg;
    assign uart_mode_w    = mode_w_reg;
    assign uart_sr_start  = sr_start_reg;
    assign uart_dht_start = dht_start_reg;
    assign uart_get_start = get_start_reg;

    always @(posedge clk, posedge reset) begin
        if (reset) c_state <= IDLE;
        else c_state <= n_state;
    end

    always @(*) begin
        n_state       = c_state;
        run_reg       = 1'b0;
        stop_reg      = 1'b0;
        clear_reg     = 1'b0;
        mode_sw_reg   = 1'b0;
        sec_set_reg   = 1'b0;
        min_set_reg   = 1'b0;
        hour_set_reg  = 1'b0;
        mode_w_reg    = 1'b0;
        sr_start_reg  = 1'b0;
        dht_start_reg = 1'b0;
        get_start_reg = 1'b0;
        if (rx_done) begin
            case (c_state)
                IDLE: begin
                    case (rx_data)
                        ///////////// run
                        8'h72: begin
                            run_reg = 1'b1;
                            n_state = IDLE;
                        end
                        ///////////// stop
                        8'h73: begin
                            stop_reg = 1'b1;
                            n_state  = IDLE;
                        end
                        ///////////// clear
                        8'h63: begin
                            clear_reg = 1'b1;
                            n_state   = IDLE;
                        end
                        ///////////// mode_swatch
                        8'h6D: begin
                            mode_sw_reg = 1'b1;
                            n_state = IDLE;
                        end
                        ///////////// sec_set
                        8'h53: begin
                            sec_set_reg = 1'b1;
                            n_state = IDLE;
                        end
                        ///////////// min_set
                        8'h4D: begin
                            min_set_reg = 1'b1;
                            n_state = IDLE;
                        end
                        ///////////// hour_set
                        8'h48: begin
                            hour_set_reg = 1'b1;
                            n_state = IDLE;
                        end
                        ///////////// mode_watch
                        8'h57: begin
                            mode_w_reg = 1'b1;
                            n_state = IDLE;
                        end
                        ///////////// slash, string start
                        8'h2f: begin
                            n_state = SLASH;
                        end
                    endcase
                end
                SLASH: begin
                    ///////////// in : g (/get)
                    if (rx_data == 8'h67) n_state = GET_G;
                    ///////////// in : d (/dht)
                    else if (rx_data == 8'h64) n_state = DHT_D;
                    ///////////// in : s (/sr)
                    else if (rx_data == 8'h73) n_state = SR_S;
                    else n_state = IDLE;
                end
                ///////////////////// /get
                GET_G: begin
                    if (rx_data == 8'h65) n_state = GET_E;
                    else n_state = IDLE;
                end
                GET_E: begin
                    if (rx_data == 8'h74) begin
                        get_start_reg = 1'b1;
                        n_state       = IDLE;
                    end else n_state = IDLE;
                end
                /////////////////// /dht
                DHT_D: begin
                    if (rx_data == 8'h68) n_state = DHT_H;
                    else n_state = IDLE;
                end
                DHT_H: begin
                    if (rx_data == 8'h74) begin
                        dht_start_reg = 1'b1;
                        n_state       = IDLE;
                    end else n_state = IDLE;
                end
                /////////////////// /sr
                SR_S: begin
                    if (rx_data == 8'h72) begin
                        sr_start_reg = 1'b1;
                        n_state      = IDLE;
                    end else n_state = IDLE;
                end
            endcase
        end
    end
endmodule

// assign uart_run         = rx_done && (rx_data == 8'h72);  // r :run
// assign uart_stop        = rx_done && (rx_data == 8'h73);  // s :stop
// assign uart_clear       = rx_done && (rx_data == 8'h63);  // c :clear
// assign uart_mode_swatch = rx_done && (rx_data == 8'h6D);  // m :mode_swatch
// assign uart_sec_set     = rx_done && (rx_data == 8'h53);  // S :sec_set
// assign uart_min_set     = rx_done && (rx_data == 8'h4D);  // M :min_set
// assign uart_hour_set    = rx_done && (rx_data == 8'h48);  // H :hour_set
// assign uart_mode_watch  = rx_done && (rx_data == 8'h57);  // W :mode_watch
