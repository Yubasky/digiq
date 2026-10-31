$envMap = @{}
Get-Content -Path ".env" -Encoding UTF8 | ForEach-Object {
    $line = $_.Trim()
    if ($line -and -not $line.StartsWith('#') -and $line.Contains('=')) {
        $idx = $line.IndexOf('=')
        $k = $line.Substring(0, $idx).Trim()
        $v = $line.Substring($idx + 1).Trim().Trim('"').Trim("'")
        $envMap[$k] = $v
    }
}

$supa = $envMap['SUPABASE_URL']
$anon = $envMap['SUPABASE_ANON_KEY']
$site = $envMap['PUBLIC_SITE_URL']
if ([string]::IsNullOrEmpty($supa) -or [string]::IsNullOrEmpty($anon)) {
    Write-Error "SUPABASE_URL atau SUPABASE_ANON_KEY tidak ditemukan di .env"
    exit 1
}
if ([string]::IsNullOrEmpty($site)) {
    $site = "https://enikzrad.web.id"
}

Write-Host "Kompilasi Flutter Web Release..." -ForegroundColor Cyan
Write-Host "SUPABASE_URL: $supa"

& flutter build web --release --no-web-resources-cdn --no-wasm-dry-run "--dart-define=SUPABASE_URL=$supa" "--dart-define=SUPABASE_ANON_KEY=$anon" "--dart-define=PUBLIC_SITE_URL=$site"
if ($LASTEXITCODE -ne 0) {
    Write-Error "Build gagal dengan exit code $LASTEXITCODE"
    exit $LASTEXITCODE
}
Write-Host "Build Flutter Web Release SUKSES!" -ForegroundColor Green
exit 0

