module dedicated_cpu (
    input               clk,
    input               rst_n,
    output logic [7:0]  out
);
    logic        clk;
    logic        rst_n;
    logic        a_srcsel;
    logic        sum_srcsel;
    logic        a_load;
    logic        sum_load;
    logic        alu_srcsel;
    logic        out_control;
    logic        lt10;


    datapath U_DATAPATH(
    .*,
    .out(out)
    );

    control_unit U_CONTROL_UNIT(
    .*
    );

module control_unit(
    input logic clk,
    input logic rst_n,
    input logic lt10,
    output logic a_srcsel,
    output logic sum_srcsel,
    output logic alu_srcsel,
    output logic a_load,
    output logic sum_load,
    output logic out_control,

    typedef enum [2:0] {
        S0, S1, S2, S3, S4
    } state_e;
    state_e c_state, n_state;

    assign a_srcsel     = (c_state == S2) ? 1 : 0; 
    assign sum_srcsel   = (c_state == S3) ? 1 : 0; 
    assign alu_srcsel   = (c_state == S3) ? 1:0;
    assign a_load       = (c_state == S0) || (c_state == S2) ? 1:0;
    assign sum_load     = (c_state == S0) || (c_state == S3) ? 1:0;
    assign out_control  = (c_state == S4) ? 1:0;



    always_ff @(posedge clk) begin
        if(!rst_n)
            c_state <= S0;
        else begin
            c_state <= n_state;
        end
    end

    always_comb begin
        n_state = c_state;
        case(c_state)
            S0: begin
                n_state = S1;
            end

            S1: begin
                if(lt10)
                    n_state = S2;
                else
                    n_state = S4;
            end
            
            S2: begin
                n_state = S3;
            end
            S3: begin
                n_state =S1;
            end

            S4: begin
            end

        endcase
    end
);
endmodule












endmodule


module datapath(
    input  logic        clk,
    input  logic        rst_n,
    input  logic        a_srcsel,
    input  logic        sum_srcsel,
    input  logic        a_load,
    input  logic        sum_load,
    input  logic        alu_srcsel,
    input  logic        out_control,
    output logic        lt10,
    output logic [7:0]  out
);

    logic [7:0] alu_result, asrc_muxout, sumsrc_muxout, areg_out, sumreg_out;

    mux_2x1 U_ASRC_MUX(
        .sel(a_srcsel),
        .in0(8'd0),
        .in1(alu_result),
        .mux_out(asrc_muxout)
    );

    mux_2x1 U_SUMSRC_MUX(
        .sel(sum_srcsel),
        .in0(8'd0),
        .in1(alu_result),
        .mux_out(sumsrc_muxout)
    );

    register U_REGA (
        .clk,
        .rst_n,
        .load(a_load),
        .d_in(asrc_muxout),
        .q(areg_out),
    );


    register U_REGSUM (
        .clk,
        .rst_n,
        .load(sum_load),
        .d_in(sumsrc_muxout),
        .q(sumreg_out),
    );
 
    mux_2x1 U_ALUSRC_MUX(
        .sel(alu_srcsel),
        .in0(8'd1),
        .in1(sumreg_out),
        .mux_out(alusrc_muxout)
    );


    alu U_ALU (
        .a(areg_out),
        .b(alusrc_muxout),
        .alu_result(alu_result)
    );

    lit10 U_LT10(
        .in(areg_out),
        .lt10(lt10)
    );

    assign alu_result = a + b;

endmodule


endmodule


module register(
    input   logic       clk,
    input   logic       rst_n,
    input   logic       load,
    input   logic [7:0] d_in,
    output  logic [7:0] q,
);

    always_ff@(posedge clk)begin
        if(!rst_n) begin
            q <= 1'b0;
        end else begin
            if(load)
                q <= d_in;
        end
    end

endmodule


module mux_2x1(
    input   logic       sel,
    input   logic [7:0] in0,
    input   logic [7:0] in1,
    output  logic [7:0] mux_out
);

    assign mux_out = (sel) ? in1 : in0;

endmodule


module alu (
    input logic [7:0] a,
    input logic [7:0] b,
    output logic [7:0] alu_result
);
    assign alu_result = a + b;

endmodule

module lt10(
    input   logic [7:0] in,
    output  logic       lt10
);

    assign lt10 = (in < 10);

endmodule
