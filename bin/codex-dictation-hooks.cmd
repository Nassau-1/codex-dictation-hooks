@echo off
setlocal
set "SCRIPT_DIR=%~dp0"
if not "%CODEX_DICTATION_NODE%"=="" (
  "%CODEX_DICTATION_NODE%" "%SCRIPT_DIR%codex-dictation-hooks.js" %*
) else (
  node "%SCRIPT_DIR%codex-dictation-hooks.js" %*
)
exit /b %ERRORLEVEL%
