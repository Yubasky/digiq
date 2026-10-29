with open('scripts/spa_server.py', 'r', encoding='utf-8') as f:
    c = f.read()

target = """        self.send_header("Strict-Transport-Security", "max-age=31536000; includeSubDomains; preload")
        csp_policy = (
            "default-src 'self'; "
            "script-src 'self' 'unsafe-inline' 'unsafe-eval' https://www.gstatic.com; "
            "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; "
            "font-src 'self' https://fonts.gstatic.com data:; "
            "img-src 'self' data: blob: https://*.supabase.co; "
            "connect-src 'self' https://*.supabase.co wss://*.supabase.co; "
            "object-src 'none'; "
            "base-uri 'self'; "
            "frame-ancestors 'self';"
        )"""

replacement = """        self.send_header("Strict-Transport-Security", "max-age=31536000; includeSubDomains")
        csp_policy = (
            "default-src 'self'; "
            "script-src 'self' 'unsafe-inline' 'unsafe-eval' 'wasm-unsafe-eval' https://www.gstatic.com; "
            "worker-src 'self' blob:; "
            "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; "
            "font-src 'self' https://fonts.gstatic.com data:; "
            "img-src 'self' data: blob: https://*.supabase.co; "
            "connect-src 'self' https://*.supabase.co wss://*.supabase.co; "
            "object-src 'none'; "
            "base-uri 'self'; "
            "frame-ancestors 'self';"
        )"""

if '\r\n' in c:
    target = target.replace('\n', '\r\n')
    replacement = replacement.replace('\n', '\r\n')

if target in c:
    new_c = c.replace(target, replacement, 1)
    with open('scripts/spa_server.py', 'w', encoding='utf-8', newline='') as f:
        f.write(new_c)
    print("Successfully updated CSP and HSTS in scripts/spa_server.py")
else:
    print("Target not found, checking current content...")

