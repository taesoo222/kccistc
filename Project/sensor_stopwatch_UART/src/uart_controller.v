`timescale 1ns / 1ps

module uart_controller (
    input        clk,
    input        reset,
    input        rx,
    input        rx_pop,
    output [7:0] rx_data,
    output       rx_empty
);
    wire w_baud_tick_x16_rx;
    // wire rx
    wire w_rx_done;
    wire [7:0] w_rx_data;
    uart_rx U_UART_RX (
        .clk        (clk),
        .reset      (reset),
        .rx         (rx),
        .i_baud_tick(w_baud_tick_x16_rx),
        .rx_data    (w_rx_data),
        .rx_done    (w_rx_done)
    );

    fifo_rx U_FIFO_RX (
        .clk  (clk),
        .reset(reset),
        .push (w_rx_done),
        .pop  (rx_pop),
        .wdata(w_rx_data),  // push data
        .rdata(rx_data),    // pop data
        .full (),
        .empty(rx_empty)
    );
    baud_tick_x16_rx U_BAUD_TICK_x16 (
        .clk        (clk),
        .reset      (reset),
        .o_baud_tick(w_baud_tick_x16_rx)
    );
endmodule

module baud_tick_x16_rx (
    input  clk,
    input  reset,
    output o_baud_tick
);
    //9600hz
    parameter F_COUNT = 100_000_000 / (9600 * 16);
    reg  [$clog2(F_COUNT)-1:0] count_reg;
    wire [$clog2(F_COUNT)-1:0] count_next;

    always @(posedge clk, posedge reset) begin
        if (reset) begin
            count_reg <= 1'b0;
        end else begin
            count_reg <= count_next;
        end
    end
    // next CL
    assign count_next  = (count_reg == (F_COUNT - 1)) ? 0 : count_reg + 1;
    // output CL
    assign o_baud_tick = (count_reg == (F_COUNT - 1)) ? 1 : 0;
endmodule

module uart_rx (
    input        clk,
    input        reset,
    input        rx,
    input        i_baud_tick,
    output [7:0] rx_data,
    output       rx_done
);
    // state
    localparam [1:0] IDLE = 2'b00, START = 2'b01, DATA = 2'b10, STOP = 2'b11;
    reg [1:0] c_state, n_state;
    reg [3:0] tick_count_reg, tick_count_next;
    reg [2:0] bit_count_reg, bit_count_next;
    reg [7:0] data_reg, data_next;
    //for CL output
    //reg rx_done_reg;
    reg rx_done_reg, rx_done_next;

    assign rx_done = rx_done_reg;
    assign rx_data = data_reg;

    // state SL
    always @(posedge clk, posedge reset) begin
        if (reset) begin
            c_state        <= IDLE;
            tick_count_reg <= 0;
            bit_count_reg  <= 0;
            data_reg       <= 0;
            rx_done_reg    <= 0;
        end else begin
            c_state        <= n_state;
            tick_count_reg <= tick_count_next;
            bit_count_reg  <= bit_count_next;
            data_reg       <= data_next;
            rx_done_reg    <= rx_done_next;
        end
    end

    // next
    always @(*) begin
        n_state = c_state;
        tick_count_next = tick_count_reg;
        bit_count_next = bit_count_reg;
        data_next = data_reg;
        //for CL output
        //rx_done_reg = 0;
        rx_done_next = rx_done_reg;
        case (c_state)
            IDLE: begin
                //for CL output
                //rx_done_reg = 0;
                rx_done_next   = 0;
                bit_count_next = 0;
                if (i_baud_tick) begin
                    if (!rx) begin
                        if (tick_count_reg == 7) begin
                            n_state         = START;
                            tick_count_next = 0;
                        end else begin
                            tick_count_next = tick_count_reg + 1;
                        end
                    end else begin
                        tick_count_next = 0;
                    end
                end
            end
            START: begin
                if (i_baud_tick) begin
                    if (tick_count_reg == 15) begin
                        tick_count_next = 0;
                        n_state = DATA;
                    end else begin
                        tick_count_next = tick_count_reg + 1;
                    end
                end
            end
            DATA: begin
                if (i_baud_tick) begin
                    if (tick_count_reg == 0) begin
                        //data_next = data_reg[bit_count_reg]; //PIPO, bit.indexing
                        //SIPO 
                        data_next = {rx, data_reg[7:1]};
                    end
                    if (tick_count_reg == 15) begin
                        tick_count_next = 0;
                        if (bit_count_reg == 7) begin
                            n_state = STOP;
                        end else begin
                            bit_count_next = bit_count_reg + 1;
                        end
                    end else begin
                        tick_count_next = tick_count_reg + 1;
                    end
                end
            end
            STOP: begin
                if (i_baud_tick) begin
                    //rx_done_reg = 1;
                    rx_done_next = 1;
                    if (tick_count_reg == 7) begin
                        //for CL output
                        //rx_done_reg = 0;
                        n_state = IDLE;
                    end else begin
                        rx_done_next = 0;
                        tick_count_next = tick_count_reg + 1;
                    end
                end
            end
        endcase
    end
endmodule

module fifo_rx #(
    parameter WIDTH = 2
) (
    input        clk,
    input        reset,
    input        push,
    input        pop,
    input  [7:0] wdata,  //push data
    output [7:0] rdata,  //pop data
    output       full,
    output       empty
);
    wire [WIDTH-1 : 0] w_wptr, w_rptr;
    
    register_file_rx #(
        .WIDTH(2)
    ) U_REG_FILE (
        .clk  (clk),
        .waddr(w_wptr),
        .wdata(wdata),
        .we   ((~full&push)),
        .raddr(w_rptr),
        .rdata(rdata)
    );

    fifo_control_unit_rx #(
        .WIDTH(2)
    ) U_CONTROL_UNIT (
        .clk  (clk),
        .reset(reset),
        .push (push),
        .pop  (pop),
        .wptr (w_wptr),
        .rptr (w_rptr),
        .full (full),
        .empty(empty)
    );


endmodule

module register_file_rx #(
    parameter WIDTH = 2
) (
    input                clk,
    input  [WIDTH-1 : 0] waddr,
    input  [        7:0] wdata,
    input                we,
    input  [WIDTH-1 : 0] raddr,
    output [        7:0] rdata

);
    parameter DEPTH = 2 ** WIDTH;
    reg [7:0] register_file[0:DEPTH-1];

    always @(posedge clk) begin
        if (we) begin
            register_file[waddr] <= wdata;
        end
    end

    // rdat : CL output
    assign rdata = register_file[raddr];
endmodule


module fifo_control_unit_rx #(
    parameter WIDTH = 2
) (
    input              clk,
    input              reset,
    input              push,
    input              pop,
    output [WIDTH-1:0] wptr,
    output [WIDTH-1:0] rptr,
    output             full,
    output             empty
);

    reg [WIDTH-1:0] wptr_reg, wptr_next;
    reg [WIDTH-1:0] rptr_reg, rptr_next;
    reg full_reg, full_next;
    reg empty_reg, empty_next;

    assign wptr  = wptr_reg;
    assign rptr  = rptr_reg;
    assign full  = full_reg;
    assign empty = empty_reg;

    ////// state register //////
    always @(posedge clk, posedge reset) begin
        if (reset) begin
            wptr_reg  <= 1'b0;
            rptr_reg  <= 1'b0;
            full_reg  <= 1'b0;
            empty_reg <= 1'b1;
        end else begin
            wptr_reg  <= wptr_next;
            rptr_reg  <= rptr_next;
            full_reg  <= full_next;
            empty_reg <= empty_next;
        end
    end

    always @(*) begin
        wptr_next  = wptr_reg;
        rptr_next  = rptr_reg;
        empty_next = empty_reg;
        full_next  = full_reg;

        case ({push, pop})
            2'b00: begin
                // initial
            end
            2'b01: begin
                // pop only 
                rptr_next = rptr_reg + 1;
                full_next = 1'b0;
                if (wptr_reg == rptr_next) empty_next = 1'b1;
            end
            2'b10: begin
                // push only
                wptr_next  = wptr_reg + 1;
                empty_next = 1'b0;
                if (wptr_next == rptr_reg) full_next = 1'b1;
            end
            2'b11: begin
                // push_pop
                if (full) begin
                    rptr_next = rptr_reg + 1;
                    full_next = 1'b0;
                end else if (empty) begin
                    wptr_next  = wptr_reg + 1;
                    empty_next = 1'b0;
                end else begin
                    wptr_next = wptr_reg + 1;
                    rptr_next = rptr_reg + 1;
                end
            end
        endcase
    end
endmodule
