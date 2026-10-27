// lib/services/web_url_cleaner_web.dart
//
// Implementasi web: hapus token_hash & type dari query string menggunakan
// History API (window.history.replaceState) tanpa reload halaman.
// Menggunakan package:web (bukan dart:html).

import 'package:web/web.dart' as web;

/// Hapus [keys] dari query string address bar saat ini (web only).
/// Fragment (#/...) dan path dipertahankan.
void removeTokensFromUrl(List<String> keys) {
  final href = web.window.location.href;
  final uri = Uri.parse(href);

  // Bangun query baru tanpa kunci yang dihapus
  final newQuery = Map<String, String>.from(uri.queryParameters)
    ..removeWhere((k, _) => keys.contains(k));

  final newUri = newQuery.isEmpty
      ? uri.replace(query: '')
      : uri.replace(queryParameters: newQuery);

  // replaceState: tidak menambah history entry baru
  web.window.history.replaceState(null, '', newUri.toString());
}
