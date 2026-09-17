# kccistc — repo guide for Claude Code

Verilog/SystemVerilog study + project repo. Owner works from **two machines** and
uses this GitHub repo (`taesoo222/kccistc`) as the single sync point.

## Layout

```
Project/              complete projects
study/Systemverilog/  SystemVerilog / UVM work
study/Verilog/        Verilog exercises
```

Each project folder tracks **only** hand-written sources:

```
<category>/<project>/
├── src/        design sources (.v/.sv)
├── sim/        testbenches (tb_*.sv)
└── constrs/    *.xdc constraints (when the project has any)
```

## Repo tooling: what's for whom

- **`.gitignore`** — read by `git`. Filters out everything Vivado's GUI
  generates locally (`*.srcs/`, `*.cache/`, `*.runs/`, `*.xpr`, `.jou`, `.log`,
  `.wdb`, …) plus OS junk, so none of it gets committed.
- **`CLAUDE.md`** (this file) — read by Claude Code at session start as
  project instructions, so it understands the layout and conventions below
  without being told each time.

## Vivado projects live OUTSIDE this repo (Option B)

Actual Vivado projects (`.xpr`, `.srcs/`, `.cache/`, …) sit under a **workspace
root**, default `E:\work\2026_AI_COMP\<project>\`. They are **not** committed.
`.gitignore` drops `*.xpr` and every Vivado-generated dir.

`.xpr` is intentionally not tracked: it is machine-specific and churns on every
GUI action. Recreate the project locally (New Project → Add Sources pointing at
`src/ sim/ constrs/`) or from a `create_project.tcl` if one is added.

## Sync workflow (manual)

No script — copy files by hand between the Vivado workspace and this repo.

```powershell
# start of a session
git pull --rebase
# copy src/ sim/ constrs/ from the repo project folder into the Vivado
# project's sources_1/ sim_1/ constrs_1/ (Add Sources for anything new)

# end of a session
# copy changed files back from sources_1/ sim_1/ constrs_1/ into
# the repo's src/ sim/ constrs/
git add -A && git commit -m "..." && git push
```

## Adding a new project

1. Create/keep the Vivado project under the workspace root.
2. Create `<category>/<project>/{src,sim,constrs}` in the repo and copy the
   matching sources in by hand.

## Conventions

- Commit messages in English, imperative mood.
- Never commit Vivado build output or `.xpr`.
