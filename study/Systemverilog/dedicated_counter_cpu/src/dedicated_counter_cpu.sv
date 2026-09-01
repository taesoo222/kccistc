module dedicated_counter_cpu (
    input  logic       clk,
    input  logic       rst_n,
    output logic [3:0] out
);



    logic asrcsel;
    logic load;
    logic out_control;
    logic lte10;

    datapath U_DATAPATH (
        .*,
        .out(out)
    );

    control_unit U_CNTL_UNIT (.*);

endmodule


module datapath (
    input  logic       clk,
    input  logic       rst_n,
    input  logic       asrcsel,
    input  logic       load,
    input  logic       out_control,
    output logic       lte10,
    output logic [3:0] out
);

    logic [3:0] alu_result;
    logic [3:0] rega_src_out;
    logic [3:0] rega_out;

    assign out = out_control ? rega_out : 4'hz;

    mux_2x1 U_REGA_SRC_MUX (
        .sel    (asrcsel),
        .in0    (4'h0),
        .in1    (alu_result),
        .mux_out(rega_src_out)
    );

    reg_a U_REG_A (
        .clk      (clk),
        .rst_n    (rst_n),
        .load     (load),
        .src_a    (rega_src_out),
        .out_reg_a(rega_out)
    );

    alu U_ALU (
        .a         (rega_out),
        .b         (4'h1),
        .alu_result(alu_result)
    );

    lte10 U_LTE10 (
        .in   (rega_out),
        .lte10(lte10)
    );

endmodule


module reg_a (
    input  logic       clk,
    input  logic       rst_n,
    input  logic       load,
    input  logic [3:0] src_a,
    output logic [3:0] out_reg_a
);

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            out_reg_a <= 4'h0;
        end else if (load) begin
            out_reg_a <= src_a;
        end
    end

endmodule


module mux_2x1 (
    input  logic       sel,
    input  logic [3:0] in0,
    input  logic [3:0] in1,
    output logic [3:0] mux_out
);

    assign mux_out = sel ? in1 : in0;

endmodule


module alu (
    input  logic [3:0] a,
    input  logic [3:0] b,
    output logic [3:0] alu_result
);

    assign alu_result = a + b;

endmodule


module lte10 (
    input  logic [3:0] in,
    output logic       lte10
);

    assign lte10 = (in < 4'd10);

endmodule


module control_unit (
    input  logic clk,
    input  logic rst_n,
    input  logic lte10,
    output logic asrcsel,
    output logic load,
    output logic out_control
);

    typedef enum logic [1:0] {
        S0 = 0,
        S1 = 1,
        S2 = 2,
        S3 = 3
    } state_t;

    state_t c_state, n_state;


    assign asrcsel = (c_state == S2) ? 1'b1 : 1'b0;
    assign load    = (c_state == S0 || c_state == S2) ? 1'b1 : 1'b0;
    assign out_control = (c_state == S3) ? 1'b1 : 1'b0;

    always_ff @(posedge clk) begin
        if (!rst_n) c_state <= S0;
        else c_state <= n_state;
    end

    always_comb begin
        n_state = c_state;
        case (c_state)
            S0: begin
                n_state = S1;
            end

            S1: begin
                if (lte10) n_state = S2;
                else n_state = S3;
            end

            S2: begin
                n_state = S1;
            end

            S3: begin
                n_state = S3;
            end

            default: begin
                n_state = S0;
            end
        endcase
    end

endmodule
