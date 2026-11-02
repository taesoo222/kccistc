/*
 * distance.c
 *
 *  Created on: 2026. 10. 29.
 *      Author: kccistc
 */
#include "distance.h"


uint32_t echo_us = 0;
bool start_flag = false;
hcsr04_status_t hcsr04_status;
extern TIM_HandleTypeDef htim10;

void dist_init() {
	HCSR04_init(GPIOC, GPIO_PIN_5, GPIOC, GPIO_PIN_6, &htim10);
}

void dist_task() {
	hcsr04_status = HCSR04_getResult(&echo_us);

//	if (hcsr04_status == HCSR04_OK) {
//		printf("distance %3lu cm\n", echo_us * 17 / 1000);
//	}
}

void dist_request(void) {
	hcsr04_status_t state_start = HCSR04_start();
	if (state_start != HCSR04_ERR_BUSY) {
		start_flag = true;
	}
}

distance_status_t distance_get(uint16_t *distance_cm) {
	if (start_flag != true) {
		return DISTANCE_NOT_READY;
	}
	if (hcsr04_status != HCSR04_OK) {
		return DISTANCE_IN_PROGRESS;
	}
	start_flag = false;
	*distance_cm = echo_us * 17 / 1000;
	return DISTANCE_OK;
}

void dist_ISR() {
	HCSR04_echoISR();
}
