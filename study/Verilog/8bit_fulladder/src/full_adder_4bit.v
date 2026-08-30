module full_adder_4bit (
    input [3:0] a,
    input [3:0] b,
    input cin,
    output [3:0] s,
    output c
);
    wire c0, c1, c2, c3;

    fulladder FA1 (
        .a  (a[0]),
        .b  (b[0]),
        .cin(cin),
        .s  (s[0]),
        .c  (c1)
    );

    fulladder FA2 (
        .a  (a[1]),
        .b  (b[1]),
        .cin(c1),
        .s  (s[1]),
        .c  (c2)
    );

    fulladder FA3 (
        .a  (a[2]),
        .b  (b[2]),
        .cin(c2),
        .s  (s[2]),
        .c  (c3)
    );

    fulladder FA4 (
        .a  (a[3]),
        .b  (b[3]),
        .cin(c3),
        .s  (s[3]),
        .c  (c)
    );

endmodule
