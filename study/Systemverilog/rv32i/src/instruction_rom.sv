
module instruction_rom (
    input  logic [31:0] instr_addr,
    output logic [31:0] instr_code
);

    logic [31:0] instr_rom[0:15];

    initial begin
        instr_rom[0] = 32'h0041_82b3;  // add x5, x3, x4
        instr_rom[1] = 32'h0053_2323;  // sw  x6, x3, x4
    end


    assign instr_code = instr_rom[instr_addr[5:2]];

endmodule
