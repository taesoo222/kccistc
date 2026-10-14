`timescale 1ns / 1ps

module fnd_controller #(
    parameter MSEC_WIDTH = 7,
    SEC_WIDTH = 6,
    MIN_WIDTH = 6,
    HOUR_WIDTH = 5,
    DHT_WIDTH = 16,
    SR04_WIDTH = 9
) (
    input                   clk,
    input                   reset,
    input  [MSEC_WIDTH-1:0] msec,
    input  [ SEC_WIDTH-1:0] sec,
    input  [ MIN_WIDTH-1:0] min,
    input  [HOUR_WIDTH-1:0] hour,
    input  [ DHT_WIDTH-1:0] humidity,
    input  [ DHT_WIDTH-1:0] temperature,
    input  [SR04_WIDTH-1:0] distance,
    input  [           2:0] display_mode,
    output [           3:0] fnd_com,
    output [           7:0] fnd_data
);
    wire [3:0] w_digit_1, w_digit_10, w_digit_100, w_digit_1000;
    wire [3:0] bcd;
    wire [2:0] w_digit_sel;
    wire w_1khz;
    wire [3:0] w_msec_digit_1, w_msec_digit_10, w_sec_digit_1, w_sec_digit_10, w_min_digit_1, w_min_digit_10, w_hour_digit_1, w_hour_digit_10;
    wire [3:0] w_humidity_digit_1, w_humidity_digit_10;
    wire [3:0] w_temperature_digit_1, w_temperature_digit_10;
    wire [3:0] w_distance_digit_1, w_distance_digit_10, w_distance_digit_100, w_distance_digit_1000;
    wire [3:0] w_msec_sec, w_min_hour, w_humidity, w_temperature, w_distance;
    wire w_dot_onoff;


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

    digit_splitter_sw_w #(
        .BIT_WIDTH(MSEC_WIDTH)
    ) U_DIGIT_SPLITTER_MSEC (
        .ds_in   (msec),
        .digit_1 (w_msec_digit_1),
        .digit_10(w_msec_digit_10)
    );

    digit_splitter_sw_w #(
        .BIT_WIDTH(SEC_WIDTH)
    ) U_DIGIT_SPLITTER_SEC (
        .ds_in   (sec),
        .digit_1 (w_sec_digit_1),
        .digit_10(w_sec_digit_10)
    );

    digit_splitter_sw_w #(
        .BIT_WIDTH(MIN_WIDTH)
    ) U_DIGIT_SPLITTER_MIN (
        .ds_in   (min),
        .digit_1 (w_min_digit_1),
        .digit_10(w_min_digit_10)
    );

    digit_splitter_sw_w #(
        .BIT_WIDTH(HOUR_WIDTH)
    ) U_DIGIT_SPLITTER_HOURE (
        .ds_in   (hour),
        .digit_1 (w_hour_digit_1),
        .digit_10(w_hour_digit_10)
    );
    // dht humidity
    digit_spliter_sensor_dht11 #(
        .BIT_WIDTH(8)
    ) U_DIGIT_SPLITER_HUMIDITY (
        .seg_data(humidity[15:8]),
        .digit_1 (w_humidity_digit_1),
        .digit_10(w_humidity_digit_10)
    );  // dht temperature
    digit_spliter_sensor_dht11 #(
        .BIT_WIDTH(8)
    ) U_DIGIT_SPLITER_TEMPERATURE (
        .seg_data(temperature[15:8]),
        .digit_1 (w_temperature_digit_1),
        .digit_10(w_temperature_digit_10)
    );
    // sr04 distance
    digit_spliter_sensor_sr04 #(
        .BIT_WIDTH(SR04_WIDTH)
    ) U_DIGIT_SPLITER_DISTANCE (
        .seg_data  (distance),
        .digit_1   (w_distance_digit_1),
        .digit_10  (w_distance_digit_10),
        .digit_100 (w_distance_digit_100),
        .digit_1000(w_distance_digit_1000)
    );
    mux_8x1 U_MUX_8X1_MSEC_SEC (
        .sel(w_digit_sel),
        .in0(w_msec_digit_1),
        .in1(w_msec_digit_10),
        .in2(w_sec_digit_1),
        .in3(w_sec_digit_10),
        .in4(4'hf),
        .in5(4'hf),
        .in6({3'b111, w_dot_onoff}),
        .in7(4'hf),
        .mux_out(w_msec_sec)
    );

    mux_8x1 U_MUX_8X1_MIN_HOUR (
        .sel(w_digit_sel),
        .in0(w_min_digit_1),
        .in1(w_min_digit_10),
        .in2(w_hour_digit_1),
        .in3(w_hour_digit_10),
        .in4(4'hf),
        .in5(4'hf),
        .in6({3'b111, w_dot_onoff}),
        .in7(4'hf),
        .mux_out(w_min_hour)
    );

    mux_8x1 U_MUX_8X1_HUMIDITY (
        .sel(w_digit_sel),
        .in0(4'hb),
        .in1(4'hf),
        .in2(w_humidity_digit_1),
        .in3(w_humidity_digit_10),
        .in4(4'hf),
        .in5(4'hf),
        .in6({3'b111, w_dot_onoff}),
        .in7(4'hf),
        .mux_out(w_humidity)
    );

    mux_8x1 U_MUX_8X1_TEMPERATURE (
        .sel(w_digit_sel),
        .in0(4'hc),
        .in1(4'ha),
        .in2(w_temperature_digit_1),
        .in3(w_temperature_digit_10),
        .in4(4'hf),
        .in5(4'hf),
        .in6({3'b111, w_dot_onoff}),
        .in7(4'hf),
        .mux_out(w_temperature)
    );

    mux_8x1 U_MUX_8X1_DISTANCE (
        .sel(w_digit_sel),
        .in0(w_distance_digit_1),
        .in1(w_distance_digit_10),
        .in2(w_distance_digit_100),
        .in3(w_distance_digit_1000),
        .in4(4'hf),
        .in5(4'hf),
        .in6({3'b111, w_dot_onoff}),
        .in7(4'hf),
        .mux_out(w_distance)
    );

    comparator_dot U_COMP_DOT (
        .msec(msec),
        .dot_onoff(w_dot_onoff)
    );

    mux_5x1 U_MUX_5x1 (
        .sel(display_mode),
        .in0(w_msec_sec),
        .in1(w_min_hour),
        .in2(w_temperature),
        .in3(w_humidity),
        .in4(w_distance),
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

module digit_splitter_sw_w #(
    parameter BIT_WIDTH = 7
) (
    input  [(BIT_WIDTH - 1):0] ds_in,
    output [              3:0] digit_1,
    output [              3:0] digit_10
);
    assign digit_1  = (ds_in) % 10;
    assign digit_10 = (ds_in / 10) % 10;
endmodule

module digit_spliter_sensor_dht11 #(
    parameter BIT_WIDTH = 8
) (
    input [(BIT_WIDTH-1):0] seg_data,
    output [3:0] digit_1,
    output [3:0] digit_10
);
    assign digit_1  = seg_data % 10;
    assign digit_10 = (seg_data / 10) % 10;

endmodule

module digit_spliter_sensor_sr04 #(
    parameter BIT_WIDTH = 9
) (
    input [(BIT_WIDTH-1):0] seg_data,
    output [3:0] digit_1,
    output [3:0] digit_10,
    output [3:0] digit_100,
    output [3:0] digit_1000
);
    assign digit_1    = seg_data % 10;
    assign digit_10   = (seg_data / 10) % 10;
    assign digit_100  = (seg_data / 100) % 10;
    assign digit_1000 = (seg_data / 1000) % 10;

endmodule


module bcd (
    input      [3:0] bcd_in,
    output reg [7:0] bcd_out
);

    always @(bcd_in) begin
        case (bcd_in)
            4'b0000: bcd_out = 8'hc0;  // 0
            4'b0001: bcd_out = 8'hf9;  // 1
            4'b0010: bcd_out = 8'ha4;  // 2
            4'b0011: bcd_out = 8'hb0;  // 3
            4'b0100: bcd_out = 8'h99;  // 4
            4'b0101: bcd_out = 8'h92;  // 5
            4'b0110: bcd_out = 8'h82;  // 6
            4'b0111: bcd_out = 8'hf8;  // 7
            4'b1000: bcd_out = 8'h80;  // 8
            4'b1001: bcd_out = 8'h90;  // 9
            4'b1010: bcd_out = 8'h9c;  // °(temperature sign)
            4'b1011: bcd_out = 8'h89;  //H
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
    input [MSEC_WIDTH-1 : 0] msec,
    output dot_onoff
);

    assign dot_onoff = (msec < 50);

endmodule

module mux_5x1 (
    input  [2:0] sel,
    input  [3:0] in0,
    input  [3:0] in1,
    input  [3:0] in2,
    input  [3:0] in3,
    input  [3:0] in4,
    output [3:0] mux_out
);

    assign mux_out = (sel == 3'b000) ? in0 :
                        (sel == 3'b001) ? in1 : 
                        (sel == 3'b010) ? in2 :
                        (sel == 3'b011) ? in3 :
                        (sel == 3'b100) ? in4 : 4'h0;
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
            if (counter_reg == (50000 - 1)) begin
                counter_reg <= 0;
                clk_reg     <= ~clk_reg;
            end
        end
    end
endmodule
