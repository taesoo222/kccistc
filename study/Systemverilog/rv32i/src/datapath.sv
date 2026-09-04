`define SIMULATION 

module datapath (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        rf_we,
    input  logic        alusrc_sel,
    input  logic [ 3:0] alu_control,
    input  logic        rf_srcsel,
    input  logic [31:0] instr_code,
    input  logic [31:0] drdata,
    output logic [31:0] instr_addr,
    output logic [31:0] daddr,
    output logic [31:0] dwdata
);

    logic [31:0] alu_result, rf_rd1, rf_rd2, alusrc_muxout, wb_muxout;
    logic [31:0] imm_extend;

    assign daddr  = alu_result;
    assign dwdata = rf_rd2;

    reg_file U_REG_FILE (
        .clk(clk),
        .rst_n(rst_n),
        .ra1(instr_code[19:15]),
        .ra2(instr_code[24:20]),
        .wa(instr_code[11:7]),
        .wd(wb_muxout),
        .we(rf_we),
        .rd1(rf_rd1),
        .rd2(rf_rd2)
    );
    imm_extender U_IMM_EXTEND (
        .instr_code(instr_code),
        .imm_extend(imm_extend)
    );
    mux_2x1 U_ALUSRC_MUX (
        .sel(alusrc_sel),
        .in0(rf_rd2),
        .in1(imm_extend),
        .mux_out(alusrc_muxout)
    );

    alu U_ALU (
        .rs1(rf_rd1),
        .rs2(alusrc_muxout),
        .alu_control(alu_control),
        .alu_result(alu_result)
    );

    mux_2x1 U_WB_MUX (
        .sel    (rf_srcsel),
        .in0    (alu_result),
        .in1    (drdata),
        .mux_out(wb_muxout)
    );

    program_counter U_PC (
        .clk(clk),
        .rst_n(rst_n),
        .pc(instr_addr)
    );
endmodule

module mux_2x1 (
    input  logic        sel,
    input  logic [31:0] in0,
    input  logic [31:0] in1,
    output logic [31:0] mux_out
);
    assign mux_out = (sel) ? in1 : in0;

endmodule


module reg_file (
    input  logic        clk,
    input  logic        rst_n,
    input  logic [ 4:0] ra1,
    input  logic [ 4:0] ra2,
    input  logic [ 4:0] wa,
    input  logic [31:0] wd,
    input  logic        we,
    output logic [31:0] rd1,
    output logic [31:0] rd2
);

    logic [31:0] ram_file[1:31];

    always_ff @(posedge clk) begin
        if (!rst_n) begin
`ifdef SIMULATION
            for (int i = 0; i < 32; i++) ram_file[i] <= i;
`else
            for (int i = 0; i < 32; i++) ram_file[i] <= 0;
`endif
        end else if (we) ram_file[wa] <= wd;
    end

    assign rd1 = (ra1 != 0) ? ram_file[ra1] : 32'd0;
    assign rd2 = (ra2 != 0) ? ram_file[ra2] : 32'd0;

endmodule

module alu (
    input  logic [31:0] rs1,
    input  logic [31:0] rs2,
    input  logic [ 3:0] alu_control,
    output logic [31:0] alu_result,
    output logic        b_taken
);

    always_comb begin
        alu_result = 32'h0000_0000;
        case (alu_control)
            // {funct7[5], funct3}
            4'b0_000: alu_result = rs1 + rs2;  // add
            4'b1_000: alu_result = rs1 - rs2;  // sub
            4'b0_100: alu_result = rs1 ^ rs2;  // xor
            4'b0_110: alu_result = rs1 | rs2;  // or
            4'b0_111: alu_result = rs1 & rs2;  // and
            4'b0_001: alu_result = rs1 << rs2;  // sll
            4'b0_101: alu_result = rs1 >> rs2;  // srl
            4'b1_101: alu_result = $signed(rs1) >>> rs2;  // sra
            4'b0_010:
            alu_result = $signed(rs1) < $signed(rs2) ? 32'd1 : 32'd0;  // slt
            4'b0_011: alu_result = rs1 < rs2 ? 32'd1 : 32'd0;  // sltu

        endcase
    end

    always_comb begin
        b_taken = 1'b0;
        case (alu_control)
            4'b0_000:
            if (rs1 == rs2) b_taken = 1;
            else b_taken = 0;  // BEQ
        
        
        
        
        endcase


    end

endmodule

// imm extender
module imm_extender
    import rv32i_pkg::*;
(
    input  logic [31:0] instr_code,
    output logic [31:0] imm_extend
);

    opcode_e opcode;

    assign opcode = opcode_e'(instr_code[6:0]); // opcode_e` : casting operator

    always_comb begin
        case (opcode)
            OP_STYPE:
            imm_extend = {
                {20{instr_code[31]}}, instr_code[31:25], instr_code[11:7]
            };
            OP_ITYPE, OP_ILTYPE:
            imm_extend = {{20{instr_code[31]}}, instr_code[31:20]};
            OP_BTYPE:
            imm_extend = {
                {20{instr_code[31]}},
                instr_code[31],
                instr_code[7],
                instr_code[30:25],
                instr_code[11:8]
            };
            //20bit + 1bit + 1bit + 6bit + 4bit + 1bit
            default: imm_extend = 32'h0000_0000;
        endcase
    end

endmodule


module program_counter (
    input  logic        clk,
    input  logic        rst_n,
    output logic [31:0] pc
);
    logic [31:0] register_pc;

    assign pc = register_pc;

    always_ff @(posedge clk) begin
        if (!rst_n) register_pc <= 32'd0;
        else register_pc <= register_pc + 4;
    end
endmodule




