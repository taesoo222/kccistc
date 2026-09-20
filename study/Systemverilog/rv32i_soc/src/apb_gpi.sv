`timescale 1ns / 1ps

module apb_gpi (
    input  logic        clk,
    input  logic        rst_n,
    input  logic [ 7:0] GPI_IN,
    input  logic        PSEL,
    input  logic        PENABLE,
    input  logic [31:0] PADDR,
    input  logic [31:0] PWDATA,
    input  logic        PWRITE,
    output logic [31:0] PRDATA,
    output logic        PREADY
);
    localparam GPI_CTR_ADDR = 8'h00, GPI_IDR_ADDR = 8'h04;

    logic [7:0] GPI_CTR;
    logic [7:0] GPI_IDR;

    assign PREADY = (PENABLE & PSEL) ? 1'b1 : 1'b0;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            GPI_CTR <= 8'h0;
            GPI_IDR <= 8'h0;
        end else begin
            if (PREADY & PWRITE) begin
                if (PADDR[7:0] == GPI_CTR_ADDR) GPI_CTR <= PWDATA;
            end
        end
    end

    assign PRDATA = (PADDR[7:0] == GPI_CTR_ADDR) ? {24'h0,GPI_CTR} :
                    (PADDR[7:0] == GPI_IDR_ADDR) ? {24'h0,GPI_IDR} : 32'hx;

    // General purpose Input
    genvar i;
    generate
        for (i = 0; i < 8; i++) begin
            assign GPI_IDR[7:0] = (GPI_CTR[i]) ? GPI_IN[i] : 1'bz;
        end
    endgenerate

endmodule
