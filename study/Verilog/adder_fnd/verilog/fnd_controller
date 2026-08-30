`timescale 1ns / 1ps

module fnd_controller (
    input  [7:0] fnd_in,
    input  [1:0] digit_sel,
    output [3:0] fnd_com,
    output [7:0] fnd_data
);
    // assign fnd_com = 4'b1110;
    wire [3:0] w_digit_1, w_digit_10, w_digit_100, w_digit_1000;
    wire [3:0] bcd;

    decoder_2x4 U_DECODER_2x4 (
    .digit_sel(digit_sel),
    .fnd_com(fnd_com)
    );

    digit_splitter U_DS (
        .seg_data(fnd_in),
        .digit_1(w_digit_1),
        .digit_10(w_digit_10),
        .digit_100(w_digit_100),
        .digit_1000(w_digit_1000)
    );

    mux_4x1 U_MUX_4x1 (
        .sel(digit_sel),  // mux selection
        .digit_1(w_digit_1),
        .digit_10(w_digit_10),
        .digit_100(w_digit_100),
        .digit_1000(w_digit_1000),
        .mux_out(bcd)
    );

    bcd U_BCD (
        .bcd_in (bcd),
        .bcd_out(fnd_data)
    );
endmodule

module decoder_2x4 (
    input [1:0] digit_sel,
    output reg [3:0] fnd_com
);
    always @(digit_sel) begin
        case(digit_sel)
            2'b00 : fnd_com = 4'b1110; //digit 1
            2'b01 : fnd_com = 4'b1101; //digit 10
            2'b10 : fnd_com = 4'b1011; //digit 100
            2'b11 : fnd_com = 4'b0111; //digit 1000
            default : fnd_com = 4'b1110; //default value 
        endcase
    end

endmodule


module mux_4x1 (
    input [1:0] sel,  // mux selection
    input [3:0] digit_1,
    input [3:0] digit_10,
    input [3:0] digit_100,
    input [3:0] digit_1000,
    output [3:0] mux_out
);
    // assgin문에  if, for 사용 안됨 
    assign mux_out = (sel == 2'b00) ? digit_1 :
        (sel == 2'b01) ? digit_10 :
        (sel == 2'b10) ? digit_100 :
        (sel == 2'b11) ? digit_1000 : 4'b1111;
endmodule

module digit_splitter (
    input  [7:0] seg_data,
    output [3:0] digit_1,
    output [3:0] digit_10,
    output [3:0] digit_100,
    output [3:0] digit_1000
);
    assign digit_1    = (seg_data) % 10;
    assign digit_10   = (seg_data / 10) % 10;
    assign digit_100  = (seg_data / 100) % 10;
    assign digit_1000 = (seg_data / 1000) % 10;
endmodule








module bcd (
    input      [3:0] bcd_in,
    output reg [7:0] bcd_out
);

    always @(bcd_in) begin // always안에 출력의 타입은 wire x, reg 여야함
        case (bcd_in)
            4'b0000: bcd_out = 8'hc0;
            4'b0001: bcd_out = 8'hf9;
            4'b0010: bcd_out = 8'ha4;
            4'b0011: bcd_out = 8'hb0;
            4'b0100: bcd_out = 8'h99;
            4'b0101: bcd_out = 8'h92;
            4'b0110: bcd_out = 8'h82;
            4'b0111: bcd_out = 8'hf8;
            4'b1000: bcd_out = 8'h80;
            4'b1001: bcd_out = 8'h90;
            4'b1010: bcd_out = 8'h88;
            4'b1011: bcd_out = 8'h83;
            4'b1100: bcd_out = 8'hc6;
            4'b1101: bcd_out = 8'ha1;
            4'b1110: bcd_out = 8'h86;
            4'b1111: bcd_out = 8'h8e;
        endcase
    end
endmodule
