@echo off
chcp 65001 >nul
title build_bundle
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0build_bundle.ps1" %*
