@echo off
pwsh -NoProfile -NonInteractive -File "%~dp0_shim.ps1" ffmpeg %*
