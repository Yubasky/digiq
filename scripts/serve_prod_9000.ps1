<#
.SYNOPSIS
  DigiQ Production Serve Script (Windows PowerShell 5.1 & PowerShell 7+)
.DESCRIPTION
  Otomasi kompilasi Release Flutter Web & penyajian SPA di Port 9000 untuk Cloudflare Tunnel.
.NOTES
  Catatan ExecutionPolicy:
  Jika skrip ini diblokir oleh kebijakan eksekusi Windows, jalankan via:
    powershell -ExecutionPolicy Bypass -File .\scripts\serve_prod_9000.ps1
#>

[CmdletBinding()]
param(
    [switch]$SkipBuild,
    [int]$Port = 9000,
    [string]$BindHost = "127.0.0.1"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Pindah ke direktori root proyek
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Resolve-Path (Join-Path $ScriptDir "..")
Set-Location $ProjectRoot

# ── Parser .env Aman Tanpa Invoke-Expression ──────────────────────────────────
function Import-SafeEnvFile {
    param([string]$FilePath)
    if (Test-Path $FilePath) {
        Get-Content -Path $FilePath -Encoding UTF8 | ForEach-Object {
            $line = $_.Trim()
            if ($line -and -not $line.StartsWith('#')) {
                $idx = $line.IndexOf('=')
                if ($idx -gt 0) {
                    $key = $line.Substring(0, $idx).Trim()
                    $val = $line.Substring($idx + 1).Trim()
                    # Hapus tanda kutip pembungkus
                    if (($val.StartsWith('"') -and $val.EndsWith('"')) -or
                        ($val.StartsWith("'") -and $val.EndsWith("'"))) {
                        $val = $val.Substring(1, $val.Length - 2)
                    }
                    # Set hanya jika belum ada di environment process
                    $existing = [System.Environment]::GetEnvironmentVariable($key, "Process")
                    if ([string]::IsNullOrEmpty($existing)) {
                        [System.Environment]::SetEnvironmentVariable($key, $val, "Process")
                    }
                }
            }
        }
    }
}

Import-SafeEnvFile (Join-Path $ProjectRoot ".env")
Import-SafeEnvFile (Join-Path $ProjectRoot ".env.local")

function Mask-Secret {
    param([string]$Str)
    if ($Str.Length -gt 8) {
        return $Str.Substring(0, 6) + "****" + $Str.Substring($Str.Length - 4)
    } elseif ($Str.Length -gt 0) {
        return "****"
    } else {
        return "(kosong)"
    }
}

$SupabaseUrl = [System.Environment]::GetEnvironmentVariable("SUPABASE_URL", "Process")
$SupabaseAnonKey = [System.Environment]::GetEnvironmentVariable("SUPABASE_ANON_KEY", "Process")
$PublicSiteUrl = [System.Environment]::GetEnvironmentVariable("PUBLIC_SITE_URL", "Process")
if ([string]::IsNullOrEmpty($PublicSiteUrl)) {
    $PublicSiteUrl = "https://enikzrad.web.id"
}

# ── Langkah 1: Build Release Flutter Web ──────────────────────────────────────
$BuildWebDir = Join-Path $ProjectRoot "build\web"
$IndexHtmlPath = Join-Path $BuildWebDir "index.html"

if (-not $SkipBuild) {
    Write-Host "=================================================================" -ForegroundColor Cyan
    Write-Host "         [1/3] Menyiapkan Build Release Flutter Web              " -ForegroundColor Cyan
    Write-Host "=================================================================" -ForegroundColor Cyan

    # Validasi binary flutter
    $flutterCmd = Get-Command flutter -ErrorAction SilentlyContinue
    if (-not $flutterCmd) {
        Write-Error "[FATAL] Perintah 'flutter' tidak ditemukan di PATH Windows!"
        exit 1
    }

    # Validasi variabel wajib Supabase
    if ([string]::IsNullOrEmpty($SupabaseUrl) -or [string]::IsNullOrEmpty($SupabaseAnonKey)) {
        Write-Error "[FATAL] SUPABASE_URL atau SUPABASE_ANON_KEY belum terisi di .env!"
        exit 1
    }

    Write-Host "SUPABASE_URL     : $SupabaseUrl"
    Write-Host "SUPABASE_ANON_KEY: $(Mask-Secret $SupabaseAnonKey)"
    Write-Host "PUBLIC_SITE_URL  : $PublicSiteUrl"
    Write-Host ""

    Write-Host "Menjalankan flutter pub get..." -ForegroundColor Yellow
    & flutter pub get
    if ($LASTEXITCODE -ne 0) {
        Write-Error "[FATAL] flutter pub get gagal!"
        exit $LASTEXITCODE
    }

    Write-Host "Mengompilasi Flutter Web (Release Mode)..." -ForegroundColor Yellow
    $buildArgs = @(
        "build", "web",
        "--release",
        "--no-web-resources-cdn",
        "--dart-define=SUPABASE_URL=$SupabaseUrl",
        "--dart-define=SUPABASE_ANON_KEY=$SupabaseAnonKey",
        "--dart-define=PUBLIC_SITE_URL=$PublicSiteUrl"
    )

    & flutter $buildArgs
    if ($LASTEXITCODE -ne 0) {
        Write-Error "[FATAL] flutter build web gagal dengan exit code $LASTEXITCODE!"
        exit $LASTEXITCODE
    }

    if (-not (Test-Path $IndexHtmlPath)) {
        Write-Error "[FATAL] Kompilasi selesai namun $IndexHtmlPath tidak ditemukan!"
        exit 1
    }

    # Verifikasi keamanan build
    $leakedEnv = Get-ChildItem -Path $BuildWebDir -Filter ".env*" -Force -ErrorAction SilentlyContinue
    if ($leakedEnv) {
        Write-Warning "[SECURITY] Ditemukan file .env di folder build/web! Menghapus file tersebut..."
        $leakedEnv | Remove-Item -Force
    }

    Write-Host "Build Release Flutter Web BERHASIL." -ForegroundColor Green
    Write-Host ""
} else {
    Write-Host "=================================================================" -ForegroundColor Cyan
    Write-Host "    [1/3] Melewati Build (-SkipBuild aktif)                      " -ForegroundColor Cyan
    Write-Host "=================================================================" -ForegroundColor Cyan
    if (-not (Test-Path $IndexHtmlPath)) {
        Write-Error "[FATAL] Parameter -SkipBuild diberikan tetapi '$IndexHtmlPath' belum ada! Jalankan tanpa -SkipBuild."
        exit 1
    }
    Write-Host "Ditemukan file build valid di: $IndexHtmlPath" -ForegroundColor Green
    Write-Host ""
}

# ── Langkah 2: Matikan Proses Lama pada Port 9000 Secara Aman ─────────────────
Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host "         [2/3] Memeriksa Ketersediaan Port $Port               " -ForegroundColor Cyan
Write-Host "=================================================================" -ForegroundColor Cyan

try {
    $activeConns = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
    if ($activeConns) {
        foreach ($conn in $activeConns) {
            $procId = $conn.OwningProcess
            if ($procId -gt 0) {
                $proc = Get-Process -Id $procId -ErrorAction SilentlyContinue
                $procName = if ($proc) { $proc.ProcessName } else { "Unknown" }
                Write-Host "[PERINGATAN] Port $Port sedang digunakan oleh proses PID $procId ($procName)." -ForegroundColor Yellow
                Write-Host "Menghentikan proses PID $procId..." -ForegroundColor Yellow
                Stop-Process -Id $procId -Force -ErrorAction SilentlyContinue
            }
        }
        Start-Sleep -Seconds 1
        Write-Host "Port $Port telah dibersihkan." -ForegroundColor Green
    } else {
        Write-Host "Port $Port bersih (tidak ada proses aktif)." -ForegroundColor Green
    }
} catch {
    Write-Warning "Pengecekan Get-NetTCPConnection dilewati: $_"
}
Write-Host ""

# ── Langkah 3: Menjalankan Server SPA Production ──────────────────────────────
Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host "         [3/3] Menjalankan DigiQ SPA Server                      " -ForegroundColor Cyan
Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host "Host Binding  : ${BindHost}:${Port}"
Write-Host "Domain Publik : $PublicSiteUrl"
Write-Host ""
Write-Host "[INFO PENTING CLOUDFLARE]" -ForegroundColor Yellow
Write-Host "  1. Pastikan Cloudflare Tunnel aktif meneruskan ke: http://127.0.0.1:${Port}"
Write-Host "  2. Jika baru saja deploy update UI, lakukan PURGE CACHE di Cloudflare Dashboard"
Write-Host "     agar browser customer mendapatkan bundle terbaru."
Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host ""

$env:HOST = $BindHost
$env:PORT = $Port.ToString()

$SpaPy = Join-Path $ScriptDir "spa_server.py"

# Urutan fallback server: (1) python / py -3, (2) npx serve, (3) dart dhttpd
$pythonCmd = Get-Command python -ErrorAction SilentlyContinue
$pyCmd = Get-Command py -ErrorAction SilentlyContinue
$npxCmd = Get-Command npx -ErrorAction SilentlyContinue
$dartCmd = Get-Command dart -ErrorAction SilentlyContinue

if ($pythonCmd) {
    Write-Host "[SERVER ENGINE] Menggunakan Python 3: $($pythonCmd.Source)" -ForegroundColor Green
    & python $SpaPy
} elseif ($pyCmd) {
    Write-Host "[SERVER ENGINE] Menggunakan Python Launcher (py -3)" -ForegroundColor Green
    & py -3 $SpaPy
} elseif ($npxCmd) {
    Write-Host "[SERVER ENGINE FALLBACK] Python tidak ditemukan. Menggunakan npx serve..." -ForegroundColor Yellow
    Write-Host "Catatan: npx serve mungkin memiliki header caching berbeda dibanding spa_server.py." -ForegroundColor DarkYellow
    & npx -y serve -s $BuildWebDir -l "tcp://${BindHost}:${Port}"
} elseif ($dartCmd) {
    Write-Host "[SERVER ENGINE FALLBACK] Menggunakan dart run dhttpd..." -ForegroundColor Yellow
    & dart run dhttpd --path=$BuildWebDir --port=$Port --host=$BindHost
} else {
    Write-Error "[FATAL] Tidak ditemukan runtime server yang didukung (Python 3, npx, atau Dart SDK)!"
    exit 1
}
