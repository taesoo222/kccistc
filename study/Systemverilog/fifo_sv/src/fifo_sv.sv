`timescale 1ns / 1ps

module fifo_sv #(
    parameter WIDTH = 2
) (
    input        clk,
    input        rst_n,
    input        push,
    input        pop,
    input  [7:0] wdata,  //push data
    output [7:0] rdata,  //pop data
    output       full,
    output       empty
);
    wire [WIDTH-1 : 0] w_wptr, w_rptr;

    ram_sv #(
        .WIDTH(WIDTH)
    ) U_RAM (
        .clk  (clk),
        .waddr(w_wptr),
        .wdata(wdata),
        .we   ((~full&push)),
        .raddr(w_rptr),
        .rdata(rdata)
    );

    fifo_control_unit #(
        .WIDTH(WIDTH)
    ) U_CONTROL_UNIT (
        .clk  (clk),
        .rst_n(rst_n),
        .push (push),
        .pop  (pop),
        .wptr (w_wptr),
        .rptr (w_rptr),
        .full (full),
        .empty(empty)
    );
endmodule

module fifo_control_unit #(
    parameter WIDTH = 4
) (
    input  logic             clk,
    input  logic             rst_n,
    input  logic             push,
    input  logic             pop,
    output logic [WIDTH-1:0] wptr,
    output logic [WIDTH-1:0] rptr,
    output logic             full,
    output logic             empty
);

    logic [WIDTH-1:0] wptr_next;
    logic [WIDTH-1:0] rptr_next;
    logic full_next;
    logic empty_next;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            wptr  <= 1'b0;
            rptr  <= 1'b0;
            full  <= 1'b0;
            empty <= 1'b1;
        end else begin
            wptr  <= wptr_next;
            rptr  <= rptr_next;
            full  <= full_next;
            empty <= empty_next;
        end
    end

    always_comb begin
        wptr_next  = wptr;
        rptr_next  = rptr;
        empty_next = empty;
        full_next  = full;

        case ({
            push, pop
        })

            2'b00: begin
            end
            // only pop
            2'b01: begin
                if (!empty) begin
                    rptr_next = rptr + 1'b1;
                    full_next = 1'b0;
                    if (wptr == rptr_next) empty_next = 1'b1;
                end
            end
            // push only
            2'b10: begin
                if (!full) begin
                    wptr_next  = wptr + 1'b1;
                    empty_next = 1'b0;
                    if (wptr_next == rptr) full_next = 1'b1;
                end
            end
            // push pop
            2'b11: begin
                if (full) begin
                    rptr_next = rptr + 1'b1;
                    full_next = 1'b0;
                end else if (empty) begin
                    wptr_next  = wptr + 1'b1;
                    empty_next = 1'b0;
                end else begin
                    wptr_next = wptr + 1'b1;
                    rptr_next = rptr + 1'b1;
                end
            end
        endcase
    end
endmodule
