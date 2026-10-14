# Stopwatch / Watch

## Overview

A digital **watch** and a **stopwatch / countdown timer** for the Basys-3 board
(Artix-7, 100 MHz clock), written in Verilog. Both run at the same time; a
switch picks which one is shown on the 4-digit 7-segment display (FND) and
which one the buttons control.

- **Watch**: free-running HH:MM:SS.cc clock (cc = 1/100 s) with a setting mode
  to adjust hours, minutes, and seconds up or down.
- **Stopwatch**: run / stop / clear, up- or down-counting.
- **Timer**: loads a preset value, counts down to zero, then lights an LED for 1 s.

## Project Structure

```
stopwatch_watch/
├── src/
│   ├── top_stopwatch_watch.v      # Top module + mux_8x4 (watch / stopwatch display select)
│   ├── btn_debounce.v             # 1 kHz sampling, 16-tap shift-register debounce + rising-edge pulse
│   ├── watch_control_unit.v       # Watch FSM (DEFAULT / SET / MIN / MODE / HOUR / SEC)
│   ├── watch_datapath.v           # Watch counters (time_counter) + tick_gen_100hz
│   ├── stopwatch_control_unit.v   # Stopwatch/timer FSM (8 states) + alarm_led_1s
│   ├── stopwatch_datapath.v       # Up/down counters (sw_time_counter) + alarm_set_unit
│   └── fnd_controller.v           # 7-segment scan, BCD decode, dot and set-mode blinking
└── sim/
    ├── README.md                  # Per-testbench notes
    └── tb_*.v                     # Testbenches
```

## Architecture

```
top_stopwatch_watch
├── btn_debounce x4            (btn_L / btn_R / btn_U / btn_D)
├── watch_control_unit ──> watch_datapath
│                            ├── tick_gen_100hz
│                            └── time_counter x4      (cc / sec / min / hour)
├── stopwatch_control_unit ──> stopwatch_datapath
│     └── alarm_led_1s          ├── alarm_set_unit
│                               ├── tick_gen_100hz
│                               └── sw_time_counter x4 (cc / sec / min / hour)
├── mux_8x4                    (sw[1] selects watch or stopwatch time)
└── fnd_controller
      ├── clk_div (1 kHz) -> counter_8 -> decoder_2x4   (digit scan)
      ├── digit_splitter x4, mux_8x1 x2, mux_2x1, bcd    (digit values)
      └── comparator_dot, blink_gen                      (dot / field blink)
```

- **Control / datapath split**: each function has an FSM-based control unit
  that turns debounced button pulses into 1-cycle control signals, and a
  datapath of cascaded counters (100 Hz tick → cc → sec → min → hour).
- **Time base**: `tick_gen_100hz` divides 100 MHz by 1,000,000 to produce a
  1-cycle tick every 10 ms.
- **Display**: `fnd_controller` scans the 4 digits at 1 kHz. `sw[0]` chooses
  `SS.cc` or `HH.MM`. The dot blinks once per second (lit while cc ≥ 50) and
  stays lit while the watch is in setting mode.

## Board Controls (Basys-3)

| Input / Output | Pin | Function |
|---|---|---|
| `reset` | btnC (U18) | Asynchronous reset |
| `sw[1]` | SW1 | `1` = watch, `0` = stopwatch / timer |
| `sw[0]` | SW0 | Display `0` = `SS.cc`, `1` = `HH.MM` |
| `sw[3]` | SW3 | Watch setting mode (when `sw[1] = 1`) |
| `sw[2]` | SW2 | Timer preset mode (when `sw[1] = 0`) |
| `led[0]` | LD0 | Always on |
| `led[1]` | LD1 | On while the watch is selected |
| `led[2]` | LD2 | On for 1 s when the timer reaches 0 |
| `led[3]` | LD3 | Always off |

### Watch (`sw[1] = 1`)

| `sw[3]` | Button | Action |
|---|---|---|
| 0 | — | Normal running, buttons ignored |
| 1 | btnU | Minute +1 (or −1) |
| 1 | btnL | Hour +1 (or −1) |
| 1 | btnR | Second +1 (or −1) |
| 1 | btnD | Toggle adjust direction (up ↔ down) |

The watch keeps running while it is being adjusted.

### Stopwatch / Timer (`sw[1] = 0`)

| Mode | Button | Action |
|---|---|---|
| Stopwatch (`sw[2] = 0`) | btnL | Run / stop |
| | btnR | Clear (while stopped) |
| | btnU | Toggle up / down counting (while stopped) |
| | btnD | Start timer: load preset and count down. Press again to return to the stopwatch (cleared) |
| Timer running | btnL / btnR / btnU | Ignored |
| Timer preset (`sw[2] = 1`) | btnL / btnR | Select left / right field (selected field blinks) |
| | btnU / btnD | Increment / decrement the selected field |
| | `sw[0]` | Field pair: `SS.cc` or `HH.MM` |

- Entering preset mode resets the preset to `00:00:00.00`.
- Leaving preset mode (`sw[2]` 1 → 0) clears the stopwatch display; the
  preset value is kept for the next timer start.
- Preset mode cannot be entered while the timer is active.
- When the countdown reaches 0, the timer stops, holds the display, and lights
  LD2 for 1 s.

## Simulation

Testbenches are in `sim/`. See [`sim/README.md`](sim/README.md) for what each
one covers and how to shorten the 100 Hz tick for faster runs.
