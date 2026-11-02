/*
 * btnEvent.h
 *
 *  Created on: 2026. 11. 1.
 *      Author: kccistc
 */

#ifndef SRC_AP_SERVICE_BTNEVENT_BTNEVENT_H_
#define SRC_AP_SERVICE_BTNEVENT_BTNEVENT_H_

typedef enum {
	EVT_NONE,
	EVT_MODE,     // PC0 release
	EVT_RUN_STOP, // PC1 push
	EVT_CLEAR     // PC3 release
} btn_evt_t;

void btnEvent_init(void);
void btnEvent_ISR(void);
btn_evt_t btnEvent_get(void);

#endif /* SRC_AP_SERVICE_BTNEVENT_BTNEVENT_H_ */
