module data_selector (
    input        clk,
    input        reset,
    input [15:0] sw,

    input [6:0] watch_msec,
    input [5:0] watch_sec,
    input [5:0] watch_min,
    input [4:0] watch_hour,

    input [6:0] stopwatch_msec,
    input [5:0] stopwatch_sec,
    input [5:0] stopwatch_min,
    input [4:0] stopwatch_hour,

    input [15:0] temperature,
    input [15:0] humidity,
    input [ 8:0] distance,

    output [2:0] display_mode,
    output [6:0] fnd_msec,
    output [5:0] fnd_sec,
    output [5:0] fnd_min,
    output [4:0] fnd_hour,
    output reg [13:0] selected_data
);

    assign display_mode =
    sw[1]  ? 3'b010 :
    sw[2]  ? 3'b011 :
    sw[3]  ? 3'b100 :
    sw[15] ? 3'b001 :
             3'b000;

    assign fnd_msec = sw[0] ? stopwatch_msec : watch_msec;
    assign fnd_sec = sw[0] ? stopwatch_sec : watch_sec;
    assign fnd_min = sw[0] ? stopwatch_min : watch_min;
    assign fnd_hour = sw[0] ? stopwatch_hour : watch_hour;

    always @(posedge clk, posedge reset) begin
        if (reset) begin
            selected_data <= 14'd0;
        end else begin
            case (display_mode)
                3'b000:  selected_data <= (fnd_sec * 100) + fnd_msec;
                3'b001:  selected_data <= (fnd_hour * 100) + fnd_min;
                3'b010:  selected_data <= temperature[15:8];
                3'b011:  selected_data <= humidity[15:8];
                3'b100:  selected_data <= {5'd0, distance};
                default: selected_data <= 14'd0;
            endcase
        end
    end
endmodule
