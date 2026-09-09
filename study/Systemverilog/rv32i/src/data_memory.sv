module data_mem (
    input  logic        clk,
    input  logic [31:0] daddr,
    input  logic [31:0] dwdata,
    input  logic        dwe,
    input  logic [ 2:0] itype,
    output logic [31:0] drdata
);

    logic [31:0] dmem[0:127];  //word addres

    always_ff @(posedge clk) begin
        if (dwe) begin
            case (itype)
                // sw word address
                3'b010: dmem[daddr[31:2]] <= dwdata;

                // sb byte address
                3'b000:
                case (daddr[1:0])
                    2'b00: dmem[daddr[31:2]][7:0] <= dwdata[7:0];
                    2'b01: dmem[daddr[31:2]][15:8] <= dwdata[7:0];
                    2'b10: dmem[daddr[31:2]][23:16] <= dwdata[7:0];
                    2'b11: dmem[daddr[31:2]][31:24] <= dwdata[7:0];
                endcase

                // sh half address
                3'b001:
                if (daddr[1]) dmem[daddr[31:2]][31:16] <= dwdata[15:0];
                else dmem[daddr[31:2]][15:0] <= dwdata[15:0];

                default: dmem[daddr[31:2]] <= dmem[daddr[31:2]];
            endcase
        end
    end

    // load
    logic [31:0] rword;
    logic [ 7:0] rbyte;
    logic [15:0] rhalf;

    assign rword = dmem[daddr[31:2]];

    always_comb begin
        // byte lane select
        case (daddr[1:0])
            2'b00:   rbyte = rword[7:0];
            2'b01:   rbyte = rword[15:8];
            2'b10:   rbyte = rword[23:16];
            2'b11:   rbyte = rword[31:24];
        endcase
        // half lane select
        rhalf = daddr[1] ? rword[31:16] : rword[15:0];

        case (itype)
            3'b000:  drdata = {{24{rbyte[7]}}, rbyte};    // LB
            3'b001:  drdata = {{16{rhalf[15]}}, rhalf};   // LH
            3'b010:  drdata = rword;                      // LW
            3'b100:  drdata = {24'b0, rbyte};             // LBU
            3'b101:  drdata = {16'b0, rhalf};             // LHU
            default: drdata = rword;
        endcase
    end

endmodule
