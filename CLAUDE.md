# kccistc — repo guide for Claude Code

Verilog/SystemVerilog study + project repo. Owner works from **two machines** and
uses this GitHub repo (`taesoo222/kccistc`) as the single sync point.

## Layout

```
Project/              complete projects
study/Systemverilog/  SystemVerilog / UVM work
study/Verilog/        Verilog exercises
study/STM32/          STM32 (C, HAL) exercises — only .ioc + hand-written code
```

Each project folder tracks **only** hand-written sources:

```
<category>/<project>/
├── src/        design sources (.v/.sv)
├── sim/        testbenches (tb_*.sv)
└── constrs/    *.xdc constraints (when the project has any)
```

## Vivado projects live OUTSIDE this repo (Option B)

Actual Vivado projects (`.xpr`, `.srcs/`, `.cache/`, …) sit under a **workspace
root**, default `E:\work\2026_AI_COMP\<project>\`. They are **not** committed.
`.gitignore` drops `*.xpr` and every Vivado-generated dir.

`.xpr` is intentionally not tracked: it is machine-specific and churns on every
GUI action. Recreate the project locally (New Project → Add Sources pointing at
`src/ sim/ constrs/`) or from a `create_project.tcl` if one is added.

## Conventions

- Commit messages in English, imperative mood.
- Never commit Vivado build output or `.xpr`.
