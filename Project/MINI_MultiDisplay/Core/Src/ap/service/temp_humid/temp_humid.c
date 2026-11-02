/*
 * temp_humid.c
 *
 *  Created on: 2026. 10. 28.
 *      Author: rhoblack
 */
#include "temp_humid.h"

#define dht_port	GPIOC
#define dht_pin		GPIO_PIN_8

static dht11_data_t TH_data;

void TH_init(void)
{
	dht11_init(dht_port, dht_pin);
}

void TH_task(void)
{
	static uint32_t nextTime = 1000;

	if ((int32_t)(HAL_GetTick() - nextTime) < 0) {
		return;
	}
	if (dht11_read(&TH_data) == DHT11_OK) {
		nextTime = HAL_GetTick() + 2000;
	} else {
		nextTime = HAL_GetTick() + 1000;
	}
}

void TH_getTempHumid(dht11_data_t *tempHumid)
{
	*tempHumid = TH_data;
}
