`timescale 1ns / 1ps

module gp_datapath (
    input  logic       clk,
    input  logic [7:0] wd,
    input  logic [1:0] ra0,
    input  logic [1:0] ra1,
    input  logic [1:0] wa,
    input  logic       we,
    input  logic       rf_srcsel,
    input  logic       out_control,
    output logic       lt10,
    output logic [7:0] out
);

    logic [7:0] rf_src_out, alu_result, rd0, rd1;

    assign out = (out_control) ? rd1 : 8'hzz;

    mux_2x1 U_MUX (
        .sel    (rf_srcsel),
        .in0    (8'd1),
        .in1    (alu_result),
        .mux_out(rf_src_out)
    );

    reg_file U_REGFILE (
        .clk(clk),
        .wd (rf_src_out),
        .ra0(ra0),
        .ra1(ra1),
        .wa (wa),
        .we (we),
        .rd0(rd0),
        .rd1(rd1)
    );

    ALU U_ALU (
        .a         (rd0),
        .b         (rd1),
        .alu_result(alu_result)
    );

    lt10 U_LT10 (
        .in      (rd0),
        .lt10_out(lt10)
    );

endmodule

module mux_2x1 (
    input  logic       sel,
    input  logic [7:0] in0,
    input  logic [7:0] in1,
    output logic [7:0] mux_out
);
    assign mux_out = (sel) ? in1 : in0;

endmodule

module reg_file (
    input  logic       clk,
    input  logic [7:0] wd,
    input  logic [1:0] ra0,
    input  logic [1:0] ra1,
    input  logic [1:0] wa,
    input  logic       we,
    output logic [7:0] rd0,
    output logic [7:0] rd1
);

    logic [7:0] ram_file[0:3];

    always_ff @(posedge clk) begin
        if (we) ram_file[wa] <= wd;
    end

    assign rd0 = (ra0 != 0) ? ram_file[ra0] : 8'd0;
    assign rd1 = (ra1 != 0) ? ram_file[ra1] : 8'd0;

endmodule

module lt10 (
    input  logic [7:0] in,
    output logic       lt10_out
);

    assign lt10_out = (in < 7'd10);

endmodule

module ALU (
    input  logic [7:0] a,
    input  logic [7:0] b,
    output logic [7:0] alu_result
);

    assign alu_result = a + b;

endmodule
