@echo off
rem Convenience wrapper so Windows users can run "scripts\dev all" from cmd or
rem PowerShell without changing the PowerShell execution policy.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0dev.ps1" %*
exit /b %ERRORLEVEL%
