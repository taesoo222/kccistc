/*
 * ap_main.c
 *
 *  Created on: 2026. 10. 16.
 *      Author: kccistc
 */

#include "ap_main.h"
#include "StopWatch/StopWatch.h"
#include "Watch/Watch.h"
#include "../driver/button/button.h"
#include "../driver/led/led.h"
#include "../driver/timer/timer.h"

typedef enum {
	MODE_STOPWATCH,
	MODE_WATCH
} ap_mode_t;

static ap_mode_t mode = MODE_STOPWATCH;

static button_t btn_mode;

static void ap_tick_100ms(void)
{
	StopWatch_tick_100ms();
	Watch_tick_100ms();
}

static void ap_changeMode(void)
{
	if (mode == MODE_STOPWATCH) {
		StopWatch_exit();
		Watch_enter();
		mode = MODE_WATCH;
	} else {
		Watch_exit();
		StopWatch_enter();
		mode = MODE_STOPWATCH;
	}
}

int ap_main(void)
{
	StopWatch_init();
	Watch_init();
	StopWatch_enter();

	button_init(&btn_mode, GPIOC, GPIO_PIN_0);

	timer_reg(ap_tick_100ms, 100);
	timer_start();

	while (1) {
		if (button_getState(&btn_mode) == ACT_PUSH) {
			ap_changeMode();
		}

		if (mode == MODE_STOPWATCH) {
			StopWatch_task();
		} else {
			Watch_task();
		}
	}
	return 0;
}
