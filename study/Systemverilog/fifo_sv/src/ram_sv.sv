`timescale 1ns / 1ps

module ram_sv #(
    parameter WIDTH = 4
) (
    input  logic             clk,
    input  logic             we,     // we = 1 : write , we = 0 : read
    input  logic [WIDTH-1:0] waddr,
    input  logic [      7:0] wdata,
    input  logic [WIDTH-1:0] raddr,
    output logic [      7:0] rdata
);
    parameter DEPTH = 2 ** WIDTH;

    reg [7:0] mem[0:DEPTH-1];

    always_ff @(posedge clk) begin
        if (we) mem[waddr] <= wdata;
    end

    assign rdata = mem[raddr];

endmodule
