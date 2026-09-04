package rv32i_pkg;

    typedef enum logic [6:0] {
        OP_RTYPE  = 7'b011_0011,
        OP_STYPE  = 7'b010_0011,
        OP_ITYPE  = 7'b001_0011,
        OP_ILTYPE = 7'b000_0011
    } opcode_e;

endpackage
