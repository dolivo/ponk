@echo off
chcp 65001 >nul
cd /d "%~dp0"
title Ponk
python run.py
if errorlevel 1 (
  echo.
  echo Ponk se nespustil. Je nainstalovany Python 3.9+ s volbou "Add to PATH"?
)
pause
