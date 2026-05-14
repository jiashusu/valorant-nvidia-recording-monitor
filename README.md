# Valorant NVIDIA 自动录屏

一个 Windows 托盘小工具：检测到 Valorant 启动后，自动通过 NVIDIA Overlay 的 `Alt + F9` 快捷键开启连续录制；检测到 Valorant 关闭后，自动停止录制并保存。

窗口会显示当前是否检测到游戏，以及 NVIDIA 录屏是否启用。

## 功能

- 自动检测 Valorant 进程。
- Valorant 启动后自动开启 NVIDIA 连续录制。
- Valorant 关闭后自动停止 NVIDIA 录制。
- 只停止由本工具自动开启的录制，避免误停你手动开启的录制。
- 读取 NVIDIA ShadowPlay 的 `CaptureCore.log`，尽量显示真实录屏状态。
- 状态窗口会显示：
  - `未检测到游戏`：Valorant 未运行。
  - `正在游戏中`：Valorant 正在运行。
  - `录屏：已启用`：NVIDIA 录屏看起来已开启。
  - `录屏：未启用`：NVIDIA 录屏看起来未开启。
  - `NVIDIA Overlay not running`：未检测到 NVIDIA Overlay。
- 支持系统托盘运行。
- 防止重复启动多个实例。
- 支持开机登录后自动启动。

## 使用要求

- Windows
- 已安装并启用 NVIDIA App / NVIDIA Overlay
- NVIDIA 录制快捷键为 `Alt + F9`
- 已安装 Valorant
- PowerShell 5.1 或更新版本

本工具不会修改你的 NVIDIA 录制画质设置。分辨率、FPS、编码器、码率、保存位置等都沿用你在 NVIDIA App 里已经设置好的配置。

## 快速开始

双击启动：

```text
启动录屏提醒.bat
```

也可以使用英文启动文件：

```text
Start-Monitor.bat
```

强制停止监控：

```text
停止录屏提醒.bat
```

或：

```text
Stop-Monitor.bat
```

## 设置开机自启动

双击：

```text
Install-StartupTask.bat
```

它会创建一个 Windows 计划任务：

```text
Valorant NVIDIA Recording Monitor
```

之后每次登录 Windows，工具会自动启动。

如果想取消开机自启动，双击：

```text
Uninstall-StartupTask.bat
```

## 工作方式

1. 工具每 5 秒检查一次 Valorant 是否运行。
2. 如果 Valorant 是在工具启动后打开的，工具会等待 3 秒。
3. 工具发送 `Alt + F9` 给 NVIDIA Overlay，开启连续录制。
4. Valorant 关闭后，工具再次发送 `Alt + F9`，停止录制并保存视频。
5. 工具读取下面的 NVIDIA 日志，判断录屏状态：

```text
C:\ProgramData\NVIDIA Corporation\ShadowPlay\CaptureCore.log
```

## 注意事项

- 建议先启动本工具，再打开 Valorant。
- 如果工具启动时 Valorant 已经开着，工具不会自动开启录制，避免误关你已经手动开启的录制。
- 工具管理录制时，尽量不要手动按 `Alt + F9`。
- NVIDIA 没有提供稳定公开的录制状态 API，所以本工具通过本地 NVIDIA 日志推断录屏状态。
- 如果 NVIDIA 以后改变日志格式，状态显示可能会退回到工具内部记录。

## 文件说明

- `Monitor-ValorantRecording.ps1`：主程序。
- `启动录屏提醒.bat`：中文启动文件。
- `停止录屏提醒.bat`：中文停止文件。
- `Start-Monitor.bat`：英文启动文件。
- `Stop-Monitor.bat`：英文停止文件。
- `Install-StartupTask.ps1`：安装开机自启动计划任务。
- `Uninstall-StartupTask.ps1`：移除开机自启动计划任务。

---

# Valorant NVIDIA Recording Monitor

A small Windows tray tool that watches for Valorant and automatically toggles NVIDIA continuous recording with `Alt + F9`.

The status window shows whether Valorant is detected and whether NVIDIA recording appears to be enabled.

## Features

- Detects Valorant by process name.
- Starts NVIDIA recording automatically after Valorant opens.
- Stops NVIDIA recording automatically after Valorant closes.
- Stops recording only when this tool started it.
- Reads NVIDIA ShadowPlay `CaptureCore.log` to infer recording status when available.
- Shows a compact status window:
  - `未检测到游戏`: Valorant is not running.
  - `正在游戏中`: Valorant is running.
  - `录屏：已启用`: recording appears to be enabled.
  - `录屏：未启用`: recording appears to be disabled.
  - `NVIDIA Overlay not running`: NVIDIA Overlay was not detected.
- Runs from the system tray.
- Prevents duplicate instances.
- Supports Windows logon startup.

## Requirements

- Windows
- NVIDIA App / NVIDIA Overlay enabled
- NVIDIA recording hotkey set to `Alt + F9`
- Valorant installed
- PowerShell 5.1 or newer

This tool does not change your NVIDIA recording quality settings. Resolution, FPS, codec, bitrate, and save location all come from your existing NVIDIA App configuration.

## Quick Start

Start the monitor:

```text
启动录屏提醒.bat
```

or:

```text
Start-Monitor.bat
```

Force-stop the monitor:

```text
停止录屏提醒.bat
```

or:

```text
Stop-Monitor.bat
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

To remove startup behavior, double-click:

```text
Uninstall-StartupTask.bat
```

## How It Works

1. The monitor checks every 5 seconds for Valorant.
2. If Valorant starts after the monitor is already running, it waits 3 seconds.
3. It sends `Alt + F9` to NVIDIA Overlay to start continuous recording.
4. When Valorant closes, it sends `Alt + F9` again to stop and save recording.
5. It reads NVIDIA's local capture log:

```text
C:\ProgramData\NVIDIA Corporation\ShadowPlay\CaptureCore.log
```

## Notes

- Start the monitor before opening Valorant.
- If Valorant is already running when the monitor starts, it will not auto-start recording.
- Avoid manually pressing `Alt + F9` while the monitor is managing a recording.
- NVIDIA does not provide a stable public recording-state API for this script, so recording state is inferred from local NVIDIA logs.
- If NVIDIA changes the log format, the monitor may fall back to its internal state.
