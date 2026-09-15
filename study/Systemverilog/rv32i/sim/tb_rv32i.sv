module tb_rv32i_cpu ();

    logic clk = 0, rst = 1;
    logic [11:0] sw;
    logic [11:0] led;

    always #5 clk = ~clk;

    rv32i_top dut (.*);

    // initial begin
    //     $fsdbDumpfile("wave.fsdb");
    //     $fsdbDumpvars(0, tb_rv32i_cpu);
    // end

    initial begin
        #10;
        rst = 0;
        sw = 12'h0ff;

        #15000;
        $finish;
    end

endmodule
