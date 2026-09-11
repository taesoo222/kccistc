module control_unit
    import rv32i_pkg::*;
(
    input  logic [31:0] instr_code,
    input  logic        clk,
    input  logic        rst_n,
    input  logic        ready,  //form APB requester
    output logic        pc_en,        
    output logic        rf_we,
    output logic        alusrc_sel,
    output logic        branch,
    output logic        jal,
    output logic        jalr,
    output logic [ 3:0] alu_control,
    output logic [ 2:0] rf_srcsel,
    output logic        bus_we,
    output logic        transfer,
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
            rf_we       = 1'b0;
            alusrc_sel  = 1'b0;
            alu_control = 4'b0_000;
            rf_srcsel   = 3'd0;
            branch      = 1'b0;
            jal         = 1'b0;
            jalr        = 1'b0;
            bus_we      = 1'b0;
            pc_en       = 1'b0;
            transfer    = 1'b0;
            itype       = 3'b010;
            case (c_state)
                FETCH: begin
                    pc_en       = 1'b1;
                    n_state     = DECODE;
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
                            rf_we       = 1'b0;
                            alusrc_sel  = 1'b1;
                            n_state     = MEM;
                        end
                        OP_ITYPE: begin
                            rf_we      = 1'b1;
                            alusrc_sel = 1'b1;
                            if (funct3 == 3'b101)
                                alu_control = {instr_code[30], funct3};
                            else alu_control = {1'b0, funct3};
                            n_state   = FETCH;
                        end
                        OP_ILTYPE: begin
                            alusrc_sel  = 1'b1;
                            n_state     = MEM;
                        end

                        OP_BTYPE: begin
                            alu_control = {1'b0, funct3};
                            branch      = 1'b1;
                            n_state   = FETCH;
                        end

                        OP_ULTYPE: begin
                            rf_we       = 1'b1;
                            rf_srcsel   = 3'd2;
                            n_state     = FETCH;
                        end

                        OP_UATYPE: begin
                            rf_we       = 1'b1;
                            rf_srcsel   = 3'd3;
                            n_state     = FETCH;
                        end

                        OP_JTYPE: begin
                            rf_we       = 1'b1;
                            rf_srcsel   = 3'd4;
                            jal         = 1'b1;
                            n_state     = FETCH;
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
                    transfer    = 1'b1; // to APB requester
                    if(opcode == OP_STYPE) begin
                        bus_we = 1'b1;
                        if(ready) n_state = FETCH;
                    end 
                    else n_state = WB; // OP_ILTYPE
                end

                WB: begin
                    rf_we     = 1'b1;
                    rf_srcsel = 3'd1;
                    if(ready) n_state   = FETCH;
                end
            endcase
        end


endmodule

/*
    always_comb begin
            n_state     = c_state;
            pc_en       = 1'b0;
            rf_we       = 1'b0;
            alusrc_sel  = 1'b0;
            alu_control = 4'b0_000;
            rf_srcsel   = 3'd0;
            branch      = 1'b0;
            jal         = 1'b0;
            jalr        = 1'b0;
            dwe         = 1'b0;
            itype       = 3'b010;
            case (c_state)
                FETCH: begin
                    n_state     = DECODE;
                end

                DECODE: begin
                    n_state = EXECUTE;
                end

                EXECUTE: begin
                    case(opcode)
                        OP_RTYPE, OP_BTYPE, OP_ITYPE, OP_ULTYPE, OP_UATYPE, OP_JLTYPE, OP_JLTYPE : 
                            n_state = FETCH;
                        OP_STYPE, OP_ILTYPE :
                            n_state = MEM;
                    endcase
                end

                MEM : begin
                    if(opcode == OP_STYPE) n_state = FETCH;
                    else n_state = WB;
                end

                WB : n_state = FETCH;

            endcase
    end
*/

/*
always_comb begin
        rf_we       = 1'b0;
        alusrc_sel  = 1'b0;
        alu_control = 4'b0_000;  // {funct7[5],funct3}
        rf_srcsel   = 3'd0; // To control for WB to reg_file, 0:alu_result, 1: drdata
        branch      = 1'b0;
        jal         = 1'b0;
        jalr        = 1'b0;
        dwe         = 1'b0;
        itype       = 3'b010; // SW,LW
        case (c_state)
            OP_RTYPE: begin
                rf_we       = 1'b1;
                alusrc_sel  = 1'b0;
                alu_control = {instr_code[30], funct3};
                rf_srcsel   = 3'd0;
                branch      = 1'b0;
                jal         = 1'b0;
                jalr        = 1'b0;
                dwe         = 1'b0;
                itype       = 3'b000;
                //alu_control = {instr_code[14:12], instr_code[31:25]};
            end
            OP_STYPE: begin
                rf_we       = 1'b0;
                alusrc_sel  = 1'b1;
                alu_control = 4'd0;
                rf_srcsel   = 3'd0;
                branch      = 1'b0;
                jal         = 1'b0;
                jalr        = 1'b0;
                dwe         = 1'b1;
                itype       = funct3;
            end
            OP_ITYPE: begin
                rf_we       = 1'b1;
                alusrc_sel  = 1'b1;
                if(funct3 == 3'b 101) alu_control = {instr_code[30], funct3};
                else alu_control = {1'b0, funct3};
                rf_srcsel   = 3'd0;
                branch      = 1'b0;
                jal         = 1'b0;
                jalr        = 1'b0;
                dwe         = 1'b0;
                itype       = 3'b111; // for : data mem default mode
            end
            OP_ILTYPE: begin
                rf_we       = 1'b1;
                alusrc_sel  = 1'b1;
                alu_control = 4'd0;
                rf_srcsel   = 3'd1;
                jal         = 1'b0;
                jalr        = 1'b0;
                dwe         = 1'b0;
                itype       = funct3;
            end
             
            OP_BTYPE: begin
                rf_we       = 1'b0;
                alusrc_sel  = 1'b0;
                alu_control = {1'b0, funct3};
                rf_srcsel   = 3'd0;
                branch      = 1'b1;
                jal         = 1'b0;
                jalr        = 1'b0;
                dwe         = 1'b0;
                itype       = 3'b111;
            end

            OP_ULTYPE: begin
                rf_we       = 1'b1;
                alusrc_sel  = 1'b0;
                alu_control = 4'd0;
                rf_srcsel   = 3'd2;
                branch      = 1'b0;
                jal         = 1'b0;
                jalr        = 1'b0;
                dwe         = 1'b0;
                itype       = 3'b111;
            end

            OP_UATYPE: begin
                rf_we       = 1'b1;
                alusrc_sel  = 1'b0;
                alu_control = 4'd0;
                rf_srcsel   = 3'd3;
                branch      = 1'b0;
                jal         = 1'b0;
                jalr        = 1'b0;
                dwe         = 1'b0;
                itype       = 3'b111;
            end

            OP_JTYPE: begin
                rf_we       = 1'b1;
                alusrc_sel  = 1'b0;
                alu_control = 4'd0;
                rf_srcsel   = 3'd4;
                branch      = 1'b0;
                jal         = 1'b1;
                jalr        = 1'b0;
                dwe         = 1'b0;
                itype       = 3'b111;
            end

            OP_JLTYPE: begin
                rf_we       = 1'b1;
                //alusrc_sel  = 1'b0;
                //alu_control = 4'd0;
                rf_srcsel   = 3'd4;
                //branch      = 1'b0;
                //jal         = 1'b0;
                jalr        = 1'b1;
                //dwe         = 1'b0;
                //itype       = 3'b000;
            end
        endcase
    end
*/