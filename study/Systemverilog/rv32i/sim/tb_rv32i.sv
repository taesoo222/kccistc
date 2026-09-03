module tb_rv32i_cpu ();
    logic clk = 0, rst_n = 0;

    always #5 clk = ~clk;

    rv32i_top dut (.*);

    // initial begin
    //     $fsdbDumpfile("wave.fsdb");
    //     $fsdbDumpvars(0, tb_rv32i_cpu);
    // end

    initial begin
        #10;
        rst_n = 1;

        #150;
        $finish;
    end

endmodule
