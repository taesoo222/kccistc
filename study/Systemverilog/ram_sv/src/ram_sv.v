`timescale 1ns / 1ps

module ram (
    input        clk,
    input        we,     // we = 1 : write , we = 0 : read
    input  [7:0] addr,
    input  [7:0] wdata,
    output [7:0] rdata
);

    reg [7:0] mem[0:255];

    always @(posedge clk) begin
        if (we) mem[addr] <= wdata;
    end

    assign rdata = mem[addr];

endmodule
