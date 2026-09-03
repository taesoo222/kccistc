module rv32i_top (
    input clk,
    input rst_n
);
    logic [31:0] instr_code;
    logic [31:0] instr_addr;
    logic [31:0] daddr;
    logic [31:0] dwdata;
    logic        dwe;
    logic [ 2:0] itype;

    instruction_rom U_INSTR_ROM (.*);

    rv32i_cpu U_RV32I_CPU (.*);

    data_mem U_DATA_MEM (.*);

endmodule

module rv32i_cpu (
    input  logic        clk,
    input  logic        rst_n,
    input  logic [31:0] instr_code,
    output logic [31:0] instr_addr,
    output logic [31:0] daddr,
    output logic [31:0] dwdata,
    output logic        dwe,
    output logic [ 2:0] itype
);
    logic rf_we;
    logic alusrc_sel;
    logic [3:0] alu_control;

    control_unit U_CONTROL_UNIT (.*);

    datapath U_DATAPATH (.*);
endmodule
