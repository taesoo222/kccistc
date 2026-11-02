/*
 * Display.c
 *
 *  Created on: 2026. 10. 20.
 *      Author: kccistc
 */
#include <stdio.h>
#include "Display.h"
#include "../../../driver/fnd/fnd.h"
#include "../../../driver/lcd/lcd.h"
#include "../../../driver/led/led.h"
#include "../TimeClock/TimeClock.h"
#include "../StopWatch/StopWatch.h"
#include "../temp_humid/temp_humid.h"
#include "../ruler/ruler.h"

enum { STOPWATCH_STOP, STOPWATCH_RUN };

stopWatchTime_t *pStopWatchTime;
timeClockTime_t *pTimeClockTime;
led_t ledTimeClock, ledStopWatch;
led_t ledStopWatchRun, ledStopWatchStop;

static int dispMode = CALENDAR_MODE;
static const char *dayStr[8] = { "???", "SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT" };
static const char *modeStr[4] = { "CAL", "TH", "DIST", "SW" };

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
	if (mode == CALENDAR_MODE) {
		led_on(&ledTimeClock);
		led_off(&ledStopWatch);
	} else if (mode == STOPWATCH_MODE) {
		led_off(&ledTimeClock);
		led_on(&ledStopWatch);
	} else {
		led_off(&ledTimeClock);
		led_off(&ledStopWatch);
	}
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
	char line[24];

	sprintf(line, "%-8s%02d:%02d:%02d", modeStr[dispMode & 0x03], pTimeClockTime->hour, pTimeClockTime->min,
	        pTimeClockTime->sec);
	Lcd_writeStringXY(0, 0, line);

	if (dispMode == CALENDAR_MODE) {
		sprintf(line, " 20%02d.%02d.%02d.%s ", pTimeClockTime->year, pTimeClockTime->month, pTimeClockTime->date,
		        dayStr[pTimeClockTime->day & 0x07]);
	} else if (dispMode == TEMPHUMID_MODE) {
		dht11_data_t th;
		TH_getTempHumid(&th);
		sprintf(line, "T:%2u.%uC  H:%2u%%  ", th.t_int, th.t_dec, th.h_int);
	} else if (dispMode == DISTANCE_MODE) {
		ruler_state_t rs = ruler_getState();
		if (rs == RULER_MEASURING) {
			sprintf(line, "Measure.. %3u cm", ruler_getDistance());
		} else if (rs == RULER_DONE) {
			sprintf(line, "Result    %3u cm", ruler_getDistance());
		} else {
			sprintf(line, "PC1 to measure  ");
		}
	} else {
		sprintf(line, "SW   %02d:%02d:%02d:%02d", pStopWatchTime->hour, pStopWatchTime->min, pStopWatchTime->sec,
		        pStopWatchTime->msec);
	}
	Lcd_writeStringXY(1, 0, line);
}