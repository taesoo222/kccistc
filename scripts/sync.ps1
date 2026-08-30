<#
================================================================================
  sync.ps1  -  Vivado <-> git repo source sync   (Option B)

  Vivado projects stay under the workspace root (default E:\work\2026_AI_COMP).
  This repo tracks only  <category>/<project>/src , /sim , /constrs .

  USAGE
    .\scripts\sync.ps1 push            # Vivado  -> repo   (then: git add/commit/push)
    .\scripts\sync.ps1 pull            # repo    -> Vivado  (after: git pull)
    .\scripts\sync.ps1 push -Project counter_sv
    .\scripts\sync.ps1 pull  -DryRun            # show what would change, do nothing
    .\scripts\sync.ps1 push -Mirror            # also delete repo files removed in Vivado
    .\scripts\sync.ps1 push -Force             # overwrite repo even from an empty Vivado template

  SAFETY: 'push' refuses to replace real repo code with a freshly-created,
  never-edited Vivado source template (guards against a wrong-direction run on a
  brand-new project). Use 'pull' to populate the new project first.

  Mapping lives in scripts\projects.json.  Add a project = add one entry there.
  Per-PC override of the workspace path: put the path in
    scripts\workspace-root.local   (git-ignored)   or pass -WorkspaceRoot.

  Direction memo (matches git):  push = send my work out,  pull = bring work in.
================================================================================
#>
#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateSet('push', 'pull')]
    [string]$Mode,

    [string]$Project = '*',
    [string]$WorkspaceRoot,
    [switch]$Mirror,
    [switch]$DryRun,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent $scriptDir

# ---- config -------------------------------------------------------------------
$cfgPath = Join-Path $scriptDir 'projects.json'
if (-not (Test-Path $cfgPath)) { throw "Missing config: $cfgPath" }
$cfg = Get-Content $cfgPath -Raw | ConvertFrom-Json

if (-not $WorkspaceRoot) {
    $localFile = Join-Path $scriptDir 'workspace-root.local'
    if (Test-Path $localFile) { $WorkspaceRoot = (Get-Content $localFile -Raw).Trim() }
}
if (-not $WorkspaceRoot) { $WorkspaceRoot = $cfg.workspaceRootDefault }
if (-not (Test-Path $WorkspaceRoot)) {
    throw "Workspace root not found: $WorkspaceRoot`n  -> create scripts\workspace-root.local with the correct path, or pass -WorkspaceRoot"
}

$srcExt = @('.v', '.sv', '.svh', '.vh', '.vhd', '.vhdl')

# repo-dir  <->  Vivado .srcs subtree
$areas = @(
    [pscustomobject]@{ repo = 'src'    ; vivado = 'sources_1' ; ext = $srcExt },
    [pscustomobject]@{ repo = 'sim'    ; vivado = 'sim_1'     ; ext = $srcExt },
    [pscustomobject]@{ repo = 'constrs'; vivado = 'constrs_1' ; ext = @('.xdc') }
)

# ---- helpers ----------------------------------------------------------------
function Get-SrcsDir([string]$vivadoName) {
    $projDir = Join-Path $WorkspaceRoot $vivadoName
    if (-not (Test-Path $projDir)) { throw "Vivado project folder missing: $projDir" }
    $srcs = Get-ChildItem -Path $projDir -Directory -Filter '*.srcs' -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $srcs) { throw "No *.srcs folder under $projDir  (open the project in Vivado and save it once)" }
    return $srcs.FullName
}

function Get-Files([string]$baseDir, [string[]]$extensions) {
    if (-not (Test-Path $baseDir)) { return @() }
    Get-ChildItem -Path $baseDir -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $extensions -contains $_.Extension.ToLower() }
}

function Test-SameContent([string]$a, [string]$b) {
    if (-not (Test-Path $b)) { return $false }
    (Get-FileHash -Algorithm SHA1 -LiteralPath $a).Hash -eq (Get-FileHash -Algorithm SHA1 -LiteralPath $b).Hash
}

function Test-VivadoStub([string]$path) {
    # a freshly created, never-edited Vivado source template
    if (-not (Test-Path $path)) { return $false }
    $t = Get-Content -LiteralPath $path -Raw
    if ($t -notmatch 'Revision 0\.01 - File Created') { return $false }
    # module body still empty:  module foo(  ...  ); endmodule   with nothing between ) and endmodule
    return ($t -match '(?s)module\s+\w+\s*\([^)]*\)\s*;\s*endmodule')
}

function Copy-File([string]$from, [string]$to) {
    if (Test-SameContent $from $to) { return 'same' }
    if ($DryRun) { return 'would-copy' }
    $dir = Split-Path -Parent $to
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    Copy-Item -LiteralPath $from -Destination $to -Force
    return 'copied'
}

# ---- run ------------------------------------------------------------------
$selected = $cfg.projects | Where-Object {
    $Project -eq '*' -or $_.vivado -eq $Project -or $_.repo -eq $Project -or
    ($_.repo.Split('/')[-1]) -eq $Project
}
if (-not $selected) { throw "No project matched '$Project' in projects.json" }

$arrow = if ($Mode -eq 'push') { 'Vivado workspace  --->  git repo' } else { 'git repo  --->  Vivado workspace' }
Write-Host ""
Write-Host "=== SYNC ($Mode) : $arrow ===" -ForegroundColor Cyan
Write-Host "    workspace : $WorkspaceRoot"
Write-Host "    repo      : $repoRoot"
if ($DryRun) { Write-Host "    DRY RUN - no files will be written" -ForegroundColor Yellow }
Write-Host ""

$touched = 0
$warnNew = 0

foreach ($p in $selected) {
    $srcsDir = Get-SrcsDir $p.vivado
    $repoProj = Join-Path $repoRoot ($p.repo.Replace('/', '\'))
    Write-Host ("[{0}]  <->  {1}" -f $p.vivado, $p.repo) -ForegroundColor Green

    foreach ($area in $areas) {
        $repoDir = Join-Path $repoProj $area.repo
        $vivDir = Join-Path $srcsDir $area.vivado

        if ($Mode -eq 'push') {
            # Vivado -> repo  (flatten every matching file into repo\<area>)
            $files = Get-Files $vivDir $area.ext
            $seen = @{}
            foreach ($f in $files) {
                if ($seen.ContainsKey($f.Name)) {
                    if (-not (Test-SameContent $f.FullName $seen[$f.Name])) {
                        Write-Warning "  name clash on flatten: $($area.repo)/$($f.Name)  ($($f.FullName)  vs  $($seen[$f.Name])) - kept first, skipped this one"
                    }
                    continue
                }
                $seen[$f.Name] = $f.FullName
                $dst = Join-Path $repoDir $f.Name
                if (-not $Force -and (Test-Path $dst) -and (Test-VivadoStub $f.FullName) -and -not (Test-VivadoStub $dst)) {
                    Write-Warning "  SKIP $($area.repo)/$($f.Name): Vivado side is an empty template, repo has real code. Run 'pull' to fill Vivado, or pass -Force to overwrite the repo."
                    continue
                }
                $r = Copy-File $f.FullName $dst
                if ($r -ne 'same') { Write-Host "    [$r] $($area.repo)/$($f.Name)"; $touched++ }
            }
            if ($Mirror -and (Test-Path $repoDir)) {
                foreach ($old in Get-ChildItem $repoDir -File) {
                    if (-not $seen.ContainsKey($old.Name)) {
                        if ($DryRun) { Write-Host "    [would-remove] $($area.repo)/$($old.Name)" -ForegroundColor Yellow }
                        else { Remove-Item $old.FullName -Force; Write-Host "    [removed] $($area.repo)/$($old.Name)" -ForegroundColor Yellow }
                        $touched++
                    }
                }
            }
        }
        else {
            # repo -> Vivado  (overwrite the existing file wherever it sits; new files land in <area>\new)
            if (-not (Test-Path $repoDir)) { continue }
            $existing = @{}
            if (Test-Path $vivDir) {
                foreach ($e in (Get-ChildItem $vivDir -Recurse -File)) {
                    if (-not $existing.ContainsKey($e.Name)) { $existing[$e.Name] = $e.FullName }
                }
            }
            $repoNames = @()
            foreach ($f in Get-ChildItem $repoDir -File) {
                $repoNames += $f.Name
                if ($existing.ContainsKey($f.Name)) {
                    $r = Copy-File $f.FullName $existing[$f.Name]
                    if ($r -ne 'same') { Write-Host "    [$r] $($existing[$f.Name].Substring($srcsDir.Length + 1))"; $touched++ }
                }
                else {
                    $dst = Join-Path (Join-Path $vivDir 'new') $f.Name
                    $r = Copy-File $f.FullName $dst
                    if ($r -ne 'same') {
                        Write-Host "    [$r] $($area.vivado)/new/$($f.Name)" -ForegroundColor Magenta
                        Write-Warning "  NEW FILE - open Vivado and 'Add Sources' for $($f.Name), or it will not be compiled/simulated"
                        $touched++; $warnNew++
                    }
                }
            }
            if ($Mirror) {
                foreach ($kv in $existing.GetEnumerator()) {
                    if ($repoNames -notcontains $kv.Key -and ($area.ext -contains ([IO.Path]::GetExtension($kv.Key).ToLower()))) {
                        Write-Warning "  STALE in Vivado (gone from repo): $($kv.Value)  - remove it from the Vivado project manually"
                        if (-not $DryRun) { Remove-Item $kv.Value -Force }
                    }
                }
            }
        }
    }
}

Write-Host ""
if ($touched -eq 0) {
    Write-Host "Nothing to sync - already identical." -ForegroundColor Green
}
elseif ($Mode -eq 'push') {
    Write-Host "$touched file(s) updated in the repo. Review and commit:" -ForegroundColor Cyan
    Write-Host ""
    & git -C $repoRoot status --short
    Write-Host ""
    Write-Host "    git -C `"$repoRoot`" add -A" -ForegroundColor DarkGray
    Write-Host "    git -C `"$repoRoot`" commit -m `"...`"" -ForegroundColor DarkGray
    Write-Host "    git -C `"$repoRoot`" push" -ForegroundColor DarkGray
}
else {
    Write-Host "$touched file(s) updated in the Vivado workspace." -ForegroundColor Cyan
    if ($warnNew -gt 0) { Write-Host "$warnNew new file(s) need 'Add Sources' in Vivado (see warnings above)." -ForegroundColor Yellow }
    Write-Host "Open the project in Vivado and re-run synthesis/simulation." -ForegroundColor DarkGray
}
Write-Host ""
