#ifndef SRC_AP_TASK_ULTRASONIC_TASK_ULTRASONIC_TASK_H_
#define SRC_AP_TASK_ULTRASONIC_TASK_ULTRASONIC_TASK_H_

#include <stdint.h>

#define SENSOR_COUNT	3
enum { SENSOR_L, SENSOR_C, SENSOR_R };

void ultrasonic_task_init(void);
void ultrasonic_task(void);
uint32_t ultrasonic_get(int cm[SENSOR_COUNT]);
uint32_t ultrasonic_age_ms(void);

#endif
