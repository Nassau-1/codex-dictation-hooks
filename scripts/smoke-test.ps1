$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$cli = Join-Path $repoRoot "bin\codex-dictation-hooks.ps1"
$zshWrapper = Join-Path $repoRoot "bin\codex-dictation-hooks"
$nodeScript = Join-Path $repoRoot "bin\codex-dictation-hooks.js"
$configExample = Join-Path $repoRoot "config\hooks.example.json"
$installer = Join-Path $repoRoot "install-windows.ps1"

function Write-Step($Message) {
  Write-Host "==> $Message"
}

function Assert-Equal($Actual, $Expected, $Label) {
  if ($Actual -ne $Expected) {
    throw "$Label failed. Expected '$Expected', got '$Actual'."
  }
}

Write-Step "Checking Node.js syntax"
node --check $nodeScript | Out-Null

Write-Step "Checking hooks.example.json"
$null = Get-Content -Raw $configExample | ConvertFrom-Json

Write-Step "Checking install-windows.ps1 syntax"
$tokens = $null
$errors = $null
$null = [System.Management.Automation.Language.Parser]::ParseFile($installer, [ref] $tokens, [ref] $errors)
if ($errors.Count -gt 0) {
  $errors | Format-List
  throw "install-windows.ps1 has parse errors."
}

Write-Step "Checking macOS preservation markers"
$zshContent = Get-Content -Raw $zshWrapper
$nodeContent = Get-Content -Raw $nodeScript
if ($zshContent -notmatch "#!/bin/zsh" -or $zshContent -notmatch "codex-dictation-hooks\.js") {
  throw "macOS zsh wrapper no longer delegates to the shared Node core."
}
foreach ($marker in @("launchctl", "/usr/bin/pbcopy", "codex-dictation-hooks-hud.swift")) {
  if ($nodeContent -notmatch [regex]::Escape($marker)) {
    throw "Missing macOS preservation marker: $marker"
  }
}

Write-Step "Checking doctor command"
& $cli doctor | Out-Null

Write-Step "Checking raw latest action"
$tmp = Join-Path $env:TEMP ("codex-dictation-hooks-test-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $tmp | Out-Null

try {
  $history = Join-Path $tmp "history.jsonl"
  $config = Join-Path $tmp "hooks.json"
  $output = Join-Path $tmp "out.txt"

  '{"text":"plain dictation without hook trigger"}' | Set-Content -Encoding utf8 -Path $history
  '{"hooks":[]}' | Set-Content -Encoding utf8 -Path $config

  $env:CODEX_DICTATION_HISTORY = $history
  $env:CODEX_DICTATION_HOOKS_CONFIG = $config
  $env:CODEX_DICTATION_ACTION = "[Console]::In.ReadToEnd() | Set-Content -Encoding utf8 -NoNewline -Path '$output'"
  & $cli latest
  Assert-Equal (Get-Content -Raw $output) "plain dictation without hook trigger" "Raw latest action"
} finally {
  Remove-Item Env:CODEX_DICTATION_HISTORY -ErrorAction SilentlyContinue
  Remove-Item Env:CODEX_DICTATION_HOOKS_CONFIG -ErrorAction SilentlyContinue
  Remove-Item Env:CODEX_DICTATION_ACTION -ErrorAction SilentlyContinue
  Remove-Item -Recurse -Force -LiteralPath $tmp -ErrorAction SilentlyContinue
}

Write-Step "Checking accent-insensitive hook matching"
$tmp = Join-Path $env:TEMP ("codex-dictation-hooks-test-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $tmp | Out-Null

try {
  $history = Join-Path $tmp "history.jsonl"
  $config = Join-Path $tmp "hooks.json"
  $output = Join-Path $tmp "out.txt"

  $accentedText = "r$([char]0x00E9)sume ceci en deux lignes"
  @{ text = $accentedText } | ConvertTo-Json -Compress | Set-Content -Encoding utf8 -Path $history
  @'
{
  "agentCommandByPlatform": {
    "win32": "node -e \"process.stdout.write('MATCHED_ACCENTED_TRIGGER')\""
  },
  "defaultModel": "test-model",
  "hooks": [
    {
      "name": "summary-fr-test",
      "phrases": ["resume"],
      "prompt": "{{text}}"
    }
  ]
}
'@ | Set-Content -Encoding utf8 -Path $config

  $env:CODEX_DICTATION_HISTORY = $history
  $env:CODEX_DICTATION_HOOKS_CONFIG = $config
  $env:CODEX_DICTATION_ACTION = "[Console]::In.ReadToEnd() | Set-Content -Encoding utf8 -NoNewline -Path '$output'"
  & $cli latest
  Assert-Equal (Get-Content -Raw $output) "MATCHED_ACCENTED_TRIGGER" "Accent-insensitive matching"
} finally {
  Remove-Item Env:CODEX_DICTATION_HISTORY -ErrorAction SilentlyContinue
  Remove-Item Env:CODEX_DICTATION_HOOKS_CONFIG -ErrorAction SilentlyContinue
  Remove-Item Env:CODEX_DICTATION_ACTION -ErrorAction SilentlyContinue
  Remove-Item -Recurse -Force -LiteralPath $tmp -ErrorAction SilentlyContinue
}

Write-Host "Smoke tests passed."
