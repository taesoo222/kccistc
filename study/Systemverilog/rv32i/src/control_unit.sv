module control_unit (
    input  logic [31:0] instr_code,
    output logic        rf_we,
    output logic [ 9:0] alu_control
);
    always_comb begin
        rf_we       = 1'b0;
        alu_control = 10'b000_000_0000;
        case (instr_code[6:0])
            7'b011_0011: begin
                rf_we = 1'b1;
                alu_control = {instr_code[14:12], instr_code[31:25]};
            end


        endcase
    end
endmodule
