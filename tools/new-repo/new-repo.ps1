<#
.SYNOPSIS
  Create a complete, well-set-up GitHub repo in one go. Skill: new-repo (asks the questions first).

.DESCRIPTION
  Creates the local folder and the GitHub repo with:
    README, AGENTS.md (+ CLAUDE.md), CONTRIBUTING, SECURITY, CHANGELOG, docs/ARCHITECTURE.md,
    .gitignore for the language, .gitattributes, .editorconfig, PR and issue templates, CODEOWNERS,
    Dependabot (where it applies), LICENSE and CODE_OF_CONDUCT (public repos), optional CI,
    an empty .agents/skills/ for the repo's own skills,
  then main + dev branches, GitHub settings (description, topics, auto-delete merged branches,
  secret scanning and branch protection where the plan allows), and registers the repo with your
  AGENTS.md and skills sync (when -Config points at them).
  Every commit message carries [skip ci] unless -CI is on.

  Use -WhatIf to see what it would do without creating anything.

.EXAMPLE
  .\new-repo.ps1 -Name connect -Description "Remote-control viewer app" -Visibility private -Kind go `
    -Related "my-org/edge: imports its protocol packages" -Config ~\.config\new-repo.json
#>
[CmdletBinding(SupportsShouldProcess)]
param(
  [Parameter(Mandatory)][ValidatePattern('^[a-z0-9][a-z0-9-]{0,62}$')][string]$Name,
  [Parameter(Mandatory)][string]$Description,
  [Parameter(Mandatory)][ValidateSet('private', 'public')][string]$Visibility,
  [ValidateSet('go', 'node', 'python', 'powershell', 'docs', 'other')][string]$Kind = 'other',
  [ValidateSet('MIT', 'Apache-2.0', 'none')][string]$License = 'MIT',
  [string[]]$Related = @(),         # "owner/repo: how it relates"
  [string[]]$Topics = @(),
  [string[]]$Rules = @(),           # repo-specific rules for AGENTS.md
  [switch]$ClientData,              # will hold client or personal data: forces private, extra ignores
  [switch]$CI,                      # add a GitHub Actions check (uses Actions minutes)
  [string]$Owner,                   # GitHub user or org; default from -Config
  [string]$LocalRoot,               # parent folder for the clone; default from -Config
  [string]$Config,                  # JSON: owner, localRoot, registry, syncAgents, syncSkills, skillSources
  [switch]$LocalOnly                # build the folder and first commit only: nothing on GitHub, nothing registered
)
$ErrorActionPreference = 'Stop'
$cfg = if ($Config) { Get-Content -Raw $Config | ConvertFrom-Json } else { [pscustomobject]@{} }
if (-not $Owner) { $Owner = $cfg.owner }
if (-not $LocalRoot) { $LocalRoot = $cfg.localRoot }
if (-not $Owner -or -not $LocalRoot) { throw 'Give -Owner and -LocalRoot, or a -Config that has them.' }
if ($ClientData -and $Visibility -eq 'public') { throw 'A repo that will hold client or personal data must be private.' }
$public = $Visibility -eq 'public'
if (-not $public) { $License = 'none' }
$full = "$Owner/$Name"
$dir = Join-Path $LocalRoot $Name
$templates = Join-Path $PSScriptRoot 'templates'

# ── Preconditions ────────────────────────────────────────────────────────
if (Test-Path $dir) { throw "$dir already exists." }
if ($LocalOnly) { $me = $Owner } else {
  gh auth status 2>&1 | Out-Null; if ($LASTEXITCODE) { throw 'Sign in to GitHub first: gh auth login' }
  gh repo view $full 2>&1 | Out-Null; if (-not $LASTEXITCODE) { throw "$full already exists on GitHub." }
  $me = gh api user -q .login
}

# ── What each kind of project needs ──────────────────────────────────────
$kinds = @{
  go         = @{ checks = "gofmt -l .`ngo vet ./...`ngo test ./..."; start = "Install [Go](https://go.dev/dl/), then ``go build ./...``."; ignore = "bin/`ndist/`n*.exe`n*.test`n*.out`ncoverage*.txt"; eco = 'gomod' }
  node       = @{ checks = "npm run lint`nnpm test"; start = "Install [Node.js](https://nodejs.org/) (LTS), then ``npm install``."; ignore = "node_modules/`ndist/`ncoverage/`n*.tsbuildinfo"; eco = 'npm' }
  python     = @{ checks = "python -m ruff check .`npython -m pytest"; start = "Install [Python](https://www.python.org/downloads/), then ``python -m venv .venv`` and ``pip install -r requirements.txt``."; ignore = "__pycache__/`n*.pyc`n.venv/`nvenv/`ndist/`nbuild/`n*.egg-info/`n.pytest_cache/`n.ruff_cache/"; eco = 'pip' }
  powershell = @{ checks = "Invoke-ScriptAnalyzer -Path . -Recurse`nInvoke-Pester"; start = "Open PowerShell 7 in this folder. Install the checkers once: ``Install-Module PSScriptAnalyzer, Pester -Scope CurrentUser``."; ignore = "*.log`nout/"; eco = $null }
  docs       = @{ checks = "# Read it through once, and check every link opens."; start = "Everything is Markdown. Open the files on GitHub or in any editor."; ignore = ''; eco = $null }
  other      = @{ checks = "# Add this project's build and test commands here."; start = "Add setup steps here as the project takes shape."; ignore = ''; eco = $null }
}
$k = $kinds[$Kind]
$relatedLines = if ($Related) { ($Related | ForEach-Object { $r, $how = $_ -split ':\s*', 2; "- [$r](https://github.com/$r)$(if ($how) { ": $how" })" }) -join "`n" } else { '- None yet.' }
$relatedShort = if ($Related) { ($Related | ForEach-Object { ($_ -split ':')[0] }) -join ', ' } else { 'other systems' }
$ruleLines = @($Rules | ForEach-Object { "- $_" })
if ($ClientData) { $ruleLines += '- This repo can hold client or personal data. Never copy it into issues, pull request text, logs, skills or any other repo, and never share it outside the people who already have access.' }
$generic = if ($public) {
  @"

## How to work here

- Work on ``dev``; ``main`` only moves forward from ``dev``. Changes from others come as pull requests.
- Never commit passwords, keys, tokens or personal data.
- Fix the cause of a bug, not just the symptom, and add a test so it stays fixed.
- If a doc, skill or this file turns out wrong, fix it in the same change.
"@
} else { '' }
$licenseLine = switch ($License) { 'MIT' { '[MIT](LICENSE): use, change and share freely.' } 'Apache-2.0' { '[Apache 2.0](LICENSE).' } default { "Private. All rights reserved by $Owner." } }
$vars = @{
  NAME = $Name; DESCRIPTION = $Description; OWNER = $Owner; OWNER_USER = $me
  CHECKS = $k.checks; GETTING_STARTED = $k.start; RELATED = $relatedLines; RELATED_SHORT = $relatedShort
  RULES = ($ruleLines -join "`n"); GENERIC_RULES = $generic; LICENSE_LINE = $licenseLine
}
function Fill([string]$text) {
  $lines = foreach ($line in ($text -replace "`r`n", "`n") -split "`n") {
    foreach ($key in $vars.Keys) {
      $ph = "{{$key}}"; $i = $line.IndexOf($ph)
      if ($i -lt 0) { continue }
      # A placeholder alone on an indented line (inside a list's code block): indent every line of the value.
      $lead = $line.Substring(0, $i)
      $value = [string]$vars[$key]
      if ($lead.Trim() -eq '' -and $lead) { $value = ($value -split "`n") -join "`n$lead" }
      $line = $line.Replace($ph, $value)
    }
    $line
  }
  return $lines -join "`n"
}
function Put($rel, $text) {
  $path = Join-Path $dir $rel
  New-Item -ItemType Directory -Force -Path (Split-Path $path) | Out-Null
  [IO.File]::WriteAllText($path, ($text.TrimEnd() + "`n"), [Text.UTF8Encoding]::new($false))
}

if (-not $PSCmdlet.ShouldProcess($full, "create $Visibility $Kind repo in $dir")) { return }

# ── Files ────────────────────────────────────────────────────────────────
New-Item -ItemType Directory -Path $dir | Out-Null
foreach ($f in Get-ChildItem -LiteralPath $templates -Recurse -File -Force) {
  $rel = $f.FullName.Substring($templates.Length + 1)
  if ($rel -eq 'CODE_OF_CONDUCT.md' -and -not $public) { continue }
  Put $rel (Fill (Get-Content -Raw -LiteralPath $f.FullName))
}
$ignore = @"
# Secrets and local settings: never commit these.
.env
.env.*
*.pem
*.key
*.pfx
*.p12
secrets/
*.local.*

# Editors and operating systems
.DS_Store
Thumbs.db
.idea/
*.swp

# Linked by tooling (skills sync)
.claude/skills

# Logs
*.log
"@
if ($k.ignore) { $ignore += "`n# $Kind`n$($k.ignore)`n" }
if ($ClientData) { $ignore += "`n# Client data stays out of git unless it's meant to be here`ndata/`nexports/`n*.csv`n*.xlsx`n" }
Put '.gitignore' $ignore
Put '.agents/skills/.gitkeep' ''
if ($License -eq 'MIT') {
  Put 'LICENSE' @"
MIT License

Copyright (c) $(Get-Date -Format yyyy) $Owner

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
"@
} elseif ($License -eq 'Apache-2.0') {
  Put 'LICENSE' ((Invoke-RestMethod 'https://www.apache.org/licenses/LICENSE-2.0.txt') -replace "`r`n", "`n")
}
$deps = @()
if ($k.eco) { $deps += "  - package-ecosystem: $($k.eco)`n    directory: /`n    schedule:`n      interval: weekly`n    open-pull-requests-limit: 5" }
if ($CI) { $deps += "  - package-ecosystem: github-actions`n    directory: /`n    schedule:`n      interval: monthly" }
if ($deps) { Put '.github/dependabot.yml' ("# Keeps dependencies up to date with small pull requests.`nversion: 2`nupdates:`n" + ($deps -join "`n")) }
if ($CI) {
  $setup = switch ($Kind) {
    'go' { "      - uses: actions/setup-go@v5`n        with:`n          go-version-file: go.mod" }
    'node' { "      - uses: actions/setup-node@v4`n        with:`n          node-version: lts/*`n      - run: npm ci" }
    'python' { "      - uses: actions/setup-python@v5`n        with:`n          python-version: '3.x'`n      - run: pip install -r requirements.txt ruff pytest" }
    default { '' }
  }
  $run = ($k.checks -split "`n" | Where-Object { $_ -and -not $_.StartsWith('#') } | ForEach-Object { "      - run: $_" }) -join "`n"
  Put '.github/workflows/ci.yml' @"
name: CI
on:
  push:
    branches: [main, dev]
  pull_request:
    branches: [main, dev]
permissions:
  contents: read
jobs:
  check:
    runs-on: ubuntu-latest
    timeout-minutes: 15
    steps:
      - uses: actions/checkout@v4
$setup
$run
"@
}

# Private repos get your shared AGENTS.md rules in the first commit.
if ($cfg.syncAgents -and -not $public) { & $cfg.syncAgents -Repos $dir | Out-Host }

# ── Git and GitHub ───────────────────────────────────────────────────────
$skip = if ($CI) { '' } else { ' [skip ci]' }
Push-Location $dir
try {
  git init -q -b main
  git add -A
  git commit -q -m "Start $Name$skip"
  if ($LocalOnly) { git checkout -q -b dev; "local only: $dir (nothing created on GitHub)"; return }
  gh repo create $full "--$Visibility" --description $Description --source . --remote origin --push | Out-Null
  if ($LASTEXITCODE) { throw 'gh repo create failed' }
  git checkout -q -b dev; git push -q -u origin dev
  "created  https://github.com/$full (main + dev)"

  gh api -X PATCH "repos/$full" -F delete_branch_on_merge=true -F has_wiki=false -F has_projects=false -F allow_merge_commit=false -F allow_squash_merge=true -F allow_rebase_merge=true | Out-Null
  $tags = @($Topics + $Kind | Where-Object { $_ -and $_ -ne 'other' } | ForEach-Object { $_.ToLower() -replace '[^a-z0-9-]', '-' } | Select-Object -Unique)
  if ($tags) { gh repo edit $full ($tags | ForEach-Object { '--add-topic'; $_ }) | Out-Null }
  if ($public) {
    '{"security_and_analysis":{"secret_scanning":{"status":"enabled"},"secret_scanning_push_protection":{"status":"enabled"}}}' |
      gh api -X PATCH "repos/$full" --input - | Out-Null
    if (-not $LASTEXITCODE) { 'turned on secret scanning and push protection' }
  }
  # Protect main and dev: changes from others arrive as pull requests. The owner (admin) can still push.
  $protect = '{"required_status_checks":null,"enforce_admins":false,"required_pull_request_reviews":{"required_approving_review_count":0},"restrictions":null,"allow_force_pushes":false,"allow_deletions":false}'
  $protected = $true
  foreach ($b in 'main', 'dev') {
    $out = $protect | gh api -X PUT "repos/$full/branches/$b/protection" --input - 2>&1
    if ($LASTEXITCODE) { $protected = $false; if ($out -match 'Upgrade to GitHub Pro') { break } else { Write-Warning "protecting ${b}: $out" } }
  }
  if ($protected) { 'protected main and dev (pull requests required for others; no force-push)' }
  else { 'NOTE: branch protection could not be enabled. Check repository permissions and the GitHub plan; private organization repositories may require GitHub Team. Until protection is available, outside AI tools should get read-only access.' }
} finally { Pop-Location }

# ── Register with your AGENTS.md and skills sync ─────────────────────────
if ($cfg.registry) {
  $line = if ($public) { "$dir public" } else { $dir }
  Add-Content -LiteralPath $cfg.registry $line
  "registered in $($cfg.registry)"
}
if ($cfg.syncSkills) {
  & $cfg.syncSkills -Sources $cfg.skillSources -ProjectsFile $cfg.registry -Schedule | Select-Object -Last 2 | Out-Host
}
"done: $dir"
