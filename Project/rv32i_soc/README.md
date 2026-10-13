# RV32I CPU

## What is RV32I?

**RV32I** is the **32-bit base integer** instruction set of the RISC-V instruction set architecture (ISA).
RISC-V is an open ISA, and RV32I is its most fundamental, mandatory instruction subset, with the following characteristics:

- 32 registers (x0–x31, 32-bit each); x0 is hardwired to zero
- Fixed 32-bit instruction length, with 6 encoding formats (R/I/S/B/U/J-type)
- Load/store architecture: memory is accessed only through dedicated instructions such as `lw`/`sw`
- Supports arithmetic/logical operations (R-type), immediate operations (I-type), branches (B-type), jumps (J-type), and upper-immediate loads (U-type)

This project implements a CPU that processes RV32I instructions in SystemVerilog, and controls peripherals (such as GPI,GPO,GPIO<Not Yet>,UART<Not Yet>) over an APB bus.

## Project Structure

```
rv32i/
├── src/
│   ├── rv32i_cpu.sv          # rv32i_top, rv32i_cpu modules (connects control_unit + datapath)
│   ├── control_unit.sv       # FSM-based control unit (FETCH/DECODE/EXECUTE/MEM/WB)
│   ├── datapath.sv           # Register file, ALU, PC, and other datapath logic
│   ├── rv32i_pkg.sv          # Package defining opcode/instruction enum types
│   ├── define.svh            # Macro definitions for R-type/B-type instructions
│   ├── instruction_rom.sv    # Instruction ROM
│   ├── apb_requester.sv      # CPU <-> APB bus bridge (APB Master)
│   ├── apb_bram.sv           # APB slave - BRAM (data memory)
│   ├── apb_gpi.sv            # APB slave - General Purpose Input
│   ├── apb_gpo.sv            # APB slave - General Purpose Output
│   ├── rom_code_apb_gpi_gpo.mem   # Instruction code for GPI/GPO testing
│   └── rom_code_sw_sumtest.mem    # Instruction code for addition test
└── sim/
    ├── tb_rv32i.sv           # Basic testbench
    └── tb_rv32i_uvm.sv       # UVM-based testbench
```

## Architecture

- **CPU design**: Multi-cycle. The FSM in `control_unit` transitions through `FETCH -> DECODE -> EXECUTE -> (MEM) -> (WB)` to process each instruction.
- **Bus structure**: The CPU accesses memory/peripherals over the APB (Advanced Peripheral Bus) protocol via `apb_requester`. In `rv32i_top`, BRAM, GPI, and GPO are connected as APB slaves.
- **Supported instruction types** (from `rv32i_pkg.sv`):
  - R-type: `ADD SUB SLL SLT SLTU XOR SRL SRA OR AND`
  - I-type (ALU): same ALU operations as R-type, with an immediate operand
  - I-type (load): memory loads such as `lw`
  - S-type: memory stores such as `sw`
  - B-type: `BEQ BNE BLT BGE BLTU BGEU`
  - U-type: `LUI`, `AUIPC`
  - J-type: `JAL`, `JALR`

## Simulation

- `sim/tb_rv32i.sv`: standard SystemVerilog testbench
- `sim/tb_rv32i_uvm.sv`: UVM-based testbench
- `src/rom_code_sw_sumtest.mem`, `src/rom_code_apb_gpi_gpo.mem`: instruction ROM images used during simulation
