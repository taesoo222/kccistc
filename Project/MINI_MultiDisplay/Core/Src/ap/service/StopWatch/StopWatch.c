/*
 * StopWatch.c
 *
 *  Created on: 2026. 10. 16.
 *      Author: rhoblack
 */

#include "StopWatch.h"
#include "../../../driver/led/led.h"
#include "../../../driver/fnd/fnd.h"


static void StopWatch_stop(btn_evt_t evt);
static void StopWatch_run(btn_evt_t evt);
static void StopWatch_clear();
static void StopWatch_setState(stopWatch_state_t s);
static void StopWatch_incMSec(void);
static void StopWatch_clearTime(void);

static stopWatch_t stopWatch_time;
static stopWatch_state_t stopWatch_state;


stopWatch_t * StopWatch_getTimeData(void)
{
	return &stopWatch_time;
}

void StopWatch_ISR(void)
{
	if (stopWatch_state == RUN) {
		StopWatch_incMSec();
	}
}

static void StopWatch_incMSec(void)
{
	if (stopWatch_time.msec < 99) {
		stopWatch_time.msec++;
		return;
	}
	stopWatch_time.msec = 0;
	if (stopWatch_time.sec < 59) {
		stopWatch_time.sec++;
		return;
	}
	stopWatch_time.sec = 0;
	if (stopWatch_time.min < 59) {
		stopWatch_time.min++;
		return;
	}
	stopWatch_time.min = 0;
	if (stopWatch_time.hour < 23) {
		stopWatch_time.hour++;
		return;
	}
	stopWatch_time.hour = 0;
}

static void StopWatch_clearTime(void)
{
	stopWatch_time.hour = 0;
	stopWatch_time.min = 0;
	stopWatch_time.sec = 0;
	stopWatch_time.msec = 0;
}

static void StopWatch_setState(stopWatch_state_t s)
{
	stopWatch_state = s;
}

stopWatch_state_t StopWatch_getState(void)
{
	return stopWatch_state;
}

void StopWatch_init(void)
{
	stopWatch_state = STOP;

	stopWatch_time.hour = 0;
	stopWatch_time.min = 0;
	stopWatch_time.sec = 0;
	stopWatch_time.msec = 0;

}

void StopWatch_task(btn_evt_t evt)
{
	switch(stopWatch_state)
	{
	case STOP:
		StopWatch_stop(evt);
		break;
	case RUN:
		StopWatch_run(evt);
		break;
	case CLEAR:
		StopWatch_clear();
		break;
	default:
		StopWatch_stop(evt);
		break;
	}
}

static void StopWatch_stop(btn_evt_t evt)
{
	if (evt == EVT_RUN_STOP) {
		StopWatch_setState(RUN);
	}
	else if (evt == EVT_CLEAR) {
		StopWatch_setState(CLEAR);
	}
}

static void StopWatch_run(btn_evt_t evt)
{
	if (evt == EVT_RUN_STOP) {
		StopWatch_setState(STOP);
	}

}

static void StopWatch_clear()
{
	StopWatch_clearTime();
	StopWatch_setState(STOP);
}

