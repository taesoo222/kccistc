`timescale 1ns / 1ps

module apb_gpo (
    input  logic        clk,
    input  logic        rst_n,
    output logic [ 7:0] led,
    input  logic        PSEL,
    input  logic        PENABLE,
    input  logic [31:0] PADDR,
    input  logic [31:0] PWDATA,
    input  logic        PWRITE,
    output logic [31:0] PRDATA,
    output logic        PREADY
);

    logic [31:0] gpo_ctr;
    logic [31:0] gpo_odr;

    assign PREADY = (PENABLE & PSEL) ? 1'b1 : 1'b0;

    assign led = gpo_odr[7:0] & gpo_ctr[7:0];

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            gpo_ctr <= 32'd0;
            gpo_odr <= 32'd0;
        end else begin
            if (PREADY && PWRITE) begin
                case (PADDR[2])
                    1'b0: gpo_ctr <= PWDATA;
                    1'b1: gpo_odr <= PWDATA;
                endcase
            end
        end
    end

    always_comb begin
        PRDATA = 32'd0;
        if (PREADY && !PWRITE) begin
            case (PADDR[2])
                1'b0: PRDATA = gpo_ctr;
                1'b1: PRDATA = gpo_odr;
            endcase
        end else begin
            PRDATA = 32'd0;
        end
    end


endmodule
