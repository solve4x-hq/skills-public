<#
.SYNOPSIS
  Keep every AI coding tool's skills folder pointing at your skills repos, so you edit a
  skill once (in git) and Claude Code, Cursor, Codex, Devin and Grok all see it.

.DESCRIPTION
  1. With -Pull, runs `git pull --ff-only` in each source repo first.
  2. Links each skill folder (a folder holding SKILL.md) from -Sources into every user-level
     skills folder below, as a directory junction (no admin rights needed). Edits to the repo
     show up immediately; nothing is copied.
  3. Removes links it made earlier whose skill no longer exists. Never touches real folders.
  4. For each -Projects repo, links <repo>/.claude/skills to <repo>/.agents/skills (Claude Code
     doesn't read .agents/skills) and hides that link from git via .git/info/exclude. Grok skips
     git-ignored skill folders, so project skills reach Grok through its config.toml instead.
  5. With -Schedule, registers a per-user scheduled task that runs this again (with -Pull)
     at sign-in and every few hours.

  Where each tool looks (user level):
    ~/.agents/skills             Cursor, Codex
    ~/.claude/skills             Claude Code, Grok (Cursor also reads it)
    %APPDATA%\devin\skills       Devin CLI on Windows
    ~/.codeium/windsurf/skills   Devin desktop / Windsurf
  In a repo: .agents/skills is read by Cursor, Codex and Devin.

  When two sources have a skill with the same name, the first source wins.

.EXAMPLE
  .\tools\sync-skills.ps1 -Sources D:\src\skills\skills, D:\src\skills-public\skills -Projects D:\src\app -Pull
  .\tools\sync-skills.ps1 -Sources D:\src\skills\skills -Pull -Schedule
#>
param(
  [Parameter(Mandatory)][string[]]$Sources,
  [string[]]$Projects = @(),
  [string[]]$Targets = @(
    (Join-Path $HOME '.agents\skills'),
    (Join-Path $HOME '.claude\skills'),
    (Join-Path $env:APPDATA 'devin\skills'),
    (Join-Path $HOME '.codeium\windsurf\skills')
  ),
  [string]$ProjectsFile,            # a list of project folders, one per line ("# comments" and a trailing " public" allowed)
  [string]$GrokConfig = (Join-Path $HOME '.grok\config.toml'),
  [switch]$Pull,
  [switch]$Schedule,
  [int]$EveryHours = 3
)
$ErrorActionPreference = 'Stop'
# `pwsh -File` (the scheduled task) passes a list as one comma-joined string; split it back.
$Sources = $Sources -split ',' | Where-Object { $_ } | ForEach-Object { (Resolve-Path $_.Trim()).Path.TrimEnd('\') }
$Projects = @($Projects -split ',' | Where-Object { $_ } | ForEach-Object { $_.Trim() })
if ($ProjectsFile -and (Test-Path $ProjectsFile)) {
  $Projects += Get-Content $ProjectsFile | Where-Object { $_.Trim() -and -not $_.TrimStart().StartsWith('#') } |
    ForEach-Object { ($_ -replace '\spublic\s*$', '').Trim() }
}
$Projects = @($Projects | Select-Object -Unique | Where-Object { Test-Path (Join-Path $_ '.agents\skills') })

function Test-Junction($path) {
  $i = Get-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
  return $i -and ($i.Attributes -band [IO.FileAttributes]::ReparsePoint)
}
function Get-LinkTarget($path) { [string](Get-Item -LiteralPath $path -Force).Target }
function Test-Managed($target) { foreach ($s in $Sources) { if ($target -like "$s\*") { return $true } } $false }

# 1. Pull.
$pullFailed = $false
if ($Pull) {
  foreach ($s in $Sources) {
    $repo = (git -C $s rev-parse --show-toplevel 2>$null)
    if ($repo) {
      git -C $repo pull -q --ff-only 2>&1 | Out-Null
      if ($LASTEXITCODE) { $pullFailed = $true; Write-Warning "pull failed in $repo (local changes or diverged); linked what's there" } else { "pulled   $repo" }
    }
  }
}

# 2. Collect skills: first source wins on a name clash.
$skills = [ordered]@{}
foreach ($s in $Sources) {
  foreach ($d in Get-ChildItem -LiteralPath $s -Directory) {
    if (-not (Test-Path (Join-Path $d.FullName 'SKILL.md'))) { continue }
    if ($skills.Contains($d.Name)) { Write-Warning "$($d.Name): already linked from another source; skipped $($d.FullName)"; continue }
    $skills[$d.Name] = $d.FullName
  }
}

# 3. Link into every target; remove stale links we made.
foreach ($t in $Targets) {
  New-Item -ItemType Directory -Force -Path $t | Out-Null
  foreach ($name in $skills.Keys) {
    $link = Join-Path $t $name
    if (Test-Junction $link) {
      if ((Get-LinkTarget $link) -eq $skills[$name]) { continue }
      if (-not (Test-Managed (Get-LinkTarget $link))) { Write-Warning "$link links somewhere else; left alone"; continue }
      (Get-Item -LiteralPath $link -Force).Delete()
    } elseif (Test-Path -LiteralPath $link) { Write-Warning "$link is a real folder; left alone"; continue }
    New-Item -ItemType Junction -Path $link -Target $skills[$name] | Out-Null
    "linked   $link"
  }
  foreach ($e in Get-ChildItem -LiteralPath $t -Directory -Force) {
    if ((Test-Junction $e.FullName) -and (Test-Managed (Get-LinkTarget $e.FullName)) -and -not $skills.Contains($e.Name)) {
      $e.Delete(); "removed  $($e.FullName) (skill gone)"
    }
  }
}

# 4. Projects: Claude Code reads .claude/skills; Grok gets the paths through its config.
$grokPaths = @()
foreach ($p in $Projects) {
  $agents = Join-Path $p '.agents\skills'
  if (-not (Test-Path $agents)) { Write-Warning "$p has no .agents/skills"; continue }
  $grokPaths += ($agents -replace '\\', '/')
  $claude = Join-Path $p '.claude\skills'
  if (-not (Test-Path -LiteralPath $claude)) {
    New-Item -ItemType Directory -Force -Path (Split-Path $claude) | Out-Null
    New-Item -ItemType Junction -Path $claude -Target $agents | Out-Null
    "linked   $claude"
  } elseif (-not (Test-Junction $claude)) { Write-Warning "$claude is a real folder; left alone" }
  $exclude = Join-Path $p '.git\info\exclude'
  if ((Test-Path $exclude) -and -not (Select-String -LiteralPath $exclude -SimpleMatch '.claude/skills' -Quiet)) {
    Add-Content -LiteralPath $exclude "`n.claude/skills"
  }
}
if ($grokPaths -and (Test-Path $GrokConfig)) {
  $toml = (Get-Content -Raw $GrokConfig) -replace "`r`n", "`n"
  $b = '# BEGIN sync-skills (managed)'; $e = '# END sync-skills'
  $block = "$b`n[skills]`npaths = [$(($grokPaths | ForEach-Object { '"' + $_ + '"' }) -join ', ')]`n$e"
  $i = $toml.IndexOf($b); $j = $toml.IndexOf($e)
  $outside = if ($i -ge 0) { $toml.Substring(0, $i) + $toml.Substring($j + $e.Length) } else { $toml }
  if ($outside -match '(?m)^\[skills\]') { Write-Warning "$GrokConfig already has its own [skills]; add these paths there by hand: $($grokPaths -join ', ')" }
  else {
    $new = if ($i -ge 0 -and $j -gt $i) { $toml.Substring(0, $i) + $block + $toml.Substring($j + $e.Length) } else { $toml.TrimEnd() + "`n`n$block`n" }
    if ($new -ne $toml) { [IO.File]::WriteAllText($GrokConfig, $new, [Text.UTF8Encoding]::new($false)); "updated  $GrokConfig ([skills] paths)" }
  }
}

# 5. Schedule.
if ($Schedule) {
  $quote = { param($a) '"' + $a + '"' }
  $argList = @('-NoProfile', '-WindowStyle', 'Hidden', '-ExecutionPolicy', 'Bypass', '-File', (& $quote $PSCommandPath), '-Pull', '-Sources') +
    (($Sources | ForEach-Object { & $quote $_ }) -join ',')
  # A projects file is re-read on every run, so repos added to it later are picked up.
  if ($ProjectsFile) { $argList += @('-ProjectsFile', (& $quote (Resolve-Path $ProjectsFile).Path)) }
  elseif ($Projects) { $argList += @('-Projects', (($Projects | ForEach-Object { & $quote $_ }) -join ',')) }
  $shell = (Get-Command pwsh -ErrorAction SilentlyContinue)?.Source ?? (Get-Command powershell).Source
  $action = New-ScheduledTaskAction -Execute $shell -Argument ($argList -join ' ')
  $triggers = @(
    (New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"),
    (New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(5) -RepetitionInterval (New-TimeSpan -Hours $EveryHours))
  )
  $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -DontStopIfGoingOnBatteries -AllowStartIfOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 10)
  Register-ScheduledTask -TaskName 'Sync AI skills' -Action $action -Trigger $triggers -Settings $settings -Description 'Pull skills repos and link them into every AI tool (sync-skills.ps1).' -Force | Out-Null
  "scheduled 'Sync AI skills' at sign-in and every $EveryHours h"
}
"done: $($skills.Count) skills in $($Targets.Count) tool folders$(if ($Projects) { ", $($Projects.Count) projects" })"
if ($pullFailed) { exit 1 }
