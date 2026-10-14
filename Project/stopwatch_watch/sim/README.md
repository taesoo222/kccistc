# Simulation testbenches

Testbenches exported as-is from the Vivado project (`sim_1/new/`).
All five compile against the current `src/` (checked with Icarus Verilog
`iverilog -g2012`).

> **Timing note** — `src/` now uses board timing (100 MHz clock):
> `tick_gen_100hz` ticks every 1,000,000 cycles (10 ms) and `btn_debounce`
> samples at 1 kHz, so a button must be held ~16 ms to register.
> Some of these testbenches were written when both were set to
> simulation speed (tick every cycle, no debounce divider), so they no longer
> show meaningful activity in their short run time. To speed up a run without
> touching `src/`, override the tick count from the testbench:
>
> ```verilog
> defparam dut.U_WATCH_DATAPATH.U_TICK_GEN_100hz.F_COUNT = 10;
> ```

## Files

| Testbench | DUT | What it does | Status |
|---|---|---|---|
| `tb_debounce.v` | `btn_debounce` | Holds `i_btn` high for 16 ms, then releases | Works with board timing: `o_btn` pulses once at ~15.5 ms |
| `tb_watch.v` | `top_stopwatch_watch` | `sw = 4'b1011` (watch view, set mode), presses `btn_U` for 160 ns | Written for simulation-speed timing; 160 ns is far below the 16 ms debounce window, so no button event reaches the FSM. `sw[3]` is X for the first 20 ns |
| `tb_datapath.v` | `watch_datapath` | Initializes inputs only | `reset` is set to 1 twice and never released, and there is no `$stop`/`$finish`, so the counters stay at 0 and the run never ends on its own |
| `tb_watch_datapath.v` | `watch_datapath` | Same DUT and setup as `tb_datapath.v`, releases reset | Calls `$stop` right after reset release (t = 10 ns), so no counting is observed |
| `tb_fnd_controller.v` | — | Empty Vivado template | No DUT, no stimulus |

## Running

Vivado: add `src/*.v` as design sources and the chosen `sim/tb_*.v` as a
simulation source, set it as top, then *Run Behavioral Simulation*.

Icarus Verilog:

```sh
iverilog -g2012 -s tb_debounce -o tb_debounce.vvp sim/tb_debounce.v src/*.v
vvp tb_debounce.vvp
```
