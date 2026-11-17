#include "comm_task.h"
#include "usart.h"
#include "../../message.h"
#include "../../service/sound/sound.h"
#include <string.h>
#include <stdlib.h>

#define RX_BUFF_SIZE	32

typedef struct {
	UART_HandleTypeDef *huart;
	uint8_t rx_data;
	uint8_t index;
	char buff[RX_BUFF_SIZE];
	char line[RX_BUFF_SIZE];
	volatile uint8_t ready;
} rx_t;

static rx_t rx_pc = { .huart = &huart2 };
static rx_t rx_bt = { .huart = &huart6 };

static comm_data_t comm_data;

static const struct {
	const char *name;
	comm_status_t status;
} cmd_tbl[] = {
	{"RUN", COMM_RUN}, {"STOP", COMM_STOP}, {"LEFT", COMM_LEFT},
	{"RIGHT", COMM_RIGHT}, {"BACK", COMM_BACK}, {"AUTO", COMM_AUTO},
	{"MANUAL", COMM_MANUAL},
};

void comm_task_init(void)
{
	sound_init();
	HAL_UART_Receive_IT(rx_pc.huart, &rx_pc.rx_data, 1);
	HAL_UART_Receive_IT(rx_bt.huart, &rx_bt.rx_data, 1);
}

static void handle_line(const char *line)
{
	if (strncmp(line, "HORN", 4) == 0) {
		sound_error();
		return;
	}
	if (strncmp(line, "SPD", 3) == 0) {
		comm_data.status = COMM_SPEED;
		comm_data.speed = atoi(&line[3]);
		osMessagePut(CommQueueHandle, (uint32_t)&comm_data, 10);
		return;
	}
	for (uint32_t i = 0; i < sizeof(cmd_tbl) / sizeof(cmd_tbl[0]); i++) {
		if (strncmp(line, cmd_tbl[i].name, strlen(cmd_tbl[i].name)) == 0) {
			comm_data.status = cmd_tbl[i].status;
			osMessagePut(CommQueueHandle, (uint32_t)&comm_data, 10);
			return;
		}
	}
}

void comm_task(void)
{
	if (rx_pc.ready) {
		handle_line(rx_pc.line);
		rx_pc.ready = 0;
	}
	if (rx_bt.ready) {
		handle_line(rx_bt.line);
		rx_bt.ready = 0;
	}
}

static void rx_byte(rx_t *rx)
{
	uint8_t c = rx->rx_data;

	if (c == '*') {
		rx->buff[rx->index] = '\0';
		if (!rx->ready) {
			memcpy(rx->line, rx->buff, rx->index + 1);
			rx->ready = 1;
		}
		rx->index = 0;
	}
	else if (c == '\r' || c == '\n') {
	}
	else if (rx->index < RX_BUFF_SIZE - 1) {
		rx->buff[rx->index++] = c;
	}
	else {
		rx->index = 0;
	}
	HAL_UART_Receive_IT(rx->huart, &rx->rx_data, 1);
}

void HAL_UART_RxCpltCallback(UART_HandleTypeDef *huart)
{
	if (huart->Instance == USART2) {
		rx_byte(&rx_pc);
	}
	else if (huart->Instance == USART6) {
		rx_byte(&rx_bt);
	}
}
