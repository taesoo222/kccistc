/*
 * btnEvent.c
 *
 *  Created on: 2026. 11. 1.
 *      Author: kccistc
 */

#include "btnEvent.h"
#include "../../../driver/button/button.h"
#include "../../../common/queue/que_buffer.h"

#define EVT_QUE_SIZE	8

static button_t btn_mode;
static button_t btn_run_stop;
static button_t btn_clear;

static btn_evt_t evt_storage[EVT_QUE_SIZE];
static que_buf_t evt_que;

static void btnEvent_put(btn_evt_t evt)
{
	que_put(&evt_que, &evt);
}

void btnEvent_init(void)
{
	button_init(&btn_mode, GPIOC, GPIO_PIN_0);
	button_init(&btn_run_stop, GPIOC, GPIO_PIN_1);
	button_init(&btn_clear, GPIOC, GPIO_PIN_3);

	que_buf_init(&evt_que, evt_storage, sizeof(btn_evt_t), EVT_QUE_SIZE);
}

void btnEvent_ISR(void)
{
	if (button_getState(&btn_mode) == ACT_RELEASE) {
		btnEvent_put(EVT_MODE);
	}
	if (button_getState(&btn_run_stop) == ACT_PUSH) {
		btnEvent_put(EVT_RUN_STOP);
	}
	if (button_getState(&btn_clear) == ACT_RELEASE) {
		btnEvent_put(EVT_CLEAR);
	}
}

btn_evt_t btnEvent_get(void)
{
	btn_evt_t evt;

	if (!que_get(&evt_que, &evt)) {
		return EVT_NONE;
	}
	return evt;
}
