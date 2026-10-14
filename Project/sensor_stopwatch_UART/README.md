# Sensor + Stopwatch/Watch + UART

## Overview

A Basys-3 (Artix-7, 100 MHz) design in Verilog that combines a **watch**, a
**stopwatch**, a **DHT11** temperature/humidity sensor, and an **HC-SR04**
ultrasonic distance sensor. Values are shown on the 4-digit 7-segment display
(FND), and everything can be controlled either by the board buttons or by
ASCII commands over **UART** (9600 baud, 8N1). The `/get` command sends the
currently displayed value back over UART.

## Project Structure

```
sensor_stopwatch_UART/
└── src/
    ├── top_merge.v             # Top module: connects all blocks
    ├── btn_debounce.v          # btn_debouncer: 1 kHz sampling, 16-tap shift register + rising-edge pulse
    ├── control_unit.v          # Main FSM (16 states): watch / stopwatch / sensor modes
    ├── watch_data_path.v       # Watch counters (time_counter) + tick_gen_100hz
    ├── stopwatch_data_path.v   # Stopwatch up/down counters (time_counter_stopwatch)
    ├── dht11.v                 # DHT11 single-wire protocol FSM + edge_detection filter
    ├── sr04.v                  # HC-SR04 trigger / echo-width measurement FSM
    ├── data_selector.v         # Picks the display mode, FND time source, and the value for /get
    ├── fnd_controller.v        # 7-segment scan, digit split, BCD → segment decode
    ├── uart_controller.v       # UART RX + RX FIFO
    ├── uart_ascii_decoder.v    # ASCII command parser (single chars and /get, /dht, /sr)
    ├── uart_sender.v           # Converts a value to 4 ASCII digits + LF, TX FIFO, UART TX
    └── uart_common.v           # Shared by RX/TX: baud_tick_x16, fifo, register_file, fifo_control_unit
```

## Architecture

```
top_merge
├── btn_debouncer x4                         (btnL / btnR / btnU / btnD)
├── uart_controller                          rx ─> uart_rx ─> fifo (4 bytes)
│     └── uart_ascii_decoder                 bytes ─> 1-cycle command pulses
├── control_unit                             buttons + UART commands + sw[3:0] ─> control pulses
├── watch_data_path      ── tick_gen_100hz ─> time_counter x4      (cc / sec / min / hour)
├── stopwatch_data_path  ── tick_gen_100hz ─> time_counter_stopwatch x4
├── dht11                                    dht11_io (inout) ─> humidity, temperature
├── sr04_controller                          trigger / echo ─> distance (cm)
├── data_selector                            sw ─> display_mode, FND time, /get value
├── fnd_controller                           fnd_com, fnd_data
└── uart_sender                              /get ─> "dddd\n" ─> fifo (4 bytes) ─> uart_tx ─> tx
```

- **Control / datapath split**: `control_unit` is the only FSM that decides
  what happens. Buttons and UART commands are OR-ed into the same
  transitions, so both inputs behave the same way.
- **Time base**: `tick_gen_100hz` divides 100 MHz by 1,000,000 (10 ms tick).
  The cascaded counters run cc (0–99) → sec → min → hour (0–23).
- **UART**: 16× oversampling (`baud_tick_x16`, 100 MHz / (9600 × 16)). RX
  samples each bit at mid-point. RX and TX each have a 4-entry FIFO.
- **DHT11**: drives the line low for 19 ms, releases it, waits for the
  sensor's response, then reads 40 bits. A bit is `1` if its high pulse lasts
  ≥ 40 µs. Humidity and temperature update only when the checksum matches.
  The line goes through a 2-FF synchronizer and a 4-sample glitch filter.
- **HC-SR04**: sends a ~11 µs trigger pulse and counts the echo high time in
  58 µs units (= 1 cm). Measurements above 399 cm are discarded.

## Controls

### Mode selection

`control_unit` checks `sw[0]` → `sw[1]` → `sw[2]` → `sw[3]` in that order
when leaving the watch state. With all four off, it stays in watch mode.

| Switch | Mode | FND shows |
|---|---|---|
| all off | Watch | `SS.cc` (`HH.MM` if `sw[15] = 1`) |
| `sw[0]` | Stopwatch | Stopwatch `SS.cc` (`HH.MM` if `sw[15] = 1`) |
| `sw[1]` | DHT11 temperature | `TT°c` |
| `sw[2]` | DHT11 humidity | `HH H` (two digits, blank, `H`) |
| `sw[3]` | HC-SR04 distance | `dddd` (cm) |

The dot blinks once per second, driven by the selected time source's cc
value.

### Buttons and UART commands

| Mode | Button | UART | Action |
|---|---|---|---|
| Watch | btnL | `H` | Hour +1 (or −1) |
| | btnU | `M` | Minute +1 (or −1) |
| | btnR | `S` | Second +1 (or −1) |
| | btnD | `W` | Toggle adjust direction (up ↔ down) |
| Stopwatch (stopped) | btnL | `r` | Run |
| | btnR | `c` | Clear |
| | btnU | `m` | Toggle up / down counting |
| | btnD | — | `OPTION` state, currently no function |
| Stopwatch (running) | btnL | `s` | Stop |
| Temperature / humidity | btnL | `/dht` | Start a DHT11 measurement |
| Distance | btnL | `/sr` | Start an HC-SR04 measurement |
| Any | — | `/get` | Send the displayed value as 4 ASCII digits + LF |

`/get` payload by display mode: `SS.cc` → `sec*100 + cc`, `HH.MM` →
`hour*100 + min`, temperature / humidity → integer part, distance → cm.
For example, 12.34 s is sent as `1234\n`.

## Simulation

No testbenches are included for this project yet.
