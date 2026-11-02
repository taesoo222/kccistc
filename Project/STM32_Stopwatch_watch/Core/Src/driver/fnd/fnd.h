/*
 * fnd.h
 *
 *  Created on: 2026. 10. 14.
 *      Author: kccistc
 */

#ifndef SRC_DRIVER_FND_FND_H_
#define SRC_DRIVER_FND_FND_H_

#include "stm32f4xx_hal.h"
void fnd_set_num(uint16_t n);
void fnd_set_dp(int digit, int enable);
void fnd_clear_dp(void);
uint16_t fnd_get_num(void);
void fnd_show_number();

#endif /* SRC_DRIVER_FND_FND_H_ */
