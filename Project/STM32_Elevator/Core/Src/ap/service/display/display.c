/*
 * display.c
 *
 *  Created on: 2026. 11. 6.
 *      Author: kccistc
 *
 *  실제 엘리베이터 상단 표시기처럼: 2줄 높이의 큰 화살표 + 큰 층 숫자만 표시
 *
 *      열  5 6   8 9 10
 *         [▲▲]  [ 큰  ]     <- 0줄
 *         [██]  [숫자 ]     <- 1줄
 *
 *  - 이동 중: 화살표가 진행 방향으로 흐르는 애니메이션 (HOMING은 ▼)
 *  - 도착: 화살표 몇 번 깜빡이고 사라짐
 *  - 숫자: 현재 층 1~3, HOMING 중 '-', 오류 'E'
 *
 *  LCD 사용자 정의 문자 8칸(CGRAM) 배치
 *   1~3: 큰 숫자용 블록 (꽉 찬 칸은 LCD 내장 0xFF)
 *   4~7: 화살표 4조각 (좌상, 우상, 좌하, 우하) -> 이 4칸 모양만 바꿔 써서 애니메이션
 */

#include "display.h"
#include <stdbool.h>
#include "../elevator/elevator.h"
#include "../../../driver/lcd/lcd.h"

#define ARROW_COL 5
#define DIGIT_COL 8
#define ARROW_FRAME_MS 150 // 화살표 한 칸 흐르는 주기 (LCD 액정 반응이 느려서 너무 빠르면 번짐)
#define BLINK_MS 250       // 도착 깜빡임 주기
#define BLINK_TOTAL_MS 1500

// 큰 숫자 블록
#define B_TOP  1    // 위쪽 가로줄
#define B_BOT  2    // 아래쪽 가로줄
#define B_TB   3    // 위 + 아래 가로줄
#define B_FULL 0xFF // LCD 내장 꽉 찬 칸
#define B_NONE ' '

#define CH_ARROW 4  // 4,5,6,7 = 화살표 좌상, 우상, 좌하, 우하

static const uint8_t blockTop[8] = {0x1F, 0x1F, 0x1F, 0x00, 0x00, 0x00, 0x00, 0x00};
static const uint8_t blockBot[8] = {0x00, 0x00, 0x00, 0x00, 0x00, 0x1F, 0x1F, 0x1F};
static const uint8_t blockTB[8]  = {0x1F, 0x1F, 0x1F, 0x00, 0x00, 0x1F, 0x1F, 0x1F};

// 큰 글자: {0줄 3칸, 1줄 3칸}
typedef struct {
	char ch;
	uint8_t cell[6];
} bigGlyph_t;

static const bigGlyph_t glyphs[] = {
	{'1', {B_TOP,  B_FULL, B_NONE, B_BOT,  B_FULL, B_BOT }},
	{'2', {B_TB,   B_TB,   B_FULL, B_FULL, B_BOT,  B_BOT }},
	{'3', {B_TB,   B_TB,   B_FULL, B_BOT,  B_BOT,  B_FULL}},
	{'E', {B_FULL, B_TB,   B_TB,   B_FULL, B_BOT,  B_BOT }},
	{'-', {B_BOT,  B_BOT,  B_BOT,  B_NONE, B_NONE, B_NONE}},
};

// 위 화살표 10픽셀 x 16줄 (bit9 = 왼쪽 끝). 아래 4줄은 빈칸 -> 흐를 때 화살표 사이 간격
static const uint16_t arrowBmp[16] = {
	0x030, 0x078, 0x0FC, 0x1FE, 0x3FF, 0x078, 0x078, 0x078,
	0x078, 0x078, 0x078, 0x078, 0x000, 0x000, 0x000, 0x000,
};
#define ARROW_STILL_FRAME 14 // 멈춘 화살표: 위아래 2줄씩 비워서 가운데 오게

typedef enum {
	ARROW_NONE,
	ARROW_UP,
	ARROW_DOWN,
} arrow_t;

static char shownGlyph = 0;
static bool shownArrow = false;
static arrow_t loadedDir = ARROW_NONE;
static uint8_t loadedFrame = 0xFF;

static void loadChars(uint8_t code, const uint8_t *data, uint8_t n)
{
	Lcd_writeCmdData(0x40 | (code << 3)); // CGRAM 주소, 이후 쓰면 자동 증가
	for (uint8_t i = 0; i < n; i++) {
		Lcd_writeCharData(data[i]);
	}
}

// 화살표 4조각 모양을 frame만큼 흘린 위치로 다시 만든다 (화면의 화살표가 그 자리에서 바뀜)
static void loadArrowFrame(arrow_t dir, uint8_t frame)
{
	if (dir == loadedDir && frame == loadedFrame) {
		return;
	}
	uint8_t data[32]; // 좌상 8줄, 우상 8줄, 좌하 8줄, 우하 8줄 = CGRAM 4~7 순서

	for (uint8_t r = 0; r < 16; r++) {
		uint16_t row;
		if (dir == ARROW_UP) {
			row = arrowBmp[(r + frame) % 16];             // frame이 커질수록 위로 흐름
		}
		else {
			row = arrowBmp[15 - ((r + 16 - frame) % 16)]; // 뒤집은 화살표, 아래로 흐름
		}
		uint8_t half = (r < 8) ? 0 : 16; // 위 칸 / 아래 칸
		data[half + (r % 8)] = (row >> 5) & 0x1F;  // 왼쪽 5픽셀
		data[half + 8 + (r % 8)] = row & 0x1F;     // 오른쪽 5픽셀
	}
	loadChars(CH_ARROW, data, sizeof(data));
	loadedDir = dir;
	loadedFrame = frame;
}

static void showArrow(bool show)
{
	if (show == shownArrow) {
		return;
	}
	shownArrow = show;
	Lcd_gotoXY(0, ARROW_COL);
	Lcd_writeCharData(show ? CH_ARROW : ' ');
	Lcd_writeCharData(show ? CH_ARROW + 1 : ' ');
	Lcd_gotoXY(1, ARROW_COL);
	Lcd_writeCharData(show ? CH_ARROW + 2 : ' ');
	Lcd_writeCharData(show ? CH_ARROW + 3 : ' ');
}

static void showGlyph(char ch)
{
	if (ch == shownGlyph) {
		return;
	}
	for (uint8_t i = 0; i < sizeof(glyphs) / sizeof(glyphs[0]); i++) {
		if (glyphs[i].ch == ch) {
			for (uint8_t row = 0; row < 2; row++) {
				Lcd_gotoXY(row, DIGIT_COL);
				for (uint8_t c = 0; c < 3; c++) {
					Lcd_writeCharData(glyphs[i].cell[row * 3 + c]);
				}
			}
			shownGlyph = ch;
			return;
		}
	}
}

void display_init(I2C_HandleTypeDef *hi2c)
{
	Lcd_init(hi2c); // 화면 지움
	loadChars(B_TOP, blockTop, 8);
	loadChars(B_BOT, blockBot, 8);
	loadChars(B_TB, blockTB, 8);
	shownGlyph = 0;
	shownArrow = false;
	loadedDir = ARROW_NONE;
}

void display_task(void)
{
	static elev_state_t prevState = ELEV_HOMING;
	static arrow_t lastDir = ARROW_DOWN;
	static uint32_t frameTick = 0;
	static uint8_t frame = 0;
	static uint32_t blinkStart = 0;
	static bool blinking = false;

	uint32_t now = HAL_GetTick();
	elev_state_t st = elevator_getState();
	uint8_t floor = elevator_getFloor();

	// 큰 숫자
	char ch = (st == ELEV_ERROR) ? 'E' : (floor == 0) ? '-' : (char)('0' + floor);
	showGlyph(ch);

	// 화살표 방향
	arrow_t moving = ARROW_NONE;
	if (st == ELEV_MOVING_UP) moving = ARROW_UP;
	else if (st == ELEV_MOVING_DOWN || st == ELEV_HOMING) moving = ARROW_DOWN;

	if (st == ELEV_DOOR_OPEN && (prevState == ELEV_MOVING_UP || prevState == ELEV_MOVING_DOWN)) {
		blinking = true; // 방금 도착
		blinkStart = now;
	}
	prevState = st;

	if (moving != ARROW_NONE) {
		blinking = false;
		lastDir = moving;
		if (now - frameTick >= ARROW_FRAME_MS) {
			frameTick = now;
			frame = (frame + 1) % 16;
		}
		loadArrowFrame(moving, frame);
		showArrow(true);
	}
	else if (blinking && now - blinkStart < BLINK_TOTAL_MS) {
		loadArrowFrame(lastDir, ARROW_STILL_FRAME);
		showArrow(((now - blinkStart) / BLINK_MS) % 2 == 0);
	}
	else {
		blinking = false;
		showArrow(false);
	}
}
