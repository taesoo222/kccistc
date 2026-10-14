`timescale 1ns / 1ps

module uart_sender (
    input         clk,
    input         reset,
    input         tx_trigger,
    input  [13:0] selected_data,
    output        tx
);
    // push state
    localparam P_IDLE = 0, P_1000 = 1, P_100 = 2, P_10 = 3, P_1 = 4, P_CARRY = 5;
    reg [2:0] p_nstate, p_cstate;

    // tx state
    localparam TX_IDLE = 0, TX_START = 1, TX_POP = 2, TX_WAIT = 3;
    reg [1:0] tx_cstate, tx_nstate;

    wire w_baud_tick_x16_tx;
    // wire fifo_tx
    wire [7:0] w_fifo_tx_rdata;
    wire w_fifo_tx_empty, w_fifo_tx_full;
    //wire tx
    wire w_tx_busy, w_tx_done;

    wire [3:0] d1000 = (selected_data / 1000) % 10;
    wire [3:0] d100 = (selected_data / 100) % 10;
    wire [3:0] d10 = (selected_data / 10) % 10;
    wire [3:0] d1 = selected_data % 10;

    reg r_fifo_tx_push, r_fifo_tx_pop, r_tx_start;
    reg [7:0] r_fifo_tx_wdata;

    reg r_tx_trigger_ed;
    wire w_tx_trigger_pulse = tx_trigger && !r_tx_trigger_ed;
    fifo U_FIFO_TX (
        .clk  (clk),
        .reset(reset),
        .push (r_fifo_tx_push),
        .pop  (r_fifo_tx_pop),
        .wdata(r_fifo_tx_wdata),  // push data
        .rdata(w_fifo_tx_rdata),  // pop data
        .full (w_fifo_tx_full),
        .empty(w_fifo_tx_empty)
    );

    uart_tx U_UART_TX (
        .clk        (clk),
        .reset      (reset),
        .tx_start   (r_tx_start),
        .tx_data    (w_fifo_tx_rdata),
        .i_baud_tick(w_baud_tick_x16_tx),
        .tx         (tx),
        .tx_busy    (w_tx_busy),
        .tx_done    (w_tx_done)
    );

    baud_tick_x16 U_BAUD_TICK_x16 (
        .clk        (clk),
        .reset      (reset),
        .o_baud_tick(w_baud_tick_x16_tx)
    );
    // push state
    always @(posedge clk, posedge reset) begin
        if (reset) begin
            p_cstate <= P_IDLE;
        end else begin
            p_cstate <= p_nstate;
        end
    end

    always @(*) begin
        p_nstate        = p_cstate;
        r_fifo_tx_wdata = 8'h00;
        r_fifo_tx_push  = 0;
        case (p_cstate)
            P_IDLE: begin
                if (w_tx_trigger_pulse) p_nstate = P_1000;
            end
            P_1000: begin
                r_fifo_tx_wdata = 8'h30 + d1000;
                if (!w_fifo_tx_full) begin
                    r_fifo_tx_push = 1;
                    p_nstate = P_100;
                end
            end
            P_100: begin
                r_fifo_tx_wdata = 8'h30 + d100;
                if (!w_fifo_tx_full) begin
                    r_fifo_tx_push = 1;
                    p_nstate = P_10;
                end
            end
            P_10: begin
                r_fifo_tx_wdata = 8'h30 + d10;
                if (!w_fifo_tx_full) begin
                    r_fifo_tx_push = 1;
                    p_nstate = P_1;
                end
            end
            P_1: begin
                r_fifo_tx_wdata = 8'h30 + d1;
                if (!w_fifo_tx_full) begin
                    r_fifo_tx_push = 1;
                    p_nstate = P_CARRY;
                end
            end
            P_CARRY: begin
                r_fifo_tx_wdata = 8'h0A;
                if (!w_fifo_tx_full) begin
                    r_fifo_tx_push = 1;
                    p_nstate = P_IDLE;
                end
            end
        endcase
    end

    // tx state
    always @(posedge clk, posedge reset) begin
        if (reset) begin
            tx_cstate <= TX_IDLE;
            r_tx_trigger_ed <= 0;
        end else begin
            tx_cstate <= tx_nstate;
            r_tx_trigger_ed <= tx_trigger;
        end
    end

    always @(*) begin
        tx_nstate     = tx_cstate;
        r_fifo_tx_pop = 0;
        r_tx_start    = 0;
        case (tx_cstate)
            TX_IDLE: begin
                if (!w_fifo_tx_empty & !w_tx_busy) tx_nstate = TX_START;
            end
            TX_START: begin
                r_tx_start = 1;
                tx_nstate  = TX_POP;
            end
            TX_POP: begin
                r_fifo_tx_pop = 1;
                tx_nstate = TX_WAIT;
            end

            TX_WAIT: begin
                if (w_tx_done) tx_nstate = TX_IDLE;
            end
        endcase
    end

endmodule

module uart_tx (
    input        clk,
    input        reset,
    input        tx_start,
    input  [7:0] tx_data,
    input        i_baud_tick,
    output       tx,
    output       tx_busy,
    output       tx_done
);
    localparam [1:0] IDLE = 2'b00;
    localparam [1:0] START = 2'b01;
    localparam [1:0] DATA = 2'b10;
    localparam [1:0] STOP = 2'b11;

    reg [3:0] tick_count_reg, tick_count_next;
    reg [2:0] c_state, n_state;
    reg [2:0] bit_count_reg, bit_count_next;
    reg tx_reg, tx_next;
    reg [7:0] data_reg, data_next;  //tx_data save
    reg tx_busy_reg, tx_busy_next;
    reg tx_done_reg, tx_done_next;

    assign tx      = tx_reg;
    assign tx_busy = tx_busy_reg;
    assign tx_done = tx_done_reg;

    always @(posedge clk, posedge reset) begin
        if (reset) begin
            c_state        <= IDLE;
            tx_reg         <= 1'b1;
            bit_count_reg  <= 3'b000;
            data_reg       <= 8'b0000_0000;
            tx_busy_reg    <= 1'b0;
            tx_done_reg    <= 1'b0;
            tick_count_reg <= 4'b0000;
        end else begin
            c_state        <= n_state;
            bit_count_reg  <= bit_count_next;
            tx_reg         <= tx_next;
            data_reg       <= data_next;
            tx_busy_reg    <= tx_busy_next;
            tx_done_reg    <= tx_done_next;
            tick_count_reg <= tick_count_next;
        end
    end
    //next, output CL
    always @(*) begin
        n_state         = c_state;
        bit_count_next  = bit_count_reg;
        tx_next         = tx_reg;
        data_next       = data_reg;
        tx_busy_next    = tx_busy_reg;
        tx_done_next    = tx_done_reg;
        tick_count_next = tick_count_reg;

        case (c_state)
            IDLE: begin
                tx_next         = 1'b1;
                tx_busy_next    = 1'b0;
                tx_done_next    = 1'b0;
                tick_count_next = 0;
                if (tx_start) begin
                    data_next    = tx_data;
                    tx_busy_next = 1'b1;
                    n_state      = START;
                end
            end

            START: begin
                tx_next = 1'b0;
                bit_count_next = 3'd0;
                if (i_baud_tick) begin
                    if (tick_count_reg == 15) begin
                        tick_count_next = 0;
                        n_state = DATA;
                    end else tick_count_next = tick_count_reg + 1;
                end
            end

            DATA: begin
                tx_next = data_reg[0];
                if (i_baud_tick) begin
                    if (tick_count_reg == 15) begin
                        data_next       = {1'b0, data_reg[7:1]};
                        tick_count_next = 0;
                        if (bit_count_reg == 7) n_state = STOP;
                        else begin
                            n_state        = DATA;
                            bit_count_next = bit_count_reg + 1;
                        end
                    end else begin
                        tick_count_next = tick_count_reg + 1;
                    end
                end
            end

            STOP: begin
                tx_next = 1'b1;
                if (i_baud_tick) begin
                    if (tick_count_reg == 15) begin
                        tx_busy_next = 1'b0;
                        tx_done_next = 1'b1;
                        n_state = IDLE;
                    end else tick_count_next = tick_count_reg + 1;
                end
            end
        endcase
    end
endmodule
