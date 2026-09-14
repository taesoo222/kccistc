module rv32i_top (
    input               clk,
    input               rst,
    input  logic [11:0] sw,
    output logic [11:0] led
);
    logic rst_n;
    assign rst_n = ~rst;

    // rv32 cpu
    logic [31:0] instr_code;
    logic [31:0] instr_addr;
    logic [31:0] bus_addr;
    logic [31:0] bus_wdata;
    logic [31:0] bus_rdata;
    logic        ready;
    logic        bus_we;
    logic        transfer;
    logic [ 2:0] itype;

    // apb bus
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
    logic        PENABLE;
    logic        PWRITE;
    logic        PSEL0;
    logic        PSEL1;
    logic        PSEL2;
    logic        PSEL3;
    logic        PSEL4;
    logic        PSEL5;
    logic        PSEL6;

    instruction_rom U_INSTR_ROM (.*);
    rv32i_cpu U_RV32I_CPU (.*);

    apb_requester U_APB_REQUESTER (.*);
    apb_bram U_APB_BRAM (
        .*,
        .PSEL  (PSEL0),
        .PREADY(PREADY0),
        .PRDATA(PRDATA0)
    );
    apb_gpi U_APB_GPI (
        .*,
        .PSEL  (PSEL1),
        .PREADY(PREADY1),
        .PRDATA(PRDATA1),
        .GPI_IN   (sw[7:0])
    );

    apb_gpo U_APB_GPO (
        .*,
        .PSEL  (PSEL2),
        .PREADY(PREADY2),
        .PRDATA(PRDATA2),
        .led   (led[7:0])

    );

    // apb_gpio U_APB_GPIO (
    //     .*,
    //     .PSEL  (PSEL3),
    //     .PREADY(PREADY3),
    //     .PRDATA(PRDATA3)

    // );

    //data_memory U_DATA_MEM(.*);
endmodule

module rv32i_cpu (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        ready,
    input  logic [31:0] instr_code,
    input  logic [31:0] bus_rdata,
    output logic [31:0] instr_addr,
    output logic [31:0] bus_addr,
    output logic [31:0] bus_wdata,
    output logic        bus_we,
    output logic        transfer,
    output logic [ 2:0] itype
);
    logic rf_we, alusrc_sel, branch, jal, jalr, pc_en;
    logic [2:0] rf_srcsel;
    logic [3:0] alu_control;

    control_unit U_CONTROL_UNIT (.*);

    datapath U_DATAPATH (.*);
endmodule
