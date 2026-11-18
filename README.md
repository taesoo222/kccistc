# 대한상공회의소 서울기술교육센터

## 폴더 한눈에 보기

```
kccistc/
├── Project/   완성된 프로젝트 (각 폴더에 README 있음)
└── study/     수업 중 만든 연습 코드
```

## Project/ — 완성된 프로젝트

### 임베디드 (STM32F411RE NUCLEO, C / HAL)

| 폴더 | 내용 |
|------|------|
| [STM32_Elevator](Project/STM32_Elevator) | 3층 엘리베이터 모형. 스텝모터 + 포토 인터럽터, UART 패킷으로 PC 모니터(`elevator_monitor`, Python)와 연동, 비상 정지 |
| [STM32_RC_Car_RTOS_ISR](Project/STM32_RC_Car_RTOS_ISR) | FreeRTOS 초음파 자율주행 RC카. 태스크 4개 + 메시지 큐, 수동/자동 주행 FSM |
| [STM32_MultiDisplay](Project/STM32_MultiDisplay) | 스마트 워치. I2C LCD에 달력 · 온습도(DHT11) · 초음파 거리(HC-SR04) · 스톱워치 · 시계 |
| [STM32_StopWatch_TimeClock_Analog](Project/STM32_StopWatch_TimeClock_Analog) | 스텝모터 3개로 시침/분침/초침을 돌리는 아날로그 시계 + 스톱워치 (DS3231 RTC) |
| [STM32_Stopwatch_watch](Project/STM32_Stopwatch_watch) | FND 스톱워치 / 시계 2모드 |

### FPGA (Verilog / SystemVerilog)

| 폴더 | 내용 |
|------|------|
| [rv32i_soc](Project/rv32i_soc) | RISC-V RV32I CPU / SoC |
| [fifo_UVM](Project/fifo_UVM) | 동기식 FIFO(16x8bit) UVM 검증 (Synopsys VCS) |
| [fifo_UVM_xsim](Project/fifo_UVM_xsim) | 위 프로젝트를 Vivado xsim에서 돌리도록 옮긴 버전 |
| [stopwatch_watch](Project/stopwatch_watch) | Basys-3 디지털 시계 + 스톱워치/카운트다운 |
| [sensor_stopwatch_UART](Project/sensor_stopwatch_UART) | 시계 + 스톱워치 + DHT11 + HC-SR04를 버튼 또는 UART 명령으로 제어 |

### AI

| 폴더 | 내용 |
|------|------|
| [AirGesture](Project/AirGesture) | 라즈베리파이 카메라로 손동작을 인식해 Windows PC의 영상 재생·PPT 슬라이드를 제어 (팀 프로젝트). `AIRGESTURE`(Pi 쪽 + 모델) / `AirGesture_PC_bridge`(PC 쪽) / `experiments`(스와이프 MLP 실험) |
