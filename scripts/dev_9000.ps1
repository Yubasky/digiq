<#
.SYNOPSIS
  DigiQ Development Web Server (Port 9000)
.DESCRIPTION
  Menjalankan Flutter run mode dev web-server untuk pengujian lokal.
.NOTES
  PERINGATAN PENTING ARSITEKTUR:
  Mode development (dev_9000) ini HANYA untuk pengujian lokal / LAN internal.
  Hot reload dan WebSocket devtools LEWAT DOMAIN PUBLIK CLOUDFLARE
  (https://enikzrad.web.id) TIDAK didukung secara praktis karena restriksi
  Host Header validation dan WebSockets handshake.

  Untuk akses publik melalui Cloudflare Zero Trust Tunnel, WAJIB gunakan:
    .\scripts\serve_prod_9000.ps1
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Resolve-Path (Join-Path $ScriptDir "..")
Set-Location $ProjectRoot

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
                    if (($val.StartsWith('"') -and $val.EndsWith('"')) -or
                        ($val.StartsWith("'") -and $val.EndsWith("'"))) {
                        $val = $val.Substring(1, $val.Length - 2)
                    }
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

$SupabaseUrl = [System.Environment]::GetEnvironmentVariable("SUPABASE_URL", "Process")
$SupabaseAnonKey = [System.Environment]::GetEnvironmentVariable("SUPABASE_ANON_KEY", "Process")
$PublicSiteUrl = [System.Environment]::GetEnvironmentVariable("PUBLIC_SITE_URL", "Process")

if ([string]::IsNullOrEmpty($SupabaseUrl) -or [string]::IsNullOrEmpty($SupabaseAnonKey)) {
    Write-Error "[FATAL] SUPABASE_URL atau SUPABASE_ANON_KEY belum dikonfigurasi di .env!"
    exit 1
}

Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host "       Memulai Flutter Dev Server di http://0.0.0.0:9000         " -ForegroundColor Cyan
Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host "Akses Lokal: http://localhost:9000 atau http://127.0.0.1:9000" -ForegroundColor Green
Write-Host "Catatan    : Hot reload aktif untuk browser lokal." -ForegroundColor Yellow
Write-Host "=================================================================" -ForegroundColor Cyan

$runArgs = @(
    "run",
    "-d", "web-server",
    "--web-port=9000",
    "--web-hostname=0.0.0.0",
    "--web-allow-expose-url",
    "--dart-define=SUPABASE_URL=$SupabaseUrl",
    "--dart-define=SUPABASE_ANON_KEY=$SupabaseAnonKey"
)

if (-not [string]::IsNullOrEmpty($PublicSiteUrl)) {
    $runArgs += "--dart-define=PUBLIC_SITE_URL=$PublicSiteUrl"
}

& flutter $runArgs
