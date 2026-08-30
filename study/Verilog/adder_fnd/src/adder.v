module adder ( //8bit full adder
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


module fulladder (
    input  a,
    input  b,
    input  cin,
    output s,
    output c
);

    wire s1, c1, c2;
    assign c = c2 | c1;

    half_adder HA2 (
        .a(s1),
        .b(cin),
        .s(s),
        .c(c2)
    );

    half_adder HA1 (
        .a(a),
        .b(b),
        .s(s1),
        .c(c1)
    );
endmodule


module half_adder (
    input  a,
    input  b,
    output s,
    output c
);

    assign s = a ^ b;
    assign c = a & b;

    //by gate primitive 
    // xor(s,a,b); // gatename(ouput, input0, input1, input...)
    // and(c,a,b);

endmodule
