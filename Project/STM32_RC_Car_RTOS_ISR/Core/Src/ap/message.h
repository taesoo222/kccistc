#ifndef SRC_AP_MESSAGE_H_
#define SRC_AP_MESSAGE_H_

#include "cmsis_os.h"

typedef enum { BTN_NO, BTN_RUN_STOP, BTN_LEFT, BTN_RIGHT, BTN_AUTO } btn_status_t;
typedef enum {
	COMM_NO, COMM_RUN, COMM_STOP, COMM_SPEED,
	COMM_LEFT, COMM_RIGHT, COMM_BACK, COMM_AUTO, COMM_MANUAL
} comm_status_t;
typedef struct {
	comm_status_t status;
	int speed;
} comm_data_t;

extern osMessageQId btnQueHandle;
extern osMessageQId CommQueueHandle;
extern osMutexId lcdMutexHandle;
extern osMutexId uartMutexHandle;

#endif
