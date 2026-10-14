`timescale 1ns / 1ps
module fnd_controller #(
    parameter MSEC_WIDTH = 7,
    SEC_WIDTH = 6,
    MIN_WIDTH = 6,
    HOUR_WIDTH = 5
) (
    input                   clk,
    input                   reset,
    input  [MSEC_WIDTH-1:0] msec,
    input  [ SEC_WIDTH-1:0] sec,
    input  [ MIN_WIDTH-1:0] min,
    input  [HOUR_WIDTH-1:0] hour,
    input                   display_mode,
    input                   set_mode,      // add
    input                   field_ptr,     // add
    input                   def,
    output [           3:0] fnd_com,
    output [           7:0] fnd_data
);
    wire [3:0] w_digit_1, w_digit_10, w_digit_100, w_digit_1000;
    wire [3:0] bcd;
    wire [2:0] w_digit_sel;
    wire w_1khz;
    wire [3:0] w_msec_digit_1, w_msec_digit_10, w_sec_digit_1, w_sec_digit_10, w_min_digit_1, w_min_digit_10, w_hour_digit_1, w_hour_digit_10;
    wire [3:0] w_msec_sec, w_min_hour;
    wire w_dot_onoff;
    wire w_blink;  //add
    wire w_blank = set_mode & (w_digit_sel[1] == field_ptr) & w_blink;  //add
    wire [3:0] w_bcd_final = w_blank ? 4'hf : bcd;  //add

    clk_div U_CLK_DIV (
        .clk   (clk),
        .reset (reset),
        .o_1khz(w_1khz)
    );

    counter_8 U_COUNTER_8 (
        .clk      (w_1khz),
        .reset    (reset),
        .digit_sel(w_digit_sel)
    );

    decoder_2x4 U_DECODER_2x4 (
        .digit_sel(w_digit_sel[1:0]),
        .fnd_com  (fnd_com)
    );

    digit_splitter #(
        .BIT_WIDTH(MSEC_WIDTH)
    ) U_DIGIT_SPLITTER_MSEC (
        .ds_in   (msec),
        .digit_1 (w_msec_digit_1),
        .digit_10(w_msec_digit_10)
    );

    digit_splitter #(
        .BIT_WIDTH(SEC_WIDTH)
    ) U_DIGIT_SPLITTER_SEC (
        .ds_in   (sec),
        .digit_1 (w_sec_digit_1),
        .digit_10(w_sec_digit_10)
    );

    digit_splitter #(
        .BIT_WIDTH(MIN_WIDTH)
    ) U_DIGIT_SPLITTER_MIN (
        .ds_in   (min),
        .digit_1 (w_min_digit_1),
        .digit_10(w_min_digit_10)
    );

    digit_splitter #(
        .BIT_WIDTH(HOUR_WIDTH)
    ) U_DIGIT_SPLITTER_HOURE (
        .ds_in   (hour),
        .digit_1 (w_hour_digit_1),
        .digit_10(w_hour_digit_10)
    );

    mux_8x1 U_MUX_8X1_MSEC_SEC (
        .sel    (w_digit_sel),
        .in0    (w_msec_digit_1),
        .in1    (w_msec_digit_10),
        .in2    (w_sec_digit_1),
        .in3    (w_sec_digit_10),
        .in4    (4'hf),
        .in5    (4'hf),
        .in6    ({3'b111, w_dot_onoff}),
        .in7    (4'hf),
        .mux_out(w_msec_sec)
    );

    comparator_dot U_COMP_DOT (
        .msec     (msec),
        .def      (def),
        .dot_onoff(w_dot_onoff)
    );

    mux_8x1 U_MUX_8X1_MIN_HOUR (
        .sel    (w_digit_sel),
        .in0    (w_min_digit_1),
        .in1    (w_min_digit_10),
        .in2    (w_hour_digit_1),
        .in3    (w_hour_digit_10),
        .in4    (4'hf),
        .in5    (4'hf),
        .in6    ({3'b111, w_dot_onoff}),
        .in7    (4'hf),
        .mux_out(w_min_hour)
    );

    mux_2x1 U_MUX_2X1 (
        .sel    (display_mode),
        .in0    (w_msec_sec),
        .in1    (w_min_hour),
        .mux_out(bcd)
    );


    bcd U_BCD (
        .bcd_in (w_bcd_final),  //add bcd ->w_bcd_final
        .bcd_out(fnd_data)
    );

    blink_gen U_BLINK_GEN (
        .clk        (clk),
        .reset      (reset),
        .blink_phase(w_blink)
    );

endmodule
module decoder_2x4 (
    input [1:0] digit_sel,
    output reg [3:0] fnd_com
);
    always @(digit_sel) begin
        case (digit_sel)
            2'b00:   fnd_com = 4'b1110;  //digit 1
            2'b01:   fnd_com = 4'b1101;  //digit 10
            2'b10:   fnd_com = 4'b1011;  //digit 100
            2'b11:   fnd_com = 4'b0111;  //digit 1000
            default: fnd_com = 4'b1110;  //default value 
        endcase
    end
endmodule

module mux_8x1 (
    input      [2:0] sel,     // mux selection
    input      [3:0] in0,     // sel 3'b000
    input      [3:0] in1,     // sel 3'b001
    input      [3:0] in2,     // sel 3'b010
    input      [3:0] in3,     // sel 3'b011
    input      [3:0] in4,     // sel 3'b100
    input      [3:0] in5,     // sel 3'b101
    input      [3:0] in6,     // sel 3'b110
    input      [3:0] in7,     // sel 3'b111
    output reg [3:0] mux_out
);

    always @(*) begin
        case (sel)
            3'b000: mux_out = in0;
            3'b001: mux_out = in1;
            3'b010: mux_out = in2;
            3'b011: mux_out = in3;
            3'b100: mux_out = in4;
            3'b101: mux_out = in5;
            3'b110: mux_out = in6;
            3'b111: mux_out = in7;
        endcase
    end
endmodule

module digit_splitter #(
    parameter BIT_WIDTH = 7
) (
    input  [(BIT_WIDTH - 1):0] ds_in,
    output [              3:0] digit_1,
    output [              3:0] digit_10
);
    assign digit_1  = (ds_in) % 10;
    assign digit_10 = (ds_in / 10) % 10;
endmodule

module bcd (
    input      [3:0] bcd_in,
    output reg [7:0] bcd_out
);

    always @(bcd_in) begin
        case (bcd_in)
            4'b0000: bcd_out = 8'hc0;  //0
            4'b0001: bcd_out = 8'hf9;  //1
            4'b0010: bcd_out = 8'ha4;
            4'b0011: bcd_out = 8'hb0;
            4'b0100: bcd_out = 8'h99;
            4'b0101: bcd_out = 8'h92;
            4'b0110: bcd_out = 8'h82;
            4'b0111: bcd_out = 8'hf8;
            4'b1000: bcd_out = 8'h80;
            4'b1001: bcd_out = 8'h90;
            4'b1010: bcd_out = 8'h88;  //a
            4'b1011: bcd_out = 8'h83;  //b
            4'b1100: bcd_out = 8'hc6;  //c
            4'b1101: bcd_out = 8'ha1;  //d
            4'b1110: bcd_out = 8'h7f;  // dot display on
            4'b1111: bcd_out = 8'hff;  // dot display off
        endcase
    end
endmodule

module comparator_dot #(
    parameter MSEC_WIDTH = 7
) (
    input  [MSEC_WIDTH-1 : 0] msec,
    input                     def,
    output                    dot_onoff
);
    assign dot_onoff = (def) ? (msec < 50) : 1'b0;  //watch option add
endmodule

module mux_2x1 (
    input sel,
    input [3:0] in0,
    input [3:0] in1,
    output [3:0] mux_out
);

    assign mux_out = (sel) ? in1 : in0;  // msec_sec -> 0 , min_houre ->1
endmodule

module counter_8 (
    input        clk,
    input        reset,
    output [2:0] digit_sel
);
    reg [2:0] counter_reg;

    assign digit_sel = counter_reg;

    // sequential logic : SL
    always @(posedge clk, posedge reset) begin
        if (reset) begin
            counter_reg <= 0;
        end else begin
            //operation
            counter_reg <= counter_reg + 1;
        end
    end
endmodule

module clk_div (
    input  clk,
    input  reset,
    output o_1khz
);
    reg [15:0] counter_reg;
    reg clk_reg;

    assign o_1khz = clk_reg;
    // sequential logic
    always @(posedge clk, posedge reset) begin
        if (reset) begin
            counter_reg <= 0;
            clk_reg     <= 1'b0;
        end else begin
            counter_reg <= counter_reg + 1;
            if (counter_reg == (50_000 - 1)) begin
                counter_reg <= 0;
                clk_reg     <= ~clk_reg;
            end
        end
    end
endmodule

module blink_gen (
    input  clk,
    input  reset,
    output blink_phase
);
    reg [25:0] counter_reg;
    assign blink_phase = counter_reg[25];

    always @(posedge clk, posedge reset) begin
        if (reset) counter_reg <= 0;
        else counter_reg <= counter_reg + 1;
    end
endmodule
