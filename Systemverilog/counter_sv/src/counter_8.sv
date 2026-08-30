`timescale 1ns / 1ps

module counter (
    input  logic       clk,
    input  logic       rst_n,
    input  logic       enable,
    output logic [2:0] counter,
    output logic       o_tick
);

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            counter <= 1'b0;
            o_tick  <= 1'b0;
        end else begin
            if (enable) begin
                counter <= counter + 1;
                if (counter == 7) begin
                    o_tick <= 1'b1;
                end else begin
                    o_tick <= 1'b0;
                end
            end else o_tick <= 1'b0;
        end
    end

endmodule

