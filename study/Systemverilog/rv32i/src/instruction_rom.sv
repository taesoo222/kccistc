
module instruction_rom (
    input  logic [31:0] instr_addr,
    output logic [31:0] instr_code
);

    logic [31:0] instr_rom[0:15];

    initial begin
        // edge case
        instr_rom[0]  = 32'h00110533;  // add   x10 = x2 + x1           (0xFFFFFFFF + 1)
        instr_rom[1]  = 32'h401005b3;  // sub   x11 = x0 - x1           (0 - 1)
        instr_rom[2]  = 32'h01f09633;  // sll   x12 = x1 << x31         (1 << 31)
        instr_rom[3]  = 32'h001126b3;  // slt   x13 = (x2 < x1) signed  (0xFFFFFFFF < 1)
        instr_rom[4]  = 32'h00113733;  // sltu  x14 = (x2 < x1) unsigned(0xFFFFFFFF < 1)
        instr_rom[5]  = 32'h0010c7b3;  // xor   x15 = x1 ^ x1           (1 ^ 1)
        instr_rom[6]  = 32'h00104833;  // xor   x16 = x0 ^ x1           (0 ^ 1)
        instr_rom[7]  = 32'h0042d8b3;  // srl   x17 = x5 >> x4          (0x80000000 >> 4)
        instr_rom[8]  = 32'h4042d933;  // sra   x18 = x5 >>> x4         (0x80000000 >>> 4)
        instr_rom[9]  = 32'h002069b3;  // or    x19 = x0 | x2           (0 | 0xFFFFFFFF)
        instr_rom[10] = 32'h00017a33;  // and   x20 = x2 & x0           (0xFFFFFFFF & 0)
    end


    assign instr_code = instr_rom[instr_addr[5:2]];

endmodule
