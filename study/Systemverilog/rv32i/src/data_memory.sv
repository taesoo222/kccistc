module data_mem (
    input logic        clk,
    input logic [31:0] daddr,
    input logic [31:0] dwdata,
    input logic        dwe,
    input logic [ 2:0] itype
);

    logic [31:0] dmem[0:127];  //word addres

    always_ff @(posedge clk) begin
        if (dwe) begin
            case (itype)
                3'b010:  dmem[daddr[31:2]] <= dwdata;
                default: dmem[daddr[31:2]] <= dmem[daddr[31:2]];
            endcase
        end
    end

endmodule
