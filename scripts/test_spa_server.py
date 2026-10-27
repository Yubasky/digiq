import urllib.request
import urllib.error
import sys

BASE_URL = "http://127.0.0.1:9000"

def test_request(method, path, headers=None):
    url = f"{BASE_URL}{path}"
    req = urllib.request.Request(url, method=method, headers=headers or {})
    try:
        with urllib.request.urlopen(req) as resp:
            body = resp.read()
            return {
                "status": resp.status,
                "headers": dict(resp.headers),
                "body_len": len(body),
                "body_snippet": body[:100].decode("utf-8", errors="replace")
            }
    except urllib.error.HTTPError as e:
        body = e.read()
        return {
            "status": e.code,
            "headers": dict(e.headers),
            "body_len": len(body),
            "body_snippet": body[:100].decode("utf-8", errors="replace")
        }
    except Exception as e:
        return {"error": str(e)}

tests = [
    ("GET", "/", {}, "Root URL (index.html)"),
    ("GET", "/verify", {}, "SPA Route /verify without ext"),
    ("GET", "/login", {}, "SPA Route /login without ext"),
    ("GET", "/file-tidak-ada.js", {}, "Non-existent JS asset (must be 404 text, NOT HTML)"),
    ("GET", "/flutter_bootstrap.js", {}, "Existing JS asset (application/javascript)"),
    ("GET", "/canvaskit/canvaskit.js", {}, "Canvaskit asset cache check"),
    ("GET", "/.env", {}, "Security: dotfile /.env block"),
    ("GET", "/.git/config", {}, "Security: dotfile /.git/config block"),
    ("GET", "/..%2f..%2fetc/passwd", {}, "Security: path traversal encoded block"),
    ("HEAD", "/", {}, "HEAD request support"),
    ("GET", "/verify", {"Accept": "text/html,application/xhtml+xml"}, "SPA Route with Accept: text/html"),
]

print("=================================================================")
print("             HASIL PENGUJIAN OTOMATIS SPA SERVER                 ")
print("=================================================================")

all_passed = True
for method, path, hdrs, desc in tests:
    res = test_request(method, path, hdrs)
    status = res.get("status")
    headers = res.get("headers", {})
    sec_headers = (
        headers.get("X-Content-Type-Options") == "nosniff" and
        headers.get("X-Frame-Options") == "SAMEORIGIN" and
        headers.get("Referrer-Policy") == "strict-origin-when-cross-origin"
    )
    cache_ctrl = headers.get("Cache-Control", "")
    content_type = headers.get("Content-Type", "")

    print(f"Test: [{method} {path}] - {desc}")
    print(f"  -> HTTP Status   : {status}")
    print(f"  -> Content-Type  : {content_type}")
    print(f"  -> Cache-Control : {cache_ctrl}")
    print(f"  -> Sec Headers   : {'OK (Lengkap)' if sec_headers else 'TIDAK LENGKAP'}")
    print(f"  -> Body Snippet  : {res.get('body_snippet', '').strip()[:60]}...")
    print("-" * 65)

print("\nPengujian selesai.")
