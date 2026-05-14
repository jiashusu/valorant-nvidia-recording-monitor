$ErrorActionPreference = "Stop"

$taskName = "Valorant NVIDIA Recording Monitor"
$projectDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$monitorScript = Join-Path $projectDir "Monitor-ValorantRecording.ps1"

if (-not (Test-Path $monitorScript)) {
    throw "Monitor script was not found: $monitorScript"
}

$action = New-ScheduledTaskAction `
    -Execute "powershell.exe" `
    -Argument "-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File `"$monitorScript`"" `
    -WorkingDirectory $projectDir

$trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -ExecutionTimeLimit (New-TimeSpan -Days 0)

Register-ScheduledTask `
    -TaskName $taskName `
    -Action $action `
    -Trigger $trigger `
    -Settings $settings `
    -Description "Start Valorant NVIDIA Recording Monitor at Windows logon." `
    -Force | Out-Null

Write-Host "Installed startup task: $taskName"
