/*
 * Display.h
 *
 *  Created on: 2026. 10. 20.
 *      Author: kccistc
 */

#ifndef SRC_AP_DISPLAY_DISPLAY_H_
#define SRC_AP_DISPLAY_DISPLAY_H_

#include <stdint.h>

enum { CALENDAR_MODE, TEMPHUMID_MODE, DISTANCE_MODE, STOPWATCH_MODE };

typedef struct {
	uint8_t year;
	uint8_t month;
	uint8_t date;
	uint8_t day;
	uint8_t hour;
	uint8_t min;
	uint8_t sec;
	uint8_t msec;
} timeClockTime_t;

typedef struct {
	uint8_t hour;
	uint8_t min;
	uint8_t sec;
	uint8_t msec;
} stopWatchTime_t;

void Disp_init(void);
void Disp_setMode(int mode);
void Disp_setStopWatchState(int state);
void Disp_setStopWatchTime(stopWatchTime_t *pTime);
void Disp_stopWatchTime(void);
void Disp_ISR(void);
void Disp_Lcd(void);

#endif /* SRC_AP_DISPLAY_DISPLAY_H_ */
