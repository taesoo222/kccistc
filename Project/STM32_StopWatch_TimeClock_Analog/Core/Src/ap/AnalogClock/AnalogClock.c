/*
 * AnalogClock.c
 *
 *  Created on: 2026. 10. 24.
 *      Author: kccistc
 */

#include "AnalogClock.h"
#include "../../driver/StepMotor/StepMotor.h"

#define STEPS_PER_REV 4096 // 28BYJ-48 half-step, 1 revolution

typedef struct {
	stepMotor_t motor;
	volatile uint16_t pos;    // current position (0 = 12 o'clock)
	volatile uint16_t target; // position to move to
} needle_t;

static stepMotor_pin_t hourMotorPin = {
	.port = {GPIOC, GPIOC, GPIOC, GPIOD},
	.pin = {GPIO_PIN_10, GPIO_PIN_11, GPIO_PIN_12, GPIO_PIN_2}
};

static stepMotor_pin_t minMotorPin = {
	.port = {GPIOC, GPIOC, GPIOC, GPIOC},
	.pin = {GPIO_PIN_5, GPIO_PIN_6, GPIO_PIN_8, GPIO_PIN_9}
};

static stepMotor_pin_t secMotorPin = {
	.port = {GPIOA, GPIOA, GPIOA, GPIOB},
	.pin = {GPIO_PIN_0, GPIO_PIN_1, GPIO_PIN_4, GPIO_PIN_0}
};

static needle_t needleHour;
static needle_t needleMin;
static needle_t needleSec;

static void AnalogClock_initNeedle(needle_t *n, stepMotor_pin_t *pin)
{
	n->motor.pin = pin;
	n->motor.stepCounter = 0;
	n->pos = 0; // needle is set to 12 o'clock by hand before power on
	n->target = 0;
}

// value(0 ~ range-1) -> step position(0 ~ STEPS_PER_REV-1)
static uint16_t AnalogClock_toStep(uint16_t value, uint16_t range)
{
	return (uint32_t)(value % range) * STEPS_PER_REV / range;
}

// move one step toward target, clockwise only
static void AnalogClock_moveNeedle(needle_t *n)
{
	if (n->pos == n->target) {
		StepMotor_release(&n->motor); // coil off while waiting
		return;
	}
	StepMotor_stepPhase(&n->motor, STEP_MOTOR_DIR_CCW);
	n->pos = (n->pos + 1) % STEPS_PER_REV;
}

void AnalogClock_init(void)
{
	AnalogClock_initNeedle(&needleHour, &hourMotorPin);
	AnalogClock_initNeedle(&needleMin, &minMotorPin);
	AnalogClock_initNeedle(&needleSec, &secMotorPin);
}

void AnalogClock_setTime(uint8_t hour, uint8_t min, uint8_t sec)
{
	needleHour.target = AnalogClock_toStep(hour, 12);
	needleMin.target = AnalogClock_toStep(min, 60);
	needleSec.target = AnalogClock_toStep(sec, 60);
}

// called every TIM9 period (1ms) : one step per needle
void AnalogClock_ISR(void)
{
	AnalogClock_moveNeedle(&needleHour);
	AnalogClock_moveNeedle(&needleMin);
	AnalogClock_moveNeedle(&needleSec);
}
