module datapath (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        rt_we,
    input  logic [ 9:0] alu_control,
    input  logic [31:0] instr_code,
    output logic [ 5:0] instr_addr
);
    logic [31:0] alu_result, rf_rd1, rf_rd2;

    reg_file U_REG_FILE (
        .clk(clk),
        .ra1(instr_code[19:15]),
        .ra2(instr_code[24:20]),
        .wa (instr_code[11:7]),
        .wd (alu_result),
        .we (rf_we),
        .rd1(rf_rd1),
        .rd2(rf_rd2)
    );

    alu U_ALU (
        .a          (rf_rd1),
        .b          (rf_rd2),
        .alu_control(alu_control),
        .alu_result (alu_result)
    );

    program_counter U_PC (
        .clk  (clk),
        .rst_n(rst_n),
        .pc   ({26'd0,instr_addr})
    );

endmodule

module reg_file (
    input  logic        clk,
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
        if (we) ram_file[wa] <= wd;
    end

    assign rd1 = (ra1 != 0) ? ram_file[ra1] : 32'd0;
    assign rd2 = (ra2 != 0) ? ram_file[ra2] : 32'd0;

endmodule

module alu (
    input  logic [31:0] a,
    input  logic [31:0] b,
    input  logic [ 9:0] alu_control,
    output logic [31:0] alu_result
);

    always_comb begin
        alu_result = 32'h0000_0000;
        case (alu_control)
            // {funct3, funct7}
            10'b000_000_0000: alu_result = a + b;
            10'b000_010_0000: alu_result = a - b;
            10'b100_000_0000: alu_result = a ^ b;
            10'b110_000_0000: alu_result = a | b;
            10'b111_000_0000: alu_result = a & b;
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
        if (!rst_n) register_pc <= 32'b0;
        else register_pc <= register_pc + 4;
    end
endmodule

