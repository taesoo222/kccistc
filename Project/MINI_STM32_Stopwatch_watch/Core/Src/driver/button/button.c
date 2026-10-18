#include "button.h"
#include "stm32f411xe.h"
#include <stdint.h>

void button_init(button_t *btn, GPIO_TypeDef *GPIOx, uint16_t GPIO_Pin)
{
	btn->GPIOx = GPIOx;
	btn->GPIO_Pin = GPIO_Pin;
	btn->prevState = RELEASED;
}

button_state_t button_getState(button_t *btn)
{

	int curState;

	curState = HAL_GPIO_ReadPin(btn->GPIOx, btn->GPIO_Pin);

	if ((btn->prevState == RELEASED) && (curState == PUSHED)) {
		btn->prevState = PUSHED;
		HAL_Delay(5);
		return ACT_PUSH;

	} else if ((btn->prevState == PUSHED) && (curState == RELEASED)) {
		btn->prevState = RELEASED;
		HAL_Delay(5);
		return ACT_RELEASE;
	}
	return NO_ACT;
}
