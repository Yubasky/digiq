#!/usr/bin/env python3
"""
DigiQ SPA Production Server
============================
Server HTTP berbasis Python 3 standard library (ThreadingHTTPServer) yang dirancang
khusus untuk melayani build release Flutter Web di balik Cloudflare Zero Trust Tunnel.

Fitur Utama:
1. SPA History Fallback cerdas (route non-ekstensi -> index.html status 200, aset tidak ada -> 404 asli).
2. Header Keamanan: X-Content-Type-Options, X-Frame-Options, Referrer-Policy.
3. MIME Type eksplisit independen dari registry OS (khususnya .js, .wasm, .json, .woff2).
4. Kebijakan Cache akurat: no-cache untuk index/service-worker, immutable 1 tahun untuk canvaskit/assets.
5. Dukungan conditional headers: ETag, Last-Modified, dan HTTP 304 Not Modified.
6. Kompresi: Cloudflare Edge otomatis melakukan kompresi Brotli & Gzip di depan tunnel,
   sehingga server lokal tetap ringan tanpa overhead CPU kompresi ganda.
"""

import os
import sys
import posixpath
import urllib.parse
from datetime import datetime, timezone
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
import email.utils

# ── Lokasi Direktori Dokumen ──────────────────────────────────────────────────
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.realpath(os.path.join(SCRIPT_DIR, ".."))
BUILD_WEB_DIR = os.path.realpath(os.path.join(PROJECT_ROOT, "build", "web"))

# ── Konfigurasi Port & Host ───────────────────────────────────────────────────
DEFAULT_HOST = os.environ.get("HOST", "0.0.0.0")
DEFAULT_PORT = int(os.environ.get("PORT", 9000))

# ── Pemetaan MIME Type Eksplisit ──────────────────────────────────────────────
MIME_TYPES = {
    ".html": "text/html; charset=utf-8",
    ".htm": "text/html; charset=utf-8",
    ".js": "application/javascript; charset=utf-8",
    ".mjs": "application/javascript; charset=utf-8",
    ".wasm": "application/wasm",
    ".json": "application/json; charset=utf-8",
    ".css": "text/css; charset=utf-8",
    ".txt": "text/plain; charset=utf-8",
    ".png": "image/png",
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
    ".webp": "image/webp",
    ".svg": "image/svg+xml",
    ".ico": "image/x-icon",
    ".woff2": "font/woff2",
    ".woff": "font/woff",
    ".ttf": "font/ttf",
    ".otf": "font/otf",
    ".map": "application/json; charset=utf-8",
}

# ── File yang Wajib No-Cache (Revalidasi Setiap Akses) ─────────────────────────
NO_CACHE_FILES = {
    "index.html",
    "flutter_service_worker.js",
    "flutter_bootstrap.js",
    "version.json",
    "manifest.json",
}


class SpaRequestHandler(BaseHTTPRequestHandler):
    """Handler HTTP dengan SPA Fallback, Security Headers, dan Cache-Control."""

    server_version = "DigiQ-SPA-Server/1.0"

    def log_message(self, format, *args):
        # Format log kustom yang ringkas: [YYYY-MM-DD HH:MM:SS] pesan
        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        sys.stdout.write(f"[{timestamp}] {self.address_string()} - {format % args}\n")
        sys.stdout.flush()

    def do_HEAD(self):
        self._handle_request(send_body=False)

    def do_GET(self):
        self._handle_request(send_body=True)

    def _send_security_headers(self):
        """Menambahkan header keamanan fundamental ke seluruh respons."""
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("X-Frame-Options", "SAMEORIGIN")
        self.send_header("Referrer-Policy", "strict-origin-when-cross-origin")
        self.send_header("Content-Security-Policy", "default-src 'self' 'unsafe-inline' 'unsafe-eval' https: wss: data: blob:;")

    def _determine_cache_control(self, rel_path, is_spa_fallback):
        """Menentukan header Cache-Control berdasarkan jenis file."""
        if is_spa_fallback:
            return "no-cache, no-store, must-revalidate"

        filename = posixpath.basename(rel_path)
        if filename in NO_CACHE_FILES:
            return "no-cache, no-store, must-revalidate"

        normalized = rel_path.replace("\\", "/").lower()
        # Aset CanvasKit, subfolder assets/, font, dan icon bersifat statis/immutable
        if (
            normalized.startswith("canvaskit/")
            or normalized.startswith("assets/")
            or normalized.endswith((".woff2", ".woff", ".ttf", ".otf", ".ico"))
        ):
            return "public, max-age=31536000, immutable"

        # Asset lainnya memiliki TTL 1 jam untuk keseimbangan pembaruan
        return "public, max-age=3600"

    def _send_not_found(self):
        """Mengembalikan respons 404 asli (bukan HTML) untuk aset yang hilang."""
        body = b"404 Not Found\n"
        self.send_response(404, "Not Found")
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self._send_security_headers()
        self.end_headers()
        try:
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def _send_forbidden(self):
        """Mengembalikan respons 403 untuk akses file terlarang / traversal."""
        body = b"403 Forbidden\n"
        self.send_response(403, "Forbidden")
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self._send_security_headers()
        self.end_headers()
        try:
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def _handle_request(self, send_body=True):
        try:
            # 1. Parse URL & bersihkan query string / fragment
            parsed_url = urllib.parse.urlparse(self.path)
            raw_path = parsed_url.path
            unquoted_path = urllib.parse.unquote(raw_path)

            # Deteksi Path Traversal eksplisit sebelum normalisasi
            raw_segments = [s for s in unquoted_path.replace("\\", "/").split("/") if s]
            if any(seg == ".." for seg in raw_segments):
                self._send_forbidden()
                return

            clean_path = posixpath.normpath(unquoted_path)

            # 0. Health-Check Endpoint instan untuk Uptime Monitor / Cloudflare
            if clean_path == "/health":
                health_payload = b'{"status":"ok","server":"DigiQ-SPA-Windows","port":9000}\n'
                self.send_response(200, "OK")
                self.send_header("Content-Type", "application/json; charset=utf-8")
                self.send_header("Content-Length", str(len(health_payload)))
                self.send_header("Cache-Control", "no-cache, no-store")
                self._send_security_headers()
                self.end_headers()
                if send_body:
                    self.wfile.write(health_payload)
                return

            # 2. Proteksi Dotfile: cegah akses .env, .git, .vscode, dll (kecuali /.well-known/)
            path_segments = [seg for seg in clean_path.strip("/").split("/") if seg]
            for segment in path_segments:
                if segment.startswith(".") and segment != ".well-known":
                    self._send_not_found()
                    return

            # 3. Path Traversal Guard: resolve path absolut & validasi di dalam BUILD_WEB_DIR
            rel_path = clean_path.lstrip("/")
            target_file = os.path.realpath(os.path.join(BUILD_WEB_DIR, rel_path))

            # Verifikasi bahwa target_file berada tepat di bawah BUILD_WEB_DIR
            try:
                common_prefix = os.path.commonpath([BUILD_WEB_DIR, target_file])
            except ValueError:
                self._send_forbidden()
                return

            if common_prefix != BUILD_WEB_DIR:
                self._send_forbidden()
                return

            # 4. Tangani direktori (misal / atau /assets/)
            if os.path.isdir(target_file):
                index_candidate = os.path.join(target_file, "index.html")
                if os.path.isfile(index_candidate):
                    target_file = index_candidate
                    rel_path = os.path.relpath(target_file, BUILD_WEB_DIR).replace("\\", "/")

            # 5. Logika SPA History Fallback (Cerdas, bukan buta)
            is_spa_fallback = False
            if not os.path.isfile(target_file):
                filename = posixpath.basename(clean_path)
                has_extension = "." in filename
                accept_header = self.headers.get("Accept", "")
                wants_html = "text/html" in accept_header

                # Fallback ke index.html hanya jika route tanpa ekstensi ATAU request meminta HTML
                if (not has_extension) or wants_html:
                    index_path = os.path.join(BUILD_WEB_DIR, "index.html")
                    if os.path.isfile(index_path):
                        target_file = index_path
                        rel_path = "index.html"
                        is_spa_fallback = True
                    else:
                        self._send_not_found()
                        return
                else:
                    # File aset (misal .js, .png, .wasm) yang tidak ada -> 404 asli
                    self._send_not_found()
                    return

            # 6. Baca metadata file untuk Header Caching & Conditional HTTP
            stat_result = os.stat(target_file)
            file_size = stat_result.st_size
            last_modified_time = stat_result.st_mtime
            last_modified_str = email.utils.formatdate(last_modified_time, usegmt=True)
            etag = f'"{int(last_modified_time)}-{file_size}"'

            # 7. Validasi Conditional Request (HTTP 304 Not Modified)
            if_none_match = self.headers.get("If-None-Match")
            if_modified_since = self.headers.get("If-Modified-Since")

            if if_none_match and if_none_match == etag:
                self.send_response(304, "Not Modified")
                self._send_security_headers()
                self.send_header("ETag", etag)
                self.send_header("Cache-Control", self._determine_cache_control(rel_path, is_spa_fallback))
                self.end_headers()
                return

            if if_modified_since and not if_none_match:
                try:
                    ims_time = email.utils.parsedate_to_datetime(if_modified_since).timestamp()
                    if int(last_modified_time) <= int(ims_time):
                        self.send_response(304, "Not Modified")
                        self._send_security_headers()
                        self.send_header("Last-Modified", last_modified_str)
                        self.send_header("Cache-Control", self._determine_cache_control(rel_path, is_spa_fallback))
                        self.end_headers()
                        return
                except Exception:
                    pass

            # 8. Tentukan MIME Type
            _, ext = os.path.splitext(target_file)
            content_type = MIME_TYPES.get(ext.lower(), "application/octet-stream")

            # 9. Kirim Status & Headers 200 OK
            self.send_response(200, "OK")
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(file_size))
            self.send_header("Last-Modified", last_modified_str)
            self.send_header("ETag", etag)
            self.send_header("Cache-Control", self._determine_cache_control(rel_path, is_spa_fallback))
            self._send_security_headers()
            self.end_headers()

            # 10. Streaming isi file jika method GET
            if send_body:
                with open(target_file, "rb") as f:
                    # Kirim dalam chunk 64KB
                    while True:
                        chunk = f.read(65536)
                        if not chunk:
                            break
                        self.wfile.write(chunk)

        except (BrokenPipeError, ConnectionResetError):
            # Koneksi ditutup oleh klien sebelum transmisi selesai (normal pada web)
            pass
        except Exception as e:
            self.log_message("Internal server error: %s", str(e))
            try:
                self.send_error(500, f"Internal Server Error: {str(e)}")
            except Exception:
                pass


def main():
    # Validasi awal ketersediaan build web
    index_file = os.path.join(BUILD_WEB_DIR, "index.html")
    if not os.path.isfile(index_file):
        sys.stderr.write(
            "\n[FATAL] Direktori 'build/web' atau file 'build/web/index.html' tidak ditemukan!\n"
            f"Path yang diperiksa: {index_file}\n\n"
            "Silakan lakukan kompilasi Flutter Web terlebih dahulu:\n"
            "  flutter build web --release\n\n"
        )
        sys.exit(1)

    host = DEFAULT_HOST
    port = DEFAULT_PORT

    server_address = (host, port)
    try:
        httpd = ThreadingHTTPServer(server_address, SpaRequestHandler)
    except OSError as e:
        sys.stderr.write(
            f"\n[FATAL] Gagal mengikat server ke {host}:{port}. Error: {e}\n"
            "Pastikan tidak ada proses lain yang sedang menggunakan port ini.\n\n"
        )
        sys.exit(1)

    print("=================================================================")
    print("      DigiQ Production SPA Web Server (Release Mode)            ")
    print("=================================================================")
    print(f" Dokumen Root : {BUILD_WEB_DIR}")
    print(f" Listening on : http://{host}:{port}")
    if host == "0.0.0.0":
        print(f" Akses Lokal  : http://127.0.0.1:{port} / http://localhost:{port}")
    print(" Cloudflare   : Teruskan cloudflared tunnel ke http://127.0.0.1:9000")
    print(" Domain Publik: https://enikzrad.web.id")
    print(" Tekan Ctrl+C untuk menghentikan server.")
    print("=================================================================\n")

    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\nMenerima sinyal shutdown (Ctrl+C). Menutup server dengan bersih...")
    finally:
        httpd.server_close()
        print("Server dihentikan.")


if __name__ == "__main__":
    main()
