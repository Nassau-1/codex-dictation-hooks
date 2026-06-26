$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$nodeScript = Join-Path $scriptDir "codex-dictation-hooks.js"
$node = $env:CODEX_DICTATION_NODE

if (-not $node) {
  $nodeCommand = Get-Command node -ErrorAction SilentlyContinue
  if (-not $nodeCommand) {
    Write-Error "Node.js is required. Install Node.js or set CODEX_DICTATION_NODE."
    exit 127
  }
  $node = $nodeCommand.Source
}

& $node $nodeScript @args
exit $LASTEXITCODE
