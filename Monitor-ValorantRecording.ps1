Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;

public static class KeyboardInput {
    [DllImport("user32.dll", SetLastError = true)]
    public static extern void keybd_event(byte bVk, byte bScan, int dwFlags, UIntPtr dwExtraInfo);
}
"@

$ErrorActionPreference = "SilentlyContinue"

$mutexName = "Global\ValorantRecordingReminder.SingleInstance"
$createdNew = $false
$mutex = New-Object System.Threading.Mutex($true, $mutexName, [ref]$createdNew)
if (-not $createdNew) {
    exit
}

$checkIntervalSeconds = 5
$recordingStartDelaySeconds = 3
$debounceConfirmations = 2
$recordToggleKeys = @(0x12, 0x78)
$nvidiaCaptureLogPath = "C:\ProgramData\NVIDIA Corporation\ShadowPlay\CaptureCore.log"
$stateCacheDirectory = Join-Path $env:LOCALAPPDATA "ValorantRecordingMonitor"
$stateCachePath = Join-Path $stateCacheDirectory "state.json"
$valorantProcessNames = @(
    "VALORANT-Win64-Shipping",
    "VALORANT"
)
$nvidiaOverlayProcessNames = @(
    "NVIDIA Overlay",
    "nvsphelper64"
)

function New-Text {
    param([int[]]$CodePoints)

    return -join ($CodePoints | ForEach-Object { [char]$_ })
}

function Get-GameStatusForCache {
    param([string]$Status)

    if ($Status -eq "Idle" -or $Status -eq "Stopped") {
        return "NotRunning"
    }
    if ($Status -eq "NoOverlay" -or $Status -eq "Game" -or $Status -eq "NotRecording" -or $Status -eq "Recording" -or $Status -eq "AudioWarning" -or $Status -eq "AudioUnknown" -or $Status -eq "Preparing") {
        return "Running"
    }

    return "Unknown"
}

function Get-RecordingStatusForCache {
    param([string]$Status)

    if ($Status -eq "Recording" -or $Status -eq "AudioWarning" -or $Status -eq "AudioUnknown") {
        return "Recording"
    }
    if ($Status -eq "NotRecording" -or $Status -eq "Idle" -or $Status -eq "Stopped") {
        return "NotRecording"
    }

    return "Unknown"
}

function Read-StateCache {
    if (-not (Test-Path $stateCachePath)) {
        return $null
    }

    try {
        return Get-Content -Path $stateCachePath -Raw -ErrorAction Stop | ConvertFrom-Json
    }
    catch {
        return $null
    }
}

function Save-StateCache {
    param([string]$Status)

    try {
        if (-not (Test-Path $stateCacheDirectory)) {
            New-Item -ItemType Directory -Path $stateCacheDirectory -Force | Out-Null
        }

        [PSCustomObject]@{
            GameStatus = Get-GameStatusForCache -Status $Status
            RecordingStatus = Get-RecordingStatusForCache -Status $Status
            LastReliableStatus = $Status
            UpdatedAt = (Get-Date).ToString("o")
        } | ConvertTo-Json | Set-Content -Path $stateCachePath -Encoding UTF8
    }
    catch {
    }
}

function Get-CachedDisplayStatus {
    $cache = Read-StateCache
    if (-not $cache) {
        return $null
    }

    $validStatuses = @("Idle", "Game", "Preparing", "Recording", "NotRecording", "Stopped", "NoOverlay", "AudioWarning", "AudioUnknown")
    if ($validStatuses -contains $cache.LastReliableStatus) {
        return [string]$cache.LastReliableStatus
    }

    if ($cache.GameStatus -eq "Running" -and $cache.RecordingStatus -eq "Recording") {
        return "Recording"
    }
    if ($cache.GameStatus -eq "Running" -and $cache.RecordingStatus -eq "NotRecording") {
        return "NotRecording"
    }
    if ($cache.GameStatus -eq "Running") {
        return "Game"
    }
    if ($cache.GameStatus -eq "NotRunning") {
        return "Idle"
    }

    return $null
}

function Test-RecordingStatus {
    param([string]$Status)

    return ($Status -eq "Recording" -or $Status -eq "AudioWarning" -or $Status -eq "AudioUnknown")
}

function Test-ValorantRunning {
    foreach ($name in $valorantProcessNames) {
        $process = Get-Process -Name $name -ErrorAction SilentlyContinue
        if ($process) {
            return $true
        }
    }

    return $false
}

function Test-NvidiaOverlayRunning {
    foreach ($name in $nvidiaOverlayProcessNames) {
        $process = Get-Process -Name $name -ErrorAction SilentlyContinue
        if ($process) {
            return $true
        }
    }

    return $false
}

function Send-RecordToggleHotkey {
    foreach ($key in $recordToggleKeys) {
        [KeyboardInput]::keybd_event([byte]$key, 0, 0, [UIntPtr]::Zero)
        Start-Sleep -Milliseconds 60
    }

    [array]::Reverse($recordToggleKeys)
    foreach ($key in $recordToggleKeys) {
        [KeyboardInput]::keybd_event([byte]$key, 0, 2, [UIntPtr]::Zero)
        Start-Sleep -Milliseconds 60
    }
    [array]::Reverse($recordToggleKeys)
}

function Get-NvidiaRecordingState {
    if (-not (Test-Path $nvidiaCaptureLogPath)) {
        return "Unknown"
    }

    $lines = Get-Content -Path $nvidiaCaptureLogPath -Tail 300 -ErrorAction SilentlyContinue
    if (-not $lines) {
        return "Unknown"
    }

    for ($index = $lines.Count - 1; $index -ge 0; $index--) {
        $line = $lines[$index]
        if ($line -match "COverlayApi::SetSP: \([^,]+,\s*5\)") {
            return "Recording"
        }
        if ($line -match "COverlayApi::SetSP: \([^,]+,\s*2\)") {
            return "NotRecording"
        }
    }

    return "Unknown"
}

function Get-NvidiaAudioState {
    if (-not (Test-Path $nvidiaCaptureLogPath)) {
        return "Unknown"
    }

    $lines = Get-Content -Path $nvidiaCaptureLogPath -Tail 2000 -ErrorAction SilentlyContinue
    if (-not $lines) {
        return "Unknown"
    }

    $sawAudioThread = $false
    $sawAudioSamples = $false
    $sawMicError = $false
    foreach ($line in $lines) {
        if ($line -match "AudioCaptureThread") {
            $sawAudioThread = $true
            $sawAudioSamples = $false
            $sawMicError = $false
        }
        elseif ($sawAudioThread -and $line -match "AudioCapture::InitializeNvVAD\s*:\s*Failed to set mic") {
            $sawMicError = $true
        }
        elseif ($sawAudioThread -and $line -match "Finished reading all track-\d+ \(Audio\) samples \(empty:0/") {
            $sawAudioSamples = $true
        }
    }

    if (-not $sawAudioThread) {
        return "Unknown"
    }
    if ($sawMicError) {
        return "MicError"
    }
    if ($sawAudioThread -and -not $sawAudioSamples) {
        return "NoAudioSamples"
    }

    return "Ok"
}

function Get-RawDisplayStatus {
    param([bool]$IsRunning)

    if (-not $IsRunning) {
        return "Idle"
    }

    if (-not (Test-NvidiaOverlayRunning)) {
        return "NoOverlay"
    }

    $recordingState = Get-NvidiaRecordingState
    if ($recordingState -eq "Recording") {
        $audioState = Get-NvidiaAudioState
        if ($audioState -eq "MicError") {
            return "AudioWarning"
        }
        if ($audioState -eq "NoAudioSamples") {
            return "AudioUnknown"
        }

        return "Recording"
    }
    if ($recordingState -eq "NotRecording") {
        return "NotRecording"
    }

    if ($script:recordingStartedByTool) {
        return "Recording"
    }

    return "Game"
}

function Get-DisplayStatus {
    param([bool]$IsRunning)

    $rawStatus = Get-RawDisplayStatus -IsRunning $IsRunning

    if (-not $IsRunning) {
        $script:gameMissingCount++
        $script:recordingNotDetectedCount = 0

        if ($script:gameMissingCount -lt $debounceConfirmations -and $script:lastReliableStatus) {
            return $script:lastReliableStatus
        }

        $script:lastReliableStatus = "Idle"
        return "Idle"
    }

    $script:gameMissingCount = 0

    if (Test-RecordingStatus -Status $rawStatus) {
        $script:recordingNotDetectedCount = 0
        $script:lastReliableStatus = $rawStatus
        return $rawStatus
    }

    if ($rawStatus -eq "NotRecording") {
        $script:recordingNotDetectedCount++
        if ($script:recordingNotDetectedCount -lt $debounceConfirmations -and (Test-RecordingStatus -Status $script:lastReliableStatus)) {
            return $script:lastReliableStatus
        }

        $script:lastReliableStatus = "NotRecording"
        return "NotRecording"
    }

    $script:recordingNotDetectedCount = 0

    if ($rawStatus -eq "Game" -and (Test-RecordingStatus -Status $script:lastReliableStatus)) {
        return $script:lastReliableStatus
    }

    $script:lastReliableStatus = $rawStatus
    return $rawStatus
}

function Update-StatusDisplay {
    param([string]$Status)

    switch ($Status) {
        "Recording" {
            $statusText = New-Text @(0x6B63,0x5728,0x5F55,0x5236)
            $detailText = New-Text @(0x5F55,0x5236,0x72B6,0x6001,0x6765,0x81EA,0x20,0x4E,0x56,0x49,0x44,0x49,0x41,0x20,0x65E5,0x5FD7)
            $script:statusLabel.ForeColor = [System.Drawing.Color]::FromArgb(0, 130, 70)
        }
        "NotRecording" {
            $statusText = New-Text @(0x672A,0x5728,0x5F55,0x5236)
            $detailText = New-Text @(0x6E38,0x620F,0x8FD0,0x884C,0x4E2D,0xFF0C,0x4E,0x56,0x49,0x44,0x49,0x41,0x20,0x672A,0x5728,0x5F55,0x5236,0x3002)
            $script:statusLabel.ForeColor = [System.Drawing.Color]::FromArgb(185, 80, 0)
        }
        "Preparing" {
            $statusText = New-Text @(0x51C6,0x5907,0x81EA,0x52A8,0x5F55,0x5236)
            $detailText = New-Text @(0x7B49,0x5F85,0x20,0x4E,0x56,0x49,0x44,0x49,0x41,0x20,0x4F,0x76,0x65,0x72,0x6C,0x61,0x79,0x20,0x548C,0x6E38,0x620F,0x7A33,0x5B9A,0x3002)
            $script:statusLabel.ForeColor = [System.Drawing.Color]::FromArgb(0, 95, 160)
        }
        "Game" {
            $statusText = New-Text @(0x6B63,0x5728,0x6E38,0x620F,0x4E2D)
            $detailText = New-Text @(0x672A,0x68C0,0x6D4B,0x5230,0x20,0x4E,0x56,0x49,0x44,0x49,0x41,0x20,0x5F55,0x5236,0x72B6,0x6001)
            $script:statusLabel.ForeColor = [System.Drawing.Color]::FromArgb(0, 130, 70)
        }
        "Stopped" {
            $statusText = New-Text @(0x5DF2,0x81EA,0x52A8,0x505C,0x6B62,0x5F55,0x5236)
            $detailText = New-Text @(0x7A0B,0x5E8F,0x8FD0,0x884C,0x4E2D)
            $script:statusLabel.ForeColor = [System.Drawing.Color]::FromArgb(80, 80, 80)
        }
        "NoOverlay" {
            $statusText = New-Text @(0x4E,0x56,0x49,0x44,0x49,0x41,0x20,0x4F,0x76,0x65,0x72,0x6C,0x61,0x79,0x20,0x672A,0x8FD0,0x884C)
            $detailText = New-Text @(0x672A,0x68C0,0x6D4B,0x5230,0x20,0x4E,0x56,0x49,0x44,0x49,0x41,0x20,0x4F,0x76,0x65,0x72,0x6C,0x61,0x79,0xFF0C,0x672A,0x81EA,0x52A8,0x5F55,0x5236,0x3002)
            $script:statusLabel.ForeColor = [System.Drawing.Color]::FromArgb(185, 80, 0)
        }
        "AudioWarning" {
            $statusText = New-Text @(0x97F3,0x9891,0x8BBE,0x7F6E,0x5F02,0x5E38)
            $detailText = New-Text @(0x4E,0x56,0x49,0x44,0x49,0x41,0x20,0x9EA6,0x514B,0x98CE,0x8BBE,0x5907,0x5F02,0x5E38,0xFF1A,0x6309,0x20,0x41,0x6C,0x74,0x2B,0x5A,0x20,0x6253,0x5F00,0x53E0,0x52A0,0x5C42,0xFF0C,0x91CD,0x65B0,0x9009,0x62E9,0x5F53,0x524D,0x9EA6,0x514B,0x98CE,0x3002)
            $script:statusLabel.ForeColor = [System.Drawing.Color]::FromArgb(185, 80, 0)
        }
        "AudioUnknown" {
            $statusText = New-Text @(0x97F3,0x9891,0x672A,0x786E,0x8BA4)
            $detailText = New-Text @(0x4E,0x56,0x49,0x44,0x49,0x41,0x20,0x65E5,0x5FD7,0x91CC,0x6682,0x672A,0x770B,0x5230,0x97F3,0x8F68,0xFF0C,0x5148,0x5F55,0x4E00,0x5C0F,0x6BB5,0x6D4B,0x8BD5,0x58F0,0x97F3,0x3002)
            $script:statusLabel.ForeColor = [System.Drawing.Color]::FromArgb(185, 80, 0)
        }
        default {
            $statusText = New-Text @(0x672A,0x68C0,0x6D4B,0x5230,0x6E38,0x620F)
            $detailText = New-Text @(0x7A0B,0x5E8F,0x8FD0,0x884C,0x4E2D)
            $script:statusLabel.ForeColor = [System.Drawing.Color]::FromArgb(80, 80, 80)
        }
    }

    switch ($Status) {
        "Recording" {
            $recordingText = New-Text @(0x5F55,0x5C4F,0xFF1A,0x5DF2,0x542F,0x7528)
            $script:recordingLabel.ForeColor = [System.Drawing.Color]::FromArgb(0, 130, 70)
        }
        "AudioWarning" {
            $recordingText = New-Text @(0x5F55,0x5C4F,0xFF1A,0x5DF2,0x542F,0x7528)
            $script:recordingLabel.ForeColor = [System.Drawing.Color]::FromArgb(0, 130, 70)
        }
        "AudioUnknown" {
            $recordingText = New-Text @(0x5F55,0x5C4F,0xFF1A,0x5DF2,0x542F,0x7528)
            $script:recordingLabel.ForeColor = [System.Drawing.Color]::FromArgb(0, 130, 70)
        }
        "Preparing" {
            $recordingText = New-Text @(0x5F55,0x5C4F,0xFF1A,0x51C6,0x5907,0x5F00,0x542F)
            $script:recordingLabel.ForeColor = [System.Drawing.Color]::FromArgb(0, 95, 160)
        }
        "NoOverlay" {
            $recordingText = "NVIDIA Overlay not running"
            $script:recordingLabel.ForeColor = [System.Drawing.Color]::FromArgb(185, 80, 0)
        }
        "Game" {
            $recordingText = New-Text @(0x5F55,0x5C4F,0xFF1A,0x672A,0x77E5)
            $script:recordingLabel.ForeColor = [System.Drawing.Color]::FromArgb(80, 80, 80)
        }
        default {
            $recordingText = New-Text @(0x5F55,0x5C4F,0xFF1A,0x672A,0x542F,0x7528)
            $script:recordingLabel.ForeColor = [System.Drawing.Color]::FromArgb(80, 80, 80)
        }
    }

    if ($Status -eq "NoOverlay" -or $Status -eq "AudioWarning" -or $Status -eq "AudioUnknown") {
        $script:statusLabel.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 14, [System.Drawing.FontStyle]::Bold)
    }
    else {
        $script:statusLabel.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 20, [System.Drawing.FontStyle]::Bold)
    }

    $script:statusLabel.Text = $statusText
    $script:recordingLabel.Text = $recordingText
    $script:detailLabel.Text = $detailText
    $script:statusItem.Text = $statusText
    Save-StateCache -Status $Status
}

function Start-AutomaticRecording {
    Update-StatusDisplay -Status "Preparing"
    Start-Sleep -Seconds $recordingStartDelaySeconds

    if (-not (Test-ValorantRunning)) {
        Update-StatusDisplay -Status "Idle"
        return
    }

    if (-not (Test-NvidiaOverlayRunning)) {
        $script:recordingStartedByTool = $false
        Update-StatusDisplay -Status "NoOverlay"
        return
    }

    Send-RecordToggleHotkey
    $script:recordingStartedByTool = $true
    Update-StatusDisplay -Status "Recording"
}

function Stop-AutomaticRecording {
    if (-not $script:recordingStartedByTool) {
        Update-StatusDisplay -Status "Idle"
        return
    }

    if (-not (Test-NvidiaOverlayRunning)) {
        $script:recordingStartedByTool = $false
        Update-StatusDisplay -Status "NoOverlay"
        return
    }

    Send-RecordToggleHotkey
    $script:recordingStartedByTool = $false
    Update-StatusDisplay -Status "Stopped"
}

$contextMenu = New-Object System.Windows.Forms.ContextMenuStrip
$statusItem = New-Object System.Windows.Forms.ToolStripMenuItem
$statusItem.Text = New-Text @(0x6B63,0x5728,0x76D1,0x63A7,0x20,0x56,0x61,0x6C,0x6F,0x72,0x61,0x6E,0x74)
$statusItem.Enabled = $false
$showWindowItem = New-Object System.Windows.Forms.ToolStripMenuItem
$showWindowItem.Text = New-Text @(0x9690,0x85CF,0x72B6,0x6001,0x7A97,0x53E3)
$exitItem = New-Object System.Windows.Forms.ToolStripMenuItem
$exitItem.Text = New-Text @(0x9000,0x51FA)
$contextMenu.Items.Add($statusItem) | Out-Null
$contextMenu.Items.Add($showWindowItem) | Out-Null
$contextMenu.Items.Add($exitItem) | Out-Null

$form = New-Object System.Windows.Forms.Form
$form.Text = New-Text @(0x56,0x61,0x6C,0x6F,0x72,0x61,0x6E,0x74,0x20,0x5F55,0x5C4F,0x63D0,0x9192)
$form.Size = New-Object System.Drawing.Size(320, 195)
$form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedSingle
$form.MaximizeBox = $false
$form.TopMost = $false

$titleLabel = New-Object System.Windows.Forms.Label
$titleLabel.Text = New-Text @(0x6B63,0x5728,0x76D1,0x63A7)
$titleLabel.AutoSize = $false
$titleLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$titleLabel.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 10, [System.Drawing.FontStyle]::Regular)
$titleLabel.Location = New-Object System.Drawing.Point(16, 14)
$titleLabel.Size = New-Object System.Drawing.Size(270, 24)

$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Text = New-Text @(0x672A,0x68C0,0x6D4B,0x5230,0x6E38,0x620F)
$statusLabel.AutoSize = $false
$statusLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$statusLabel.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 20, [System.Drawing.FontStyle]::Bold)
$statusLabel.Location = New-Object System.Drawing.Point(16, 45)
$statusLabel.Size = New-Object System.Drawing.Size(270, 44)

$recordingLabel = New-Object System.Windows.Forms.Label
$recordingLabel.Text = New-Text @(0x5F55,0x5C4F,0xFF1A,0x672A,0x542F,0x7528)
$recordingLabel.AutoSize = $false
$recordingLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$recordingLabel.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 10, [System.Drawing.FontStyle]::Bold)
$recordingLabel.Location = New-Object System.Drawing.Point(16, 91)
$recordingLabel.Size = New-Object System.Drawing.Size(270, 24)

$detailLabel = New-Object System.Windows.Forms.Label
$detailLabel.Text = New-Text @(0x53CC,0x51FB,0x6258,0x76D8,0x56FE,0x6807,0x53EF,0x663E,0x793A,0x7A97,0x53E3)
$detailLabel.AutoSize = $false
$detailLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$detailLabel.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 9, [System.Drawing.FontStyle]::Regular)
$detailLabel.Location = New-Object System.Drawing.Point(16, 122)
$detailLabel.Size = New-Object System.Drawing.Size(270, 24)

$form.Controls.Add($titleLabel)
$form.Controls.Add($statusLabel)
$form.Controls.Add($recordingLabel)
$form.Controls.Add($detailLabel)

$trayIcon = New-Object System.Windows.Forms.NotifyIcon
$trayIcon.Icon = [System.Drawing.SystemIcons]::Information
$trayIcon.Text = New-Text @(0x56,0x61,0x6C,0x6F,0x72,0x61,0x6E,0x74,0x20,0x5F55,0x5C4F,0x63D0,0x9192)
$trayIcon.ContextMenuStrip = $contextMenu
$trayIcon.Visible = $true

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = $checkIntervalSeconds * 1000
$lastRunningState = $null
$recordingStartedByTool = $false
$gameMissingCount = 0
$recordingNotDetectedCount = 0
$lastReliableStatus = Get-CachedDisplayStatus

$timer.Add_Tick({
    $isRunning = Test-ValorantRunning

    if ($null -eq $script:lastRunningState) {
        $script:lastRunningState = $isRunning
        Update-StatusDisplay -Status (Get-DisplayStatus -IsRunning $isRunning)
        return
    }

    if ($isRunning -and -not $script:lastRunningState) {
        Start-AutomaticRecording
    }
    elseif (-not $isRunning -and $script:lastRunningState) {
        Stop-AutomaticRecording
    }
    else {
        Update-StatusDisplay -Status (Get-DisplayStatus -IsRunning $isRunning)
    }

    $script:lastRunningState = $isRunning
})

$showWindowItem.Add_Click({
    if ($script:form.Visible) {
        $script:form.Hide()
        $script:showWindowItem.Text = New-Text @(0x663E,0x793A,0x72B6,0x6001,0x7A97,0x53E3)
    }
    else {
        $script:form.Show()
        $script:form.Activate()
        $script:showWindowItem.Text = New-Text @(0x9690,0x85CF,0x72B6,0x6001,0x7A97,0x53E3)
    }
})

$exitItem.Add_Click({
    $script:timer.Stop()
    $script:trayIcon.Visible = $false
    $script:trayIcon.Dispose()
    $script:mutex.ReleaseMutex()
    $script:mutex.Dispose()
    [System.Windows.Forms.Application]::Exit()
})

$form.Add_FormClosing({
    param($sender, $eventArgs)

    if ($eventArgs.CloseReason -eq [System.Windows.Forms.CloseReason]::UserClosing) {
        $eventArgs.Cancel = $true
        $script:form.Hide()
        $script:showWindowItem.Text = New-Text @(0x663E,0x793A,0x72B6,0x6001,0x7A97,0x53E3)
    }
})

$trayIcon.Add_DoubleClick({
    $script:form.Show()
    $script:form.Activate()
    $script:showWindowItem.Text = New-Text @(0x9690,0x85CF,0x72B6,0x6001,0x7A97,0x53E3)
})

$cachedStatus = Get-CachedDisplayStatus
if ($cachedStatus) {
    $lastReliableStatus = $cachedStatus
    Update-StatusDisplay -Status $cachedStatus
}

$initialRunningState = Test-ValorantRunning
$lastRunningState = $initialRunningState
Update-StatusDisplay -Status (Get-DisplayStatus -IsRunning $initialRunningState)
$form.Show()
$timer.Start()
[System.Windows.Forms.Application]::Run($form)
