/*
 * StopWatch.h
 *
 *  Created on: 2026. 10. 16.
 *      Author: kccistc
 */

#ifndef SRC_AP_STOPWATCH_STOPWATCH_H_
#define SRC_AP_STOPWATCH_STOPWATCH_H_
#include "stm32f4xx_hal.h"

void StopWatch_init(void);
void StopWatch_enter(void);
void StopWatch_exit(void);
void StopWatch_task(void);
void StopWatch_tick_100ms(void);

#endif /* SRC_AP_STOPWATCH_STOPWATCH_H_ */
