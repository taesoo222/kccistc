/*
 * ap_main.c
 *
 *  Created on: 2026. 11. 5.
 *      Author: kccistc
 *
 *  4단계: 호출 기억 + 운행 순서 + 문 열림
 *   전원 ON -> HOMING (1층 찾기)
 *   PC3 = 1층, PC1 = 2층, PC0 = 3층 (언제 눌러도 기억, 멈춘 층 버튼 = 문 열림 연장)
 *   ERROR가 나면 점검 운전: 2층 버튼 누르는 동안 모터 정방향(CW), 3층 버튼 역방향(CCW),
 *                          1층 버튼 2초 길게 = 다시 HOMING
 *   B1(PC13, 파란 버튼) 또는 외부 비상 버튼(PB5/D4, 외부 풀업, 누르면 GND) = 현장 비상 정지 -> ERROR
 *     (해제: 1층 버튼 2초 또는 PC에서 관리자 PIN)
 *   ERROR 동안 비상 LED(PB4/D5 - 330옴 - LED - GND) 깜빡임 + 경보음 1초마다 반복, 해제되면 꺼짐
 *   UART(115200) = PC 감시 프로그램(elevator_monitor) 패킷 통신 (service/protocol)
 *   UART_TEXT_LOG를 1로 하면 텍스트 로그도 같이 나감 (시리얼 터미널로 디버깅할 때만, 평소 0):
 *     [시간ms] 2F IN  step=5312                 <- 센서 진입/이탈 + 이번 이동 시작 후 스텝 수
 *     [시간ms] DOOR 2F calls=[--3] step=5562    <- 상태/층/호출이 바뀔 때
 */

#include "ap_main.h"
#include <stdio.h>
#include "service/elevator/elevator.h"
#include "service/sound/sound.h"
#include "service/display/display.h"
#include "service/protocol/protocol.h"
#include "../driver/StepMotor/StepMotor.h"
#include "../driver/button/button.h"
#include "../driver/led/led.h"
#include "../driver/photoSensor/photoSensor.h"
#include "../common/queue/que_buffer.h"

extern TIM_HandleTypeDef htim9;
extern UART_HandleTypeDef huart2;
extern I2C_HandleTypeDef hi2c1;

// 스텝 주기(us). TIM9 = 1MHz라 이 값이 곧 us. 1000보다 작게 하면 탈조함 (실측)
#define STEP_PERIOD_US 1000
#define PHOTO_LOG_SIZE 16
#define UART_TEXT_LOG 0 // 1 = 예전 텍스트 로그 (PC 감시 프로그램과 같이 못 씀)
#define REHOME_PRESS_MS 2000 // ERROR에서 1층 버튼을 이만큼 누르고 있으면 다시 HOMING
#define ALARM_PERIOD_MS 1000 // ERROR 동안 경보음(삑삑삑 600ms) 반복 주기
#define EMG_BLINK_MS 250     // 비상 LED 깜빡임 반 주기

typedef struct {
	uint32_t tick;
	uint32_t steps;
	uint8_t floor;
	uint8_t blocked;
} photo_log_t;

static stepMotor_pin_t elevMotorPin = {
	.port = {GPIOA, GPIOA, GPIOA, GPIOB},    // IN1~IN4
	.pin  = {GPIO_PIN_0, GPIO_PIN_1, GPIO_PIN_4, GPIO_PIN_0}
};
static stepMotor_t elevMotor = {.pin = &elevMotorPin, .stepCounter = 0};

static button_t btnFloor[PHOTO_FLOOR_NUM];
static button_t btnEmergency[2]; // B1 (PC13, 보드 풀업), 외부 비상 버튼 (PB5, 외부 풀업) -> 누르면 LOW
static led_t ledEmergency;       // 비상 LED (PB4)
static led_t ledFloor[PHOTO_FLOOR_NUM]; // 호출 등록 램프

static photo_log_t photoStorage[PHOTO_LOG_SIZE];
// EXTI는 ap_main() 전에(MX_GPIO_Init에서) 켜지므로 큐는 정적 초기화로 처음부터 준비해 둔다
static que_buf_t photoQue = {
	.buf = (uint8_t *)photoStorage, .elem_size = sizeof(photo_log_t), .capacity = PHOTO_LOG_SIZE
};

static volatile uint8_t started = 0; // elevator_init 전에 들어온 EXTI는 무시

void HAL_TIM_PeriodElapsedCallback(TIM_HandleTypeDef *htim)
{
	if (htim->Instance == TIM9) {
		elevator_tick();
	}
}

void HAL_GPIO_EXTI_Callback(uint16_t GPIO_Pin)
{
	uint8_t floor = photoSensor_pinToFloor(GPIO_Pin);
	if (floor == 0 || !started) {
		return;
	}
	uint8_t blocked = photoSensor_isBlocked(floor);

	elevator_onPhoto(floor, blocked);

	photo_log_t log = {HAL_GetTick(), elevator_getSteps(), floor, blocked};
	que_put(&photoQue, &log); // 가득 차면 버림 (로그용)
}

void HAL_UART_RxCpltCallback(UART_HandleTypeDef *huart)
{
	if (huart->Instance == USART2) {
		protocol_onRxCplt();
	}
}

void HAL_UART_ErrorCallback(UART_HandleTypeDef *huart)
{
	if (huart->Instance == USART2) {
		protocol_onRxError();
	}
}

static void uart_print(const char *msg, int len)
{
	HAL_UART_Transmit(&huart2, (uint8_t *)msg, len, 100);
}

static void log_task(void)
{
	static const char *stateName[] = {"HOMING", "IDLE", "UP", "DOWN", "DOOR", "ERROR"}; // elev_state_t 순서
	static const char *errName[] = {"", " TIMEOUT", " DIRECTION", " BUTTON", " REMOTE"}; // elev_err_t 순서
	static elev_state_t prevState = (elev_state_t)-1;
	static uint8_t prevFloor = 0xFF;
	static uint8_t prevCalls = 0xFF;
	char msg[64];
	int n;

	photo_log_t log;
	while (que_get(&photoQue, &log)) {
		n = snprintf(msg, sizeof(msg), "[%lu] %uF %s step=%lu\r\n", (unsigned long)log.tick,
		             log.floor, log.blocked ? "IN " : "OUT", (unsigned long)log.steps);
		uart_print(msg, n);
	}

	static uint8_t prevFlips = 0;
	uint8_t flips = elevator_getDirFlips();
	if (flips != prevFlips) {
		prevFlips = flips;
		n = snprintf(msg, sizeof(msg), "[%lu] DIR FLIP #%u (rope wound reversed)\r\n",
		             (unsigned long)HAL_GetTick(), flips);
		uart_print(msg, n);
	}

	elev_state_t st = elevator_getState();
	uint8_t fl = elevator_getFloor();
	uint8_t calls = elevator_getCalls();
	if (st != prevState || fl != prevFloor || calls != prevCalls) {
		prevState = st;
		prevFloor = fl;
		prevCalls = calls;
		// calls=[1-3] 처럼 호출된 층 표시 ('-' = 호출 없음)
		n = snprintf(msg, sizeof(msg), "[%lu] %s %uF calls=[%c%c%c] step=%lu%s\r\n",
		             (unsigned long)HAL_GetTick(), stateName[st], fl,
		             (calls & 1) ? '1' : '-', (calls & 2) ? '2' : '-', (calls & 4) ? '3' : '-',
		             (unsigned long)elevator_getSteps(), errName[elevator_getError()]);
		uart_print(msg, n);
	}
}

// 호출 램프 = 호출 비트마스크, 상태가 바뀌는 순간 효과음, ERROR 동안 경보
static void feedback_task(void)
{
	static elev_state_t prevState = ELEV_HOMING;
	static uint32_t alarmTick = 0;
	uint32_t now = HAL_GetTick();
	uint8_t calls = elevator_getCalls();

	for (uint8_t i = 0; i < PHOTO_FLOOR_NUM; i++) {
		if (calls & (1u << i)) led_on(&ledFloor[i]);
		else led_off(&ledFloor[i]);
	}

	elev_state_t st = elevator_getState();
	if (st != prevState) {
		if (st == ELEV_DOOR_OPEN && (prevState == ELEV_MOVING_UP || prevState == ELEV_MOVING_DOWN)) {
			sound_arrive(); // 문 열림 연장(같은 층 버튼)일 땐 안 울림
		}
		prevState = st;
		if (st == ELEV_ERROR) {
			alarmTick = now - ALARM_PERIOD_MS; // ERROR 들어오자마자 바로 울림
		}
	}

	// ERROR 동안: 경보음 반복 + LED 깜빡임 (경보음 시작 시점에 맞춰서)
	if (st == ELEV_ERROR) {
		if (now - alarmTick >= ALARM_PERIOD_MS) {
			alarmTick = now;
			sound_alarm();
		}
		if (((now - alarmTick) / EMG_BLINK_MS) % 2 == 0) led_on(&ledEmergency);
		else led_off(&ledEmergency);
	}
	else {
		led_off(&ledEmergency);
	}
}

// 평소: 누르는 순간 층 호출
// ERROR(점검 운전): 2층 버튼 누르는 동안 모터 정방향, 3층 버튼 누르는 동안 역방향, 1층 버튼 2초 = 다시 HOMING
static void button_task(void)
{
	static uint8_t pressed[PHOTO_FLOOR_NUM];
	static uint32_t pressTick[PHOTO_FLOOR_NUM];
	static uint8_t longDone = 0;
	uint32_t now = HAL_GetTick();

	for (uint8_t i = 0; i < 2; i++) {
		if (button_getState(&btnEmergency[i]) == ACT_PUSH) {
			elevator_emergencyStop(ELEV_ERR_BUTTON); // 경보음/LED는 feedback_task가 ERROR 동안 처리
		}
	}

	for (uint8_t i = 0; i < PHOTO_FLOOR_NUM; i++) {
		button_state_t ev = button_getState(&btnFloor[i]);
		if (ev == ACT_PUSH) {
			pressed[i] = 1;
			pressTick[i] = now;
			if (i == 0) longDone = 0;
			elevator_request(i + 1); // ERROR 중엔 elevator가 무시함
			sound_button();
		}
		else if (ev == ACT_RELEASE) {
			pressed[i] = 0;
		}
	}

	if (elevator_getState() != ELEV_ERROR) {
		return;
	}

	elevator_jog(pressed[1] ? ELEV_JOG_CW : pressed[2] ? ELEV_JOG_CCW : ELEV_JOG_NONE);

	if (pressed[0] && !longDone && now - pressTick[0] >= REHOME_PRESS_MS) {
		longDone = 1;
		if (elevator_rehome()) {
			sound_power();
		}
	}
}

// 외부 비상 버튼/LED 핀은 CubeMX(.ioc)에 없어서 여기서 설정 (GPIOB 클럭은 MX_GPIO_Init에서 이미 켜짐)
static void emergencyGpio_init(void)
{
	GPIO_InitTypeDef g = {0};

	g.Pin = GPIO_PIN_5;
	g.Mode = GPIO_MODE_INPUT;
	g.Pull = GPIO_NOPULL; // 층 버튼(PC0/1/3)과 같이 외부 풀업 (3.3V - 10k - PB5 - 스위치 - GND)
	HAL_GPIO_Init(GPIOB, &g);

	HAL_GPIO_WritePin(GPIOB, GPIO_PIN_4, GPIO_PIN_RESET);
	g.Pin = GPIO_PIN_4; // PB4는 리셋 직후 JTAG(NJTRST)이지만 SWD만 쓰니 GPIO로 써도 됨
	g.Mode = GPIO_MODE_OUTPUT_PP;
	g.Pull = GPIO_NOPULL;
	g.Speed = GPIO_SPEED_FREQ_LOW;
	HAL_GPIO_Init(GPIOB, &g);
}

int ap_main(void)
{
	button_init(&btnFloor[0], GPIOC, GPIO_PIN_3); // 1층
	button_init(&btnFloor[1], GPIOC, GPIO_PIN_1); // 2층
	button_init(&btnFloor[2], GPIOC, GPIO_PIN_0); // 3층
	emergencyGpio_init();
	button_init(&btnEmergency[0], GPIOC, GPIO_PIN_13); // B1 (CubeMX 설정 없음: 리셋 기본값이 입력)
	button_init(&btnEmergency[1], GPIOB, GPIO_PIN_5);  // 외부 비상 버튼
	led_init(&ledEmergency, GPIOB, GPIO_PIN_4);        // 비상 LED
	led_init(&ledFloor[0], GPIOB, GPIO_PIN_13);   // 1층 램프
	led_init(&ledFloor[1], GPIOB, GPIO_PIN_14);   // 2층 램프
	led_init(&ledFloor[2], GPIOB, GPIO_PIN_15);   // 3층 램프
	sound_init();  // TIM1 CH4 (PA11)
	sound_power(); // 큐에만 넣음, 메인 루프의 sound_task()가 재생
	display_init(&hi2c1); // I2C1 (PB8 SCL, PB9 SDA), 16x2 LCD 0x27

	elevator_init(&elevMotor);
	started = 1;
	protocol_init(&huart2);

	__HAL_TIM_SET_AUTORELOAD(&htim9, STEP_PERIOD_US - 1); // CubeMX의 Period 대신 이 값을 씀
	HAL_TIM_Base_Start_IT(&htim9);

	while (1) {
		button_task();
		elevator_task();
		feedback_task();
		sound_task(); // 큐에 쌓인 음 재생, 블로킹 없음
		display_task(); // 바뀐 줄만 LCD에 씀
		protocol_task(); // PC 패킷 처리 + 도착/비상 이벤트
		if (UART_TEXT_LOG) {
			log_task(); // 꺼져 있으면 photoQue는 차서 버려짐 (로그용이라 상관없음)
		}
	}
	return 0;
}
