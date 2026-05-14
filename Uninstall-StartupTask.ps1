$ErrorActionPreference = "Stop"

$taskName = "Valorant NVIDIA Recording Monitor"
$task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue

if ($task) {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
    Write-Host "Removed startup task: $taskName"
}
else {
    Write-Host "Startup task was not installed: $taskName"
}
