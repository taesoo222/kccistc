`timescale 1ns / 1ps

module fifo #(
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

    register_file #(
        .WIDTH(WIDTH)
    ) U_REG_FILE (
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
        .reset(reset),
        .push (push),
        .pop  (pop),
        .wptr (w_wptr),
        .rptr (w_rptr),
        .full (full),
        .empty(empty)
    );


endmodule

module register_file #(
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


module fifo_control_unit #(
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

        case ({
            push, pop
        })
            2'b00: begin
                // initial
            end
            2'b01: begin
                // pop only 
                if (!empty_reg) begin
                    rptr_next = rptr_reg + 1;
                    full_next = 1'b0;
                    if (wptr_reg == rptr_next) empty_next = 1'b1;
                end
            end
            2'b10: begin
                // push only
                if (!full_reg) begin
                    wptr_next  = wptr_reg + 1;
                    empty_next = 1'b0;
                    if (wptr_next == rptr_reg) full_next = 1'b1;
                end
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
