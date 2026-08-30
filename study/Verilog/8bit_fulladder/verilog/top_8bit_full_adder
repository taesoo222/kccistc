module top_8bit_full_adder (
    input [7:0] a,
    input [7:0] b,
    output [7:0] s,
    output c
);
    full_adder_4bit FA1_4bit (
        .a  (a[3:0]),
        .b  (b[3:0]),
        .cin(0),
        .s  (s[3:0]),
        .c  (c1)
    );
    full_adder_4bit FA2_4bit (
        .a  (a[7:4]),
        .b  (b[7:4]),
        .cin(c1),
        .s  (s[7:4]),
        .c  (c)
    );
endmodule
