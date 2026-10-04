@echo off
rem The in-game editor panel, on the desktop. Turn LIVE PREVIEW on in Skin
rem Studio first - that watcher is what draws the frames.
rem   Try In-Game Panel.bat 1064300      pretend that skin is on screen
powershell -NoProfile -ExecutionPolicy RemoteSigned -File "%~dp0ingame\panel_sim.ps1" -Skin "%~1"
