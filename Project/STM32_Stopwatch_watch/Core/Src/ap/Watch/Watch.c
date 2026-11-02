#include "Watch.h"
#include "../../driver/fnd/fnd.h"
#include "../../driver/led/led.h"
#include <stdint.h>

static volatile uint32_t watch_100ms = 0;
static led_t led_mode;

void Watch_init(void)
{
	led_init(&led_mode, GPIOB, GPIO_PIN_15);
}

void Watch_enter(void)
{
	led_on(&led_mode);
}

void Watch_exit(void)
{
	fnd_clear_dp();
	led_off(&led_mode);
}

void Watch_tick_100ms(void)
{
	if (++watch_100ms >= 864000) {
		watch_100ms = 0;
	}
}

void Watch_task(void)
{
	uint32_t t = watch_100ms;

	uint32_t sec = (t / 10) % 60;
	uint32_t min = (t / 600) % 60;

	fnd_set_num(min * 100 + sec);
	fnd_set_dp(1, (t / 5) % 2);
}