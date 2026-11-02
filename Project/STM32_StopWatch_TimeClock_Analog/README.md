# HW3_StopWatch_TimeClock_Analog

STM32F411RE(NUCLEO)로 만든 아날로그 시계와 스톱워치입니다. 스텝 모터 3개(28BYJ-48)가 시침, 분침, 초침을 돌리고, I2C LCD와 FND에 시간을 보여 줍니다.

## 기능

| 모드 | LCD 1행 | LCD 2행 | 시곗바늘 / FND |
|------|---------|---------|----------------|
| 시계 | `TIME    hh:mm:ss` | 날짜 (`20yy.mm.dd.요일`) | RTC 시간 |
| 스톱워치 | `TIME    hh:mm:ss` | `SW   hh:mm:ss:cc` | 스톱워치 시간 |

- 시계는 DS3231 RTC 값을 씁니다.
- 모드를 바꾸면 바늘이 새 값으로 다시 맞춰집니다. 스톱워치는 시계 모드에서도 계속 돌아갑니다.
- 바늘은 시계 방향으로만 돕니다.
- 전원을 켜기 전에 세 바늘을 손으로 12시에 맞춰 두어야 합니다.

## 버튼

| 버튼 | 핀 | 동작 |
|------|----|------|
| MODE | PC0 | 시계 ↔ 스톱워치 |
| RUN/STOP | PC1 | 스톱워치 시작/정지 |
| CLEAR | PC3 | 스톱워치 초기화 |

## 하드웨어 연결

| 부품 | 핀 |
|------|----|
| I2C LCD (0x27), DS3231 | I2C1: PB8 (SCL), PB9 (SDA) |
| 시침 모터 IN1~IN4 | PC10, PC11, PC12, PD2 |
| 분침 모터 IN1~IN4 | PC5, PC6, PC8, PC9 |
| 초침 모터 IN1~IN4 | PA0, PA1, PA4, PB0 |
| FND 자리 선택 D1~D4 | PA5, PB6, PC7, PA10 |
| FND 세그먼트 a~dp | PA6, PA9, PB5, PB10, PA8, PA7, PB3, PB4 |
| LED | PB15 (시계), PB14 (스톱워치), PB13 (정지), PC4 (동작) |

## 구조

```
Core/Src/
├── ap/        # ap_main.c (모드 상태 머신), AnalogClock, Display, StopWatch, TimeClock
└── driver/    # StepMotor, button, fnd, lcd, led, rtc
```

- TIM9 (1ms): 바늘마다 목표 위치까지 한 스텝씩 이동 (1바퀴 4096스텝, 하프 스텝)
- TIM4: 시계, 스톱워치
- TIM3: FND 표시

## 빌드

이 폴더에는 `.ioc`와 직접 작성한 코드(`main.c`, `ap/`, `driver/`)만 들어 있습니다.

1. STM32CubeIDE에서 `HW3_StopWatch_TimeClock_Analog.ioc`로 새 프로젝트를 만들고 코드를 생성합니다.
2. 이 폴더의 `Core/Src`를 생성된 프로젝트의 `Core/Src`에 덮어씁니다.
3. 빌드합니다.
