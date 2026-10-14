`timescale 1ns / 1ps

module dht11 (
    input             clk,
    input             reset,
    input             start,
    output     [15:0] humidity,
    output     [15:0] temperature,
    output            done,
    output reg        valid,
    inout             dht11_io
);

    localparam [2:0] IDLE = 0, START = 1, WAIT = 2, SYNCL = 3, SYNCH = 4, DATA = 5, STOP = 6;

    reg ctrl_run, ctrl_clear;
    reg [2:0] n_state, c_state;
    reg [$clog2(19_000)-1:0] tick_count_reg, tick_count_next;
    reg io_control;
    reg dht11_io_reg, dht11_io_next;
    reg [5:0] bit_cnt_reg, bit_cnt_next;
    reg [6:0] hus_cnt_reg, hus_cnt_next;
    reg [39:0] shift_reg, shift_reg_next;
    reg done_reg, done_next;
    reg [15:0] humidity_reg, humidity_next;
    reg [15:0] temperature_reg, temperature_next;

    wire w_tick_us;
    wire w_io_pedge, w_io_nedge, w_io_level;

    assign dht11_io = (io_control) ? (dht11_io_reg) : 1'bz;
    assign done = done_reg;
    assign humidity    = humidity_reg;
    assign temperature = temperature_reg;

    tick_us_dht11 U_TICK_US_DHT11 (
        .clk   (clk),
        .reset (reset),
        .i_run (ctrl_run),
        .clear (ctrl_clear),
        .o_tick(w_tick_us)
    );

    edge_detection U_EDGE_DETECTION (
        .clk  (clk),
        .reset(reset),
        .d_in (dht11_io),
        .pedge(w_io_pedge),
        .nedge(w_io_nedge),
        .level(w_io_level)
    );

    always @(posedge clk, posedge reset) begin
        if (reset) begin
            c_state         <= IDLE;
            dht11_io_reg    <= 1;
            tick_count_reg  <= 0;
            bit_cnt_reg     <= 0;
            hus_cnt_reg     <= 0;
            shift_reg       <= 0;
            done_reg        <= 0;
            humidity_reg    <= 0;
            temperature_reg <= 0;
        end else begin
            c_state         <= n_state;
            dht11_io_reg    <= dht11_io_next;
            tick_count_reg  <= tick_count_next;
            bit_cnt_reg     <= bit_cnt_next;
            hus_cnt_reg     <= hus_cnt_next;
            shift_reg       <= shift_reg_next;
            done_reg        <= done_next;
            humidity_reg    <= humidity_next;
            temperature_reg <= temperature_next;
        end
    end

    always @(*) begin
        n_state          = c_state;
        dht11_io_next    = dht11_io_reg;
        io_control       = 1'b1;
        ctrl_run         = 0;
        ctrl_clear       = 0;
        tick_count_next  = tick_count_reg;
        bit_cnt_next     = bit_cnt_reg;
        hus_cnt_next     = hus_cnt_reg;
        shift_reg_next   = shift_reg;
        humidity_next    = humidity_reg;
        temperature_next = temperature_reg;
        done_next        = 0;
        valid            = 0;
        case (c_state)
            IDLE: begin
                ctrl_run        = 0;
                ctrl_clear      = 1;
                dht11_io_next   = 1;
                io_control      = 1;
                tick_count_next = 0;
                bit_cnt_next    = 0;
                hus_cnt_next    = 0;
                shift_reg_next  = 0;
                if (start) begin
                    n_state = START;
                end
            end
            START: begin
                ctrl_run = 1;
                ctrl_clear = 0;
                dht11_io_next = 1'b0;
                // delay 19msec low
                if (w_tick_us) begin
                    if (tick_count_reg == 19_000) begin
                        n_state = WAIT;
                        tick_count_next = 0;
                    end else begin
                        tick_count_next = tick_count_reg + 1;
                    end
                end
            end
            WAIT: begin
                dht11_io_next = 1'b1;
                ctrl_run = 1;
                if (w_tick_us) begin
                    tick_count_next = tick_count_reg + 1;
                end
                if (tick_count_reg == 30) begin
                    n_state = SYNCL;
                    tick_count_next = 0;
                end
            end
            SYNCL: begin
                io_control = 0;
                ctrl_run   = 1;
                if (w_tick_us) begin
                    tick_count_next = tick_count_reg + 1;
                end
                if (w_io_pedge) begin // wait 10us because of noise and wait 80us
                    n_state         = SYNCH;
                    tick_count_next = 0;
                    hus_cnt_next    = 0;
                end else if (tick_count_reg > 200) begin
                    n_state = IDLE;
                    tick_count_next = 0;
                end
            end
            SYNCH: begin
                io_control = 0;
                ctrl_run   = 1;
                if (w_tick_us) begin
                    tick_count_next = tick_count_reg + 1;
                end
                if (w_io_nedge) begin
                    n_state = DATA;
                    tick_count_next = 0;
                end else if (tick_count_reg > 200) begin
                    n_state = IDLE;
                    tick_count_next = 0;
                end
            end
            DATA: begin
                io_control = 0;
                ctrl_run   = 1;
                if (w_tick_us) begin
                    tick_count_next = tick_count_reg + 1;
                end
                if (w_io_level) begin
                    if (w_tick_us) begin
                        hus_cnt_next = hus_cnt_reg + 1;
                    end
                end
                if (w_io_nedge) begin
                    shift_reg_next = {shift_reg[38:0], (hus_cnt_reg >= 40)};
                    bit_cnt_next   = bit_cnt_reg + 1;
                    hus_cnt_next   = 0;
                end
                if (bit_cnt_reg == 40) begin
                    n_state         = STOP;
                    tick_count_next = 0;
                    done_next       = 1;

                end

            end
            STOP: begin
                io_control = 0;
                ctrl_run   = 1;
                if(shift_reg[39:32] + shift_reg[31:24] + shift_reg[23:16] + shift_reg[15:8] == shift_reg[7:0]) begin
                    valid       = 1;
                    humidity_next    = shift_reg[39:24];
                    temperature_next = shift_reg[23:8];
                end
                // wait 50us
                if (w_tick_us) begin
                    tick_count_next = tick_count_reg + 1;
                    if (tick_count_reg >= 50) begin
                        tick_count_next = 0;
                        n_state = IDLE;
                    end
                end
            end
        endcase
    end

endmodule

module tick_us_dht11 (
    input  clk,
    input  reset,
    input  i_run,
    input  clear,
    output o_tick
);

    parameter F_COUNT = 100;
    reg [$clog2(F_COUNT)-1:0] count;
    reg tick_us;

    assign o_tick = tick_us;

    always @(posedge clk, posedge reset) begin
        if (reset | clear) begin
            count   <= 0;
            tick_us <= 0;
        end else begin
            if (i_run) begin
                count <= count + 1;
                if (count == (F_COUNT - 1)) begin
                    count   <= 0;
                    tick_us <= 1'b1;
                end else tick_us <= 1'b0;
            end
        end
    end

endmodule

module edge_detection (
    input  clk,
    input  reset,
    input  d_in,
    output pedge,
    output nedge,
    output level
);

    reg sync0, sync1, old;
    reg filter_sync1, filter_old;

    always @(posedge clk, posedge reset) begin
        if (reset) begin
            sync0 <= 1'b1;
            sync1 <= 1'b1;
        end else begin
            sync0 <= d_in;
            sync1 <= sync0;
        end
    end

    reg [3:0] filter_shift;
    reg       filtered_level;

    always @(posedge clk, posedge reset) begin
        if (reset) begin
            filter_shift   <= 4'b1111;
            filtered_level <= 1'b1;
        end else begin
            filter_shift <= {filter_shift[2:0], sync1};

            if (filter_shift == 4'b1111) begin
                filtered_level <= 1'b1;
            end else if (filter_shift == 4'b0000) begin
                filtered_level <= 1'b0;
            end
        end
    end
    always @(posedge clk, posedge reset) begin
        if (reset) begin
            old <= 1'b1;
        end else begin
            old <= filtered_level;
        end
    end

    assign pedge = (~old) & filtered_level;
    assign nedge = old & (~filtered_level);
    assign level = filtered_level;
endmodule
