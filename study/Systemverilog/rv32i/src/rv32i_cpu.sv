module rv32i_top (
    input clk,
    input rst_n
);
    // rv32 cpu interface
    logic [31:0] instr_code;
    logic [31:0] instr_addr;
    logic [31:0] bus_addr;
    logic [31:0] bus_wdata;
    logic [31:0] bus_rdata;
    logic        ready;
    logic        bus_we;
    logic        transfer;
    logic [ 2:0] itype;

    // APB interface
    logic        PREADY0;
    logic        PREADY1;
    logic        PREADY2;
    logic        PREADY3;
    logic        PREADY4;
    logic        PREADY5;
    logic        PREADY6;
    logic [31:0] PRDATA0;
    logic [31:0] PRDATA1;
    logic [31:0] PRDATA2;
    logic [31:0] PRDATA3;
    logic [31:0] PRDATA4;
    logic [31:0] PRDATA5;
    logic [31:0] PRDATA6;
    logic [31:0] PADDR;
    logic [31:0] PWDATA;
    logic        PWRITE;
    logic        PENABLE;
    logic        PSEL0;
    logic        PSEL1;
    logic        PSEL2;
    logic        PSEL3;
    logic        PSEL4;
    logic        PSEL5;
    logic        PSEL6;

    instruction_rom U_INSTR_ROM (.*);

    rv32i_cpu U_RV32I_CPU (.*);

    apb_requester U_APB_REQ (.*);

    //data_mem U_DATA_MEM (.*);

    apb_bram U_APB_BRAM (
        .*,
        .PSEL  (PSEL0),
        .PREADY(PREADY0),
        .PRDATA(PRDATA0)
    );


endmodule

module rv32i_cpu (
    input  logic        clk,
    input  logic        rst_n,
    input  logic [31:0] instr_code,
    input  logic [31:0] bus_rdata,
    input  logic        ready,
    output logic [31:0] instr_addr,
    output logic [31:0] bus_addr,
    output logic [31:0] bus_wdata,
    output logic        bus_we,
    output logic        transfer,
    output logic [ 2:0] itype
);
    logic       pc_en;
    logic       rf_we;
    logic       alusrc_sel;
    logic [3:0] alu_control;
    logic [2:0] rf_srcsel;
    logic       branch;
    logic       jalr;
    logic       jal;

    control_unit U_CONTROL_UNIT (.*);

    datapath U_DATAPATH (.*);
endmodule
