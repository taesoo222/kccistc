`timescale 1ns / 1ps

//======================================================================
// control_unit — 5단계 교체 (상태 4개 -> 8개, c_state 2 -> 3비트)
//
//  btnD 는 상태와 무관하게 타이머 모드를 토글합니다 (초기값 0).
//    0 -> 1 : 저장된 알람 값으로 카운트다운 시작
//    1 -> 0 : 스톱워치로 복귀 + 카운터 초기화 (알람 값은 보존)
//
//  btnL·btnR·btnU 잠금은 FSM 구조로 해결됩니다.
//  TIMER_RUN / TIMER_DONE 의 case 안에 normal[0]·normal[1]·normal[2] 전이가
//  없으므로 그 버튼들은 무시됩니다. 따로 마스킹 회로가 필요 없습니다.
//
//  alarm_led_1s 를 이 안에 품고 있습니다. 트리거가 되는 alarm_reg 를
//  만드는 곳이 바로 여기라, 밖으로 뺐다가 다시 받을 이유가 없습니다.
//
//  버튼 게이팅과 엣지 검출도 이 안으로 들였습니다.
//  "버튼이 언제 유효한가" 는 스위치와 타이머 상태로 정해지는 제어 판단이고,
//  그 판단에 필요한 timer_reg 를 여기서 만들기 때문입니다.
//  덕분에 datapath 는 이 모듈의 출력만 받습니다 (되먹임 time_zero 제외).
//======================================================================
module stopwatch_control_unit(
    input        clk,
    input        reset,
    input        i_en,           // ~sw[1] : 이 도메인이 화면에 보이는가
    input        i_set_mode,     // sw[2]  : 알람 설정 스위치
    input  [3:0] i_btn,          // {btnD, btnU, btnR, btnL} 디바운스된 생버튼
    input        i_disp_sel,     // sw[0]  : 편집 대상 필드 쌍
    input        i_done,         // datapath 의 time_zero
    output       o_run_stop,
    output       o_clear,
    output       o_mode,
    output       o_load,         // 타이머 시작 시 알람 값 로드 1클럭 펄스
    output       o_alarm_led,    // 카운트다운 0 도달 후 1초간 점등 (LD15)
    output       o_set_en,       // 설정 모드 활성 (= set_active)
    output       o_set_rise,     // 설정 진입 1클럭 : 알람 값 초기화
    output [3:0] o_set_btn,      // 설정용으로 게이팅된 버튼
    output       o_disp_sel      // i_disp_sel 통과 (datapath 로 단방향 전달)
);

    // 상태가 8개이므로 c_state 는 반드시 3비트여야 합니다
    parameter STOP       = 3'd0,
              RUN        = 3'd1,
              CLEAR      = 3'd2,
              MODE       = 3'd3,
              TIMER_LOAD = 3'd4,
              TIMER_WAIT = 3'd5,
              TIMER_RUN  = 3'd6,
              TIMER_DONE = 3'd7;

    reg [2:0] c_state, n_state;
    reg run_stop_reg, run_stop_next;
    reg clear_reg,    clear_next;
    reg mode_reg,     mode_next;
    reg load_reg,     load_next;
    reg timer_reg,    timer_next;
    reg alarm_reg,    alarm_next;

    //------------------------------------------------------------------
    // 입력 조건화 — 예전 btn_gate + 엣지 검출을 이 안으로 들였습니다.
    //   set_mode_eff : 타이머 진행 중에는 설정 모드 진입을 막습니다.
    //   normal       : 일반 조작용. FSM 이 직접 씁니다.
    //   o_set_btn    : 설정용. datapath 안의 alarm_set_unit 으로 갑니다.
    //   timer_reg 는 레지스터라 조합 루프가 생기지 않습니다.
    //   비트 순서 : [0]=btnL [1]=btnR [2]=btnU [3]=btnD
    //------------------------------------------------------------------
    wire       set_mode_eff = i_set_mode & ~timer_reg;
    wire       set_en_w     = i_en & set_mode_eff;
    wire [3:0] normal       = i_btn & {4{i_en & ~set_mode_eff}};

    // set_d 하나로 진입 엣지와 종료 엣지를 모두 만듭니다
    reg set_d;
    always @(posedge clk, posedge reset) begin
        if (reset) set_d <= 1'b0;
        else       set_d <= set_en_w;
    end
    wire set_rise_w = set_en_w & ~set_d;   // 설정 진입 -> 알람 값 초기화
    wire set_fall_w = set_d & ~set_en_w;   // 설정 종료 -> 스톱워치 클리어

    assign o_set_en   = set_en_w;
    assign o_set_rise = set_rise_w;
    assign o_set_btn  = i_btn & {4{set_en_w}};
    assign o_disp_sel = i_disp_sel;

    assign o_run_stop = run_stop_reg & ~(timer_reg & i_done);
    assign o_clear    = clear_reg;
    assign o_mode     = mode_reg;
    assign o_load     = load_reg;

    // alarm_reg 는 카운트다운이 0 에 도달한 1클럭 펄스입니다.
    // 그대로 내보내면 눈에 안 보이므로 여기서 1초로 늘려서 출력합니다.
    alarm_led_1s U_ALARM_LED(
        .clk  (clk),
        .reset(reset),
        .trig (alarm_reg),
        .led  (o_alarm_led)
    );

    always @(posedge clk, posedge reset) begin
        if (reset) begin
            c_state      <= STOP;
            run_stop_reg <= 1'b0;
            clear_reg    <= 1'b0;
            mode_reg     <= 1'b0;
            load_reg     <= 1'b0;
            timer_reg    <= 1'b0;   // btnD 초기값 0
            alarm_reg    <= 1'b0;
        end else begin
            c_state      <= n_state;
            run_stop_reg <= run_stop_next;
            clear_reg    <= clear_next;
            mode_reg     <= mode_next;
            load_reg     <= load_next;
            timer_reg    <= timer_next;
            alarm_reg    <= alarm_next;
        end
    end

    always @(*) begin
        n_state       = c_state;
        run_stop_next = run_stop_reg;
        clear_next    = clear_reg;
        mode_next     = mode_reg;
        load_next     = 1'b0;        // 기본 0 : 1클럭 펄스
        timer_next    = timer_reg;
        alarm_next    = 1'b0;        // 기본 0 : 1클럭 펄스

        //--------------------------------------------------------------
        // btnD 는 어떤 상태에서든 최우선으로 처리합니다.
        // timer_reg 가 그대로 btnD 의 0/1 토글값입니다.
        //--------------------------------------------------------------
        if (normal[3]) begin
            if (!timer_reg) begin        // 0 -> 1 : 카운트다운 시작
                run_stop_next = 1'b0;    // 로드가 끝날 때까지 잠시 멈춤
                n_state       = TIMER_LOAD;
            end else begin               // 1 -> 0 : 스톱워치 복귀 + 초기화
                run_stop_next = 1'b0;
                mode_next     = 1'b0;    // 업카운트로 복귀
                timer_next    = 1'b0;
                n_state       = CLEAR;   // 다음 클럭에 카운터 클리어
            end
        end
        //--------------------------------------------------------------
        // 시간 설정이 끝나면 (sw[2] 1->0) 스톱워치를 0 으로 초기화합니다.
        // 설정 중에는 load 가 계속 켜져 화면이 알람 값이었으므로,
        // 그 값이 화면에 남지 않도록 여기서 지웁니다.
        // 알람 값 자체는 alarm_set_unit 안에 그대로 보존됩니다.
        //--------------------------------------------------------------
        else if (set_fall_w) begin
            run_stop_next = 1'b0;        // 설정 전에 돌고 있었어도 정지시킵니다
            n_state       = CLEAR;
        end else begin
        case (c_state)
            STOP: begin
                run_stop_next = 1'b0;
                clear_next    = 1'b0;
                if      (normal[0]) n_state = RUN;
                else if (normal[1]) n_state = CLEAR;
                else if (normal[2]) n_state = MODE;
                else                n_state = c_state;
            end

            RUN: begin
                run_stop_next = 1'b1;
                if (normal[0]) n_state = STOP;
                else           n_state = c_state;
            end

            CLEAR: begin
                clear_next = 1'b1;
                n_state    = STOP;
            end

            MODE: begin
                mode_next = ~mode_reg;
                n_state   = STOP;
            end

            // 저장된 알람 값을 카운터에 로드
            TIMER_LOAD: begin
                load_next  = 1'b1;
                mode_next  = 1'b1;       // 다운카운트 강제
                timer_next = 1'b1;
                clear_next = 1'b0;
                n_state    = TIMER_WAIT;
            end

            // 로드가 카운터에 반영될 한 클럭을 기다립니다.
            // 이 상태가 없으면 i_done 이 로드 전 값(0)을 보고 바로 끝나 버립니다.
            TIMER_WAIT: begin
                n_state = TIMER_RUN;
            end

            // 카운트다운. btnL·btnR·btnU 는 이 상태에서 아예 쳐다보지 않습니다.
            TIMER_RUN: begin
                run_stop_next = 1'b1;
                if (i_done) begin
                    alarm_next = 1'b1;   // 0 도달 -> LD15 트리거
                    n_state    = TIMER_DONE;
                end else n_state = c_state;
            end

            // 0 도달 : 정지하고 화면 유지. btnD 를 누를 때까지 머뭅니다.
            TIMER_DONE: begin
                run_stop_next = 1'b0;
                n_state       = c_state;
            end

            default: n_state = STOP;
        endcase
        end
    end
endmodule

//======================================================================
// alarm_led_1s — trig 이 들어오면 정확히 1초간 출력을 1 로 유지합니다.
//   재트리거되면 카운터를 다시 0 부터 셉니다.
//======================================================================
module alarm_led_1s #(parameter COUNT = 100_000_000)(   // 100MHz x 1초
    input      clk,
    input      reset,
    input      trig,
    output reg led
);
    reg [$clog2(COUNT)-1:0] counter_reg;

    always @(posedge clk, posedge reset) begin
        if (reset) begin
            counter_reg <= 0;
            led         <= 1'b0;
        end else if (trig) begin
            counter_reg <= 0;
            led         <= 1'b1;
        end else if (led) begin
            if (counter_reg == COUNT-1) begin
                counter_reg <= 0;
                led         <= 1'b0;
            end else begin
                counter_reg <= counter_reg + 1;
            end
        end
    end
endmodule