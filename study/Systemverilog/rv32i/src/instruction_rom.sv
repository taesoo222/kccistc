module instruction_rom(
    input  logic [31:0] instr_addr,
    output logic [31:0] instr_code

);
    logic [31:0] instr_rom [0:127];
    


    `ifdef SIMULATION_TEST
    initial begin
        //instr_rom [0] = 32'h0041_82b3; // add x5, x3, x4 
        //instr_rom [1] = 32'h0053_2323; // sw x6, 6(x6) 
        //instr_rom [2] = 32'h0023_8413; // addi x8, x7,2
        //instr_rom [3] = 32'h0063_2503; // lw x10, 6(x6)
        //instr_rom [4] = 32'hfe62_8ce3; // beq x5,x6 -8
        //instr_rom [5] = 32'hfe62_9ce3; // bne x5,x6 -8
        //instr_rom [6] = 32'h1234_5437; // lui   x8, 0x12345
        //instr_rom [7] = 32'h0000_1497; // auipc x9, 0x00001

        //R_type
        //instr_rom[0]  = 32'h0020_81B3; // ADD  x3,  x1,  x2
        //instr_rom[1]  = 32'h4031_0233; // SUB  x4,  x2,  x3
        //instr_rom[2]  = 32'h0012_42B3; // XOR  x5,  x4,  x1
        //instr_rom[3]  = 32'h0022_E333; // OR   x6,  x5,  x2
        //instr_rom[4]  = 32'h0033_73B3; // AND  x7,  x6,  x3
        //instr_rom[5]  = 32'h0023_9433; // SLL  x8,  x7,  x2
        //instr_rom[6]  = 32'h0024_54B3; // SRL  x9,  x8,  x2
        //instr_rom[7]  = 32'h4024_D533; // SRA  x10, x9,  x2
        //instr_rom[8]  = 32'h0035_25B3; // SLT x12, x10, x3
        //instr_rom[9]  = 32'h40B2_5633; // SRA x11, x4, x12
        //instr_rom[10] = 32'h00B2_26B3; // SLT  x13, x4,  x11
        //instr_rom[11] = 32'h00C2_2733; // SLT x14, x4, x12
        //instr_rom[12] = 32'h00A5_B7B3; // SLTU x15, x11, x10
    end
    `endif
    initial begin
        $readmemh("./rtl/rom_code2.mem",instr_rom);
    end
    assign instr_code = instr_rom[instr_addr[31:2]];

endmodule   