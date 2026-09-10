`define SIMULATION

module datapath (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        pc_en,
    input  logic        rf_we,
    input  logic        alusrc_sel,
    input  logic [ 3:0] alu_control,
    input  logic [ 2:0] rf_srcsel,
    input  logic        branch,
    input  logic        jal,
    input  logic        jalr,
    input  logic [31:0] drdata,
    input  logic [31:0] instr_code,
    output logic [31:0] instr_addr,
    output logic [31:0] daddr,
    output logic [31:0] dwdata
);

    logic [31:0] alu_result, rf_rd1, rf_rd2, pc_4, pc_imm;
    logic [31:0] imm_extend, alusrc_muxout, wb_muxout;
    logic [31:0]
        dec2exe_rs1,
        dec2exe_rs2,
        dec2exe_imm,
        exe2mem_alu,
        exe2mem_rs2,
        mem2wb_rdata;
    logic b_taken;


    assign daddr  = exe2mem_alu;
    assign dwdata = exe2mem_rs2;

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

    // decode to execute
    register U_DEC_RS1 (
        .clk(clk),
        .rst_n(rst_n),
        .data_in(rf_rd1),
        .data_out(dec2exe_rs1)
    );


    register U_DEC_RS2 (
        .clk(clk),
        .rst_n(rst_n),
        .data_in(rf_rd2),
        .data_out(dec2exe_rs2)
    );

    register U_DEC_IMM (
        .clk(clk),
        .rst_n(rst_n),
        .data_in(imm_extend),
        .data_out(dec2exe_imm)
    );

    // execute to mem
    register U_EXE_ALU (
        .clk(clk),
        .rst_n(rst_n),
        .data_in(alu_result),
        .data_out(exe2mem_alu)
    );

    register U_EXE_RS2 (
        .clk(clk),
        .rst_n(rst_n),
        .data_in(dec2exe_rs2),
        .data_out(exe2mem_rs2)
    );

    register U_MEM_RDATA (
        .clk(clk),
        .rst_n(rst_n),
        .data_in(drdata),
        .data_out(mem2wb_rdata)
    );


    mux_wb U_WB_MUX (
        .sel(rf_srcsel),
        .in0(alu_result),
        .in1(mem2wb_rdata),
        .in2(dec2exe_imm),
        .in3(pc_imm),
        .in4(pc_4),
        .mux_out(wb_muxout)
    );


    imm_extend U_IMM_EXTEND (
        .clk(clk),
        .rst_n(rst_n),
        .instr_code(instr_code),
        .imm_extend(imm_extend)
    );

    mux_2x1 U_ALUSRC_MUX (
        .sel(alusrc_sel),
        .in0(dec2exe_rs2),
        .in1(dec2exe_imm),
        .mux_out(alusrc_muxout)
    );

    alu U_ALU (
        .rs1(dec2exe_rs1),
        .rs2(alusrc_muxout),
        .alu_control(alu_control),
        .alu_result(alu_result),
        .b_taken(b_taken)
    );

    program_counter U_PC (
        .clk       (clk),
        .rst_n     (rst_n),
        .b_taken   (b_taken),
        .branch    (branch),
        .jal       (jal),
        .jalr      (jalr),
        .pc_en     (pc_en),
        .rs1       (rf_rd1),
        .imm_extend(dec2exe_imm),
        .pc        (instr_addr),
        .pc_4      (pc_4),
        .pc_imm    (pc_imm)        //pc_imm
    );
endmodule

module register (
    input  logic        clk,
    input  logic        rst_n,
    input  logic [31:0] data_in,
    output logic [31:0] data_out
);
    always_ff @(posedge clk) begin
        if (!rst_n) data_out <= 32'd0;
        else data_out <= data_in;
    end

endmodule



module mux_2x1 (
    input logic sel,
    input logic [31:0] in0,
    input logic [31:0] in1,
    output logic [31:0] mux_out
);

    assign mux_out = (sel) ? in1 : in0;
endmodule

module mux_wb (
    input  logic [ 2:0] sel,
    input  logic [31:0] in0,
    input  logic [31:0] in1,
    input  logic [31:0] in2,
    input  logic [31:0] in3,
    input  logic [31:0] in4,
    output logic [31:0] mux_out
);

    //    assign mux_out = (sel==3'd0) ? in0 : (sel==3'd1) ? in1 :
    //                    (sel==3'd2) ? in2 :  (sel==3'd3) ? in3 :
    //                    (sel==3'd4) ? in4 : 32'd0;
    always_comb begin
        mux_out = in0;
        case (sel)
            3'b000: mux_out = in0;
            3'b001: mux_out = in1;
            3'b010: mux_out = in2;
            3'b011: mux_out = in3;
            3'b100: mux_out = in4;
        endcase
    end
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
        //if(!rst_n) begin
        //`ifdef SIMULATION
        //for(int i = 1; i<32 ; i++)
        //    ram_file[i] <= i;
        //`endif
        //ram_file[1] <= 4;
        //ram_file[2] <= 8;
        //end
        //else 
        if (we) ram_file[wa] <= wd;
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
        alu_result = 4'h0;
        case (alu_control)
            // {funct7[5], funct3}
            4'b0_000: alu_result = rs1 + rs2;  // add
            4'b1_000: alu_result = rs1 - rs2;  // sub
            4'b0_100: alu_result = rs1 ^ rs2;  // xor
            4'b0_110: alu_result = rs1 | rs2;  // or
            4'b0_111: alu_result = rs1 & rs2;  // and
            4'b0_001: alu_result = rs1 << rs2;  // sll
            4'b0_101: alu_result = rs1 >> rs2;  // srl
            4'b1_101: alu_result = $signed(rs1) >>> rs2;  //sra
            4'b0_010:
            alu_result = ($signed(rs1) < $signed(rs2)) ? 32'd1 : 32'd0;  //slt
            4'b0_011: alu_result = (rs1 < rs2) ? 32'd1 : 32'd0;  //sltu
        endcase

    end

    always_comb begin
        b_taken = 1'b0;
        case (alu_control)
            //BEQ
            4'b0_000: begin
                if ($signed(rs1) == $signed(rs2)) b_taken = 1'b1;
                else b_taken = 1'b0;
            end
            //BNE
            4'b0_001: begin
                if ($signed(rs1) != $signed(rs2)) b_taken = 1'b1;
                else b_taken = 1'b0;
            end
            //BLT
            4'b0_100: begin
                if ($signed(rs1) < $signed(rs2)) b_taken = 1'b1;
                else b_taken = 1'b0;
            end
            //BGE
            4'b0_101: begin
                if ($signed(rs1) >= $signed(rs2)) b_taken = 1'b1;
                else b_taken = 1'b0;
            end
            //BLTU
            4'b0_110: begin
                if (rs1 < rs2) b_taken = 1'b1;
                else b_taken = 1'b0;
            end
            //BGEU
            4'b0_111: begin
                if (rs1 >= rs2) b_taken = 1'b1;
                else b_taken = 1'b0;
            end
        endcase
    end

endmodule

// imm extender

module imm_extend
    import rv32i_pkg::*;
(
    input  logic        clk,
    input  logic        rst_n,
    input  logic [31:0] instr_code,
    //output logic [31:0] imm_extend
    output logic [31:0] imm_extend
);
    opcode_e opcode;


    assign opcode = opcode_e'(instr_code[6:0]);


    always_comb begin
        case (opcode)
            OP_STYPE:
            imm_extend = {
                {20{instr_code[31]}}, {instr_code[31:25], instr_code[11:7]}
            };
            OP_ITYPE, OP_ILTYPE, OP_JLTYPE:
            imm_extend = {{20{instr_code[31]}}, instr_code[31:20]};
            OP_BTYPE:
            imm_extend = {
                {20{instr_code[31]}},
                instr_code[7],
                instr_code[30:25],
                instr_code[11:8],
                1'b0
            };
            OP_ULTYPE, OP_UATYPE: imm_extend = {instr_code[31:12], 12'd0};
            OP_JTYPE:
            imm_extend = {
                {12{instr_code[31]}},
                instr_code[19:12],
                instr_code[20],
                instr_code[30:21],
                1'b0
            };

            default: imm_extend = 32'h0000_0000;
        endcase
    end

endmodule


module program_counter (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        b_taken,
    input  logic        branch,
    input  logic        jal,
    input  logic        jalr,
    input  logic        pc_en,
    input  logic [31:0] imm_extend,
    input  logic [31:0] rs1,
    output logic [31:0] pc,
    output logic [31:0] pc_4,
    output logic [31:0] pc_imm
);
    logic [31:0] register_pc;
    logic [31:0] pc_next;
    logic [31:0] pc_jalr;
    logic [31:0] exe2fetch_pc_next;
    logic        pc_srcsel;


    assign pc = register_pc;
    assign pc_srcsel = (b_taken & branch) | jal | jalr;
    assign pc_4 = pc + 4;
    assign pc_imm = jalr ? {{pc_jalr + imm_extend} & 32'hffff_fffe} :
                            pc_jalr + imm_extend;



    always_ff @(posedge clk) begin
        if (!rst_n) register_pc <= 32'd0;
        else begin
            if (pc_en) register_pc <= exe2fetch_pc_next;
        end
    end

    register U_EXE_PC_NEXT (
        .clk(clk),
        .rst_n(rst_n),
        .data_in(pc_next),
        .data_out(exe2fetch_pc_next)
    );

    mux_2x1 U_PC_RS1_MUX (
        .sel(jalr),
        .in0(pc),
        .in1(rs1),
        .mux_out(pc_jalr)
    );

    mux_2x1 U_PC_IMM_MUX (
        .sel(pc_srcsel),
        .in0(pc_4),
        .in1(pc_imm),
        .mux_out(pc_next)
    );


endmodule
