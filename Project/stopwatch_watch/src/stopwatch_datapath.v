`timescale 1ns / 1ps

//======================================================================
// stopwatch_datapath — 카운터 사슬 + 알람 값 저장소
//   (stopwatch 래퍼 제거. top_stopwatch_watch.v 가 이 모듈을 직접 인스턴스합니다.
//    watch_datapath 와 대칭 위치입니다.)
//
//   alarm_set_unit 을 안으로 들였습니다. 그 출력 24비트(msec/sec/min/hour)가
//   전부 아래 카운터로만 가기 때문에, 밖에 두면 상위 계층에 24비트짜리
//   버스 4개가 그냥 지나가기만 합니다. 안으로 넣으면 상위(top)에 필요한 것은
//   set_en / set_rise / set_btn / disp_sel 7비트와 field_ptr 1비트뿐입니다.
//
//   입력은 전부 control_unit 에서 옵니다. 버튼도 스위치도 직접 받지 않습니다.
//
//   tick_gen_100hz 인스턴스는 여기 그대로 둡니다. 시계 도메인도 자기 것을
//   따로 인스턴스하지만, 같은 모듈/clk/reset 이라 두 틱이 항상 같은 클럭에
//   발생합니다. 즉 하나를 공유한 것과 동작이 동일합니다.
//======================================================================
module stopwatch_datapath #(
    parameter MSEC_WIDTH = 7,
    SEC_WIDTH = 6,
    MIN_WIDTH = 6,
    HOUR_WIDTH = 5
) (
    input clk,
    input reset,
    input run_stop,
    input clear,
    input mode,
    input load,  // control_unit 의 o_load : 타이머 시작 1클럭
    input set_en,  // 설정 모드 활성 (설정 중 계속 로드)
    input set_rise,  // 설정 진입 1클럭 : 알람 값 초기화
    input [3:0] set_btn,  // control_unit 에서 게이팅되어 온 버튼
    input disp_sel,  // control_unit 을 거쳐 온 sw[0]
    output field_ptr,  // 0 = 오른쪽 필드, 1 = 왼쪽 필드
    output [MSEC_WIDTH-1:0] msec,
    output [SEC_WIDTH-1:0] sec,
    output [MIN_WIDTH-1:0] min,
    output [HOUR_WIDTH-1:0] hour,
    output time_zero
);
    wire w_tick_100hz, w_tick_sec, w_tick_min, w_tick_hour;

    assign time_zero = (msec == 0) && (sec == 0) && (min == 0) && (hour == 0);


    // 알람 값 저장소
    wire [MSEC_WIDTH-1:0] w_set_msec;
    wire [SEC_WIDTH-1:0] w_set_sec;
    wire [MIN_WIDTH-1:0] w_set_min;
    wire [HOUR_WIDTH-1:0] w_set_hour;

    alarm_set_unit U_ALARM_SET (
        .clk(clk),
        .reset(reset),
        .set_en(set_en),
        .set_rise(set_rise),
        .a_btn(set_btn),
        .disp_sel(disp_sel),
        .field_ptr(field_ptr),
        .set_msec(w_set_msec),
        .set_sec(w_set_sec),
        .set_min(w_set_min),
        .set_hour(w_set_hour)
    );

    // 설정 중에는 계속 로드해 화면에 알람 값을 띄우고,
    // 타이머 시작 시에는 1클럭 로드로 카운터에 값을 주입합니다.
    wire load_eff = set_en | load;

    tick_gen_100hz U_TICK_GEN_100HZ (
        .clk(clk),
        .reset(reset),
        .o_tick(w_tick_100hz)
    );

    sw_time_counter #(
        .BIT_WIDTH(MSEC_WIDTH),
        .TIMES(100)
    ) U_MSEC_COUNTER (
        .clk(clk),
        .reset(reset),
        .i_tick(w_tick_100hz),
        .mode(mode),
        .run_stop(run_stop),
        .clear(clear),
        .load(load_eff),
        .load_value(w_set_msec),
        .time_count(msec),
        .o_tick(w_tick_sec)
    );

    sw_time_counter #(
        .BIT_WIDTH(SEC_WIDTH),
        .TIMES(60)
    ) U_SEC_COUNTER (
        .clk(clk),
        .reset(reset),
        .i_tick(w_tick_sec),
        .mode(mode),
        .run_stop(run_stop),
        .clear(clear),
        .load(load_eff),
        .load_value(w_set_sec),
        .time_count(sec),
        .o_tick(w_tick_min)
    );

    sw_time_counter #(
        .BIT_WIDTH(MIN_WIDTH),
        .TIMES(60)
    ) U_MIN_COUNTER (
        .clk(clk),
        .reset(reset),
        .i_tick(w_tick_min),
        .mode(mode),
        .run_stop(run_stop),
        .clear(clear),
        .load(load_eff),
        .load_value(w_set_min),
        .time_count(min),
        .o_tick(w_tick_hour)
    );

    sw_time_counter #(
        .BIT_WIDTH(HOUR_WIDTH),
        .TIMES(24)
    ) U_HOUR_COUNTER (
        .clk(clk),
        .reset(reset),
        .i_tick(w_tick_hour),
        .mode(mode),
        .run_stop(run_stop),
        .clear(clear),
        .load(load_eff),
        .load_value(w_set_hour),
        .time_count(hour),
        .o_tick()
    );
endmodule


//======================================================================
// alarm_set_unit — 알람 시간을 필드 단위로 편집합니다.
//   btnL / btnR : 왼쪽 / 오른쪽 필드 선택
//   btnU / btnD : 선택된 필드의 값 증감
// 어느 두 필드를 편집하는지는 disp_sel(sw[0]) 이 정합니다.
//   disp_sel = 0  ->  오른쪽 = msec, 왼쪽 = sec
//   disp_sel = 1  ->  오른쪽 = min,  왼쪽 = hour
// 자리별 BCD 를 쓰지 않고 값을 직접 증감하므로 상한을 넘으면 0 으로,
// 0 에서 내리면 상한으로 순환합니다.
//======================================================================
module alarm_set_unit (
    input clk,
    input reset,
    input set_en,  // 설정 모드 활성
    input        set_rise,      // 설정 모드로 들어온 순간 1클럭 -> 값 초기화
    input [3:0] a_btn,  // {btnD, btnU, btnR, btnL}
    input disp_sel,  // sw[0]
    output field_ptr,  // 0 = 오른쪽 필드, 1 = 왼쪽 필드
    output [6:0] set_msec,
    output [5:0] set_sec,
    output [5:0] set_min,
    output [4:0] set_hour
);
    reg [6:0] r_msec;
    reg [5:0] r_sec;
    reg [5:0] r_min;
    reg [4:0] r_hour;
    reg       r_field;

    assign set_msec  = r_msec;
    assign set_sec   = r_sec;
    assign set_min   = r_min;
    assign set_hour  = r_hour;
    assign field_ptr = r_field;

    wire btn_left = a_btn[0];  // 왼쪽 필드로
    wire btn_right = a_btn[1];  // 오른쪽 필드로
    wire btn_up = a_btn[2];
    wire btn_down = a_btn[3];

    always @(posedge clk, posedge reset) begin
        if (reset || set_rise) begin
            // sw[2] 가 1 로 올라간 순간 알람 값이 00.00 으로 초기화됩니다
            r_msec  <= 7'd0;
            r_sec   <= 6'd0;
            r_min   <= 6'd0;
            r_hour  <= 5'd0;
            r_field <= 1'b0;
        end else if (set_en) begin
            if (btn_left) r_field <= 1'b1;
            if (btn_right) r_field <= 1'b0;

            if (btn_up) begin
                if (!disp_sel) begin
                    if (!r_field)
                        r_msec <= (r_msec == 7'd99) ? 7'd0 : r_msec + 1'b1;
                    else r_sec <= (r_sec == 6'd59) ? 6'd0 : r_sec + 1'b1;
                end else begin
                    if (!r_field)
                        r_min <= (r_min == 6'd59) ? 6'd0 : r_min + 1'b1;
                    else r_hour <= (r_hour == 5'd23) ? 5'd0 : r_hour + 1'b1;
                end
            end

            if (btn_down) begin
                if (!disp_sel) begin
                    if (!r_field)
                        r_msec <= (r_msec == 7'd0) ? 7'd99 : r_msec - 1'b1;
                    else r_sec <= (r_sec == 6'd0) ? 6'd59 : r_sec - 1'b1;
                end else begin
                    if (!r_field)
                        r_min <= (r_min == 6'd0) ? 6'd59 : r_min - 1'b1;
                    else r_hour <= (r_hour == 5'd0) ? 5'd23 : r_hour - 1'b1;
                end
            end
        end
    end
endmodule


//======================================================================
// sw_time_counter — 우선순위 : reset > clear > load > count
//   load 가 세는 것보다 앞서야 설정 모드에서 값이 유지됩니다.
//======================================================================
module sw_time_counter #(
    parameter BIT_WIDTH = 7,
    TIMES = 100
) (
    input                      clk,
    input                      reset,
    input                      i_tick,
    input                      mode,        // 0 = up, 1 = down
    input                      run_stop,
    input                      clear,
    input                      load,
    input      [BIT_WIDTH-1:0] load_value,
    output     [BIT_WIDTH-1:0] time_count,
    output reg                 o_tick
);
    reg [BIT_WIDTH-1:0] counter_reg;
    assign time_count = counter_reg;

    always @(posedge clk, posedge reset) begin
        if (reset | clear) begin
            counter_reg <= 0;
            o_tick      <= 1'b0;
        end else if (load) begin
            counter_reg <= load_value;
            o_tick      <= 1'b0;
        end else if (i_tick && run_stop) begin
            if (!mode) begin  // ---- UP ----
                if (counter_reg == TIMES - 1) begin
                    counter_reg <= 0;
                    o_tick      <= 1'b1;
                end else begin
                    counter_reg <= counter_reg + 1;
                    o_tick      <= 1'b0;
                end
            end else begin  // ---- DOWN ----
                if (counter_reg == 0) begin
                    counter_reg <= TIMES - 1;
                    o_tick      <= 1'b1;
                end else begin
                    counter_reg <= counter_reg - 1;
                    o_tick      <= 1'b0;
                end
            end
        end else begin
            o_tick <= 1'b0;
        end
    end
endmodule
