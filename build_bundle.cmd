@echo off
chcp 65001 >nul
title build_bundle (StudyProject)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0VIEWER\build_bundle.ps1" -Root "%~dp0" -Title "StudyProject" -Subtitle "Study with DevelopPrompt" %*
