/*
 * TimeClock.c
 *
 *  Created on: 2026. 10. 19.
 *      Author: rhoblack
 */
#include "TimeClock.h"
#include "../../driver/rtc/rtc.h"


static TimeClock_t timeClockData; // 중심 데이터

void TimeClock_init(void)
{
	DS3231_init();
	timeClockData.msec = 0;
}

TimeClock_t *TimeClock_getTimeData(void)
{
	return &timeClockData;
}

void TimeClock_ISR(void)
{
	timeClockData.msec++;
	if (timeClockData.msec > 99) {
		timeClockData.msec = 0;
	}
}

void TimeClock_task(void)
{
	static uint8_t prevSec = 0xFF;

	DS3231_getTime((rtc_t *)&timeClockData); // year ~ sec

	// RTC sec changed -> restart msec from 0 (sync 0.5s blink with RTC)
	if (timeClockData.sec != prevSec) {
		prevSec = timeClockData.sec;
		timeClockData.msec = 0;
	}
}
