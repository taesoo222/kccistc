/*
 * ruler.h
 *
 *  Created on: 2026. 11. 1.
 *      Author: kccistc
 */

#ifndef SRC_AP_SERVICE_RULER_RULER_H_
#define SRC_AP_SERVICE_RULER_RULER_H_

#include <stdint.h>
#include "../btnEvent/btnEvent.h"

typedef enum { RULER_IDLE, RULER_MEASURING, RULER_DONE } ruler_state_t;

void ruler_task(btn_evt_t evt);
void ruler_reset(void);
ruler_state_t ruler_getState(void);
uint16_t ruler_getDistance(void);

#endif /* SRC_AP_SERVICE_RULER_RULER_H_ */
