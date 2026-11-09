/*
 * elevator.h
 *
 *  Created on: 2026. 11. 5.
 *      Author: kccistc
 *
 *  - HOMING: 전원 ON 때 1층 찾기
 *  - 호출 기억: 버튼은 언제 눌러도 저장 (비트마스크), 도착하면 지워짐
 *  - 운행 순서: 가던 방향에 남은 호출 먼저, 없으면 방향 전환
 *  - 지나가는 층에 호출이 있으면 거기서 선다
 *  - 도착하면 DOOR_OPEN 상태로 DOOR_OPEN_MS 대기 (같은 층 버튼 = 문 열림 연장)
 *  - 위치는 포토 센서(EXTI)로만 판단, 스텝 수는 타임아웃/로그용
 *  - 모터의 "위" 방향은 센서가 걸리는 순서로 자동 판별 (실이 반대로 감겨도 스스로 맞춤)
 *  - 층 센서에 들어가면 STOP_OFFSET_STEPS 더 가서 정지 -> 차단판 가운데에 선다
 */

#ifndef SRC_AP_SERVICE_ELEVATOR_ELEVATOR_H_
#define SRC_AP_SERVICE_ELEVATOR_ELEVATOR_H_

#include <stdbool.h>
#include "../../../driver/StepMotor/StepMotor.h"

typedef enum {
	ELEV_HOMING,
	ELEV_IDLE,       // 문 닫힘, 호출 없음
	ELEV_MOVING_UP,
	ELEV_MOVING_DOWN,
	ELEV_DOOR_OPEN,  // 도착 후 문 열림 대기
	ELEV_ERROR,
} elev_state_t;

typedef enum {
	ELEV_ERR_NONE,
	ELEV_ERR_TIMEOUT,   // 정해진 스텝 안에 다음 센서가 안 걸림
	ELEV_ERR_DIRECTION, // 층 센서를 하나 건너뜀 (센서를 놓침)
} elev_err_t;

typedef enum {
	ELEV_JOG_NONE,
	ELEV_JOG_CW,   // 모터 정방향 (실이 어느 쪽으로 감겼는지 모르니 위/아래가 아니라 모터 기준)
	ELEV_JOG_CCW,  // 모터 역방향
} elev_jog_t;

void elevator_init(stepMotor_t *motor);

// 점검 운전 (ERROR 상태에서만 동작): 누르고 있는 동안 jog 방향으로 돌고, 떼면(NONE) 정지
void elevator_jog(elev_jog_t jog);
bool elevator_rehome(void); // ERROR에서 다시 HOMING 시작, ERROR가 아니면 false
void elevator_request(uint8_t floor); // 층 버튼 (언제든 호출 가능)
void elevator_task(void);             // 메인 루프에서 계속 호출 (문 시간, 다음 호출 선택)

void elevator_tick(void);                              // TIM9 ISR에서 호출 (1스텝 주기)
void elevator_onPhoto(uint8_t floor, uint8_t blocked); // EXTI ISR에서 호출

elev_state_t elevator_getState(void);
elev_err_t elevator_getError(void);
uint8_t elevator_getFloor(void);   // 0 = 아직 모름 (HOMING 중)
uint8_t elevator_getTarget(void);  // 이동 중 목표 층
uint8_t elevator_getDirFlips(void); // 실이 반대로 감긴 걸 감지해 모터 방향을 뒤집은 횟수
uint8_t elevator_getCalls(void);   // bit0 = 1층 호출 ... bit2 = 3층 호출
uint32_t elevator_getSteps(void);  // 이번 이동 시작 후 스텝 수

#endif /* SRC_AP_SERVICE_ELEVATOR_ELEVATOR_H_ */
