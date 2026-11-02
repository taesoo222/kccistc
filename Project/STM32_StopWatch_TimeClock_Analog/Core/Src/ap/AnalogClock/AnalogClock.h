/*
 * AnalogClock.h
 *
 *  Created on: 2026. 10. 24.
 *      Author: kccistc
 */

#ifndef SRC_AP_ANALOGCLOCK_ANALOGCLOCK_H_
#define SRC_AP_ANALOGCLOCK_ANALOGCLOCK_H_

#include <stdint.h>

void AnalogClock_init(void);
void AnalogClock_setTime(uint8_t hour, uint8_t min, uint8_t sec);
void AnalogClock_ISR(void);

#endif /* SRC_AP_ANALOGCLOCK_ANALOGCLOCK_H_ */
