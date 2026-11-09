/*
 * elevator.c
 *
 *  Created on: 2026. 11. 5.
 *      Author: kccistc
 */

#include "elevator.h"
#include "../../../driver/photoSensor/photoSensor.h"

// 실이 축에 묶여 있어서 끝까지 풀리면 반대로 감긴다 -> "위"가 CW인지 CCW인지는 고정이 아님.
// 처음엔 CW를 위로 가정하고, 센서가 걸리는 순서를 보고 틀리면 자동으로 뒤집는다.
#define MOTOR_DIR_UP_GUESS STEP_MOTOR_DIR_CW
// 같은 센서에 다시 들어온 걸 "실이 뒤집혀 되돌아옴"으로 인정하는 최소 스텝 (이보다 짧으면 엣지 튐으로 보고 무시)
#define REENTRY_MIN_STEPS 1000

// 실측: 차단판 통과 ~500스텝 -> 절반만 더 가면 위/아래 어느 쪽에서 와도 가운데에 선다
#define STOP_OFFSET_STEPS 250
// 실측: 층 사이 최대 ~6400스텝 -> 넉넉히 1.4배. 이 안에 다음 센서가 안 걸리면 ERROR
#define MAX_SEGMENT_STEPS 9000
// 도착 후 문 열림 유지 시간
#define DOOR_OPEN_MS 3000

#define FLOOR_BIT(f) (1u << ((f) - 1))

typedef enum {
	DIR_STOP,
	DIR_UP,
	DIR_DOWN,
} dir_t;

static stepMotor_t *motor;

static volatile elev_state_t state = ELEV_HOMING;
static volatile elev_err_t error = ELEV_ERR_NONE;
static volatile dir_t dir = DIR_STOP;     // 지금 모터가 도는 방향 (ISR이 봄)
static dir_t lastDir = DIR_UP;            // 마지막 운행 방향 (다음 호출 고를 때 우선)
static volatile stepMotor_dir_t upDir = MOTOR_DIR_UP_GUESS; // 지금 "위"에 해당하는 모터 방향
static volatile uint8_t dirFlips = 0;     // 자동으로 방향을 뒤집은 횟수 (로그용)
static volatile uint8_t refFloor = 0;     // 방향 판별 기준: 칸이 마지막으로 있던 센서 층 (0 = 없음)
static volatile uint8_t curFloor = 0;     // 0 = 모름
static volatile uint8_t targetFloor = 0;
static volatile uint8_t calls = 0;        // 호출 비트마스크 (메인에서 쓰고 ISR은 읽기만)
static volatile uint8_t arrived = 0;      // ISR -> 메인: 방금 도착함
static volatile uint8_t homingUp = 0;     // 전원 ON 때 1층 센서가 가려져 있으면 먼저 위로 빠져나온다
static volatile uint16_t stopCountdown = 0;
static volatile uint16_t segmentSteps = 0; // 마지막 센서 진입 후 스텝 수
static volatile uint32_t totalSteps = 0;
static volatile uint32_t doorStart = 0;   // 도착 시 ISR에서 세팅 (메인이 예전 값으로 문을 바로 닫지 않게)
static volatile elev_jog_t jog = ELEV_JOG_NONE; // 점검 운전 방향 (메인에서 쓰고 ISR이 읽음)
static volatile uint8_t jogging = 0;             // ISR 전용: 점검 운전으로 코일이 켜져 있음

/* ---------- ISR 쪽 (TIM9, EXTI) ---------- */

static stepMotor_dir_t opposite(stepMotor_dir_t d)
{
	return (d == STEP_MOTOR_DIR_CW) ? STEP_MOTOR_DIR_CCW : STEP_MOTOR_DIR_CW;
}

static void stop(elev_state_t next)
{
	dir = DIR_STOP;
	stopCountdown = 0;
	StepMotor_release(motor); // 실측: 코일 해제해도 칸이 안 내려감
	state = next;
}

static void fail(elev_err_t err)
{
	error = err;
	stop(ELEV_ERROR);
}

static void startMove(dir_t d, uint8_t target)
{
	targetFloor = target;
	segmentSteps = 0;
	totalSteps = 0;
	stopCountdown = 0;
	dir = d; // 마지막에 세팅: ISR은 dir을 보고 움직이기 시작한다
}

void elevator_tick(void)
{
	// 점검 운전: 센서/스텝 제한 없이 버튼 누르는 동안만 돈다
	if (state == ELEV_ERROR) {
		if (jog != ELEV_JOG_NONE) {
			StepMotor_stepPhase(motor, (jog == ELEV_JOG_CW) ? STEP_MOTOR_DIR_CW : STEP_MOTOR_DIR_CCW);
			jogging = 1;
		}
		else if (jogging) {
			StepMotor_release(motor); // 코일 끄기는 ISR에서만 (메인과 동시에 핀을 건드리지 않게)
			jogging = 0;
		}
		return;
	}

	if (dir == DIR_STOP) {
		return;
	}

	if (++segmentSteps > MAX_SEGMENT_STEPS) {
		fail(ELEV_ERR_TIMEOUT);
		return;
	}

	StepMotor_stepPhase(motor, (dir == DIR_UP) ? upDir : opposite(upDir));
	totalSteps++;

	if (stopCountdown > 0 && --stopCountdown == 0) {
		if (state == ELEV_HOMING) {
			stop(ELEV_IDLE); // HOMING 완료는 문 안 열고 바로 대기
		}
		else {
			doorStart = HAL_GetTick(); // state보다 먼저: 메인이 DOOR_OPEN을 보는 순간 이미 새 시각
			arrived = 1;
			stop(ELEV_DOOR_OPEN);
		}
	}
}

void elevator_onPhoto(uint8_t floor, uint8_t blocked)
{
	if (dir == DIR_STOP || floor == 0) {
		return; // 멈춰 있을 때 들어온 엣지는 무시
	}

	// HOMING 1단계: 1층 차단판에서 위로 빠져나오면 바로 내려가면서 정상 도착 처리
	if (homingUp) {
		if (floor == 1 && !blocked) {
			homingUp = 0;
			refFloor = 0; // 우리가 방향을 바꿨으니 이번 재진입은 방향 판별에 쓰지 않는다
			startMove(DIR_DOWN, 1);
		}
		return;
	}

	if (!blocked) {
		return; // 빠져나가는 엣지는 로그용, 판단은 들어가는 엣지로만
	}

	// 방향 자동 판별: 직전 센서 층(refFloor)과 비교해서 칸이 실제로 어느 쪽으로 움직였는지 본다
	if (refFloor != 0) {
		int diff = (int)floor - (int)refFloor;

		if (diff > 1 || diff < -1) {
			fail(ELEV_ERR_DIRECTION); // 층 하나를 건너뜀 = 센서를 놓침
			return;
		}
		if (diff == 0 && segmentSteps < REENTRY_MIN_STEPS) {
			return; // 빠져나가자마자 다시 걸린 건 엣지 튐
		}

		// 위층 센서 = 올라가는 중. 같은 센서에 다시 들어옴 = 맨 아래에서 실이 다 풀리고 반대로 감겨 올라오는 중
		dir_t moved = (diff >= 0) ? DIR_UP : DIR_DOWN;
		if (moved != dir) {
			upDir = opposite(upDir); // 실이 반대로 감겨 있음 -> "위" 방향을 뒤집는다
			dirFlips++;
			if (floor == targetFloor) {
				dir = moved; // 목표 층이면 지금 움직이는 그대로 계속 가서 가운데에 선다
			}
			// 아니면 dir은 그대로 -> 모터가 실제로 반대로 돌아서 원래 가려던 쪽으로 간다
		}
	}
	refFloor = floor;

	curFloor = floor; // 지나가는 층도 현재 층으로 갱신
	segmentSteps = 0;

	// 목표 층이거나, 지나가는 층에 호출이 있으면 여기서 선다 (HOMING 중엔 1층만)
	if (floor == targetFloor || (state != ELEV_HOMING && (calls & FLOOR_BIT(floor)))) {
		targetFloor = floor;
		stopCountdown = STOP_OFFSET_STEPS;
	}
}

/* ---------- 메인 루프 쪽 ---------- */

void elevator_init(stepMotor_t *m)
{
	motor = m;
	error = ELEV_ERR_NONE;
	curFloor = 0;
	calls = 0;
	upDir = MOTOR_DIR_UP_GUESS;
	dirFlips = 0;
	refFloor = 0;
	state = ELEV_HOMING;

	// 2·3층 센서에 걸린 채로 켜졌으면 그 층을 기준으로 다음 센서가 위인지 아래인지 보고 방향을 판별
	for (uint8_t f = 2; f <= PHOTO_FLOOR_NUM; f++) {
		if (photoSensor_isBlocked(f)) {
			refFloor = f;
		}
	}

	if (photoSensor_isBlocked(1)) {
		homingUp = 1;            // 1층 차단판 안 어디쯤인지 모름 -> 위로 빠져나왔다가 다시 내려오며 맞춘다
		startMove(DIR_UP, 1);
	}
	else {
		homingUp = 0;
		startMove(DIR_DOWN, 1);
	}
}

void elevator_jog(elev_jog_t j)
{
	jog = (state == ELEV_ERROR) ? j : ELEV_JOG_NONE;
}

bool elevator_rehome(void)
{
	if (state != ELEV_ERROR) {
		return false;
	}
	jog = ELEV_JOG_NONE;
	jogging = 0;
	elevator_init(motor); // 방향 추정도 처음부터 다시 (손으로 돌리는 동안 실이 뒤집혔을 수 있음)
	return true;
}

bool elevator_request(uint8_t floor)
{
	if (floor < 1 || floor > PHOTO_FLOOR_NUM || state == ELEV_ERROR) {
		return false;
	}
	// 멈춰 있는 층의 버튼 = 문 열기 / 문 열림 연장
	if (floor == curFloor && (state == ELEV_IDLE || state == ELEV_DOOR_OPEN)) {
		doorStart = HAL_GetTick();
		state = ELEV_DOOR_OPEN;
		return true;
	}
	calls |= FLOOR_BIT(floor);
	return true;
}

bool elevator_emergencyStop(elev_err_t reason)
{
	bool ok = false;
	__disable_irq(); // TIM9/EXTI가 같은 변수(state, dir)를 바꾸는 중간에 끼지 않게
	if (state != ELEV_ERROR) {
		jog = ELEV_JOG_NONE;
		calls = 0; // 비상 정지 = 등록된 호출 취소 (PC 화면도 같이 지움)
		fail(reason);
		ok = true;
	}
	__enable_irq();
	return ok;
}

// 가장 가까운 호출 층 (dir 방향으로만), 없으면 0
static uint8_t nearestCall(dir_t d)
{
	if (d == DIR_UP) {
		for (int f = curFloor + 1; f <= PHOTO_FLOOR_NUM; f++) {
			if (calls & FLOOR_BIT(f)) return f;
		}
	}
	else {
		for (int f = curFloor - 1; f >= 1; f--) {
			if (calls & FLOOR_BIT(f)) return f;
		}
	}
	return 0;
}

void elevator_task(void)
{
	if (arrived) { // 방금 도착: 그 층 호출 지움 (문 열림 시각은 ISR이 이미 세팅)
		arrived = 0;
		calls &= ~FLOOR_BIT(curFloor);
	}

	if (state == ELEV_DOOR_OPEN && HAL_GetTick() - doorStart >= DOOR_OPEN_MS) {
		state = ELEV_IDLE;
	}

	if (state != ELEV_IDLE) {
		return;
	}

	calls &= ~FLOOR_BIT(curFloor); // 대기 중인 층에 남은 호출은 이미 도착한 것

	// 가던 방향 먼저, 없으면 반대 방향
	dir_t other = (lastDir == DIR_UP) ? DIR_DOWN : DIR_UP;
	dir_t d = lastDir;
	uint8_t next = nearestCall(d);
	if (next == 0) {
		d = other;
		next = nearestCall(d);
	}
	if (next == 0) {
		return;
	}

	lastDir = d;
	state = (d == DIR_UP) ? ELEV_MOVING_UP : ELEV_MOVING_DOWN;
	startMove(d, next);
}

elev_state_t elevator_getState(void)
{
	return state;
}

elev_err_t elevator_getError(void)
{
	return error;
}

uint8_t elevator_getFloor(void)
{
	return curFloor;
}

uint8_t elevator_getDirFlips(void)
{
	return dirFlips;
}

uint8_t elevator_getTarget(void)
{
	return targetFloor;
}

uint8_t elevator_getCalls(void)
{
	return calls;
}

uint32_t elevator_getSteps(void)
{
	return totalSteps;
}
