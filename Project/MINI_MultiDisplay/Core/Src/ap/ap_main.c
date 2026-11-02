/*
 * ap_main.c
 *
 *  Created on: 2026. 10. 16.
 *      Author: rhoblack
 */

#include "ap_main.h"
#include "service/StopWatch/StopWatch.h"
#include "service/TimeClock/TimeClock.h"
#include "service/Display/Display.h"
#include "service/temp_humid/temp_humid.h"
#include "service/btnEvent/btnEvent.h"
#include "service/distance/distance.h"
#include "service/sound/sound.h"
#include "service/ruler/ruler.h"
#include "../driver/fnd/fnd.h"
#include "../driver/led/led.h"
#include "../driver/lcd/lcd.h"

extern TIM_HandleTypeDef htim3;
extern TIM_HandleTypeDef htim4;
extern I2C_HandleTypeDef hi2c1;

int modeState = CALENDAR_MODE;

void HAL_TIM_PeriodElapsedCallback(TIM_HandleTypeDef *htim)
{
	if (htim->Instance == TIM3) {
		//fnd_show_number();
		Disp_ISR();
	} else if (htim->Instance == TIM4) {
		TimeClock_ISR();
		StopWatch_ISR();
		btnEvent_ISR();
	}
}

void HAL_GPIO_EXTI_Callback(uint16_t GPIO_Pin)
{
	if (GPIO_Pin == GPIO_PIN_6) {
		dist_ISR();
	}
}

void ap_init()
{
	StopWatch_init();
	TimeClock_init();
	Disp_init();
	TH_init();
	dist_init();
	sound_init();
	sound_power();

	btnEvent_init();

	HAL_TIM_Base_Start_IT(&htim3);
	HAL_TIM_Base_Start_IT(&htim4);
}

static void ap_fndStopWatch(void)
{
	stopWatch_t *pStopWatchTime = StopWatch_getTimeData();
	Disp_setStopWatchTime((stopWatchTime_t *)pStopWatchTime);
}

void ap_calendarMode(btn_evt_t evt)
{
	if (evt == EVT_MODE) {
		modeState = TEMPHUMID_MODE;
	}
	ap_fndStopWatch();
	Disp_setMode(modeState);
}

void ap_tempHumidMode(btn_evt_t evt)
{
	if (evt == EVT_MODE) {
		modeState = DISTANCE_MODE;
	}
	ap_fndStopWatch();
	Disp_setMode(modeState);
}

void ap_distanceMode(btn_evt_t evt)
{
	if (evt == EVT_MODE) {
		modeState = STOPWATCH_MODE;
		ruler_reset();
	}
	ruler_task(evt);

	ap_fndStopWatch();
	Disp_setMode(modeState);
}

void ap_stopWatchMode(btn_evt_t evt)
{
	if (evt == EVT_MODE) {
		modeState = CALENDAR_MODE;
	}

	if (evt == EVT_CLEAR && StopWatch_getState() == RUN) {
		sound_error();
	} else if (evt == EVT_RUN_STOP || evt == EVT_CLEAR) {
		sound_button();
	}
	StopWatch_task(evt);

	ap_fndStopWatch();
	Disp_setMode(modeState);

	stopWatch_state_t stopWatchState = StopWatch_getState();
	Disp_setStopWatchState(stopWatchState);
}

static void ap_hourlyChime(void)
{
	static uint8_t chimedHour = 0xFF;
	TimeClock_t *t = TimeClock_getTimeData();

	if (t->min == 0 && t->sec == 0 && t->hour != chimedHour) {
		chimedHour = t->hour;
		sound_alarm();
	}
}

int ap_main(void)
{
	ap_init();
	Lcd_init(&hi2c1);
	while (1) // super loop
	{
		TimeClock_task();
		TH_task();
		btn_evt_t evt = btnEvent_get();
		if (evt == EVT_MODE) {
			sound_button();
		}
		switch (modeState) {
			case CALENDAR_MODE:
				ap_calendarMode(evt);
				break;
			case TEMPHUMID_MODE:
				ap_tempHumidMode(evt);
				break;
			case DISTANCE_MODE:
				ap_distanceMode(evt);
				break;
			case STOPWATCH_MODE:
				ap_stopWatchMode(evt);
				break;
			default:
				break;
		}
		Disp_Lcd();
		ap_hourlyChime();
		sound_task();
	}
	return 0;
}
