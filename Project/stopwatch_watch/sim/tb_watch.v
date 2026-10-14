`timescale 1ns / 1ps
module tb_watch ();
    reg        clk;
    reg        reset;
    reg        btn_L;
    reg        btn_R;
    reg        btn_U;
    reg        btn_D;
    reg  [3:0] sw;
    wire [3:0] fnd_com;
    wire [7:0] fnd_data;
    wire [3:0] led;

    top_stopwatch_watch dut (
        .clk(clk),
        .reset(reset),
        .btn_L(btn_L),
        .btn_R(btn_R),
        .btn_U(btn_U),
        .btn_D(btn_D),
        .sw(sw),
        .fnd_com(fnd_com),
        .fnd_data(fnd_data),
        .led(led)
    );

    always #5 clk = ~clk;
    // datpath tick 100hz x -> 100M
    initial begin
        clk   = 0;
        reset = 1;
        btn_L = 0;
        btn_R = 0;
        btn_U = 0;
        btn_D = 0;
        #10;
        reset = 0;
        sw[0] = 1;
        sw[1] = 1;
        sw[2] = 0;
        
        #10;
        sw[3] = 1;
        btn_U = 1;
        #160;
        sw[3] = 1;
        btn_U = 0;
        #160;
        $stop;
    end

endmodule
