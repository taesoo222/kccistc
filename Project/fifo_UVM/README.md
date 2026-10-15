# Synchronous FIFO UVM Verification

## Overview

A 16 x 8-bit synchronous FIFO written in SystemVerilog, verified with a UVM 1.2
testbench. Simulation runs on Synopsys VCS, and waveforms and coverage are
checked in Verdi.

## Project Structure

```
fifo_UVM/
├── src/
│   └── fifo_sv.sv        # fifo_sv (top), fifo_control_unit, registerfile_sv
├── sim/
│   └── tb_fifo_uvm.sv    # interface, UVM components, test, tb top
└── Makefile
```

## DUT

`fifo_sv` is split into `fifo_control_unit`, which handles the pointers and
the full/empty flags, and `registerfile_sv`, an 8-bit x 16 memory.

- Depth is set by the `WIDTH` parameter (`WIDTH = 4` gives 16 entries).
- Reset is synchronous, active-low.
- Read is combinational (`rdata = mem[rptr]`), so the head entry is visible
  before a pop (first-word fall-through).
- Instead of an extra pointer bit, full and empty are kept as separate
  registers and updated by comparing the next pointer value.
- On a simultaneous push and pop, only the pop happens when full, only the
  push happens when empty, and both happen otherwise.

## Testbench Architecture

```
fifo_test
└── fifo_environment
    ├── fifo_agent
    │   ├── sequencer
    │   ├── fifo_driver    -> fifo_if (drv_cb, negedge)
    │   └── fifo_monitor   <- fifo_if (mon_cb, posedge)
    ├── fifo_scoreboard    <- monitor
    └── fifo_coverage      <- monitor
```

- The scoreboard keeps a reference model as a `bit [7:0] q[$]` queue and
  compares full, empty, and rdata every cycle.
- Coverage collects push/pop combinations, full/empty states, and their cross.
  It also checks that every wdata/rdata value from 0 to 255 has been seen.
- The interface has an assertion that full and empty are never 1 at the same
  time.

### Driver / monitor timing

The driver applies values 1 ns after the negedge, and the monitor samples just
before the posedge (`#1step`), so the two are half a cycle apart. Each monitor
sample therefore holds the inputs for the coming edge together with the DUT
state before that edge. The scoreboard compares first and then updates its
queue, which follows the same order as the DUT.

## Test Scenario

`fifo_test` runs the sequences in this order:

1. Reset for 5 cycles.
2. 32 push-only cycles (twice the depth) to reach full and check that
   overflow is blocked, then 5 push+pop cycles.
3. 32 pop-only cycles to reach empty and check that underflow is blocked,
   then 5 push+pop cycles.
4. Fill the FIFO again and reset it while it holds data.
5. 5000 random cycles (push : pop : both : idle = 4 : 4 : 1 : 1, with a 2%
   chance of reset in the middle).

Steps 2 to 4 force corner cases that random stimulus rarely hits. Step 5
covers normal operation and mid-run resets.

## Troubleshooting: X on the first cycle

The first runs showed one assertion error right after the simulation
started, and the scoreboard skip count did not match the number of resets
the driver had applied.

The cause was the first posedge (5 ns). The driver applies values through the
clocking block at negedge + 1 ns, so nothing had been driven yet at the first
posedge and rst_n, push, and pop were all X. The assertion used
`disable iff (!rst_n)`. When rst_n is X, `!rst_n` is also X, so the assertion
was not disabled and it checked X values of full/empty.

The fix:

- Assertion: `disable iff (!rst_n || $isunknown(rst_n))` to exclude the X period.
- Scoreboard: `rst_n !== 1'b1` (4-state compare), so an X cycle is skipped like
  a reset cycle.

Because of this, the scoreboard skip count is one more than the driver's reset
count. The extra skip is the first X cycle, and this is expected.

## How to Run

Run on a Linux server with VCS and Verdi installed.

```bash
make            # compile + simulate
make compile    # compile only
make sim        # simulate only (sim.log)
make verdi      # waveform (wave.fsdb)
make cov        # coverage GUI
make urg        # text coverage report (urgReport/)
make clean
```

`make sim VERBOSITY=UVM_LOW` gives a shorter log, and `make compile FSDB=0`
turns off the waveform dump.

## Limitations

- The driver does not return the signals to idle between items, so the last
  push/pop values stay on the pins between sequences. Results are not
  affected because the monitor reads the actual pins, but it can be confusing
  in the waveform.
- Coverage also samples reset cycles, so some cross bins are filled by the
  reset sequence. Excluding reset cycles would give a more accurate number.
- The data width is fixed at 8 bits. Making it a `DATA_WIDTH` parameter would
  make the design easier to reuse.
