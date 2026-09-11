module apb_bram (
    input  logic        clk,
    input  logic [ 2:0] itype,
    input  logic        PSEL,
    input  logic        PENABLE,
    input  logic [31:0] PADDR,
    input  logic [31:0] PWDATA,
    input  logic        PWRITE,
    output logic [31:0] PRDATA,
    output logic        PREADY
);

    logic [31:0] dmem[0:127];

    assign PREADY = (PENABLE & PSEL) ? 1'b1 : 1'b0;




    always_ff @(posedge clk) begin
        if (PREADY) begin
            case (itype)
                // SB
                3'b000: begin
                    case (PADDR[1:0])
                        2'b00: dmem[PADDR[31:2]][7:0]   <= PWDATA[7:0];
                        2'b01: dmem[PADDR[31:2]][15:8]  <= PWDATA[7:0];
                        2'b10: dmem[PADDR[31:2]][23:16] <= PWDATA[7:0];
                        2'b11: dmem[PADDR[31:2]][31:24] <= PWDATA[7:0];
                    endcase
                end

                // SH
                3'b001: begin
                    case (PADDR[1:0])
                        2'b00: dmem[PADDR[31:2]][15:0]  <= PWDATA[15:0];
                        2'b10: dmem[PADDR[31:2]][31:16] <= PWDATA[15:0];
                    endcase
                end

                // SW
                3'b010: begin
                    dmem[PADDR[31:2]] <= PWDATA;
                end

            endcase
        end
    end

    always_comb begin
        if(PREADY) begin
            case (itype)
                // LB 
                3'b000: begin 
                    case(PADDR[1:0])
                        2'b00 : PRDATA = {{24{dmem[PADDR[31:2]][ 7]}}, dmem[PADDR[31:2]][ 7: 0]};
                        2'b01 : PRDATA = {{24{dmem[PADDR[31:2]][15]}}, dmem[PADDR[31:2]][15: 8]};
                        2'b10 : PRDATA = {{24{dmem[PADDR[31:2]][23]}}, dmem[PADDR[31:2]][23:16]};
                        2'b11 : PRDATA = {{24{dmem[PADDR[31:2]][31]}}, dmem[PADDR[31:2]][31:24]};
                    endcase
                end

                // LH
                3'b001: begin
                    case(PADDR[1:0])
                        2'b00 : PRDATA = {{16{dmem[PADDR[31:2]][15]}}, dmem[PADDR[31:2]][15: 0]};
                        2'b10 : PRDATA = {{16{dmem[PADDR[31:2]][31]}}, dmem[PADDR[31:2]][31:16]};
                        default: PRDATA = 32'd0;
                    endcase
                end

                //LW
                3'b010: PRDATA = dmem[PADDR[31:2]];

                // LBU
                3'b100: begin
                    case(PADDR[1:0])
                        2'b00 : PRDATA = {24'd0, dmem[PADDR[31:2]][ 7: 0]};
                        2'b01 : PRDATA = {24'd0, dmem[PADDR[31:2]][15: 8]};
                        2'b10 : PRDATA = {24'd0, dmem[PADDR[31:2]][23:16]};
                        2'b11 : PRDATA = {24'd0, dmem[PADDR[31:2]][31:24]};
                    endcase
                end

                // LHU
                3'b101: begin
                    case(PADDR[1:0])
                        2'b00 : PRDATA = {16'd0, dmem[PADDR[31:2]][15: 0]};
                        2'b10 : PRDATA = {16'd0, dmem[PADDR[31:2]][31:16]};
                        default: PRDATA = 32'd0;
                    endcase

                end
                default: PRDATA = 32'd0;
            endcase
        end
        else PRDATA = 32'dz;
    end
endmodule
