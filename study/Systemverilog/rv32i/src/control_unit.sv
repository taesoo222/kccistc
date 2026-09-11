module control_unit
    import rv32i_pkg::*;
(
    input  logic        clk,
    input  logic        rst_n,
    input  logic [31:0] instr_code,
    input  logic        ready,
    output logic        rf_we,
    output logic        pc_en,        // 신호 추가
    output logic        branch,
    output logic        jal,
    output logic        jalr,
    output logic        alusrc_sel,
    output logic [ 3:0] alu_control,
    output logic [ 2:0] rf_srcsel,
    output logic        bus_we,
    output logic        transfer,     // to abp_reqeuster
    output logic [ 2:0] itype
);
    logic         [2:0] funct3;

    opcode_e            opcode;
    instr_btype_e       instr_btype;
    instr_rtype_e       instr_rtype;
    state_e c_state, n_state;


    assign funct3 = instr_code[14:12];
    assign opcode = opcode_e'(instr_code[6:0]);
    //for debuging
    assign instr_rtype = instr_rtype_e'(alu_control);
    assign instr_btype = instr_btype_e'(funct3);



    always_ff @(posedge clk) begin
        if (!rst_n) c_state <= FETCH;
        else c_state <= n_state;
    end

    always_comb begin
        n_state     = c_state;
        pc_en       = 1'b0;
        branch      = 1'b0;
        rf_we       = 1'b0;
        jal         = 1'b0;
        jalr        = 1'b0;
        alusrc_sel  = 1'b0;
        alu_control = 4'b0_000;
        rf_srcsel   = 3'd0;
        bus_we      = 1'b0;
        itype       = 3'b010;
        case (c_state)
            FETCH: begin
                pc_en   = 1'b1;
                n_state = DECODE;
            end

            DECODE: begin
                n_state = EXECUTE;
            end

            EXECUTE: begin
                case (opcode)
                    OP_RTYPE: begin
                        rf_we       = 1'b1;
                        alu_control = {instr_code[30], funct3};
                        n_state     = FETCH;
                    end
                    OP_STYPE: begin
                        rf_we      = 1'b0;
                        alusrc_sel = 1'b1;
                        n_state    = MEM;
                    end
                    OP_ITYPE: begin
                        rf_we      = 1'b1;
                        alusrc_sel = 1'b1;
                        if (funct3 == 3'b101)
                            alu_control = {instr_code[30], funct3};
                        else alu_control = {1'b0, funct3};
                        n_state = FETCH;
                    end
                    OP_ILTYPE: begin
                        alusrc_sel = 1'b1;
                        n_state    = MEM;
                    end

                    OP_BTYPE: begin
                        alu_control = {1'b0, funct3};
                        branch      = 1'b1;
                        n_state     = FETCH;
                    end

                    OP_ULTYPE: begin
                        rf_we     = 1'b1;
                        rf_srcsel = 3'd2;
                        n_state   = FETCH;
                    end

                    OP_UATYPE: begin
                        rf_we     = 1'b1;
                        rf_srcsel = 3'd3;
                        n_state   = FETCH;
                    end

                    OP_JTYPE: begin
                        rf_we     = 1'b1;
                        rf_srcsel = 3'd4;
                        jal       = 1'b1;
                        n_state   = FETCH;
                    end

                    OP_JLTYPE: begin
                        rf_we     = 1'b1;
                        rf_srcsel = 3'd4;
                        jalr      = 1'b1;
                        n_state   = FETCH;
                    end
                endcase
            end

            MEM: begin
                itype = funct3;
                transfer = 1'b1;
                if (opcode == OP_STYPE) begin
                    if (ready) begin
                        bus_we  = 1'b1;
                        n_state = FETCH;
                    end
                end  // OP_ILTYPE
            end

            WB: begin
                if (ready) begin
                    rf_we     = 1'b1;
                    rf_srcsel = 3'd1;
                    n_state   = FETCH;
                end
            end
        endcase
    end


endmodule