/*
 * photoSensor.c
 *
 *  Created on: 2026. 11. 5.
 *      Author: kccistc
 */

#include "photoSensor.h"
#include "main.h"

static GPIO_TypeDef *const port[PHOTO_FLOOR_NUM] = {PHOTO_1F_GPIO_Port, PHOTO_2F_GPIO_Port, PHOTO_3F_GPIO_Port};
static const uint16_t pin[PHOTO_FLOOR_NUM] = {PHOTO_1F_Pin, PHOTO_2F_Pin, PHOTO_3F_Pin};

uint8_t photoSensor_pinToFloor(uint16_t GPIO_Pin)
{
	for (uint8_t i = 0; i < PHOTO_FLOOR_NUM; i++) {
		if (pin[i] == GPIO_Pin) {
			return i + 1;
		}
	}
	return 0;
}

uint8_t photoSensor_read(uint8_t floor)
{
	if (floor < 1 || floor > PHOTO_FLOOR_NUM) {
		return 0;
	}
	return (HAL_GPIO_ReadPin(port[floor - 1], pin[floor - 1]) == GPIO_PIN_SET) ? 1 : 0;
}

uint8_t photoSensor_isBlocked(uint8_t floor)
{
	return (floor >= 1 && floor <= PHOTO_FLOOR_NUM && photoSensor_read(floor) == PHOTO_LEVEL_BLOCKED);
}
