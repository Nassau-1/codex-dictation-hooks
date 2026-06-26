# Codex Dictation Hooks

Automation hooks for Codex dictation on Windows and macOS. The watcher reads new Codex dictation transcripts, optionally rewrites them with a cheap/low-effort Codex agent hook, then sends the final text to the clipboard or to a custom local action.

The original project was macOS-first. This fork keeps macOS support and adds Windows support with PowerShell wrappers and a Scheduled Task installer.

## What it does

Codex stores global dictation history at:

```text
~/.codex/transcription-history.jsonl
```

This tool watches that JSONL file for new transcript entries. For each transcript it:

1. checks whether a configured trigger phrase matches;
2. runs the matching deterministic hook, if any;
3. copies the final text to the clipboard by default;
4. updates the local word tally.

On Windows, the default action uses `Set-Clipboard`. On macOS, the default action uses `pbcopy`.

## Windows quick install

From PowerShell, this clones or updates the Windows fork branch under `%LOCALAPPDATA%\codex-dictation-hooks-source`, then installs the watcher:

```powershell
irm https://raw.githubusercontent.com/Nassau-1/codex-dictation-hooks/codex/windows-support-low-cost-hooks/install-windows.ps1 | iex
```

Run diagnostics:

```powershell
& "$env:LOCALAPPDATA\codex-dictation-hooks-source\bin\codex-dictation-hooks.ps1" doctor
```

This tool only watches successful Codex dictation output after Codex writes `~/.codex/transcription-history.jsonl`. If Codex itself shows `Unable to transcribe audio` or an API `429`, fix/retry native Codex dictation first; the hook will not run until Codex has produced a transcript.

## Manual Windows install

From PowerShell:

```powershell
git clone https://github.com/Nassau-1/codex-dictation-hooks.git
cd codex-dictation-hooks
Copy-Item config\hooks.example.json config\hooks.json
.\bin\codex-dictation-hooks.ps1 install
```

The installer copies the runnable files to:

```text
%LOCALAPPDATA%\codex-dictation-hooks\
```

and registers a Windows Scheduled Task named:

```text
CodexDictationHooks
```

The task starts at logon and is started immediately after install. If Windows blocks user Scheduled Task registration, the installer falls back to a hidden user Startup script at:

```text
%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\CodexDictationHooks.vbs
```

That fallback starts the same watcher at login without requiring administrator rights.

Useful Windows commands:

```powershell
.\bin\codex-dictation-hooks.ps1 watch
.\bin\codex-dictation-hooks.ps1 latest
.\bin\codex-dictation-hooks.ps1 status
.\bin\codex-dictation-hooks.ps1 doctor
.\bin\codex-dictation-hooks.ps1 uninstall
.\bin\codex-dictation-hooks.ps1 tally
.\bin\codex-dictation-hooks.ps1 import-tally 25000
```

## macOS install

From zsh:

```zsh
git clone https://github.com/Nassau-1/codex-dictation-hooks.git
cd codex-dictation-hooks
cp config/hooks.example.json config/hooks.json
./bin/codex-dictation-hooks install
```

The macOS installer copies the script to `~/.local/bin/codex-dictation-hooks`, creates a LaunchAgent at:

```text
~/Library/LaunchAgents/com.hcassar93.codex-dictation-hooks.plist
```

and starts it immediately.

## Test in the foreground

Windows:

```powershell
.\bin\codex-dictation-hooks.ps1 watch
```

macOS:

```zsh
./bin/codex-dictation-hooks watch
```

Then trigger a new Codex global dictation. You should see a log line when the new transcript is handled.

## Configuration

Create a local hooks file:

```powershell
Copy-Item config\hooks.example.json config\hooks.json
```

`config/hooks.json` is ignored by git. You can also use the per-user location:

```text
~/.config/codex-dictation-hooks/hooks.json
```

or point to another config file:

```powershell
$env:CODEX_DICTATION_HOOKS_CONFIG = "C:\path\to\hooks.json"
.\bin\codex-dictation-hooks.ps1 watch
```

Override the history file if needed:

```powershell
$env:CODEX_DICTATION_HISTORY = "C:\path\to\transcription-history.jsonl"
.\bin\codex-dictation-hooks.ps1 watch
```

Run a custom action instead of the default clipboard action:

```powershell
$env:CODEX_DICTATION_ACTION = "Set-Content -Path C:\tmp\last-dictation.txt"
.\bin\codex-dictation-hooks.ps1 watch
```

The final text is passed to the action on standard input.

## Low-cost Codex hooks

`config/hooks.example.json` defaults Windows and Linux hooks to:

```text
codex exec --ephemeral --skip-git-repo-check --ignore-rules --model {{model}} -c 'model_reasoning_effort="low"' -s read-only -a never -
```

The default model is:

```text
openai-codex/gpt-5.3-codex-spark
```

The command is intentionally configurable. If your local Codex CLI or model catalog changes, edit `defaultModel` or `agentCommandByPlatform.win32` in `config/hooks.json`.

Each hook has deterministic trigger phrases and a prompt template. Matching is case-insensitive and uses simple phrase inclusion. If a phrase matches and the configured agent command is available, the transcript is rewritten before the action runs. If there is no matching hook, no config file, no agent command, or the agent fails, the original transcript is used unchanged.

The included hooks cover English and French:

- email drafts;
- reformulation and cleanup;
- translation to English;
- translation to French;
- summaries;
- action lists.

The selected model is available as:

- `{{model}}` in `agentCommandByPlatform`, `agentCommand`, and `prompt`;
- `CODEX_DICTATION_MODEL` in the agent command environment.

You can set a model per hook:

```json
{
  "name": "email-fr",
  "phrases": ["brouillon d'email"],
  "model": "openai-codex/gpt-5.3-codex-spark",
  "prompt": "Transforme cette dictee en brouillon d'email. Retourne uniquement le texte final.\n\n{{text}}"
}
```

## Word tally

The watcher counts words from each new transcript and stores the tally at:

```text
~/.config/codex-dictation-hooks/stats.json
```

View the tally:

```powershell
.\bin\codex-dictation-hooks.ps1 tally
```

Import a starting baseline from another system:

```powershell
.\bin\codex-dictation-hooks.ps1 import-tally 25000
```

Override the stats file if needed:

```powershell
$env:CODEX_DICTATION_STATS = "C:\path\to\stats.json"
.\bin\codex-dictation-hooks.ps1 watch
```

## macOS HUD

The native Swift HUD remains macOS-only. Set `"showHud": false` in your hooks config, or run with `CODEX_DICTATION_HUD=0`, to disable it.

On Windows, hook processing is intentionally silent except for terminal logs and Scheduled Task status.

## License

MIT. This fork preserves the upstream license.
