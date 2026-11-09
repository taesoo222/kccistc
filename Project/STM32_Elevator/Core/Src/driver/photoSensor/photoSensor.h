/*
 * photoSensor.h
 *
 *  Created on: 2026. 11. 5.
 *      Author: kccistc
 *
 *  층 감지 포토 인터럽터 3개 (PC10=1F, PC11=2F, PC12=3F, EXTI 양쪽 엣지)
 */

#ifndef SRC_DRIVER_PHOTOSENSOR_PHOTOSENSOR_H_
#define SRC_DRIVER_PHOTOSENSOR_PHOTOSENSOR_H_

#include "stm32f4xx_hal.h"

#define PHOTO_FLOOR_NUM 3
#define PHOTO_LEVEL_BLOCKED 1 // 실측: 차단판이 가리면 HIGH

// EXTI 콜백의 GPIO_Pin -> 층 번호(1~3), 센서 핀이 아니면 0
uint8_t photoSensor_pinToFloor(uint16_t GPIO_Pin);

// 해당 층 센서의 현재 핀 레벨 (0 또는 1)
uint8_t photoSensor_read(uint8_t floor);

// 해당 층 센서가 차단판에 가려져 있으면 1
uint8_t photoSensor_isBlocked(uint8_t floor);

#endif /* SRC_DRIVER_PHOTOSENSOR_PHOTOSENSOR_H_ */
