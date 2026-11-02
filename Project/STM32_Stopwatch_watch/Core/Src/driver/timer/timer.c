/*
 * timer.c
 *
 *  Created on: 2026. 10. 17.
 *      Author: xotng
 */
#include <stdint.h>
#include "timer.h"
#include "../fnd/fnd.h"

#define TIMER_MAX 4

typedef struct {
	timer_cb_t cb;
	uint16_t period_ms;
	uint16_t count_ms;
} timer_slot_t;

extern TIM_HandleTypeDef htim3;

static timer_slot_t timer_slot[TIMER_MAX];
static uint8_t timer_count = 0;

int timer_reg(timer_cb_t cb, uint16_t period_ms)
{
	timer_slot[timer_count].cb = cb;
	timer_slot[timer_count].period_ms = period_ms;
	timer_slot[timer_count].count_ms = 0;
	timer_count++;

	return 0;
}

void timer_start(void)
{
	HAL_TIM_Base_Start_IT(&htim3);
}

void HAL_TIM_PeriodElapsedCallback(TIM_HandleTypeDef *htim)
{
	if (htim->Instance == TIM3) {
		fnd_show_number();

		for (int i = 0; i < timer_count; i++) {
			timer_slot[i].count_ms++;
			if (timer_slot[i].count_ms >= timer_slot[i].period_ms) {
				timer_slot[i].count_ms = 0;
				timer_slot[i].cb();
			}
		}
	}
}
