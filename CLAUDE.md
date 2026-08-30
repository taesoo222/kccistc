# kccistc — repo guide for Claude Code

Verilog/SystemVerilog study + project repo. Owner works from **two machines** and
uses this GitHub repo (`taesoo222/kccistc`) as the single sync point.

## Layout

```
Project/              complete projects
study/Systemverilog/  SystemVerilog / UVM work
study/Verilog/        Verilog exercises
scripts/              sync tooling
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
`.gitignore` drops `*.xpr` and every Vivado-generated dir. On the other machine
the workspace root may differ — set it once in
`scripts/workspace-root.local` (git-ignored) or pass `-WorkspaceRoot`.

`.xpr` is intentionally not tracked: it is machine-specific and churns on every
GUI action. Recreate the project locally (New Project → Add Sources pointing at
`src/ sim/ constrs/`) or from a `create_project.tcl` if one is added.

## Sync workflow

`scripts/sync.ps1` copies sources between a Vivado project and this repo,
using the map in `scripts/projects.json` (`{ "vivado": <folder>, "repo": <category/project> }`).

```powershell
# start of a session
git pull --rebase
.\scripts\sync.ps1 pull                 # repo -> Vivado workspace

# end of a session
.\scripts\sync.ps1 push                 # Vivado workspace -> repo
git add -A && git commit -m "..." && git push
```

- `push` flattens `sources_1/** → src/`, `sim_1/** → sim/`, `constrs_1/**.xdc → constrs/`.
- `pull` overwrites each repo file at its existing path inside the Vivado
  project; a file that exists only in the repo lands in `<area>/new/` and needs
  **Add Sources** in Vivado.
- `push` refuses to overwrite real repo code with a freshly-created empty Vivado
  template (wrong-direction guard); `-Force` overrides. `-DryRun` previews.
  `-Mirror` also removes files deleted on the other side.

## Adding a new project

1. Create/keep the Vivado project under the workspace root.
2. Add a line to `scripts/projects.json`.
3. `.\scripts\sync.ps1 push -Project <name>` then commit.

## Conventions

- Commit messages in English, imperative mood.
- Never commit Vivado build output or `.xpr`.
