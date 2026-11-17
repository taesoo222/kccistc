# STM32_RC_Car_RTOS_ISR

STM32F411RE(NUCLEO)와 FreeRTOS로 만든 초음파 자율주행 RC카입니다. 수동(버튼/블루투스 명령)과 자동(초음파 3개) 주행을 상태 머신(FSM)으로 전환하고, 초음파 에코와 UART 수신은 인터럽트로 비동기 처리합니다.

## 구조

```
Core/Src/
├── ap/
│   ├── message.c/.h        # 태스크 간 메시지 큐
│   ├── service/sound       # 부저 효과음
│   └── task/               # ultrasonic, motor_control, button, comm
├── driver/                 # HCSR04, dc_motor, button, buzzer, lcd
├── common/delay            # DWT 기반 us 지연
├── main.c
└── freertos.c              # 태스크 생성
```

- 태스크 4개: ultrasonic(측정), motor_control(FSM), button, comm(명령 수신). 태스크끼리는 메시지 큐로만 통신하고 LCD와 UART는 뮤텍스로 보호합니다.
- 초음파: HC-SR04 3개가 Trig를 공유하고, Echo는 EXTI + TIM2(1MHz)로 폭을 측정합니다.
- 주행 상태: STOP, RUN, LEFT, RIGHT, BACK.
- 자동 주행: 정면 25cm 미만이면 회전, 35cm 이상이면 직진으로 복귀하고(히스테리시스), 8cm 미만이면 후진합니다.

## 하드웨어 연결

| 부품 | 핀 |
|------|----|
| 초음파 Trig (공유) | PC12 |
| 초음파 Echo 왼쪽 / 가운데 / 오른쪽 | PC10 / PC11 / PC5 (EXTI) |
| DC 모터 PWM 왼쪽 / 오른쪽 | PC6 (TIM3_CH1) / PC8 (TIM3_CH3) |
| 부저 | PA8 (TIM1_CH1) |
| I2C LCD | I2C |
| PC 디버그 | USART2 (115200) |
| 블루투스 | USART6 (9600): PA11, PA12 |
| 자동 주행 토글 | B1 (PC13) |

- 명령은 '*'로 끝납니다.

## 트러블슈팅: 리셋 후 멈춤

- 증상: 리셋하면 가끔 시스템이 멈춤
- 원인: 에코 EXTI 인터럽트가 타이머 핸들(`sr04_htim`) 설정 전에 들어와 NULL을 참조하며 HardFault
- 해결: `HCSR04_echoISR` 진입부에 NULL 가드 추가 (리셋 10회 반복 정상)

## 빌드

STM32CubeIDE에서 `RC_CAR_F.ioc`로 프로젝트를 만든 뒤 `Core/Src`의 소스를 덮어씁니다. 이 저장소에는 직접 작성한 소스와 `.ioc`만 있습니다.
