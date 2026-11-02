/*
 * fnd.c
 *
 *  Created on: 2026. 10. 14.
 *      Author: kccistc
 */

#include "fnd.h"
#include <stdint.h>

#define FND_DIGIT_1 0
#define FND_DIGIT_2 1
#define FND_DIGIT_3 2
#define FND_DIGIT_4 3
#define FND_DP_PORT GPIOB
#define FND_DP_PIN GPIO_PIN_4

typedef struct seg_port {
	GPIO_TypeDef *GPIOx;
	uint16_t GPIO_Pin;
} seg_port_t;

static void fnd_all_off(void);
static void fnd_sel_digit(int digit);
static void fnd_disp_number(int number);
void fnd_set_dp(int digit, int enable);
void fnd_clear_dp(void);

static volatile uint16_t num = 0;

static volatile uint8_t dp_state = 0;

void fnd_set_num(uint16_t n)
{
	num = n;
}

uint16_t fnd_get_num(void)
{
	return num;
}



static void fnd_on_dp(void)
{
	HAL_GPIO_WritePin(GPIOB, GPIO_PIN_4, GPIO_PIN_SET);
}

static void fnd_off_dp(void)
{
	HAL_GPIO_WritePin(GPIOB, GPIO_PIN_4, GPIO_PIN_RESET);
}



static void fnd_all_off(void) // static 외부에서 사용 X
{
	HAL_GPIO_WritePin(GPIOA, GPIO_PIN_5, GPIO_PIN_SET); //D1
	HAL_GPIO_WritePin(GPIOB, GPIO_PIN_6, GPIO_PIN_SET); //D2
	HAL_GPIO_WritePin(GPIOC, GPIO_PIN_7, GPIO_PIN_SET); //D3
	HAL_GPIO_WritePin(GPIOA, GPIO_PIN_10, GPIO_PIN_SET); //D4
}

static void fnd_sel_digit(int digit)
{
	switch (digit) {
		case 0:
			HAL_GPIO_WritePin(GPIOA, GPIO_PIN_5, GPIO_PIN_RESET); //D1
			HAL_GPIO_WritePin(GPIOB, GPIO_PIN_6, GPIO_PIN_SET); //D2
			HAL_GPIO_WritePin(GPIOC, GPIO_PIN_7, GPIO_PIN_SET); //D3
			HAL_GPIO_WritePin(GPIOA, GPIO_PIN_10, GPIO_PIN_SET); //D4
			break;
		case 1:
			HAL_GPIO_WritePin(GPIOA, GPIO_PIN_5, GPIO_PIN_SET); //D1
			HAL_GPIO_WritePin(GPIOB, GPIO_PIN_6, GPIO_PIN_RESET); //D2
			HAL_GPIO_WritePin(GPIOC, GPIO_PIN_7, GPIO_PIN_SET); //D3
			HAL_GPIO_WritePin(GPIOA, GPIO_PIN_10, GPIO_PIN_SET); //D4
			break;
		case 2:
			HAL_GPIO_WritePin(GPIOA, GPIO_PIN_5, GPIO_PIN_SET); //D1
			HAL_GPIO_WritePin(GPIOB, GPIO_PIN_6, GPIO_PIN_SET); //D2
			HAL_GPIO_WritePin(GPIOC, GPIO_PIN_7, GPIO_PIN_RESET); //D3
			HAL_GPIO_WritePin(GPIOA, GPIO_PIN_10, GPIO_PIN_SET); //D4
			break;
		case 3:
			HAL_GPIO_WritePin(GPIOA, GPIO_PIN_5, GPIO_PIN_SET); //D1
			HAL_GPIO_WritePin(GPIOB, GPIO_PIN_6, GPIO_PIN_SET); //D2
			HAL_GPIO_WritePin(GPIOC, GPIO_PIN_7, GPIO_PIN_SET); //D3
			HAL_GPIO_WritePin(GPIOA, GPIO_PIN_10, GPIO_PIN_RESET); //D4
			break;
	}
}

static void fnd_disp_number(int number)
{
	seg_port_t seg_font[8] = {
	        {GPIOA, GPIO_PIN_6}, // A
	        {GPIOA, GPIO_PIN_9}, // B
	        {GPIOB, GPIO_PIN_5}, // C
	        {GPIOB, GPIO_PIN_10}, // D
	        {GPIOA, GPIO_PIN_8}, // E
	        {GPIOA, GPIO_PIN_7}, // F
	        {GPIOB, GPIO_PIN_3}, // G
	        {GPIOB, GPIO_PIN_4} // DP
	};
	int seg_font_data[10][8] = {
	        {1, 1, 1, 1, 1, 1, 0, 0}, // 0
	        {0, 1, 1, 0, 0, 0, 0, 0}, // 1
	        {1, 1, 0, 1, 1, 0, 1, 0}, // 2
	        {1, 1, 1, 1, 0, 0, 1, 0}, // 3
	        {0, 1, 1, 0, 0, 1, 1, 0}, // 4
	        {1, 0, 1, 1, 0, 1, 1, 0}, // 5
	        {1, 0, 1, 1, 1, 1, 1, 0}, // 6
	        {1, 1, 1, 0, 0, 0, 0, 0}, // 7
	        {1, 1, 1, 1, 1, 1, 1, 0}, // 8
	        {1, 1, 1, 1, 0, 1, 1, 0}, // 9
	};

	for (int i = 0; i < 8; i++) {
		HAL_GPIO_WritePin(seg_font[i].GPIOx, seg_font[i].GPIO_Pin, seg_font_data[number][i]);
	}
}

void fnd_show_number()
{
	static int state = 0; // 함수가 끝나도 변수값 유지

	int data = fnd_get_num();

	fnd_all_off();

	switch (state) {
		case 0:
			fnd_disp_number(data / 1000 % 10);
			if (dp_state & (1 << state)) { //dp_state의 비트가 1이면 fnd_on_dp
				fnd_on_dp();
			} else {
				fnd_off_dp();
			}
			fnd_sel_digit(FND_DIGIT_1);
			break;
		case 1:
			fnd_disp_number(data / 100 % 10);
			if (dp_state & (1 << state)) { //dp_state의 비트가 1이면 fnd_on_dp
				fnd_on_dp();
			} else {
				fnd_off_dp();
			}
			fnd_sel_digit(FND_DIGIT_2);
			break;
		case 2:
			fnd_disp_number(data / 10 % 10);
			if (dp_state & (1 << state)) { //dp_state의 비트가 1이면 fnd_on_dp
				fnd_on_dp();
			} else {
				fnd_off_dp();
			}
			fnd_sel_digit(FND_DIGIT_3);
			break;
		case 3:
			fnd_disp_number(data % 10);
			if (dp_state & (1 << state)) { //dp_state의 비트가 1이면 fnd_on_dp
				fnd_on_dp();
			} else {
				fnd_off_dp();
			}
			fnd_sel_digit(FND_DIGIT_4);
			break;
		default:
			break;
	}
	state = (state + 1) % 4;
}

void fnd_set_dp(int digit, int enable)
{
	if (enable) {
		dp_state |= (1 << digit);
	} else {
		dp_state &= ~(1 << digit);
	}
}

void fnd_clear_dp(void)
{
	dp_state = 0;
}