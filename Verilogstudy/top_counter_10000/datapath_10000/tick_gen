/*
per 1ms 1tick generate
1MHz -> 1kHz
*/
module tick_gen (
    input  clk,
    input  reset,
    input  run_stop,
    output tick
);
    reg [$clog2(1_000_000)-1:0] counter_reg;  //calculate for 1_000_000
    reg tick_reg;

    assign tick = tick_reg;

    always @(posedge clk, posedge reset) begin
        if (reset) begin
            counter_reg <= 0; //count for tick generation
            tick_reg    <= 0;

        end else begin
            if (run_stop) begin
                counter_reg <= counter_reg + 1;

                if (counter_reg == (1_000_000 - 1)) begin
                    counter_reg <= 0;
                    tick_reg    <= 1'b1;
                end else begin
                    tick_reg <= 1'b0;
                end
            end
        end
    end
endmodule
