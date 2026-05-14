@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -like '*Monitor-ValorantRecording.ps1*' -and $_.CommandLine -like '*-File*' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }"
