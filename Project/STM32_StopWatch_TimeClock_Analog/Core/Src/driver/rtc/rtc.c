/*
 * rtc.c
 *
 *  Created on: 2026. 10. 21.
 *      Author: kccistc
 */

#include "rtc.h"
#include <string.h>

#define DS3231_ADDR (0x68 << 1)

extern I2C_HandleTypeDef hi2c1;

static uint8_t bcd2dec(uint8_t bcd)
{
	return (bcd >> 4) * 10 + (bcd & 0x0F);
}

static uint8_t dec2bcd(uint8_t dec)
{
	return ((dec / 10) << 4) | (dec % 10);
}

void DS3231_getTime(rtc_t *pTime)
{
	uint8_t reg = 0x00;
	uint8_t buf[7];

	HAL_I2C_Master_Transmit(&hi2c1, DS3231_ADDR, &reg, 1, 100); // register pointer -> 0x00
	HAL_I2C_Master_Receive(&hi2c1, DS3231_ADDR, buf, 7, 100);   // read 0x00 ~ 0x06
	pTime->sec = bcd2dec(buf[0]);
	pTime->min = bcd2dec(buf[1]);
	pTime->hour = bcd2dec(buf[2] & 0x3F);
	pTime->day = buf[3];
	pTime->date = bcd2dec(buf[4]);
	pTime->month = bcd2dec(buf[5] & 0x1F);
	pTime->year = bcd2dec(buf[6]);
}

void DS3231_setTime(rtc_t *pTime)
{
	uint8_t buf[8];

	buf[0] = 0x00; // register pointer
	buf[1] = dec2bcd(pTime->sec);
	buf[2] = dec2bcd(pTime->min);
	buf[3] = dec2bcd(pTime->hour);
	buf[4] = pTime->day;
	buf[5] = dec2bcd(pTime->date);
	buf[6] = dec2bcd(pTime->month);
	buf[7] = dec2bcd(pTime->year);
	HAL_I2C_Master_Transmit(&hi2c1, DS3231_ADDR, buf, 8, 100);
}

// __DATE__ : "Oct 21 2026", __TIME__ : "14:35:27"
static void DS3231_setBuildTime(void)
{
	static const uint8_t t[] = { 0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4 };
	const char *d = __DATE__;
	const char *tm = __TIME__;
	char mon[4] = { d[0], d[1], d[2], 0 };
	rtc_t time;
	int y;

	time.month = (strstr("JanFebMarAprMayJunJulAugSepOctNovDec", mon) - "JanFebMarAprMayJunJulAugSepOctNovDec") / 3 + 1;
	time.date = (d[4] == ' ' ? 0 : d[4] - '0') * 10 + (d[5] - '0');
	time.year = (d[9] - '0') * 10 + (d[10] - '0');
	time.hour = (tm[0] - '0') * 10 + (tm[1] - '0');
	time.min = (tm[3] - '0') * 10 + (tm[4] - '0');
	time.sec = (tm[6] - '0') * 10 + (tm[7] - '0');

	// day of week (Sakamoto) : 1 = SUN ~ 7 = SAT
	y = 2000 + time.year - (time.month < 3);
	time.day = (y + y / 4 - y / 100 + y / 400 + t[time.month - 1] + time.date) % 7 + 1;

	DS3231_setTime(&time);
}

void DS3231_init(void)
{
	uint8_t buf[2] = { 0x0F, 0 }; // { register pointer, status }

	// status reg(0x0F) bit7 OSF = 1 : first power on or battery lost -> set build time
	HAL_I2C_Master_Transmit(&hi2c1, DS3231_ADDR, &buf[0], 1, 100);
	HAL_I2C_Master_Receive(&hi2c1, DS3231_ADDR, &buf[1], 1, 100);
	if (buf[1] & 0x80) {
		DS3231_setBuildTime();
		buf[1] &= ~0x80;
		HAL_I2C_Master_Transmit(&hi2c1, DS3231_ADDR, buf, 2, 100);
	}
}
