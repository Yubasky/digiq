# DigiQ Uptime Monitor
# Checks local and public /health endpoints every 5 minutes.
# Logs errors to C:\digiq_logs\health_check.log

$logDir = "C:\digiq_logs"
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}
$logFile = Join-Path $logDir "health_check.log"

$endpoints = @(
    "http://127.0.0.1:9000/health",
    "https://enikzrad.web.id/health"
)

foreach ($url in $endpoints) {
    try {
        $resp = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
        if ($resp.StatusCode -ne 200) {
            $msg = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] WARNING: $url returned status $($resp.StatusCode)"
            Add-Content -Path $logFile -Value $msg
        }
    } catch {
        $msg = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] ERROR: $url failed - $($_.Exception.Message)"
        Add-Content -Path $logFile -Value $msg
    }
}

