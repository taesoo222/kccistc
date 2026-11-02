/*
 * ap_main.c
 *
 *  Created on: 2026. 10. 16.
 *      Author: rhoblack
 */

#include "ap_main.h"
#include "StopWatch/StopWatch.h"
#include "TimeClock/TimeClock.h"
#include "Display/Display.h"
#include "AnalogClock/AnalogClock.h"
#include "../driver/fnd/fnd.h"
#include "../driver/button/button.h"
#include "../driver/led/led.h"
#include "../driver/lcd/lcd.h"

enum { TIME_CLOCK_MODE, STOP_WATCH_MODE };

extern TIM_HandleTypeDef htim3;
extern TIM_HandleTypeDef htim4;
extern TIM_HandleTypeDef htim9;

button_t btnMode;

int modeState = TIME_CLOCK_MODE;

void HAL_TIM_PeriodElapsedCallback(TIM_HandleTypeDef *htim)
{
	if (htim->Instance == TIM3) {
		//fnd_show_number();
		Disp_ISR();
	} else if (htim->Instance == TIM4) {
		TimeClock_ISR();
		StopWatch_ISR();
	} else if (htim->Instance == TIM9) {
		AnalogClock_ISR();
	}
}

void ap_init()
{
	StopWatch_init();
	TimeClock_init();
	Disp_init();
	AnalogClock_init();

	button_init(&btnMode, GPIOC, GPIO_PIN_0);

	HAL_TIM_Base_Start_IT(&htim3);
	HAL_TIM_Base_Start_IT(&htim4);
	HAL_TIM_Base_Start_IT(&htim9);
}

void ap_timeClockMode(void)
{
	if (button_getState(&btnMode) == ACT_RELEASE) {
		modeState = STOP_WATCH_MODE;
	}
	TimeClock_t *pTimeClockTime = TimeClock_getTimeData();
	Disp_setTimeClockTime((timeClockTime_t *)pTimeClockTime);
	Disp_setMode(modeState);
}

void ap_stopWatchMode(void)
{
	if (button_getState(&btnMode) == ACT_RELEASE) {
		modeState = TIME_CLOCK_MODE;
	}
	StopWatch_task();

	stopWatch_t *pStopWatchTime = StopWatch_getTimeData();
	Disp_setStopWatchTime((stopWatchTime_t *)pStopWatchTime);
	Disp_setMode(modeState);

	stopWatch_state_t stopWatchState = StopWatch_getState();
	Disp_setStopWatchState(stopWatchState);
}

int ap_main(void)
{
	ap_init();
	Lcd_init();
	while (1) // super loop
	{
		TimeClock_task(); // read RTC in both modes
		switch (modeState) {
			case TIME_CLOCK_MODE:
				ap_timeClockMode();
				break;
			case STOP_WATCH_MODE:
				ap_stopWatchMode();
				break;
			default:
				break;
		}
		Disp_Lcd();
	}
	return 0;
}
