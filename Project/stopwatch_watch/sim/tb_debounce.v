`timescale 1ns / 1ps
module tb_debounce ();

    reg  clk;
    reg  reset;
    reg  i_btn;
    wire o_btn;

    btn_debounce dut (
        .clk  (clk),
        .reset(reset),
        .i_btn(i_btn),
        .o_btn(o_btn)
    );

    always #5 clk = ~clk;

    initial begin
        clk   = 0;
        reset = 1;
        i_btn = 0;
        #10;
        reset = 0;
        i_btn = 1;
        #16_000_000;  // 16ms 
        i_btn = 0;
        #100;
        $stop;
    end

endmodule
