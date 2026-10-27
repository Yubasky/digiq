// lib/services/web_url_cleaner_stub.dart
//
// No-op untuk target non-web (mobile, desktop).
// Dipilih oleh conditional import di web_url_cleaner.dart.

/// No-op di platform non-web.
void removeTokensFromUrl(List<String> keys) {
  // Tidak ada yang perlu dibersihkan di luar web.
}
