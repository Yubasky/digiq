Write-Host "========================================" -ForegroundColor Cyan
Write-Host "   Memulai DigiQ Web pada Port 9000     " -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Aplikasi akan dapat diakses di http://localhost:9000" -ForegroundColor Green

flutter run -d chrome --web-port=9000 `
  --dart-define=SUPABASE_URL=https://iqxoofrhhrqkgehuvrlb.supabase.co `
  --dart-define=SUPABASE_ANON_KEY=sb_publishable_ICrxKBqQHJIt95kBowuW3Q_tkvgtP6L
