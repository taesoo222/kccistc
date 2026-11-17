#include "ultrasonic_task.h"
#include "usart.h"
#include "../../message.h"
#include "../../../driver/HCSR04/HCSR04.h"
#include "../../../driver/lcd/lcd.h"

extern TIM_HandleTypeDef htim2;

#define MEASURE_PERIOD_MS	50
#define PRINT_EVERY			10
#define LCD_EVERY			5

static GPIO_TypeDef *echo_ports[SENSOR_COUNT] = {GPIOC, GPIOC, GPIOC};
static uint16_t echo_pins[SENSOR_COUNT] = {GPIO_PIN_10, GPIO_PIN_11, GPIO_PIN_5};
static const char *sensor_name[SENSOR_COUNT] = {"L", "C", "R"};

static uint8_t measuring = 0;
static uint8_t done[SENSOR_COUNT];
static uint32_t last_start_ms = 0;
static uint8_t print_cnt = 0;
static uint8_t lcd_cnt = 0;
static volatile uint32_t result_seq = 0;
static volatile uint32_t result_ms = 0;
static volatile int dist_cm[SENSOR_COUNT] = {-1, -1, -1};

static int put_num(char *buf, int n, uint32_t v)
{
	char tmp[10];
	int len = 0;

	do { tmp[len++] = '0' + v % 10; v /= 10; } while (v);
	while (len) buf[n++] = tmp[--len];
	return n;
}

static int put_str(char *buf, int n, const char *s)
{
	while (*s) buf[n++] = *s++;
	return n;
}

static void print_all(void)
{
	char buf[64];
	int n = 0;

	for (int i = 0; i < SENSOR_COUNT; i++) {
		n = put_str(buf, n, sensor_name[i]);
		n = put_str(buf, n, ": ");
		n = (dist_cm[i] < 0) ? put_str(buf, n, "--") : put_num(buf, n, dist_cm[i]);
		n = put_str(buf, n, " cm  ");
	}
	n = put_str(buf, n, "\r\n");

	if (osMutexWait(uartMutexHandle, osWaitForever) == osOK) {
		HAL_UART_Transmit(&huart2, (uint8_t *)buf, n, 100);
		osMutexRelease(uartMutexHandle);
	}
}

static void put_cm3(char *dst, int cm)
{
	dst[0] = (cm >= 100) ? '0' + (cm / 100) % 10 : ' ';
	dst[1] = (cm >= 10) ? '0' + (cm / 10) % 10 : ' ';
	dst[2] = '0' + cm % 10;
	if (cm < 0) {
		dst[0] = ' '; dst[1] = '-'; dst[2] = '-';
	}
}

static void show_lcd(void)
{
	static char row1[17];
	static int shown[SENSOR_COUNT] = {-2, -2, -2};
	int changed = 0;

	for (int i = 0; i < SENSOR_COUNT; i++) {
		if (shown[i] != dist_cm[i]) {
			shown[i] = dist_cm[i];
			changed = 1;
		}
	}
	if (!changed) {
		return;
	}

	for (int i = 0; i < 16; i++) {
		row1[i] = ' ';
	}
	row1[0] = 'L'; put_cm3(&row1[1], shown[SENSOR_L]);
	row1[6] = 'C'; put_cm3(&row1[7], shown[SENSOR_C]);
	row1[12] = 'R'; put_cm3(&row1[13], shown[SENSOR_R]);

	if (osMutexWait(lcdMutexHandle, osWaitForever) == osOK) {
		Lcd_writeStringXY(1, 0, row1);
		osMutexRelease(lcdMutexHandle);
	}
}

uint32_t ultrasonic_get(int cm[SENSOR_COUNT])
{
	for (int i = 0; i < SENSOR_COUNT; i++) {
		cm[i] = dist_cm[i];
	}
	return result_seq;
}

uint32_t ultrasonic_age_ms(void)
{
	return HAL_GetTick() - result_ms;
}

void ultrasonic_task_init(void)
{
	HCSR04_init(GPIOC, GPIO_PIN_12, echo_ports, echo_pins, SENSOR_COUNT, &htim2);
}

void ultrasonic_task(void)
{
	if (!measuring) {
		if ((HAL_GetTick() - last_start_ms) >= MEASURE_PERIOD_MS &&
		    HCSR04_start() == HCSR04_OK) {
			last_start_ms = HAL_GetTick();
			measuring = 1;
			for (int i = 0; i < SENSOR_COUNT; i++) {
				done[i] = 0;
			}
		}
		return;
	}

	int finished = 1;
	for (int i = 0; i < SENSOR_COUNT; i++) {
		uint32_t echo_us;

		if (done[i]) {
			continue;
		}
		switch (HCSR04_getResult(i, &echo_us)) {
		case HCSR04_IN_PROGRESS:
			finished = 0;
			break;
		case HCSR04_OK:
			dist_cm[i] = echo_us * 17 / 1000;
			done[i] = 1;
			break;
		default:
			dist_cm[i] = -1;
			done[i] = 1;
			break;
		}
	}

	if (finished) {
		measuring = 0;
		result_ms = HAL_GetTick();
		result_seq++;
		if (++lcd_cnt >= LCD_EVERY) {
			lcd_cnt = 0;
			show_lcd();
		}
		if (++print_cnt >= PRINT_EVERY) {
			print_cnt = 0;
			print_all();
		}
	}
}

void HAL_GPIO_EXTI_Callback(uint16_t GPIO_Pin)
{
	HCSR04_echoISR(GPIO_Pin);
}
