#include "motor_control_task.h"
#include "cmsis_os.h"
#include "../../../driver/dc_motor/dc_motor.h"
#include "../../message.h"
#include "../ultrasonic_task/ultrasonic_task.h"
#include "../../../driver/lcd/lcd.h"
#include <string.h>

typedef enum { STOP, RUN, LEFT, RIGHT, BACK } motor_state_t;

#define AUTO_BACK_CM	8
#define AUTO_FRONT_CM	25
#define AUTO_CLEAR_CM	35
#define AUTO_SIDE_CM	15
#define NO_ECHO_CM		400

extern TIM_HandleTypeDef htim3;
extern osMessageQId btnQueHandle;

static motor_t motor_l, motor_r;
static motor_state_t motor_state = STOP;
static uint8_t auto_mode = 0;
static btn_status_t btn_status = BTN_NO;
static comm_data_t comm_data_dummy = {0};
static comm_data_t *pcomm_data;

void motor_control_task_init(void)
{

	motor_init(
	    &motor_r, &htim3, TIM_CHANNEL_3, GPIOA, GPIO_PIN_6, GPIOA, GPIO_PIN_5
	);
	motor_init(
	    &motor_l, &htim3, TIM_CHANNEL_1, GPIOA, GPIO_PIN_7, GPIOB, GPIO_PIN_6
	);
	motor_set_speed(900);
}

static motor_state_t auto_decide(void)
{
	static motor_state_t turning = STOP;
	int cm[SENSOR_COUNT];

	ultrasonic_get(cm);

	if (cm[SENSOR_L] < 0 && cm[SENSOR_C] < 0 && cm[SENSOR_R] < 0) {
		turning = STOP;
		return STOP;
	}
	for (int i = 0; i < SENSOR_COUNT; i++) {
		if (cm[i] < 0) {
			cm[i] = NO_ECHO_CM;
		}
	}

	if (cm[SENSOR_C] < AUTO_BACK_CM) {
		turning = STOP;
		return BACK;
	}
	if (cm[SENSOR_C] < AUTO_FRONT_CM ||
	    (turning != STOP && cm[SENSOR_C] < AUTO_CLEAR_CM)) {
		if (turning == STOP) {
			turning = (cm[SENSOR_L] >= cm[SENSOR_R]) ? LEFT : RIGHT;
		}
		return turning;
	}

	turning = STOP;
	if (cm[SENSOR_L] < AUTO_SIDE_CM && cm[SENSOR_L] < cm[SENSOR_R]) {
		return RIGHT;
	}
	if (cm[SENSOR_R] < AUTO_SIDE_CM) {
		return LEFT;
	}
	return RUN;
}

static motor_state_t manual_next(motor_state_t s, btn_status_t btn, comm_status_t cmd)
{
	if (btn == BTN_RUN_STOP) return (s == STOP) ? RUN : STOP;
	if (btn == BTN_LEFT || cmd == COMM_LEFT) return LEFT;
	if (btn == BTN_RIGHT || cmd == COMM_RIGHT) return RIGHT;
	if (cmd == COMM_RUN) return RUN;
	if (cmd == COMM_STOP) return STOP;
	if (cmd == COMM_BACK) return BACK;
	return s;
}

static int is_drive_cmd(comm_status_t cmd)
{
	return cmd == COMM_RUN || cmd == COMM_STOP || cmd == COMM_LEFT ||
	       cmd == COMM_RIGHT || cmd == COMM_BACK;
}

static void show_state(void)
{
	static const char *name[] = {"STOP ", "RUN  ", "LEFT ", "RIGHT", "BACK "};
	static int shown = -1;
	int now = (auto_mode << 4) | motor_state;
	char row[17] = "                ";

	if (now == shown) {
		return;
	}
	shown = now;
	memcpy(row, auto_mode ? "AUTO  " : "MANUAL", 6);
	memcpy(&row[7], name[motor_state], 5);

	if (osMutexWait(lcdMutexHandle, osWaitForever) == osOK) {
		Lcd_writeStringXY(0, 0, row);
		osMutexRelease(lcdMutexHandle);
	}
}

void motor_control_task(void)
{
	osEvent btn_evt;
	btn_evt = osMessageGet(btnQueHandle, 0);
	if (btn_evt.status == osEventMessage) {
		btn_status = btn_evt.value.v;
	}
	else {
		btn_status = BTN_NO;
	}

	osEvent comm_evt;
	comm_evt = osMessageGet(CommQueueHandle, 0);
	if (comm_evt.status == osEventMessage) {
		pcomm_data = comm_evt.value.p;
	}
	else {
		pcomm_data = &comm_data_dummy;
	}

	if (pcomm_data->status == COMM_SPEED) {
		motor_set_speed(pcomm_data->speed);
	}

	comm_status_t cmd = pcomm_data->status;

	if (btn_status == BTN_AUTO || cmd == COMM_AUTO || cmd == COMM_MANUAL) {
		auto_mode = (btn_status == BTN_AUTO) ? !auto_mode : (cmd == COMM_AUTO);
		motor_state = STOP;
	}
	else if (auto_mode && (btn_status != BTN_NO || is_drive_cmd(cmd))) {
		auto_mode = 0;
		motor_state = manual_next(RUN, btn_status, cmd);
	}
	else if (auto_mode) {
		motor_state = auto_decide();
	}
	else {
		motor_state = manual_next(motor_state, btn_status, cmd);
	}

	switch (motor_state) {
		case RUN:   motor_forward(&motor_l, &motor_r);  break;
		case LEFT:  motor_left(&motor_l, &motor_r);     break;
		case RIGHT: motor_right(&motor_l, &motor_r);    break;
		case BACK:  motor_backward(&motor_l, &motor_r); break;
		case STOP:
		default:    motor_stop(&motor_l, &motor_r);     break;
	}
	show_state();
}
