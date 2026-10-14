`timescale 1ns / 1ps
module tb_watch_datapath ();
    reg clk;
    reg reset;
    reg mode;
    reg secmove;
    reg minmove;
    reg hourmove;
    reg def;
    wire [6:0] msec;
    wire [5:0] sec;
    wire [5:0] min;
    wire [4:0] hour;
    wire o_def;

    watch_datapath dut (
        .clk(clk),
        .reset(reset),
        .mode(mode),
        .secmove(secmove),
        .minmove(minmove),
        .hourmove(hourmove),
        .def(def),
        .msec(msec),
        .sec(sec),
        .min(min),
        .hour(hour),
        .o_def(o_def)
    );

    always #5 clk = ~clk;

    initial begin
        clk      = 0;
        reset    = 1;
        mode     = 0;
        secmove  = 0;
        minmove  = 0;
        hourmove = 0;
        def      = 0;
        #10;
        reset = 0;
        
        $stop;

    end

endmodule
