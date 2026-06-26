#!/usr/bin/env node
"use strict";

const fs = require("fs");
const os = require("os");
const path = require("path");
const { spawn, spawnSync } = require("child_process");

const isWindows = process.platform === "win32";
const isMac = process.platform === "darwin";
const platform = process.platform;

const LABEL = "com.hcassar93.codex-dictation-hooks";
const WINDOWS_TASK_NAME = "CodexDictationHooks";
const WINDOWS_STARTUP_FILE = "CodexDictationHooks.vbs";

const scriptPath = __filename;
const scriptDir = __dirname;
const repoRoot = path.resolve(scriptDir, "..");
const homeDir = os.homedir();

const historyFile = process.env.CODEX_DICTATION_HISTORY ||
  path.join(homeDir, ".codex", "transcription-history.jsonl");
const statsFile = process.env.CODEX_DICTATION_STATS ||
  path.join(homeDir, ".config", "codex-dictation-hooks", "stats.json");
const logDir = path.join(homeDir, ".codex", "log");
const stdoutLog = path.join(logDir, "codex-dictation-hooks.out.log");
const stderrLog = path.join(logDir, "codex-dictation-hooks.err.log");
const userConfigPath = path.join(homeDir, ".config", "codex-dictation-hooks", "hooks.json");
const repoConfigPath = path.join(repoRoot, "config", "hooks.json");
const hooksConfigPath = process.env.CODEX_DICTATION_HOOKS_CONFIG ||
  (fs.existsSync(repoConfigPath) ? repoConfigPath : userConfigPath);
const hudBinaryPath = path.join(scriptDir, "codex-dictation-hooks-hud");
const hudSourcePath = path.join(scriptDir, "codex-dictation-hooks-hud.swift");
const hudPath = fs.existsSync(hudBinaryPath) ? hudBinaryPath : hudSourcePath;

let hooksConfigCache = { mtimeMs: null, config: null };

function mkdirp(target) {
  fs.mkdirSync(target, { recursive: true });
}

function copyIfExists(source, target) {
  if (!fs.existsSync(source)) return false;
  mkdirp(path.dirname(target));
  fs.copyFileSync(source, target);
  return true;
}

function installDefaultUserConfig() {
  if (fs.existsSync(userConfigPath)) return false;

  const localConfigPath = path.join(repoRoot, "config", "hooks.json");
  const exampleConfigPath = path.join(repoRoot, "config", "hooks.example.json");
  const source = fs.existsSync(localConfigPath) ? localConfigPath : exampleConfigPath;
  return copyIfExists(source, userConfigPath);
}

function chmodExecutable(target) {
  if (!isWindows && fs.existsSync(target)) fs.chmodSync(target, 0o755);
}

function stripBom(text) {
  return String(text || "").replace(/^\uFEFF/, "");
}

function firstCommandToken(command) {
  const trimmed = String(command || "").trim();
  if (!trimmed) return "";
  const withoutCall = trimmed.startsWith("& ") ? trimmed.slice(2).trim() : trimmed;
  const match = withoutCall.match(/^"([^"]+)"|^'([^']+)'|^(\S+)/);
  return match ? (match[1] || match[2] || match[3] || "") : "";
}

function quotePowerShell(value) {
  return `'${String(value).replaceAll("'", "''")}'`;
}

function quotePosix(value) {
  return `'${String(value).replaceAll("'", "'\\''")}'`;
}

function quoteForShell(value) {
  return isWindows ? quotePowerShell(value) : quotePosix(value);
}

function commandExists(command) {
  const executable = firstCommandToken(command);
  if (!executable) return false;

  if (executable.includes("/") || executable.includes("\\") || path.isAbsolute(executable)) {
    return fs.existsSync(executable);
  }

  if (isWindows) {
    const result = spawnSync("powershell.exe", [
      "-NoProfile",
      "-NonInteractive",
      "-ExecutionPolicy",
      "Bypass",
      "-Command",
      `if (Get-Command ${quotePowerShell(executable)} -ErrorAction SilentlyContinue) { exit 0 } else { exit 1 }`,
    ]);
    return result.status === 0;
  }

  const shell = process.env.SHELL || (fs.existsSync("/bin/zsh") ? "/bin/zsh" : "/bin/sh");
  const result = spawnSync(shell, ["-lc", `command -v ${quotePosix(executable)} >/dev/null 2>&1`]);
  return result.status === 0;
}

function runShellCommand(command, input, env = process.env) {
  if (isWindows) {
    return spawnSync("powershell.exe", [
      "-NoProfile",
      "-NonInteractive",
      "-ExecutionPolicy",
      "Bypass",
      "-Command",
      command,
    ], { input, encoding: "utf8", env });
  }

  const shell = process.env.SHELL || (fs.existsSync("/bin/zsh") ? "/bin/zsh" : "/bin/sh");
  return spawnSync(shell, ["-lc", command], { input, encoding: "utf8", env });
}

function readHooksConfig() {
  if (!hooksConfigPath || !fs.existsSync(hooksConfigPath)) return null;

  let stat;
  try {
    stat = fs.statSync(hooksConfigPath);
    if (hooksConfigCache.mtimeMs === stat.mtimeMs) return hooksConfigCache.config;

    const parsed = JSON.parse(stripBom(fs.readFileSync(hooksConfigPath, "utf8")));
    hooksConfigCache = { mtimeMs: stat.mtimeMs, config: parsed };
    return parsed;
  } catch (error) {
    console.error(`Failed to read hooks config: ${error.message}`);
    if (!stat || hooksConfigCache.mtimeMs !== stat.mtimeMs) {
      showHudNotice({}, "Hooks config invalid");
    }
    hooksConfigCache = { mtimeMs: stat ? stat.mtimeMs : null, config: null };
    return null;
  }
}

function platformValue(config, key) {
  const byPlatform = config && config[`${key}ByPlatform`];
  if (byPlatform && typeof byPlatform === "object") {
    const aliases = isWindows ? ["win32", "windows"] : isMac ? ["darwin", "macos", "mac"] : [platform, "linux"];
    for (const alias of aliases) {
      if (typeof byPlatform[alias] === "string" && byPlatform[alias].trim()) {
        return byPlatform[alias].trim();
      }
    }
  }

  return typeof config?.[key] === "string" ? config[key].trim() : "";
}

function countWords(text) {
  const matches = String(text).match(/[\p{L}\p{N}]+(?:['\u2019][\p{L}\p{N}]+)*/gu);
  return matches ? matches.length : 0;
}

function defaultStats() {
  return {
    baseWords: 0,
    transcribedWords: 0,
    totalWords: 0,
    entries: 0,
    updatedAt: null,
  };
}

function normalizeCount(value) {
  const count = Number(value);
  return Number.isFinite(count) && count >= 0 ? Math.floor(count) : 0;
}

function normalizeStats(stats) {
  const normalized = defaultStats();
  if (stats && typeof stats === "object") {
    normalized.baseWords = normalizeCount(stats.baseWords);
    normalized.transcribedWords = normalizeCount(stats.transcribedWords);
    normalized.entries = normalizeCount(stats.entries);
    normalized.updatedAt = typeof stats.updatedAt === "string" ? stats.updatedAt : null;
  }
  normalized.totalWords = normalized.baseWords + normalized.transcribedWords;
  return normalized;
}

function readStats() {
  if (!statsFile || !fs.existsSync(statsFile)) return defaultStats();

  try {
    return normalizeStats(JSON.parse(stripBom(fs.readFileSync(statsFile, "utf8"))));
  } catch (error) {
    console.error(`Failed to read tally: ${error.message}`);
    showHudNotice({}, "Tally file invalid");
    return defaultStats();
  }
}

function writeStats(stats) {
  if (!statsFile) return;

  mkdirp(path.dirname(statsFile));
  const tmpPath = `${statsFile}.${process.pid}.tmp`;
  fs.writeFileSync(tmpPath, `${JSON.stringify(stats, null, 2)}\n`);
  fs.renameSync(tmpPath, statsFile);
}

function addToTally(text) {
  const wordCount = countWords(text);
  if (!wordCount) return null;

  const stats = readStats();
  stats.transcribedWords += wordCount;
  stats.entries += 1;
  stats.totalWords = stats.baseWords + stats.transcribedWords;
  stats.updatedAt = new Date().toISOString();
  writeStats(stats);

  return { wordCount, totalWords: stats.totalWords };
}

function findMatchingHook(text, hooks) {
  const normalized = text.toLocaleLowerCase();

  return hooks.find((hook) => {
    if (!hook || !Array.isArray(hook.phrases)) return false;
    return hook.phrases.some((phrase) => (
      typeof phrase === "string" &&
      phrase.trim().length > 0 &&
      normalized.includes(phrase.trim().toLocaleLowerCase())
    ));
  });
}

function selectedModel(config, hook) {
  if (typeof hook.model === "string" && hook.model.trim()) return hook.model.trim();
  if (typeof config.defaultModel === "string" && config.defaultModel.trim()) return config.defaultModel.trim();
  return "";
}

function renderAgentCommand(command, model, config) {
  let rendered = String(command || "");

  if (model) {
    rendered = rendered.replaceAll("{{model}}", quoteForShell(model));
    if (!String(command || "").includes("{{model}}") && typeof config.modelArgument === "string" && config.modelArgument.trim()) {
      rendered = `${rendered} ${config.modelArgument.replaceAll("{{model}}", quoteForShell(model))}`;
    }
  } else {
    rendered = rendered.replaceAll("{{model}}", "");
  }

  return rendered;
}

function renderHookPrompt(template, text, model) {
  return String(template || "{{text}}")
    .replaceAll("{{text}}", text)
    .replaceAll("{{model}}", model || "");
}

function shouldShowHud(config = {}) {
  if (!isMac) return false;

  const envValue = process.env.CODEX_DICTATION_HUD;
  if (envValue === "0" || envValue === "false" || envValue === "off") return false;
  if (envValue === "1" || envValue === "true" || envValue === "on") return true;

  return config.showHud !== false;
}

function startHud(config = {}, args = []) {
  if (!shouldShowHud(config) || !hudPath || !fs.existsSync(hudPath)) return null;

  try {
    const child = fs.statSync(hudPath).mode & 0o111
      ? spawn(hudPath, args, { detached: false, stdio: "ignore" })
      : commandExists("swift")
        ? spawn("/usr/bin/swift", [hudPath, ...args], { detached: false, stdio: "ignore" })
        : null;

    if (!child) return null;
    child.unref();
    return child;
  } catch {
    return null;
  }
}

function showHudMessage(config, kind, message, seconds = null) {
  const args = [kind];
  if (seconds !== null && seconds !== undefined) args.push(String(seconds));
  args.push(message);

  const child = startHud(config, args);
  if (child) child.unref();
}

function showHudNotice(config, message) {
  showHudMessage(config, "error", message);
}

function showHudInfo(config, message, seconds = null) {
  showHudMessage(config, "info", message, seconds);
}

function showHudTally(config, addedMessage, totalMessage, seconds = null) {
  showHudMessage(config, "tally", `${addedMessage}||${totalMessage}`, seconds);
}

function formatNumber(value) {
  return new Intl.NumberFormat().format(value);
}

function pluralize(count, singular, plural = `${singular}s`) {
  return count === 1 ? singular : plural;
}

function durationSetting(value, fallback) {
  const duration = Number(value);
  if (!Number.isFinite(duration)) return fallback;
  return Math.max(0.8, Math.min(duration, 20));
}

function tallyHudOptions(config = {}) {
  const raw = config.tallyHud && typeof config.tallyHud === "object" ? config.tallyHud : {};
  const requestedMode = String(raw.mode || "sequence").toLocaleLowerCase();
  const mode = requestedMode === "separate"
    ? "sequence"
    : ["sequence", "combined", "total", "off"].includes(requestedMode)
      ? requestedMode
      : "sequence";

  return {
    mode,
    addedSeconds: durationSetting(raw.addedSeconds, 3),
    totalSeconds: durationSetting(raw.totalSeconds, 5),
    combinedSeconds: durationSetting(raw.combinedSeconds, 5),
  };
}

function showTallyHud(config, tally) {
  const options = tallyHudOptions(config);
  if (options.mode === "off") return;

  const addedMessage = `Added ${formatNumber(tally.wordCount)} ${pluralize(tally.wordCount, "word")}`;
  const totalMessage = `${formatNumber(tally.totalWords)} words total`;

  if (options.mode === "combined") {
    showHudTally(config, addedMessage, totalMessage, options.combinedSeconds);
    return;
  }

  if (options.mode === "total") {
    showHudInfo(config, totalMessage, options.totalSeconds);
    return;
  }

  showHudInfo(config, addedMessage, options.addedSeconds);
  setTimeout(() => showHudInfo(config, totalMessage, options.totalSeconds), options.addedSeconds * 1000);
}

function stopHud(child) {
  if (!child || child.killed) return;
  try {
    child.kill("SIGTERM");
  } catch {}
}

function maybeTransformText(text) {
  const config = readHooksConfig();
  if (!config || !Array.isArray(config.hooks)) return text;

  const hook = findMatchingHook(text, config.hooks);
  if (!hook) return text;

  const model = selectedModel(config, hook);
  const configuredCommand = process.env.CODEX_DICTATION_AGENT_COMMAND || platformValue(config, "agentCommand");
  const agentCommand = renderAgentCommand(configuredCommand, model, config);
  if (!commandExists(agentCommand)) {
    console.error(`Matched hook "${hook.name || "unnamed"}" but agent command is unavailable.`);
    showHudNotice(config, "Hook agent unavailable");
    return text;
  }

  const prompt = renderHookPrompt(hook.prompt, text, model);
  const env = { ...process.env };
  if (model) env.CODEX_DICTATION_MODEL = model;
  if (hook.name) env.CODEX_DICTATION_HOOK_NAME = String(hook.name);

  const hud = startHud(config);
  const result = runShellCommand(agentCommand, prompt, env);
  stopHud(hud);

  if (result.error || result.status !== 0) {
    const detail = result.error?.message || result.stderr?.trim() || `exit ${result.status}`;
    console.error(`Hook "${hook.name || "unnamed"}" failed: ${detail}`);
    showHudNotice(config, "Hook failed. Using original text.");
    return text;
  }

  const transformed = String(result.stdout || "").trim();
  if (!transformed) {
    showHudNotice(config, "Hook returned no text");
    return text;
  }

  const modelLabel = model ? ` using ${model}` : "";
  console.log(`[${new Date().toISOString()}] transformed dictation with hook: ${hook.name || "unnamed"}${modelLabel}`);
  return transformed;
}

function runAction(text) {
  const config = readHooksConfig() || {};
  const action = process.env.CODEX_DICTATION_ACTION || platformValue(config, "actionCommand");

  let result;
  if (action) {
    result = runShellCommand(action, text);
  } else if (isWindows) {
    result = spawnSync("powershell.exe", [
      "-NoProfile",
      "-NonInteractive",
      "-ExecutionPolicy",
      "Bypass",
      "-Command",
      "[Console]::InputEncoding=[Text.UTF8Encoding]::new(); $text=[Console]::In.ReadToEnd(); Set-Clipboard -Value $text",
    ], { input: text, encoding: "utf8" });
  } else if (isMac) {
    result = spawnSync("/usr/bin/pbcopy", { input: text, encoding: "utf8" });
  } else if (commandExists("xclip")) {
    result = spawnSync("xclip", ["-selection", "clipboard"], { input: text, encoding: "utf8" });
  } else if (commandExists("wl-copy")) {
    result = spawnSync("wl-copy", { input: text, encoding: "utf8" });
  } else {
    process.stdout.write(text);
    return;
  }

  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(`action exited with status ${result.status}`);
}

function processLine(line) {
  if (!line.trim()) return;

  let item;
  try {
    item = JSON.parse(stripBom(line));
  } catch {
    return;
  }

  const text = typeof item.text === "string" ? item.text.trim() : "";
  if (!text) return;

  try {
    const handledText = maybeTransformText(text);
    runAction(handledText);
    const tally = addToTally(text);
    if (tally) showTallyHud(readHooksConfig() || {}, tally);
    console.log(`[${new Date().toISOString()}] handled dictation: ${handledText}`);
  } catch (error) {
    console.error(`Failed to handle dictation: ${error.message}`);
    showHudNotice(readHooksConfig() || {}, "Could not handle dictation");
  }
}

function watchHistory() {
  mkdirp(path.dirname(historyFile));
  fs.closeSync(fs.openSync(historyFile, "a"));

  let offset = fs.statSync(historyFile).size;
  let buffer = "";

  function poll() {
    let size;
    try {
      size = fs.statSync(historyFile).size;
    } catch {
      return;
    }

    if (size < offset) {
      offset = 0;
      buffer = "";
    }

    if (size <= offset) return;

    const fd = fs.openSync(historyFile, "r");
    try {
      const chunk = Buffer.alloc(size - offset);
      fs.readSync(fd, chunk, 0, chunk.length, offset);
      offset = size;
      buffer += chunk.toString("utf8");
    } finally {
      fs.closeSync(fd);
    }

    let newlineIndex;
    while ((newlineIndex = buffer.indexOf("\n")) !== -1) {
      const line = buffer.slice(0, newlineIndex);
      buffer = buffer.slice(newlineIndex + 1);
      processLine(line);
    }
  }

  setInterval(poll, 500);
  console.log(`Watching ${historyFile}`);
}

function latestText() {
  const lines = fs.existsSync(historyFile)
    ? fs.readFileSync(historyFile, "utf8").trim().split(/\r?\n/).reverse()
    : [];

  for (const line of lines) {
    try {
      const item = JSON.parse(stripBom(line));
      if (typeof item.text === "string" && item.text.trim()) {
        return maybeTransformText(item.text.trim());
      }
    } catch {}
  }

  return "";
}

function handleLatest() {
  const text = latestText();
  if (text) runAction(text);
}

function tallyCommand(command = "view", value = "") {
  if (command === "view") {
    printStats(readStats());
    return;
  }

  if (command === "import") {
    const raw = Number(value);
    if (!Number.isFinite(raw) || raw < 0) {
      console.error("Usage: codex-dictation-hooks import-tally <non-negative-word-count>");
      process.exit(2);
    }

    const stats = readStats();
    stats.baseWords = Math.floor(raw);
    stats.totalWords = stats.baseWords + stats.transcribedWords;
    stats.updatedAt = new Date().toISOString();
    writeStats(stats);
    printStats(stats);
    return;
  }

  console.error("Usage: codex-dictation-hooks tally | import-tally <word-count>");
  process.exit(2);
}

function printStats(stats) {
  console.log(`Total words: ${formatNumber(stats.totalWords)}`);
  console.log(`Base words: ${formatNumber(stats.baseWords)}`);
  console.log(`Tracked words: ${formatNumber(stats.transcribedWords)}`);
  console.log(`Entries: ${formatNumber(stats.entries)}`);
  if (stats.updatedAt) console.log(`Updated: ${stats.updatedAt}`);
  console.log(`File: ${statsFile}`);
}

function powershellLiteral(value) {
  return `'${String(value).replaceAll("'", "''")}'`;
}

function vbsLiteral(value) {
  return `"${String(value).replaceAll('"', '""')}"`;
}

function installWindowsAgent() {
  const installDir = path.join(process.env.LOCALAPPDATA || path.join(homeDir, "AppData", "Local"), "codex-dictation-hooks");
  const installedPs1 = path.join(installDir, "codex-dictation-hooks.ps1");
  const installedCmd = path.join(installDir, "codex-dictation-hooks.cmd");
  const installedJs = path.join(installDir, "codex-dictation-hooks.js");

  mkdirp(installDir);
  mkdirp(logDir);
  copyIfExists(scriptPath, installedJs);
  copyIfExists(path.join(scriptDir, "codex-dictation-hooks.ps1"), installedPs1);
  copyIfExists(path.join(scriptDir, "codex-dictation-hooks.cmd"), installedCmd);
  installDefaultUserConfig();
  stopWindowsWatchers();

  const action = `powershell.exe -NoProfile -ExecutionPolicy Bypass -File "${installedPs1}" watch`;
  const ps = [
    `$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument ${powershellLiteral(`-NoProfile -ExecutionPolicy Bypass -File "${installedPs1}" watch`)}`,
    "$trigger = New-ScheduledTaskTrigger -AtLogOn",
    "$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries",
    `Register-ScheduledTask -TaskName ${powershellLiteral(WINDOWS_TASK_NAME)} -Action $action -Trigger $trigger -Settings $settings -Description ${powershellLiteral("Watch Codex dictation history and run local hooks")} -Force | Out-Null`,
    `Start-ScheduledTask -TaskName ${powershellLiteral(WINDOWS_TASK_NAME)}`,
  ].join("; ");

  const result = spawnSync("powershell.exe", ["-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", ps], {
    encoding: "utf8",
  });

  if (result.status !== 0) {
    installWindowsStartupAgent(installedPs1);
    console.warn("Scheduled Task registration failed; installed user Startup fallback instead.");
    if (result.stderr || result.stdout) console.warn(String(result.stderr || result.stdout).trim());
    console.log(`Installed ${WINDOWS_TASK_NAME} startup fallback`);
    console.log(`Command: ${action}`);
    console.log(`Install path: ${installDir}`);
    return;
  }

  console.log(`Installed ${WINDOWS_TASK_NAME}`);
  console.log(`Command: ${action}`);
  console.log(`Install path: ${installDir}`);
}

function stopWindowsWatchers() {
  const stopScript = "Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -like '*codex-dictation-hooks.ps1*watch*' -or $_.CommandLine -like '*codex-dictation-hooks.js*watch*' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }";
  spawnSync("powershell.exe", ["-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", stopScript], { stdio: "ignore" });
}

function windowsStartupPath() {
  const appData = process.env.APPDATA || path.join(homeDir, "AppData", "Roaming");
  return path.join(appData, "Microsoft", "Windows", "Start Menu", "Programs", "Startup", WINDOWS_STARTUP_FILE);
}

function installWindowsStartupAgent(installedPs1) {
  const startupPath = windowsStartupPath();
  mkdirp(path.dirname(startupPath));
  const command = `powershell.exe -NoProfile -ExecutionPolicy Bypass -File "${installedPs1}" watch`;
  const vbs = [
    'Set WshShell = CreateObject("WScript.Shell")',
    `WshShell.Run ${vbsLiteral(command)}, 0, False`,
    "",
  ].join("\r\n");

  fs.writeFileSync(startupPath, vbs, "utf8");
  const child = spawn("wscript.exe", [startupPath], { detached: true, stdio: "ignore" });
  child.unref();
}

function installMacAgent() {
  const installDir = path.join(homeDir, ".local", "bin");
  const installPath = path.join(installDir, "codex-dictation-hooks");
  const installedJs = path.join(installDir, "codex-dictation-hooks.js");
  const plistPath = path.join(homeDir, "Library", "LaunchAgents", `${LABEL}.plist`);

  mkdirp(installDir);
  mkdirp(path.dirname(plistPath));
  mkdirp(logDir);
  copyIfExists(path.join(scriptDir, "codex-dictation-hooks"), installPath);
  copyIfExists(scriptPath, installedJs);
  chmodExecutable(installPath);
  chmodExecutable(installedJs);
  installDefaultUserConfig();

  if (fs.existsSync(hudSourcePath)) copyIfExists(hudSourcePath, path.join(installDir, "codex-dictation-hooks-hud.swift"));
  if (fs.existsSync(hudBinaryPath)) {
    copyIfExists(hudBinaryPath, path.join(installDir, "codex-dictation-hooks-hud"));
    chmodExecutable(path.join(installDir, "codex-dictation-hooks-hud"));
  }

  const plist = `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>${LABEL}</string>
  <key>ProgramArguments</key>
  <array><string>${installPath}</string><string>watch</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>EnvironmentVariables</key>
  <dict><key>PATH</key><string>${process.env.PATH || ""}</string></dict>
  <key>StandardOutPath</key><string>${stdoutLog}</string>
  <key>StandardErrorPath</key><string>${stderrLog}</string>
</dict>
</plist>
`;
  fs.writeFileSync(plistPath, plist);

  spawnSync("launchctl", ["bootout", `gui/${process.getuid()}`, plistPath], { stdio: "ignore" });
  let result = spawnSync("launchctl", ["bootstrap", `gui/${process.getuid()}`, plistPath], { encoding: "utf8" });
  if (result.status !== 0) throw new Error(result.stderr || result.stdout || "launchctl bootstrap failed");
  spawnSync("launchctl", ["enable", `gui/${process.getuid()}/${LABEL}`], { stdio: "ignore" });
  result = spawnSync("launchctl", ["kickstart", "-k", `gui/${process.getuid()}/${LABEL}`], { encoding: "utf8" });
  if (result.status !== 0) throw new Error(result.stderr || result.stdout || "launchctl kickstart failed");
  console.log(`Installed ${LABEL}`);
}

function installAgent() {
  if (isWindows) {
    installWindowsAgent();
  } else if (isMac) {
    installMacAgent();
  } else {
    console.error("Automatic install is currently supported on Windows and macOS.");
    process.exit(2);
  }
}

function uninstallAgent() {
  if (isWindows) {
    spawnSync("schtasks.exe", ["/End", "/TN", WINDOWS_TASK_NAME], { stdio: "ignore" });
    const result = spawnSync("schtasks.exe", ["/Delete", "/TN", WINDOWS_TASK_NAME, "/F"], { encoding: "utf8" });
    if (result.status !== 0 && !String(result.stderr || result.stdout).includes("cannot find")) {
      throw new Error(result.stderr || result.stdout || "failed to delete scheduled task");
    }
    fs.rmSync(windowsStartupPath(), { force: true });
    stopWindowsWatchers();
    console.log(`Uninstalled ${WINDOWS_TASK_NAME}`);
    return;
  }

  if (isMac) {
    const plistPath = path.join(homeDir, "Library", "LaunchAgents", `${LABEL}.plist`);
    spawnSync("launchctl", ["bootout", `gui/${process.getuid()}`, plistPath], { stdio: "ignore" });
    fs.rmSync(plistPath, { force: true });
    console.log(`Uninstalled ${LABEL}`);
    return;
  }

  console.error("Automatic uninstall is currently supported on Windows and macOS.");
  process.exit(2);
}

function statusAgent() {
  if (isWindows) {
    const result = spawnSync("schtasks.exe", ["/Query", "/TN", WINDOWS_TASK_NAME, "/FO", "LIST", "/V"], {
      encoding: "utf8",
    });
    if (result.status === 0) {
      process.stdout.write(result.stdout || "");
      process.exit(0);
    }

    const startupPath = windowsStartupPath();
    if (fs.existsSync(startupPath)) {
      console.log(`Scheduled Task not registered. Startup fallback is installed: ${startupPath}`);
      process.exit(0);
    }

    process.stderr.write(result.stderr || result.stdout || "CodexDictationHooks is not installed.\n");
    process.exit(result.status || 1);
  }

  if (isMac) {
    const result = spawnSync("launchctl", ["print", `gui/${process.getuid()}/${LABEL}`], { encoding: "utf8" });
    process.stdout.write(result.stdout || "");
    process.stderr.write(result.stderr || "");
    process.exit(result.status || 0);
  }

  console.error("Automatic status is currently supported on Windows and macOS.");
  process.exit(2);
}

function usage() {
  console.error("Usage: codex-dictation-hooks [watch|install|uninstall|status|latest|tally|import-tally <word-count>]");
}

function main() {
  const [command = "watch", value = ""] = process.argv.slice(2);

  switch (command) {
    case "watch":
      watchHistory();
      break;
    case "install":
      installAgent();
      break;
    case "uninstall":
      uninstallAgent();
      break;
    case "status":
      statusAgent();
      break;
    case "latest":
      handleLatest();
      break;
    case "tally":
      tallyCommand("view");
      break;
    case "import-tally":
      tallyCommand("import", value);
      break;
    default:
      usage();
      process.exit(2);
  }
}

main();
