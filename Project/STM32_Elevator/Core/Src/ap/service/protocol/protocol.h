/*
 * protocol.h
 *
 *  Created on: 2026. 11. 7.
 *      Author: kccistc
 *
 *  PC 감시 프로그램(elevator_monitor)과 UART 패킷 통신
 *   패킷 : [0xAA] [LEN] [CMD] [PAYLOAD ...] [CKSUM]
 *          LEN = 1(CMD) + payload 길이, CKSUM = (LEN + CMD + PAYLOAD...) & 0xFF, 응답 CMD = 요청 CMD + 0x80
 *
 *   요청 (PC -> 보드)             응답 (보드 -> PC)
 *    0x50 층 호출 [층 1~3]   ->   0xD0 [0=OK / 1=ERR]
 *    0x51 상태 요청           ->   0xD1 [현재층][상태][방향][목표층]
 *    0x41 비상 해제           ->   0xC1 [OK/ERR]   (해제 = 1층으로 HOMING)
 *    0x43 PC 비상 정지        ->   0xC3 [OK/ERR]
 *   이벤트 (보드 -> PC)
 *    0x40 비상 정지 발생 [층][방향][원인 1=B1 버튼 2=시간 초과 3=PC 5=센서 건너뜀]
 *    0x42 도착          [층]
 */

#ifndef SRC_AP_SERVICE_PROTOCOL_PROTOCOL_H_
#define SRC_AP_SERVICE_PROTOCOL_PROTOCOL_H_

#include "stm32f4xx_hal.h"

void protocol_init(UART_HandleTypeDef *huart); // 1바이트 수신 인터럽트 시작
void protocol_onRxCplt(void);  // HAL_UART_RxCpltCallback에서 호출 (ISR)
void protocol_onRxError(void); // HAL_UART_ErrorCallback에서 호출 (오버런 등으로 수신이 멈추면 다시 시작)
void protocol_task(void);      // 메인 루프: 받은 패킷 처리 + 도착/비상 이벤트 전송

#endif /* SRC_AP_SERVICE_PROTOCOL_PROTOCOL_H_ */
