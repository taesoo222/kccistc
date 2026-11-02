/*
 * temp_humid.h
 *
 *  Created on: 2026. 10. 28.
 *      Author: rhoblack
 */

#ifndef SRC_AP_SERVICE_TEMP_HUMID_TEMP_HUMID_H_
#define SRC_AP_SERVICE_TEMP_HUMID_TEMP_HUMID_H_

#include "../../../driver/DHT11/DHT11.h"

void TH_init(void);
void TH_task(void);
void TH_getTempHumid(dht11_data_t *tempHumid);

#endif /* SRC_AP_SERVICE_TEMP_HUMID_TEMP_HUMID_H_ */
