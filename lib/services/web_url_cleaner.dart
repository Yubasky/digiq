// lib/services/web_url_cleaner.dart
//
// Façade untuk membersihkan token_hash & type dari address bar setelah
// token diproses. Menggunakan conditional import agar tidak menarik
// dart:html ke target non-web.

export 'web_url_cleaner_stub.dart'
    if (dart.library.js_interop) 'web_url_cleaner_web.dart';
