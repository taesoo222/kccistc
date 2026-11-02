#include "StopWatch.h"
#include "../../driver/button/button.h"
#include "../../driver/led/led.h"
#include "../../driver/fnd/fnd.h"
#include <stdint.h>

typedef enum {
	STOP,
	RUN,
	CLEAR
} stopWatch_t;

static void StopWatch_stop(void);
static void StopWatch_run(void);
static void StopWatch_clear(void);
static void StopWatch_setState(stopWatch_t s);
static void StopWatch_updateLed(void);
static void StopWatch_clearCounter(void);
static uint16_t StopWatch_getCounter(void);

static volatile stopWatch_t stopWatch_state;
static volatile uint16_t counter;

static led_t led_run;
static led_t led_stop;
static led_t led_mode;

static button_t btn_run_stop;
static button_t btn_clear;

static void StopWatch_updateLed(void)
{
	if (stopWatch_state == RUN) {
		led_on(&led_run);
		led_off(&led_stop);
	} else {
		led_off(&led_run);
		led_on(&led_stop);
	}
}

static void StopWatch_setState(stopWatch_t s)
{
	stopWatch_state = s;
	StopWatch_updateLed();
}

static void StopWatch_clearCounter(void)
{
	counter = 0;
}

static uint16_t StopWatch_getCounter(void)
{
	return counter;
}

void StopWatch_init(void)
{
	stopWatch_state = STOP;
	counter = 0;

	led_init(&led_stop, GPIOB, GPIO_PIN_13);
	led_init(&led_run, GPIOC, GPIO_PIN_4);
	led_init(&led_mode, GPIOB, GPIO_PIN_14);

	button_init(&btn_run_stop, GPIOC, GPIO_PIN_1);
	button_init(&btn_clear, GPIOC, GPIO_PIN_3);
}

void StopWatch_enter(void)
{
	StopWatch_updateLed();
	led_on(&led_mode);
}

void StopWatch_exit(void)
{
	led_off(&led_run);
	led_off(&led_stop);
	led_off(&led_mode);
}

void StopWatch_tick_100ms(void)
{
	if (stopWatch_state != RUN) {
		return;
	}

	if (counter >= 9999) {
		counter = 0;
	} else {
		counter++;
	}
}

void StopWatch_task(void)
{
	switch (stopWatch_state) {
		case STOP:
			StopWatch_stop();
			break;
		case RUN:
			StopWatch_run();
			break;
		case CLEAR:
			StopWatch_clear();
			break;
		default:
			StopWatch_setState(STOP);
			break;
	}
}

static void StopWatch_stop(void)
{
	if (button_getState(&btn_run_stop) == ACT_PUSH) {
		StopWatch_setState(RUN);
	} else if (button_getState(&btn_clear) == ACT_RELEASE) {
		StopWatch_setState(CLEAR);
	}

	fnd_set_num(StopWatch_getCounter());
}

static void StopWatch_run(void)
{
	if (button_getState(&btn_run_stop) == ACT_PUSH) {
		StopWatch_setState(STOP);
	}

	fnd_set_num(StopWatch_getCounter());
}

static void StopWatch_clear(void)
{
	StopWatch_clearCounter();
	fnd_set_num(StopWatch_getCounter());
	StopWatch_setState(STOP);
}