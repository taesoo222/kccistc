/*
 * sound.c
 *
 *  Created on: 2026. 10. 30.
 *      Author: kccistc
 */
#include "sound.h"
#include "../../../driver/buzzer/buzzer.h"
#include "../../../common/queue/que_buffer.h"
#include <stdbool.h>

#define C4 262
#define D4 294
#define E4 330
#define F4 349
#define G4 392
#define A4 440
#define B4 494
#define C5 (C4*2)
#define D5 (D4*2)
#define E5 (E4*2)
#define F5 (F4*2)
#define G5 (G4*2)
#define A5 (A4*2)
#define B5 (B4*2)
#define C6 (C5*2)
#define D6 (D5*2)
#define E6 (E5*2)
#define F6 (F5*2)
#define G6 (G5*2)
#define A6 (A5*2)
#define B6 (B5*2)
#define C7 (C6*2)
#define D7 (D6*2)
#define E7 (E6*2)
#define F7 (F6*2)
#define G7 (G6*2)
#define A7 (A6*2)
#define B7 (B6*2)

#define REST 0

#define NOTE_QUE_SIZE	16

typedef struct {
	uint16_t freq;
	uint16_t ms;
} note_t;

extern TIM_HandleTypeDef htim1;

static note_t note_storage[NOTE_QUE_SIZE];
static que_buf_t note_que;

static bool playing = false;
static uint32_t noteStart;
static uint16_t noteMs;

static void sound_put(uint16_t freq, uint16_t ms)
{
	note_t note = { freq, ms };
	que_put(&note_que, &note);
}

void sound_init(void)
{
	buzzer_init(&htim1, TIM_CHANNEL_4);
	que_buf_init(&note_que, note_storage, sizeof(note_t), NOTE_QUE_SIZE);
}

void sound_task(void)
{
	note_t note;

	if (playing && (HAL_GetTick() - noteStart < noteMs)) {
		return;
	}
	if (!que_get(&note_que, &note)) {
		if (playing) {
			buzzer_off();
			playing = false;
		}
		return;
	}
	buzzer_on(note.freq);
	noteStart = HAL_GetTick();
	noteMs = note.ms;
	playing = true;
}

void sound_power(void)
{
	sound_put(C6, 100);
	sound_put(E6, 100);
	sound_put(G6, 100);
	sound_put(C7, 200);
}

void sound_button(void)
{
	sound_put(G6, 40);
	sound_put(C7, 60);
}

void sound_error(void)
{
	sound_put(C5, 150);
	sound_put(REST, 60);
	sound_put(C5, 150);
}

void sound_alarm(void)
{
	for (int i = 0; i < 3; i++) {
		sound_put(C7, 100);
		sound_put(REST, 100);
	}
}
