/*
 * ruler.c
 *
 *  Created on: 2026. 11. 1.
 *      Author: kccistc
 */

#include "ruler.h"
#include "../distance/distance.h"
#include "../sound/sound.h"

#define MEASURE_MS	1000
#define SAMPLE_MS	100

static ruler_state_t ruler_state = RULER_IDLE;
static uint16_t ruler_distance;

static uint32_t startTime;
static uint32_t prevSample;
static uint32_t sum;
static uint16_t count;

static void ruler_start(void)
{
	sum = 0;
	count = 0;
	ruler_distance = 0;
	startTime = HAL_GetTick();
	prevSample = startTime;
	dist_request();

	ruler_state = RULER_MEASURING;
	sound_button();
}

static void ruler_finish(void)
{
	if (count == 0) {
		ruler_state = RULER_IDLE;
		sound_error();
		return;
	}
	ruler_distance = sum / count;
	ruler_state = RULER_DONE;
	sound_alarm();
}

static void ruler_measure(void)
{
	uint16_t cm;

	if (HAL_GetTick() - prevSample >= SAMPLE_MS) {
		prevSample = HAL_GetTick();
		dist_request();
	}
	dist_task();
	if (distance_get(&cm) == DISTANCE_OK) {
		ruler_distance = cm;
		sum += cm;
		count++;
	}

	if (HAL_GetTick() - startTime >= MEASURE_MS) {
		ruler_finish();
	}
}

void ruler_task(btn_evt_t evt)
{
	switch (ruler_state)
	{
	case RULER_IDLE:
	case RULER_DONE:
		if (evt == EVT_RUN_STOP) {
			ruler_start();
		}
		break;
	case RULER_MEASURING:
		ruler_measure();
		break;
	default:
		ruler_state = RULER_IDLE;
		break;
	}
}

void ruler_reset(void)
{
	ruler_state = RULER_IDLE;
}

ruler_state_t ruler_getState(void)
{
	return ruler_state;
}

uint16_t ruler_getDistance(void)
{
	return ruler_distance;
}
