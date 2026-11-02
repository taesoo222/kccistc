# STM32_MultiDisplay

STM32F411RE(NUCLEO)로 만든 스마트 워치입니다. I2C LCD에 달력, 온습도, 초음파 거리, 스톱워치, 시계를 보여 줍니다.

## 기능

| 모드 | LCD 1행 | LCD 2행 |
|------|---------|---------|
| 1. 달력 (CAL) | `CAL   hh:mm:ss` | 날짜 |
| 2. 온습도 (TH) | `TH    hh:mm:ss` | 온도 / 습도 (DHT11) |
| 3. 초음파 자 (DIST) | `DIST  hh:mm:ss` | 1초 동안 측정한 평균 거리 (HC-SR04) |
| 4. 스톱워치 (SW) | `SW    hh:mm:ss` | 스톱워치 시간 / 상태 |

- 시계는 DS3231 RTC 값을 씁니다.
- FND는 모드와 관계없이 항상 스톱워치를 보여 줍니다.
- 부저 소리: 전원을 켤 때, 버튼을 누를 때, 스톱워치가 도는 중에 Clear를 누를 때(에러음), 매 정시, 거리 측정이 끝났을 때 납니다.

## 버튼

| 버튼 | 핀 | 동작 |
|------|----|------|
| MODE | PC0 | 모드 전환 (달력 → 온습도 → 거리 → 스톱워치 → 달력) |
| RUN/STOP | PC1 | 스톱워치 시작/정지, 거리 모드에서는 측정 시작 |
| CLEAR | PC3 | 스톱워치 초기화 |

## 하드웨어 연결

| 부품 | 핀 |
|------|----|
| I2C LCD (0x27), DS3231 | I2C1: PB8 (SCL), PB9 (SDA) |
| DHT11 | PC8 |
| HC-SR04 | Trig PC5, Echo PC6 (EXTI) |
| 부저 | PA11 (TIM1_CH4 PWM) |
| FND 자리 선택 D1~D4 | PA5, PB6, PC7, PA10 |
| FND 세그먼트 a~dp | PA6, PA9, PB5, PB10, PA8, PA7, PB3, PB4 |
| LED | PB15 (시계), PB14 (스톱워치), PB13 (정지), PC4 (동작) |

## 구조

```
Core/Src/
├── ap/            # 앱: 모드 상태 머신 (ap_main.c)
│   └── service/   # btnEvent, Display, StopWatch, TimeClock, temp_humid, distance, ruler, sound
├── driver/        # button, buzzer, DHT11, fnd, HCSR04, lcd, led, rtc
└── common/        # delay, queue
```

- TIM4 (10ms): 시계, 스톱워치, 버튼 스캔. 버튼 이벤트는 큐에 넣고 메인 루프에서 처리합니다.
- TIM3: FND 표시
- TIM10: HC-SR04 시간 측정
- TIM1: 부저 PWM

## 빌드

이 폴더에는 `.ioc`와 직접 작성한 코드(`main.c`, `ap/`, `driver/`, `common/`)만 들어 있습니다.

1. STM32CubeIDE에서 `HW4_LCD_MultiDisplay.ioc`로 새 프로젝트를 만들고 코드를 생성합니다.
2. 이 폴더의 `Core/Src`를 생성된 프로젝트의 `Core/Src`에 덮어씁니다.
3. 빌드합니다.
