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
