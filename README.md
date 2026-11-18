# 대한상공회의소 서울기술교육센터

## 폴더 한눈에 보기

```
kccistc/
├── Project/   완성된 프로젝트 (각 폴더에 README 있음)
└── study/     수업 중 만든 연습 코드
```

## Project/ — 완성된 프로젝트

### 임베디드 (STM32F411RE NUCLEO, C / HAL)

<table width="100%">
<tr><th width="30%">폴더</th><th width="70%">내용</th></tr>
<tr><td><a href="Project/STM32_Elevator">STM32_Elevator</a></td><td>3층 엘리베이터 모형. 스텝모터 + 포토 인터럽터, UART 패킷으로 PC 모니터(<code>elevator_monitor</code>, Python)와 연동, 비상 정지</td></tr>
<tr><td><a href="Project/STM32_RC_Car_RTOS_ISR">STM32_RC_Car_RTOS_ISR</a></td><td>FreeRTOS 초음파 자율주행 RC카. 태스크 4개 + 메시지 큐, 수동/자동 주행 FSM</td></tr>
<tr><td><a href="Project/STM32_MultiDisplay">STM32_MultiDisplay</a></td><td>스마트 워치. I2C LCD에 달력 · 온습도(DHT11) · 초음파 거리(HC-SR04) · 스톱워치 · 시계</td></tr>
<tr><td><a href="Project/STM32_StopWatch_TimeClock_Analog">STM32_StopWatch_TimeClock_Analog</a></td><td>스텝모터 3개로 시침/분침/초침을 돌리는 아날로그 시계 + 스톱워치 (DS3231 RTC)</td></tr>
<tr><td><a href="Project/STM32_Stopwatch_watch">STM32_Stopwatch_watch</a></td><td>FND 스톱워치 / 시계 2모드</td></tr>
</table>

### FPGA (Verilog / SystemVerilog)

<table width="100%">
<tr><th width="30%">폴더</th><th width="70%">내용</th></tr>
<tr><td><a href="Project/rv32i_soc">rv32i_soc</a></td><td>RISC-V RV32I CPU / SoC</td></tr>
<tr><td><a href="Project/fifo_UVM">fifo_UVM</a></td><td>동기식 FIFO(16x8bit) UVM 검증 (Synopsys VCS)</td></tr>
<tr><td><a href="Project/fifo_UVM_xsim">fifo_UVM_xsim</a></td><td>위 프로젝트를 Vivado xsim에서 돌리도록 옮긴 버전</td></tr>
<tr><td><a href="Project/stopwatch_watch">stopwatch_watch</a></td><td>Basys-3 디지털 시계 + 스톱워치/카운트다운</td></tr>
<tr><td><a href="Project/sensor_stopwatch_UART">sensor_stopwatch_UART</a></td><td>시계 + 스톱워치 + DHT11 + HC-SR04를 버튼 또는 UART 명령으로 제어</td></tr>
</table>

### AI

<table width="100%">
<tr><th width="30%">폴더</th><th width="70%">내용</th></tr>
<tr><td><a href="Project/AirGesture">AirGesture</a></td><td>라즈베리파이 카메라로 손동작을 인식해 Windows PC의 영상 재생·PPT 슬라이드를 제어 (팀 프로젝트). <code>AIRGESTURE</code>(Pi 쪽 + 모델) / <code>AirGesture_PC_bridge</code>(PC 쪽) / <code>experiments</code>(스와이프 MLP 실험)</td></tr>
</table>
