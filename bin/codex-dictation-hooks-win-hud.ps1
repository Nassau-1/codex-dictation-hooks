param(
  [string] $Kind = "info",
  [string] $Message = "",
  [string] $HistoryPath = "$env:USERPROFILE\.config\codex-dictation-hooks\processed-history.jsonl",
  [double] $DurationSeconds = 5
)

$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

function Get-RecentEntries {
  param([int] $Limit = 5)

  if (-not (Test-Path -LiteralPath $HistoryPath)) {
    return @()
  }

  $lines = Get-Content -LiteralPath $HistoryPath -ErrorAction SilentlyContinue
  if (-not $lines) {
    return @()
  }

  $entries = New-Object System.Collections.Generic.List[object]
  [array]::Reverse($lines)

  foreach ($line in $lines) {
    if ([string]::IsNullOrWhiteSpace($line)) {
      continue
    }

    try {
      $item = $line | ConvertFrom-Json
      if ($item.outputText) {
        $entries.Add($item)
      }
    } catch {
      continue
    }

    if ($entries.Count -ge $Limit) {
      break
    }
  }

  return $entries.ToArray()
}

function Copy-Text {
  param([string] $Text)

  if ($null -ne $Text) {
    Set-Clipboard -Value $Text
  }
}

function Show-HistoryWindow {
  $entries = @(Get-RecentEntries -Limit 5)

  $form = New-Object System.Windows.Forms.Form
  $form.Text = "Codex Dictation History"
  $form.StartPosition = "Manual"
  $form.Width = 560
  $form.Height = 420
  $form.TopMost = $true
  $form.BackColor = [System.Drawing.Color]::FromArgb(28, 28, 30)
  $form.ForeColor = [System.Drawing.Color]::White
  $form.Font = New-Object System.Drawing.Font("Segoe UI", 9)

  $screen = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
  $form.Left = $screen.Right - $form.Width - 24
  $form.Top = $screen.Bottom - $form.Height - 48

  $title = New-Object System.Windows.Forms.Label
  $title.Text = "Last 5 processed dictations"
  $title.AutoSize = $false
  $title.Left = 16
  $title.Top = 14
  $title.Width = 430
  $title.Height = 24
  $title.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
  $form.Controls.Add($title)

  $close = New-Object System.Windows.Forms.Button
  $close.Text = "Close"
  $close.Left = 464
  $close.Top = 12
  $close.Width = 72
  $close.Height = 28
  $close.Add_Click({ $form.Close() })
  $form.Controls.Add($close)

  if ($entries.Count -eq 0) {
    $empty = New-Object System.Windows.Forms.Label
    $empty.Text = "No processed dictations yet."
    $empty.Left = 16
    $empty.Top = 62
    $empty.Width = 500
    $empty.Height = 28
    $form.Controls.Add($empty)
  } else {
    $top = 54
    for ($i = 0; $i -lt $entries.Count; $i++) {
      $entry = $entries[$i]
      $hook = if ($entry.hookName) { " [$($entry.hookName)]" } else { "" }
      $words = if ($entry.wordCount) { "$($entry.wordCount) words" } else { "" }

      $meta = New-Object System.Windows.Forms.Label
      $meta.Text = "$($i + 1). $($entry.createdAt)$hook $words"
      $meta.Left = 16
      $meta.Top = $top
      $meta.Width = 420
      $meta.Height = 18
      $meta.ForeColor = [System.Drawing.Color]::FromArgb(190, 190, 195)
      $form.Controls.Add($meta)

      $copy = New-Object System.Windows.Forms.Button
      $copy.Text = "Copy"
      $copy.Left = 464
      $copy.Top = $top - 2
      $copy.Width = 72
      $copy.Height = 26
      $textToCopy = [string] $entry.outputText
      $copy.Add_Click({ Copy-Text $textToCopy }.GetNewClosure())
      $form.Controls.Add($copy)

      $box = New-Object System.Windows.Forms.TextBox
      $box.Multiline = $true
      $box.ReadOnly = $true
      $box.ScrollBars = "Vertical"
      $box.Left = 16
      $box.Top = $top + 22
      $box.Width = 520
      $box.Height = 44
      $box.Text = [string] $entry.outputText
      $box.BackColor = [System.Drawing.Color]::FromArgb(42, 42, 46)
      $box.ForeColor = [System.Drawing.Color]::White
      $box.BorderStyle = "FixedSingle"
      $form.Controls.Add($box)

      $top += 68
    }
  }

  [void] $form.ShowDialog()
}

function Open-HistoryWindow {
  $ps = (Get-Process -Id $PID).Path
  Start-Process -FilePath $ps -ArgumentList @(
    "-NoProfile",
    "-ExecutionPolicy",
    "Bypass",
    "-File",
    "`"$PSCommandPath`"",
    "-Kind",
    "history",
    "-HistoryPath",
    "`"$HistoryPath`""
  ) | Out-Null
}

function Show-ToastWindow {
  $text = if ([string]::IsNullOrWhiteSpace($Message)) { "Copied to clipboard" } else { $Message }
  $duration = if ($DurationSeconds -le 0) { 0 } else { [Math]::Max(0.8, [Math]::Min($DurationSeconds, 20)) }

  $form = New-Object System.Windows.Forms.Form
  $form.FormBorderStyle = "None"
  $form.ShowInTaskbar = $false
  $form.TopMost = $true
  $form.BackColor = [System.Drawing.Color]::FromArgb(24, 24, 27)
  $form.Opacity = 0.95
  $form.Cursor = [System.Windows.Forms.Cursors]::Hand

  $font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
  $measure = [System.Windows.Forms.TextRenderer]::MeasureText($text, $font)
  $width = [Math]::Min([Math]::Max($measure.Width + 54, 190), 520)
  $height = 42
  $form.Width = $width
  $form.Height = $height

  $screen = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
  $form.Left = $screen.Right - $width - 24
  $form.Top = $screen.Bottom - $height - 36

  $dot = New-Object System.Windows.Forms.Panel
  $dot.Left = 16
  $dot.Top = 17
  $dot.Width = 8
  $dot.Height = 8
  $dot.BackColor = switch ($Kind) {
    "error" { [System.Drawing.Color]::FromArgb(245, 158, 11) }
    "tally" { [System.Drawing.Color]::FromArgb(34, 197, 94) }
    "processing" { [System.Drawing.Color]::FromArgb(96, 165, 250) }
    default { [System.Drawing.Color]::FromArgb(99, 102, 241) }
  }
  $form.Controls.Add($dot)

  $label = New-Object System.Windows.Forms.Label
  $label.Text = $text
  $label.Left = 34
  $label.Top = 11
  $label.Width = $width - 48
  $label.Height = 22
  $label.Font = $font
  $label.ForeColor = [System.Drawing.Color]::FromArgb(245, 245, 247)
  $label.Cursor = [System.Windows.Forms.Cursors]::Hand
  $form.Controls.Add($label)

  $clickHandler = { Open-HistoryWindow }
  $form.Add_Click($clickHandler)
  $label.Add_Click($clickHandler)
  $dot.Add_Click($clickHandler)

  if ($duration -gt 0) {
    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = [int] ($duration * 1000)
    $timer.Add_Tick({
      $timer.Stop()
      $form.Close()
    })
    $timer.Start()
  }

  [void] $form.ShowDialog()
}

if ($Kind -eq "history") {
  Show-HistoryWindow
} else {
  Show-ToastWindow
}
