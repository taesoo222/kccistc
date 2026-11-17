#include "HCSR04.h"
#include "../../common/delay/delay.h"
#include <stdbool.h>

#define RISE_TIMEOUT_MS		5
#define FALL_TIMEOUT_MS		50

typedef enum {
	STATE_IDLE,
	STATE_WAIT_RISE,
	STATE_WAIT_FALL,
	STATE_DONE
}sr04_state_t;

typedef struct {
	GPIO_TypeDef *port;
	uint16_t pin;
	volatile sr04_state_t state;
	volatile uint32_t rise_cnt;
	volatile uint32_t fall_cnt;
} echo_t;

static GPIO_TypeDef *trig_port;
static uint16_t trig_pin;
static echo_t echo[HCSR04_MAX_SENSORS];
static uint8_t echo_count;

static TIM_HandleTypeDef *sr04_htim;

static uint32_t start_ms;

void HCSR04_init(GPIO_TypeDef *t_port, uint16_t t_pin,
		GPIO_TypeDef *e_ports[], uint16_t e_pins[], uint8_t count,
		TIM_HandleTypeDef *htim)
{
	trig_port = t_port;
	trig_pin = t_pin;
	sr04_htim = htim;
	echo_count = (count > HCSR04_MAX_SENSORS) ? HCSR04_MAX_SENSORS : count;

	for (uint8_t i = 0; i < echo_count; i++) {
		echo[i].port = e_ports[i];
		echo[i].pin = e_pins[i];
		echo[i].state = STATE_IDLE;
	}

	delay_init();
	HAL_GPIO_WritePin(trig_port, trig_pin, GPIO_PIN_RESET);
	HAL_TIM_Base_Start(sr04_htim);
}

static bool echo_is_high(uint8_t i)
{
	return (HAL_GPIO_ReadPin(echo[i].port, echo[i].pin) == GPIO_PIN_SET);
}

hcsr04_status_t HCSR04_start(void)
{
	for (uint8_t i = 0; i < echo_count; i++) {
		if (echo[i].state == STATE_WAIT_RISE || echo[i].state == STATE_WAIT_FALL) {
			return HCSR04_ERR_BUSY;
		}
		if (echo_is_high(i)) {
			return HCSR04_ERR_BUSY;
		}
	}
	for (uint8_t i = 0; i < echo_count; i++) {
		echo[i].state = STATE_WAIT_RISE;
	}
	start_ms = HAL_GetTick();

	uint32_t primask = __get_PRIMASK();
	__disable_irq();
	HAL_GPIO_WritePin(trig_port, trig_pin, GPIO_PIN_SET);
	delay_us(10);
	HAL_GPIO_WritePin(trig_port, trig_pin, GPIO_PIN_RESET);
	__set_PRIMASK(primask);

	return HCSR04_OK;
}

void HCSR04_echoISR(uint16_t pin)
{
	if (sr04_htim == NULL) return;
	uint32_t cnt = __HAL_TIM_GET_COUNTER(sr04_htim);

	for (uint8_t i = 0; i < echo_count; i++) {
		if (echo[i].pin != pin) {
			continue;
		}
		bool high = echo_is_high(i);

		if ((echo[i].state == STATE_WAIT_RISE) && high) {
			echo[i].rise_cnt = cnt;
			echo[i].state = STATE_WAIT_FALL;
		}
		else if ((echo[i].state == STATE_WAIT_FALL) && !high){
			echo[i].fall_cnt = cnt;
			echo[i].state = STATE_DONE;
		}
		return;
	}
}

static uint32_t timer_diff(uint32_t start, uint32_t end)
{
	uint32_t arr = __HAL_TIM_GET_AUTORELOAD(sr04_htim);

	if (end >= start) {
		return end - start;
	}
	else {
		return (arr - start) + end + 1;
	}
}

hcsr04_status_t HCSR04_getResult(uint8_t idx, uint32_t *echo_us)
{
	if (idx >= echo_count) {
		return HCSR04_ERR_NOT_STARTED;
	}

	uint32_t elapsed_ms = HAL_GetTick() - start_ms;

	switch (echo[idx].state)
	{
	case STATE_WAIT_RISE:
		if (elapsed_ms <= RISE_TIMEOUT_MS) {
			return HCSR04_IN_PROGRESS;
		}
		echo[idx].state = STATE_IDLE;
		return HCSR04_ERR_NO_ECHO;
	case STATE_WAIT_FALL:
		if (elapsed_ms <= FALL_TIMEOUT_MS) {
			return HCSR04_IN_PROGRESS;
		}
		echo[idx].state = STATE_IDLE;
		return HCSR04_ERR_NO_ECHO;
	case STATE_DONE:
		*echo_us = timer_diff(echo[idx].rise_cnt, echo[idx].fall_cnt);
		echo[idx].state = STATE_IDLE;
		return HCSR04_OK;
	case STATE_IDLE:
	default:
		return HCSR04_ERR_NOT_STARTED;
	}
}
