`timescale 1ns / 1ps

module top_adder_fnd (
    input [7:0] a,
    input [7:0] b,
    input btn_L,
    input btn_R,
    output [3:0] fnd_com,
    output [7:0] fnd_data,
    output c
);
    wire [7:0] s;

    fnd_controller U_FND_CNTL (
        .fnd_in  (s),
        .digit_sel ({btn_L,btn_R}), // concentannation msb : btn_L / lsb : btn_R
        .fnd_com (fnd_com),
        .fnd_data(fnd_data)
    );

    adder U_ADDER (
        .a  (a),
        .b  (b),
        .s  (s),
        .c  (c)
    );
    
endmodule
