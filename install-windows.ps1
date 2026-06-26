param(
  [string] $RepoUrl = "https://github.com/Nassau-1/codex-dictation-hooks.git",
  [string] $Branch = "codex/windows-support-low-cost-hooks",
  [string] $SourceDir = "$env:LOCALAPPDATA\codex-dictation-hooks-source",
  [switch] $NoInstall
)

$ErrorActionPreference = "Stop"

function Write-Step($Message) {
  Write-Host "==> $Message"
}

function Test-GitAvailable {
  return [bool](Get-Command git -ErrorAction SilentlyContinue)
}

function Install-FromGit {
  if (Test-Path -LiteralPath (Join-Path $SourceDir ".git")) {
    Write-Step "Updating existing source checkout at $SourceDir"
    Push-Location $SourceDir
    try {
      if ((git status --porcelain) -ne $null -and (git status --porcelain).Length -gt 0) {
        throw "Source checkout has local changes. Resolve or remove $SourceDir before updating."
      }
      git fetch origin
      git switch $Branch
      git pull --ff-only origin $Branch
    } finally {
      Pop-Location
    }
    return
  }

  if (Test-Path -LiteralPath $SourceDir) {
    throw "$SourceDir exists but is not a git checkout. Remove it or pass -SourceDir to another folder."
  }

  Write-Step "Cloning $RepoUrl#$Branch to $SourceDir"
  git clone --branch $Branch --single-branch $RepoUrl $SourceDir
}

function Install-FromZip {
  if ($RepoUrl -notmatch "github\.com[:/](?<owner>[^/]+)/(?<repo>[^/.]+)") {
    throw "Zip fallback only supports GitHub HTTPS/SSH repo URLs."
  }

  $owner = $Matches.owner
  $repo = $Matches.repo
  $zipUrl = "https://github.com/$owner/$repo/archive/refs/heads/$Branch.zip"
  $tempRoot = Join-Path $env:TEMP ("codex-dictation-hooks-" + [guid]::NewGuid().ToString("N"))
  $zipPath = Join-Path $tempRoot "source.zip"
  New-Item -ItemType Directory -Path $tempRoot | Out-Null

  try {
    Write-Step "Downloading $zipUrl"
    Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath
    Expand-Archive -Path $zipPath -DestinationPath $tempRoot
    $expanded = Get-ChildItem -Path $tempRoot -Directory | Where-Object { $_.Name -ne "source" } | Select-Object -First 1
    if (-not $expanded) {
      throw "Could not find expanded source folder."
    }

    if (Test-Path -LiteralPath $SourceDir) {
      Remove-Item -LiteralPath $SourceDir -Recurse -Force
    }
    Move-Item -LiteralPath $expanded.FullName -Destination $SourceDir
  } finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
  }
}

if (-not $env:LOCALAPPDATA) {
  throw "LOCALAPPDATA is not set. This installer is intended for Windows user sessions."
}

if (Test-GitAvailable) {
  Install-FromGit
} else {
  Install-FromZip
}

if ($NoInstall) {
  Write-Step "Source is ready at $SourceDir"
  exit 0
}

$installer = Join-Path $SourceDir "bin\codex-dictation-hooks.ps1"
if (-not (Test-Path -LiteralPath $installer)) {
  throw "Installer not found: $installer"
}

Write-Step "Installing Codex dictation hooks"
& $installer install
Write-Step "Installed. Run this anytime for diagnostics:"
Write-Host "  & `"$installer`" doctor"
