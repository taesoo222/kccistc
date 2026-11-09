/*
 * protocol.c
 *
 *  Created on: 2026. 11. 7.
 *      Author: kccistc
 */

#include "protocol.h"
#include "../elevator/elevator.h"
#include "../../../common/queue/que_buffer.h"

#define PKT_START   0xAA
#define PKT_MAX_LEN 16   // LEN 최대 (PC 쪽 PKT_MAX_LEN과 같게)
#define RSP_OFFSET  0x80
#define RSP_OK      0x00
#define RSP_ERR     0x01

#define CMD_CALL      0x50
#define CMD_STATUS    0x51
#define CMD_RELEASE   0x41
#define CMD_EMG_STOP  0x43
#define EVT_EMERGENCY 0x40
#define EVT_ARRIVED   0x42

// PC 쪽 protocol.py의 ST_*, DIR_* 번호와 같아야 함
enum { PC_ST_INIT, PC_ST_IDLE, PC_ST_MOVING, PC_ST_EMERGENCY };
enum { PC_DIR_STOP, PC_DIR_UP, PC_DIR_DOWN };

typedef enum { WAIT_START, WAIT_LEN, WAIT_DATA, WAIT_CHK } parse_state_t;

static UART_HandleTypeDef *uart;
static uint8_t rxByte;
static uint8_t rxStorage[64];
static que_buf_t rxQue = {.buf = rxStorage, .elem_size = 1, .capacity = sizeof(rxStorage)};

static parse_state_t pState = WAIT_START;
static uint8_t pLen;
static uint8_t pIdx;
static uint8_t pBuf[PKT_MAX_LEN];

/* ---------- 수신 (ISR) ---------- */

void protocol_init(UART_HandleTypeDef *huart)
{
	uart = huart;
	HAL_UART_Receive_IT(uart, &rxByte, 1);
}

void protocol_onRxCplt(void)
{
	que_put(&rxQue, &rxByte); // 가득 차면 버림 -> 체크섬이 틀려서 그 패킷만 무시됨
	HAL_UART_Receive_IT(uart, &rxByte, 1);
}

void protocol_onRxError(void)
{
	HAL_UART_Receive_IT(uart, &rxByte, 1);
}

/* ---------- 송신 ---------- */

static void send(uint8_t cmd, const uint8_t *payload, uint8_t n)
{
	uint8_t pkt[PKT_MAX_LEN + 3];
	uint8_t len = n + 1;
	uint8_t cksum = len + cmd;

	pkt[0] = PKT_START;
	pkt[1] = len;
	pkt[2] = cmd;
	for (uint8_t i = 0; i < n; i++) {
		pkt[3 + i] = payload[i];
		cksum += payload[i];
	}
	pkt[3 + n] = cksum;
	HAL_UART_Transmit(uart, pkt, n + 4, 10); // 최대 8바이트 페이로드 ~1ms
}

static void reply(uint8_t cmd, bool ok)
{
	uint8_t r = ok ? RSP_OK : RSP_ERR;
	send(cmd + RSP_OFFSET, &r, 1);
}

/* ---------- 펌웨어 상태 -> PC 번호 ---------- */

static uint8_t pcState(elev_state_t st)
{
	switch (st) {
	case ELEV_HOMING:      return PC_ST_INIT;
	case ELEV_MOVING_UP:
	case ELEV_MOVING_DOWN: return PC_ST_MOVING;
	case ELEV_ERROR:       return PC_ST_EMERGENCY;
	default:               return PC_ST_IDLE; // IDLE, DOOR_OPEN (PC 화면엔 문 상태가 없음)
	}
}

static uint8_t pcDir(elev_state_t st)
{
	if (st == ELEV_MOVING_UP) return PC_DIR_UP;
	if (st == ELEV_MOVING_DOWN || st == ELEV_HOMING) return PC_DIR_DOWN;
	return PC_DIR_STOP;
}

static uint8_t pcReason(elev_err_t err)
{
	switch (err) {
	case ELEV_ERR_BUTTON:    return 1;
	case ELEV_ERR_TIMEOUT:   return 2;
	case ELEV_ERR_REMOTE:    return 3;
	case ELEV_ERR_DIRECTION: return 5;
	default:                 return 0;
	}
}

/* ---------- 패킷 처리 ---------- */

static void handle(uint8_t cmd, const uint8_t *pl, uint8_t n)
{
	switch (cmd) {
	case CMD_CALL:
		reply(cmd, n >= 1 && elevator_request(pl[0]));
		break;
	case CMD_STATUS: {
		elev_state_t st = elevator_getState();
		uint8_t s[4] = {elevator_getFloor(), pcState(st), pcDir(st), elevator_getTarget()};
		send(cmd + RSP_OFFSET, s, sizeof(s));
		break;
	}
	case CMD_RELEASE:
		reply(cmd, elevator_rehome());
		break;
	case CMD_EMG_STOP:
		reply(cmd, elevator_emergencyStop(ELEV_ERR_REMOTE));
		break;
	default:
		break; // 모르는 명령은 무시
	}
}

// PC 쪽 PacketParser.feed()와 같은 상태머신
static void parse(uint8_t b)
{
	switch (pState) {
	case WAIT_START:
		if (b == PKT_START) pState = WAIT_LEN;
		break;
	case WAIT_LEN:
		if (b == 0 || b >= PKT_MAX_LEN) {
			pState = WAIT_START;
		}
		else {
			pLen = b;
			pIdx = 0;
			pState = WAIT_DATA;
		}
		break;
	case WAIT_DATA:
		pBuf[pIdx++] = b;
		if (pIdx >= pLen) pState = WAIT_CHK;
		break;
	case WAIT_CHK: {
		pState = WAIT_START;
		uint8_t cksum = pLen;
		for (uint8_t i = 0; i < pLen; i++) cksum += pBuf[i];
		if (cksum == b) handle(pBuf[0], &pBuf[1], pLen - 1);
		break;
	}
	}
}

// 상태가 바뀌는 순간 PC에 이벤트
static void event_task(void)
{
	static elev_state_t prev = ELEV_HOMING;
	elev_state_t st = elevator_getState();
	if (st == prev) {
		return;
	}
	if (st == ELEV_ERROR) {
		uint8_t e[3] = {elevator_getFloor(), pcDir(prev), pcReason(elevator_getError())};
		send(EVT_EMERGENCY, e, sizeof(e));
	}
	else if ((st == ELEV_DOOR_OPEN && (prev == ELEV_MOVING_UP || prev == ELEV_MOVING_DOWN))
	         || (st == ELEV_IDLE && prev == ELEV_HOMING)) { // HOMING 완료(비상 해제 후 복귀 포함)도 도착
		uint8_t f = elevator_getFloor();
		send(EVT_ARRIVED, &f, 1);
	}
	prev = st;
}

void protocol_task(void)
{
	uint8_t b;
	while (que_get(&rxQue, &b)) {
		parse(b);
	}
	event_task();
}
