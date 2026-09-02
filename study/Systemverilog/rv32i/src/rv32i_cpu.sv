module rv32i_top (
    input clk,
    input rst_n
);
    logic [31:0] instr_code;
    logic [ 5:0] instr_addr;
    
    instruction_rom U_INSTR_ROM (.*);

    rv32i_cpu U_RV32I_CPU (.*);

endmodule

module rv32i_cpu (
    input               clk,
    input               rst_n,
    input  logic [31:0] instr_code,
    output logic [ 5:0] instr_addr
);
    logic rf_we;
    logic [9:0] alu_control;

    control_unit U_CONTROL_UNIT (.*);

    datapath U_DATAPATH (.*);

endmodule
