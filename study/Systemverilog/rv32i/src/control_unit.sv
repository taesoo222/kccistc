module control_unit
    import rv32i_pkg::*;
(
    input  logic [31:0] instr_code,
    output logic        rf_we,
    output logic        alusrc_sel,
    output logic [ 3:0] alu_control,
    output logic        rf_srcsel,
    output logic        dwe,
    output logic [ 2:0] itype         // instruction tpye : funct3
);
    logic [2:0] funct3;

    opcode_e opcode;
    assign opcode = opcode_e'(instr_code[6:0]);

    assign funct3 = instr_code[14:12];

    always_comb begin
        rf_we       = 1'b0;
        alusrc_sel  = 1'b0;
        alu_control = 4'b0_000;  // {funct7[5], funct3}
        rf_srcsel   = 1'b0;  // TO control for WB to reg_file,
        dwe         = 1'b0;
        itype       = 3'b010;  // SW,LW
        case (opcode)
            OP_RTYPE: begin  // R-type
                rf_we = 1'b1;
                alusrc_sel = 1'b0;  // rd2-> mux (0) -> alu
                alu_control = {instr_code[30], funct3};
                rf_srcsel   = 1'b0;  // TO control for WB to reg_file, 0 : alu_result, 1:drdata
                dwe = 1'b0;
                itype = 3'b000;  // SW,LW
            end
            OP_STYPE: begin  // S-type
                rf_we       = 1'b0;
                alusrc_sel  = 1'b1;
                alu_control = 4'd0;
                rf_srcsel   = 1'b0;

                dwe         = 1'b1;
                itype       = funct3;
            end
            OP_ITYPE: begin  // I-type
                rf_we      = 1'b1;
                alusrc_sel = 1'b1;  // use imm
                rf_srcsel  = 1'b0;
                if (funct3 == 3'b101) alu_control = {instr_code[30], funct3};
                else alu_control = {1'b0, funct3};
                dwe   = 1'b0;
                itype = 3'b111;  // data_mem default mode
            end
            OP_ILTYPE: begin // IL-type
                rf_we       = 1'b1;
                alusrc_sel  = 1'b1;     // to calculate data mem addr
                alu_control = 4'd0;     // ADD RS1 +Imm
                rf_srcsel   = 1'b1;     // To control for WB to reg_file
                dwe         = 1'b0;     // load from data mem
                itype       = funct3;   // SW,LW
            end
        endcase
    end

endmodule
