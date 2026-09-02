`timescale 1ns / 1ps

module gp_controlunit (
    input  logic       clk,
    input  logic       rst_n,
    input  logic       lt10,
    output logic       rf_srcsel,
    output logic [1:0] ra0,
    output logic [1:0] ra1,
    output logic [1:0] wa,
    output logic       we,
    output logic       out_control
);

    typedef enum logic [2:0] {
        S0,
        S1,
        S2,
        S3,
        S4,
        S5,
        S6
    } state_e;
    state_e c_state, n_state;

    always_ff @(posedge clk) begin
        if (!rst_n) c_state <= S0;
        else c_state <= n_state;
    end

    always_comb begin
        n_state = c_state;
        case (c_state)
            S0: n_state = S1;
            S1: n_state = S2;
            S2: n_state = S3;
            S3: begin
                if (lt10) n_state = S4;
                else n_state = S6;
            end
            S4: n_state = S5;
            S5: n_state = S3;
            S6: n_state = S6;
        endcase
    end

    always_comb begin
        rf_srcsel   = 1'd0;
        ra0         = 2'd0;
        ra1         = 2'd0;
        wa          = 2'd0;
        we          = 1'd0;
        out_control = 1'd0;
        case (c_state)
            S0: begin
                rf_srcsel   = 1'd1;
                ra0         = 2'd0;
                ra1         = 2'd0;
                wa          = 2'd3;
                we          = 1'd1;
                out_control = 1'd0;
            end
            S1: begin
                rf_srcsel   = 1'd1;
                ra0         = 2'd0;
                ra1         = 2'd0;
                wa          = 2'd2;
                we          = 1'd1;
                out_control = 1'd0;
            end
            S2: begin
                rf_srcsel   = 1'd0;
                ra0         = 2'd0;
                ra1         = 2'd0;
                wa          = 2'd1;
                we          = 1'd1;
                out_control = 1'd0;
            end
            S3: begin
                rf_srcsel   = 1'd0;
                ra0         = 2'd3;
                ra1         = 2'd0;
                wa          = 2'd0;
                we          = 1'd0;
                out_control = 1'd0;
            end
            S4: begin
                rf_srcsel   = 1'd1;
                ra0         = 2'd3;
                ra1         = 2'd1;
                wa          = 2'd3;
                we          = 1'd1;
                out_control = 1'd0;
            end
            S5: begin
                rf_srcsel   = 1'd1;
                ra0         = 2'd2;
                ra1         = 2'd3;
                wa          = 2'd2;
                we          = 1'd1;
                out_control = 1'd0;
            end
            S6: begin
                rf_srcsel   = 1'd0;
                ra0         = 2'd0;
                ra1         = 2'd2;
                wa          = 2'd0;
                we          = 1'd0;
                out_control = 1'd1;
            end
        endcase
    end
endmodule
