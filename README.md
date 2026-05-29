# Codex Dictation Hooks

Automation hooks for Codex dictation on macOS with launchd. Watch new transcripts and run local actions automatically.

## What it does

Codex stores global dictation history at:

```text
~/.codex/transcription-history.jsonl
```

This tool watches that file for new JSONL entries and runs an action whenever a new transcript appears. The default action sends the newest transcript to the active macOS text buffer.

## Install

Clone the repo and run:

```zsh
./bin/codex-dictation-hooks install
```

The installer copies the script to `~/.local/bin/codex-dictation-hooks`, creates a LaunchAgent at:

```text
~/Library/LaunchAgents/com.hcassar93.codex-dictation-hooks.plist
```

and starts it immediately.

## Test in the foreground

```zsh
./bin/codex-dictation-hooks watch
```

Then trigger a new Codex global dictation. You should see a log line when the new transcript is handled.

## Commands

```zsh
./bin/codex-dictation-hooks watch       # watch the history file
./bin/codex-dictation-hooks install     # install and start at login
./bin/codex-dictation-hooks uninstall   # stop and remove the LaunchAgent
./bin/codex-dictation-hooks status      # show LaunchAgent status
./bin/codex-dictation-hooks latest      # run the default action for the latest existing dictation
```

## Configuration

Override the history file if needed:

```zsh
CODEX_DICTATION_HISTORY=/path/to/transcription-history.jsonl ./bin/codex-dictation-hooks watch
```

Run a custom action instead of the default pasteboard action:

```zsh
CODEX_DICTATION_ACTION="/path/to/your-action" ./bin/codex-dictation-hooks watch
```

The transcript is passed to the action on standard input, so the action can format, rewrite, route, or store it.

## Deterministic Agent Hooks

Create a local hooks file in the repo:

```zsh
cp config/hooks.example.json config/hooks.json
```

`config/hooks.json` is ignored by git. Each hook has deterministic trigger phrases and a prompt template:

```json
{
  "agentCommand": "pi",
  "hooks": [
    {
      "name": "email",
      "phrases": ["email", "draft email"],
      "prompt": "Rewrite this as a clear email draft. Return only the rewritten text.\n\n{{text}}"
    }
  ]
}
```

Matching is case-insensitive and uses simple phrase inclusion. If a phrase matches and the configured agent command is installed, the transcript is rewritten before the action runs. If there is no matching hook, no config file, no agent command, or the agent fails, the original transcript is used unchanged.

The agent command receives the rendered prompt on standard input. Its standard output becomes the replacement transcript.

You can also point at a different config:

```zsh
CODEX_DICTATION_HOOKS_CONFIG=/path/to/hooks.json ./bin/codex-dictation-hooks watch
```

## License

MIT
