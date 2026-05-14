# Valorant NVIDIA Recording Monitor

A small Windows tray tool that watches for Valorant and automatically toggles NVIDIA continuous recording with `Alt + F9`.

It keeps a compact status window open so you can see whether Valorant is detected and whether NVIDIA recording appears to be enabled.

## Features

- Detects Valorant by process name.
- Starts NVIDIA recording automatically after Valorant opens.
- Stops NVIDIA recording automatically after Valorant closes, but only if this tool started it.
- Reads NVIDIA ShadowPlay `CaptureCore.log` to show recording status when available.
- Shows a simple desktop status window:
  - `未检测到游戏`: Valorant is not detected.
  - `正在游戏中`: Valorant is running.
  - `录屏：已启用`: recording appears to be enabled.
  - `录屏：未启用`: recording appears to be disabled.
  - `NVIDIA Overlay not running`: NVIDIA Overlay was not detected.
- Runs from the system tray and prevents duplicate instances.
- Optional Windows logon startup via Scheduled Task.

## Requirements

- Windows
- NVIDIA App / NVIDIA Overlay enabled
- NVIDIA recording hotkey set to `Alt + F9`
- Valorant installed
- PowerShell 5.1 or newer

The tool does not change your NVIDIA recording quality settings. It uses whatever you already configured in NVIDIA App, such as resolution, FPS, codec, bitrate, and save location.

## Quick Start

Double-click:

```text
Start-Monitor.bat
```

or the Chinese launcher:

```text
启动录屏提醒.bat
```

To stop the monitor, double-click:

```text
Stop-Monitor.bat
```

or:

```text
停止录屏提醒.bat
```

## Enable Startup on Login

Double-click:

```text
Install-StartupTask.bat
```

This creates a Windows Scheduled Task named:

```text
Valorant NVIDIA Recording Monitor
```

It runs the monitor automatically when you log in to Windows.

To remove startup behavior, double-click:

```text
Uninstall-StartupTask.bat
```

## How It Works

1. The monitor checks every 5 seconds for Valorant.
2. If Valorant starts after the monitor is already running, it waits 3 seconds.
3. It sends `Alt + F9` to NVIDIA Overlay to start continuous recording.
4. When Valorant closes, it sends `Alt + F9` again to stop and save recording.
5. It reads:

```text
C:\ProgramData\NVIDIA Corporation\ShadowPlay\CaptureCore.log
```

to infer whether NVIDIA recording is currently on or off.

## Important Notes

- Start the monitor before opening Valorant.
- If Valorant is already running when the monitor starts, it will not auto-start recording. This avoids accidentally stopping a recording you started yourself.
- Avoid manually pressing `Alt + F9` while the monitor is managing a recording.
- NVIDIA does not provide a stable public recording-state API for this script, so recording state is inferred from local NVIDIA logs.
- If NVIDIA changes its log format, the monitor may fall back to its internal state.

## Files

- `Monitor-ValorantRecording.ps1`: main tray monitor.
- `Start-Monitor.bat`: start the monitor.
- `Stop-Monitor.bat`: force-stop the monitor.
- `Install-StartupTask.ps1`: install Windows logon startup task.
- `Uninstall-StartupTask.ps1`: remove Windows logon startup task.
- `启动录屏提醒.bat`: Chinese start launcher.
- `停止录屏提醒.bat`: Chinese stop launcher.

