/*
 * rtc.h
 *
 *  Created on: 2026. 10. 21.
 *      Author: kccistc
 */

#ifndef SRC_DRIVER_RTC_RTC_H_
#define SRC_DRIVER_RTC_RTC_H_

#include "stm32f4xx_hal.h"

typedef struct {
	uint8_t year;  // 0~99 (2000~2099)
	uint8_t month; // 1~12
	uint8_t date;  // 1~31
	uint8_t day;   // 1~7 (1 = SUN)
	uint8_t hour;  // 0~23
	uint8_t min;   // 0~59
	uint8_t sec;   // 0~59
} rtc_t;

void DS3231_init(void);
void DS3231_getTime(rtc_t *pTime);
void DS3231_setTime(rtc_t *pTime);

#endif /* SRC_DRIVER_RTC_RTC_H_ */
