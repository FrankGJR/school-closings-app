@echo off
REM Run the PowerShell script to fetch latest school closings
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Get-SchoolClosings.ps1"

REM Open the generated HTML file in the default browser
start "" "C:\export\school_closings.html"

pause