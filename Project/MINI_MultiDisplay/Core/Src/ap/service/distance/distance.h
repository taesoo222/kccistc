/*
 * distance.h
 *
 *  Created on: 2026. 10. 29.
 *      Author: kccistc
 */

#ifndef SRC_AP_SERVICE_DISTANCE_DISTANCE_H_
#define SRC_AP_SERVICE_DISTANCE_DISTANCE_H_

#include "../../../driver/HCSR04/HCSR04.h"
#include "../../../driver/button/button.h"
#include <stdbool.h>
#include <stdio.h>

typedef enum {
	DISTANCE_OK, DISTANCE_NOT_READY, DISTANCE_IN_PROGRESS
} distance_status_t;


void dist_init();
void dist_task();
void dist_request(void);
distance_status_t distance_get(uint16_t *distance_cm);
void dist_ISR();

#endif /* SRC_AP_SERVICE_DISTANCE_DISTANCE_H_ */
