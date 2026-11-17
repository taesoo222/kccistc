#ifndef SRC_DRIVER_HCSR04_HCSR04_H_
#define SRC_DRIVER_HCSR04_HCSR04_H_

#include "stm32f4xx_hal.h"

#define HCSR04_MAX_SENSORS	3

typedef enum {
	HCSR04_OK = 0,
	HCSR04_IN_PROGRESS,
	HCSR04_ERR_NOT_STARTED,
	HCSR04_ERR_BUSY,
	HCSR04_ERR_NO_ECHO,
	HCSR04_ERR_OUT_OF_RANGE
} hcsr04_status_t;

void HCSR04_init(GPIO_TypeDef *t_port, uint16_t t_pin,
		GPIO_TypeDef *e_ports[], uint16_t e_pins[], uint8_t count,
		TIM_HandleTypeDef *htim);
hcsr04_status_t HCSR04_start(void);
void HCSR04_echoISR(uint16_t pin);
hcsr04_status_t HCSR04_getResult(uint8_t idx, uint32_t *echo_us);

#endif
