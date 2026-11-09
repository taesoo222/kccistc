/*
 * display.h
 *
 *  Created on: 2026. 11. 6.
 *      Author: kccistc
 *
 *  16x2 I2C LCD를 실제 엘리베이터 상단 표시기처럼 사용
 *   2줄 높이 큰 화살표(이동 중 흐르는 애니메이션) + 큰 층 숫자
 *  I2C가 느려서 바뀐 칸만 다시 쓴다
 */

#ifndef SRC_AP_SERVICE_DISPLAY_DISPLAY_H_
#define SRC_AP_SERVICE_DISPLAY_DISPLAY_H_

#include "stm32f4xx_hal.h"

void display_init(I2C_HandleTypeDef *hi2c);
void display_task(void); // 메인 루프에서 계속 호출

#endif /* SRC_AP_SERVICE_DISPLAY_DISPLAY_H_ */
