# Register DigiQ Uptime Monitor Scheduled Task
$ErrorActionPreference = 'Stop'

$scriptPath = "C:\Users\Administrator\Documents\digiq\scripts\uptime_monitor.ps1"
$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scriptPath`""
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 5)
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

Register-ScheduledTask -TaskName "DigiQ_Uptime_Monitor" -Action $action -Trigger $trigger -Settings $settings -User "SYSTEM" -Force
Write-Host "Scheduled task DigiQ_Uptime_Monitor registered successfully." -ForegroundColor Green

