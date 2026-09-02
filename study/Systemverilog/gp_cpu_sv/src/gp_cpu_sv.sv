`timescale 1ns / 1ps

module gp_cpu_sv (
    input  logic       clk,
    input  logic       rst_n,
    output logic [7:0] out
);

    logic [7:0] wd;
    logic [1:0] ra0, ra1, wa;
    logic we, rf_srcsel, out_control, lt10;

    gp_datapath U_GP_DATAPATH (
        .*,
        .out(out)
    );


    gp_controlunit U_GP_CONTROLUNIT (
        .*
    );

endmodule
