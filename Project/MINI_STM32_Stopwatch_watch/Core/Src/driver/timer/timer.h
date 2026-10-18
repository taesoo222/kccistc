/*
 * timer.h
 *
 *  Created on: 2026. 10. 17.
 *      Author: xotng
 */

#ifndef SRC_DRIVER_TIMER_TIMER_H_
#define SRC_DRIVER_TIMER_TIMER_H_

#include "stm32f4xx_hal.h"

typedef void (*timer_cb_t)(void);

int timer_reg(timer_cb_t cb, uint16_t period_ms);
void timer_start(void);

#endif /* SRC_DRIVER_TIMER_TIMER_H_ */
