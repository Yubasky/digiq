<#
.SYNOPSIS
  Skrip Otomasi Pemasangan & Rollback Windows Service DigiQWebSPA menggunakan NSSM.
.DESCRIPTION
  Menyediakan panduan dan otomasi terpadu untuk mendaftarkan spa_server.py sebagai 
  Windows Service otomatis, mematikan proses port 9000 lama, dan prosedur rollback.
.PARAMETER Action
  'install' : Memasang dan menjalankan service DigiQWebSPA.
  'rollback': Menghentikan dan menghapus service DigiQWebSPA.
  'status'  : Memeriksa status service dan listener port 9000.
.NOTES
  CATATAN KEAMANAN:
  Skrip ini TIDAK DIJALANKAN otomatis oleh AI auditor dan menunggu persetujuan Anda.
  Jalankan di PowerShell dengan Administrator:
    powershell -ExecutionPolicy Bypass -File .\scripts\setup_nssm_service.ps1 -Action install
#>

[CmdletBinding()]
param(
    [ValidateSet('install', 'rollback', 'status')]
    [string]$Action = 'status'
)

$ServiceName = "DigiQWebSPA"
$ServiceDisplayName = "DigiQ Web SPA Production Server"
$ProjectDir = "C:\Users\Administrator\Documents\digiq"
$PythonExe = "C:\Users\Administrator\AppData\Local\Programs\Python\Python39-32\python.exe"
$ScriptRelPath = "scripts\spa_server.py"
$LogStdout = "$ProjectDir\audit\spa_server_out.log"
$LogStderr = "$ProjectDir\audit\spa_server_err.log"

# 1. Verifikasi Hak Administrator
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Warning "Peringatan: Skrip ini membutuhkan hak akses Administrator untuk mengelola Windows Service."
}

# 2. Fungsi Pemeriksaan Keberadaan NSSM
function Get-NssmPath {
    $nssmCmd = Get-Command nssm -ErrorAction SilentlyContinue
    if ($nssmCmd) { return $nssmCmd.Source }
    
    $commonPaths = @(
        "C:\tools\nssm\nssm.exe",
        "C:\Program Files\nssm\nssm.exe",
        "C:\ProgramData\chocolatey\bin\nssm.exe",
        "$env:LOCALAPPDATA\Microsoft\WinGet\Links\nssm.exe"
    )
    foreach ($p in $commonPaths) {
        if (Test-Path $p) { return $p }
    }
    return $null
}

# ── ACTION: STATUS ────────────────────────────────────────────────────────────
if ($Action -eq 'status') {
    Write-Host "`n=== STATUS LAYANAN DIGIQ WEB SPA ===" -ForegroundColor Cyan
    $svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if ($svc) {
        Write-Host "Windows Service: DITEMUKAN" -ForegroundColor Green
        Write-Host "  Nama       : $($svc.Name)"
        Write-Host "  Status     : $($svc.Status)"
        Write-Host "  StartType  : $($svc.StartType)"
    } else {
        Write-Host "Windows Service ($ServiceName): BELUM TERPASANG" -ForegroundColor Yellow
    }

    Write-Host "`nPemeriksaan Port 9000 (Listener):" -ForegroundColor Cyan
    $connections = Get-NetTCPConnection -LocalPort 9000 -ErrorAction SilentlyContinue
    if ($connections) {
        $connections | Select-Object LocalAddress, LocalPort, State, OwningProcess | Format-Table -AutoSize
    } else {
        Write-Host "  Port 9000 saat ini tidak sedang mendengarkan (Idle)." -ForegroundColor Gray
    }
    exit 0
}

# ── ACTION: ROLLBACK ──────────────────────────────────────────────────────────
if ($Action -eq 'rollback') {
    Write-Host "`n=== PROSEDUR ROLLBACK / PENGHAPUSAN SERVICE $ServiceName ===" -ForegroundColor Yellow
    $nssm = Get-NssmPath
    if (-not $nssm) {
        Write-Error "NSSM tidak ditemukan. Tidak dapat melakukan rollback via NSSM."
        exit 1
    }

    $svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if ($svc) {
        Write-Host "[1/2] Menghentikan service $ServiceName..." -ForegroundColor Cyan
        & $nssm stop $ServiceName
        Start-Sleep -Seconds 2

        Write-Host "[2/2] Menghapus service $ServiceName dari Windows Service Control Manager..." -ForegroundColor Cyan
        & $nssm remove $ServiceName confirm
        Write-Host "[OK] Service $ServiceName berhasil dihapus." -ForegroundColor Green
    } else {
        Write-Host "Service $ServiceName memang belum terdaftar di Windows." -ForegroundColor Gray
    }
    exit 0
}

# ── ACTION: INSTALL ───────────────────────────────────────────────────────────
if ($Action -eq 'install') {
    Write-Host "`n=== PEMASANGAN SERVICE $ServiceName MENGGUNAKAN NSSM ===" -ForegroundColor Cyan
    
    # Cek NSSM
    $nssm = Get-NssmPath
    if (-not $nssm) {
        Write-Host "[!] NSSM belum terpasang di sistem ini." -ForegroundColor Yellow
        Write-Host "Silakan pasang NSSM terlebih dahulu menggunakan salah satu perintah berikut:"
        Write-Host "  winget install NSSM.NSSM" -ForegroundColor White
        Write-Host "  atau unduh langsung dari https://nssm.cc/download dan letakkan di C:\tools\nssm\nssm.exe`n"
        exit 1
    }

    Write-Host "[1/4] Menghentikan proses Python lama yang masih mendengarkan di Port 9000..." -ForegroundColor Cyan
    $oldConns = Get-NetTCPConnection -LocalPort 9000 -ErrorAction SilentlyContinue
    if ($oldConns) {
        $pidsToKill = $oldConns | Select-Object -ExpandProperty OwningProcess -Unique
        foreach ($pidItem in $pidsToKill) {
            if ($pidItem -gt 0) {
                Write-Host "  Menghentikan proses PID: $pidItem..." -ForegroundColor Yellow
                Stop-Process -Id $pidItem -Force -ErrorAction SilentlyContinue
            }
        }
        Start-Sleep -Seconds 2
    } else {
        Write-Host "  Tidak ada proses lama yang memblokir port 9000." -ForegroundColor Green
    }

    Write-Host "[2/4] Mendaftarkan Windows Service '$ServiceName' via NSSM ($nssm)..." -ForegroundColor Cyan
    $existing = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if ($existing) {
        Write-Host "  Service sudah ada, memperbarui konfigurasi parameter..."
    } else {
        & $nssm install $ServiceName $PythonExe $ScriptRelPath
    }

    Write-Host "[3/4] Mengatur parameter direktori, rotasi log, dan startup otomatis..." -ForegroundColor Cyan
    & $nssm set $ServiceName AppDirectory $ProjectDir
    & $nssm set $ServiceName DisplayName $ServiceDisplayName
    & $nssm set $ServiceName Description "Server HTTP SPA Flutter Web lokal pada port 9000 untuk Cloudflare Zero Trust Tunnel"
    & $nssm set $ServiceName Start SERVICE_AUTO_START
    & $nssm set $ServiceName AppStdout $LogStdout
    & $nssm set $ServiceName AppStderr $LogStderr
    & $nssm set $ServiceName AppRotateFiles 1
    & $nssm set $ServiceName AppRotateOnline 1
    & $nssm set $ServiceName AppRotateBytes 10485760 # Rotasi log per 10 MB

    Write-Host "[4/4] Menjalankan service $ServiceName..." -ForegroundColor Cyan
    & $nssm start $ServiceName
    Start-Sleep -Seconds 3

    # Verifikasi akhir
    $finalSvc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if ($finalSvc -and $finalSvc.Status -eq 'Running') {
        Write-Host "`n[SUKSES] Service $ServiceName berjalan dengan status: $($finalSvc.Status)" -ForegroundColor Green
        Get-NetTCPConnection -LocalPort 9000 -ErrorAction SilentlyContinue | Select-Object LocalAddress, LocalPort, State, OwningProcess | Format-Table -AutoSize
    } else {
        Write-Warning "Service telah didaftarkan namun belum berstatus Running. Silakan periksa log di: $LogStderr"
    }
}

