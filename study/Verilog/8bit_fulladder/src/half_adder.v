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
