module control_unit (
    input  logic [31:0] instr_code,
    output logic        rf_we,
    output logic        alusrc_sel,
    output logic [ 3:0] alu_control,
    output logic        dwe,
    output logic [ 2:0] itype         // instruction tpye : funct3
);
    logic [2:0] funct3;
    logic [6:0] opcode;
    
    assign funct3 = instr_code[14:12];
    assign opcode = instr_code[6:0];

    always_comb begin
        rf_we       = 1'b0;
        alusrc_sel  = 1'b0;
        alu_control = 4'b0_000;  // {funct7[5], funct3}
        dwe         = 1'b0;
        itype       = 3'b010;  // SW,LW
        case (opcode)
            7'b011_0011: begin  // R-type
                rf_we       = 1'b1;
                alusrc_sel  = 1'b0;  // rd2-> mux (0) -> alu
                alu_control = {instr_code[30], funct3};
                dwe         = 1'b0;
                itype       = 3'b000;  // SW,LW
            end
            7'b010_0011: begin  // S-type
                rf_we       = 1'b0;
                alusrc_sel  = 1'b1;
                alu_control = 4'd0;
                dwe         = 1'b1;
                itype       = funct3;
            end
        endcase
    end

endmodule
