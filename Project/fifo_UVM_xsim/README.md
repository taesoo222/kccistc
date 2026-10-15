# Synchronous FIFO UVM Verification (Vivado xsim)

## Overview

A copy of [`../fifo_UVM`](../fifo_UVM) set up to run on the Vivado simulator
(xsim) instead of Synopsys VCS. The DUT and the UVM testbench are the same,
except for one constraint that had to be rewritten for xsim (see below).

Tested with Vivado 2020.2 on Windows (built-in UVM 1.2).

For the DUT, testbench architecture and test scenario, see the
[fifo_UVM README](../fifo_UVM/README.md).

## Project Structure

```
fifo_UVM_xsim/
├── src/
│   └── fifo_sv.sv              # same as fifo_UVM
├── sim/
│   └── tb_fifo_uvm.sv          # fifo_UVM testbench + xsim fix
└── scripts/
    └── create_project.tcl      # creates the Vivado project
```

The Vivado project itself is not committed. It is generated from the Tcl
script.

## How to Run

Create the project (from this folder):

```
vivado -mode batch -source scripts/create_project.tcl
```

Then open `fifo_uvm.xpr` in Vivado and run
**Run Simulation > Run Behavioral Simulation**.

The script sets these simulation options, so the run goes to the end by
itself:

| Option | Value |
|---|---|
| `xsim.compile.xvlog.more_options` | `-L uvm` |
| `xsim.elaborate.xelab.more_options` | `-L uvm` |
| `xsim.simulate.runtime` | `all` |
| `xsim.simulate.xsim.more_options` | `-testplusarg UVM_VERBOSITY=UVM_LOW` |

## Difference from fifo_UVM: dist constraint

The original sequence item puts the operation distribution on a
concatenation:

```systemverilog
constraint c_op_dist {
    {push, pop} dist {2'b10 := 4, 2'b01 := 4, 2'b11 := 1, 2'b00 := 1};
}
```

xvlog accepts this, but xelab in Vivado 2020.2 crashes on it with
`ERROR: [XSIM 43-3294] Signal EXCEPTION_ACCESS_VIOLATION received.`
Removing only this constraint makes the crash go away.

The fix puts the distribution on a separate `op` field and ties `push`/`pop`
to its bits. The 4 : 4 : 1 : 1 distribution is unchanged, and the inline
constraints in the directed sequences (`push == 1; pop == 0;` etc.) still
work.

```systemverilog
rand bit [1:0] op;

constraint c_op_dist {
    op dist {2'b10 := 4, 2'b01 := 4, 2'b11 := 1, 2'b00 := 1};
    push == op[1];
    pop == op[0];
}
```

## Result

| Item | Result |
|---|---|
| UVM_ERROR / UVM_FATAL | 0 / 0 |
| Flag pass / fail | 10034 / 0 |
| Data pass / fail | 4336 / 0 |
| Skip | 101 (100 reset cycles + the first X cycle) |
| Functional coverage (overall, op, wdata, rdata, cross) | 100 % |

Simulation ends at 51175 ns.

## Notes

- The testbench file has a `timescale` but the UVM package does not. The
  Vivado flow passes `--relax`, which turns this into a warning. If you run
  xelab by hand, add `--relax` as well.
- The `FSDB` dump block is inside `` `ifdef FSDB `` and is not compiled in
  Vivado. Use the Vivado waveform window instead.
