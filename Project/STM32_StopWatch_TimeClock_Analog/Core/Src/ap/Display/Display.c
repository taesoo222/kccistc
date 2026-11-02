/*
 * Display.c
 *
 *  Created on: 2026. 10. 20.
 *      Author: kccistc
 */
#include <stdio.h>
#include "Display.h"
#include "../../driver/fnd/fnd.h"
#include "../../driver/lcd/lcd.h"
#include "../../driver/led/led.h"
#include "../TimeClock/TimeClock.h"
#include "../StopWatch/StopWatch.h"
#include "../AnalogClock/AnalogClock.h"

enum { TIMECLOCK_MODE, STOPWATCH_MODE };
enum { STOPWATCH_STOP, STOPWATCH_RUN };

stopWatchTime_t *pStopWatchTime;
timeClockTime_t *pTimeClockTime;
led_t ledTimeClock, ledStopWatch;
led_t ledStopWatchRun, ledStopWatchStop;

static int dispMode = TIMECLOCK_MODE;
static const char *dayStr[8] = { "???", "SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT" };

void Disp_init(void)
{
	led_init(&ledTimeClock, GPIOB, GPIO_PIN_15);
	led_init(&ledStopWatch, GPIOB, GPIO_PIN_14);
	led_init(&ledStopWatchStop, GPIOB, GPIO_PIN_13);
	led_init(&ledStopWatchRun, GPIOC, GPIO_PIN_4);

	pTimeClockTime = (timeClockTime_t *)TimeClock_getTimeData();
	pStopWatchTime = (stopWatchTime_t *)StopWatch_getTimeData();
}

void Disp_setMode(int mode)
{
	dispMode = mode;
	if (mode == TIMECLOCK_MODE) {
		led_on(&ledTimeClock);
		led_off(&ledStopWatch);
	} else {
		led_off(&ledTimeClock);
		led_on(&ledStopWatch);
	}
}

void Disp_setTimeClockTime(timeClockTime_t *pTime)
{
	pTimeClockTime = pTime;
	Disp_timeClockTime();
}

void Disp_setStopWatchTime(stopWatchTime_t *pTime)
{
	pStopWatchTime = pTime;
	Disp_stopWatchTime();
}

void Disp_stopWatchTime(void)
{
	uint16_t num;
	num = ((pStopWatchTime->min % 10) * 1000) + (pStopWatchTime->sec * 10) + (pStopWatchTime->msec / 10 % 10);
	fnd_set_num(num);

	if (pStopWatchTime->msec < 50) {
		fnd_set_dp(FND_DIGIT_3, FND_DP_ON);
	} else {
		fnd_set_dp(FND_DIGIT_3, FND_DP_OFF);
	}
	fnd_set_dp(FND_DIGIT_1, FND_DP_ON);
	fnd_set_dp(FND_DIGIT_2, FND_DP_OFF);

	AnalogClock_setTime(pStopWatchTime->hour, pStopWatchTime->min, pStopWatchTime->sec);
}

void Disp_timeClockTime(void)
{
	uint16_t num;
	num = (pTimeClockTime->min * 100) + pTimeClockTime->sec;
	fnd_set_num(num);

	if (pTimeClockTime->msec < 50) {
		fnd_set_dp(FND_DIGIT_2, FND_DP_ON);
	} else {
		fnd_set_dp(FND_DIGIT_2, FND_DP_OFF);
	}
	fnd_set_dp(FND_DIGIT_1, FND_DP_OFF);
	fnd_set_dp(FND_DIGIT_3, FND_DP_OFF);

	AnalogClock_setTime(pTimeClockTime->hour, pTimeClockTime->min, pTimeClockTime->sec);
}

void Disp_setStopWatchState(int state)
{
	if (state == STOPWATCH_RUN) {
		led_on(&ledStopWatchRun);
		led_off(&ledStopWatchStop);
	} else {
		led_off(&ledStopWatchRun);
		led_on(&ledStopWatchStop);
	}
}

void Disp_ISR(void)
{
	fnd_show_number();
}

void Disp_Lcd(void)
{
	char line[24]; // 16 chars + margin for 3-digit garbage values

	sprintf(line, "TIME    %02d:%02d:%02d", pTimeClockTime->hour, pTimeClockTime->min, pTimeClockTime->sec);
	Lcd_writeStringXY(0, 0, line);

	if (dispMode == TIMECLOCK_MODE) {
		sprintf(line, " 20%02d.%02d.%02d.%s ", pTimeClockTime->year, pTimeClockTime->month, pTimeClockTime->date,
		        dayStr[pTimeClockTime->day & 0x07]);
	} else {
		sprintf(line, "SW   %02d:%02d:%02d:%02d", pStopWatchTime->hour, pStopWatchTime->min, pStopWatchTime->sec,
		        pStopWatchTime->msec);
	}
	Lcd_writeStringXY(1, 0, line);
}