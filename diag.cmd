@echo off
setlocal
chcp 65001 >nul
title PRINTER SCAN - HP OfficeJet Pro 9015
cd /d "%~dp0"
if not exist "%~dp0HP9015_Diagnostic.ps1" (
  echo [ERREUR] Le script HP9015_Diagnostic.ps1 est introuvable.
  echo Extrayez tous les fichiers du ZIP dans le meme dossier.
  pause
  exit /b 1
)
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0HP9015_Diagnostic.ps1"
if errorlevel 1 (
  echo.
  echo [ERREUR] PowerShell n'a pas termine correctement.
  pause
)
endlocal
