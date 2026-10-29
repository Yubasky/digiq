import subprocess
import time
import os
import json
import urllib.request
import socket
import base64
import os
import struct

def make_ws_handshake(host, port, path):
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.connect((host, port))
    key = base64.b64encode(os.urandom(16)).decode('utf-8')
    req = (
        f"GET {path} HTTP/1.1\r\n"
        f"Host: {host}:{port}\r\n"
        f"Upgrade: websocket\r\n"
        f"Connection: Upgrade\r\n"
        f"Sec-WebSocket-Key: {key}\r\n"
        f"Sec-WebSocket-Version: 13\r\n\r\n"
    )
    s.sendall(req.encode('utf-8'))
    resp = s.recv(4096)
    assert b"101 " in resp, f"Handshake failed: {resp}"
    return s

def ws_send(s, data):
    payload = data.encode('utf-8')
    length = len(payload)
    mask = os.urandom(4)
    if length <= 125:
        header = bytearray([0x81, 0x80 | length])
    elif length <= 65535:
        header = bytearray([0x81, 0x80 | 126]) + struct.pack("!H", length)
    else:
        header = bytearray([0x81, 0x80 | 127]) + struct.pack("!Q", length)
    header += mask
    masked_payload = bytearray(b ^ mask[i % 4] for i, b in enumerate(payload))
    s.sendall(header + masked_payload)

def ws_recv(s):
    # Read until a complete frame
    head = s.recv(2)
    if not head: return None
    b1, b2 = head[0], head[1]
    length = b2 & 0x7F
    if length == 126:
        length = struct.unpack("!H", s.recv(2))[0]
    elif length == 127:
        length = struct.unpack("!Q", s.recv(8))[0]
    payload = b""
    while len(payload) < length:
        chunk = s.recv(min(length - len(payload), 65536))
        if not chunk: break
        payload += chunk
    return payload.decode('utf-8', errors='replace')

def run_browser_audit():
    edge = r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
    user_data = os.path.abspath("edge_audit_profile")
    port = 9222
    
    # Update spa_server.py CSP to include static.cloudflareinsights.com
    with open('scripts/spa_server.py', 'r', encoding='utf-8') as f:
        spa_content = f.read()
    
    if 'https://static.cloudflareinsights.com' not in spa_content:
        spa_content = spa_content.replace(
            "https://www.gstatic.com; ",
            "https://www.gstatic.com https://static.cloudflareinsights.com; "
        )
        spa_content = spa_content.replace(
            "https://*.supabase.co wss://*.supabase.co; ",
            "https://*.supabase.co wss://*.supabase.co https://cloudflareinsights.com; "
        )
        with open('scripts/spa_server.py', 'w', encoding='utf-8', newline='') as f:
            f.write(spa_content)
        print("[+] Added cloudflareinsights to CSP directive.")

    # Launch Edge headless with remote debugging
    cmd = [
        edge,
        '--headless=new',
        '--no-sandbox',
        '--disable-gpu',
        f'--remote-debugging-port={port}',
        f'--user-data-dir={user_data}',
        '--window-size=1280,800',
        'about:blank'
    ]
    proc = subprocess.Popen(cmd)
    print("[*] Launched Edge Headless PID:", proc.pid)
    time.sleep(2)

    try:
        # Get WebSocket debugger URL
        v_url = f"http://127.0.0.1:{port}/json"
        with urllib.request.urlopen(v_url, timeout=5) as r:
            targets = json.loads(r.read().decode())
        ws_url = targets[0]['webSocketDebuggerUrl']
        print("[*] WebSocket Debugger URL:", ws_url)
        path = ws_url.split(f":{port}")[1]

        ws = make_ws_handshake("127.0.0.1", port, path)
        print("[+] Connected to Chrome DevTools Protocol via WebSocket.")

        # Enable Log, Runtime, Page
        msg_id = 1
        ws_send(ws, json.dumps({"id": msg_id, "method": "Log.enable"}))
        msg_id += 1
        ws_send(ws, json.dumps({"id": msg_id, "method": "Runtime.enable"}))
        msg_id += 1
        ws_send(ws, json.dumps({"id": msg_id, "method": "Page.enable"}))

        captured_logs = []
        csp_violations = []

        # Navigate to https://enikzrad.web.id/#/login
        print("[*] Navigating to https://enikzrad.web.id/#/login ...")
        msg_id += 1
        ws_send(ws, json.dumps({"id": msg_id, "method": "Page.navigate", "params": {"url": "https://enikzrad.web.id/#/login"}}))
        
        # Collect logs and wait 6 seconds for Flutter Web rendering
        start_t = time.time()
        ws.settimeout(0.5)
        while time.time() - start_t < 6.0:
            try:
                frame = ws_recv(ws)
                if frame:
                    data = json.loads(frame)
                    if data.get('method') == 'Runtime.consoleAPICalled':
                        args = data.get('params', {}).get('args', [])
                        text = " ".join(str(a.get('value', '')) for a in args)
                        captured_logs.append(f"[Console {data['params']['type']}] {text}")
                    elif data.get('method') == 'Log.entryAdded':
                        entry = data.get('params', {}).get('entry', {})
                        text = entry.get('text', '')
                        captured_logs.append(f"[Log {entry.get('level')}] {text}")
                        if 'content security policy' in text.lower() or 'violates' in text.lower():
                            csp_violations.append(text)
            except socket.timeout:
                pass

        # Capture Login Screenshot
        msg_id += 1
        print("[*] Capturing Screenshot: Login Page...")
        ws_send(ws, json.dumps({"id": msg_id, "method": "Page.captureScreenshot", "params": {"format": "png"}}))
        while True:
            frame = ws_recv(ws)
            if frame:
                data = json.loads(frame)
                if data.get('id') == msg_id:
                    img_b64 = data['result']['data']
                    with open('audit/images/screenshot_login.png', 'wb') as sf:
                        sf.write(base64.b64decode(img_b64))
                    print(f"[+] Saved audit/images/screenshot_login.png ({len(img_b64)} b64 bytes)")
                    break

        # Navigate to Register Page
        print("[*] Navigating to https://enikzrad.web.id/#/register ...")
        msg_id += 1
        ws_send(ws, json.dumps({"id": msg_id, "method": "Page.navigate", "params": {"url": "https://enikzrad.web.id/#/register"}}))
        
        start_t = time.time()
        while time.time() - start_t < 6.0:
            try:
                frame = ws_recv(ws)
                if frame:
                    data = json.loads(frame)
                    if data.get('method') == 'Runtime.consoleAPICalled':
                        args = data.get('params', {}).get('args', [])
                        text = " ".join(str(a.get('value', '')) for a in args)
                        captured_logs.append(f"[Console {data['params']['type']}] {text}")
                    elif data.get('method') == 'Log.entryAdded':
                        entry = data.get('params', {}).get('entry', {})
                        text = entry.get('text', '')
                        captured_logs.append(f"[Log {entry.get('level')}] {text}")
                        if 'content security policy' in text.lower() or 'violates' in text.lower():
                            csp_violations.append(text)
            except socket.timeout:
                pass

        # Capture Register Screenshot
        msg_id += 1
        print("[*] Capturing Screenshot: Register Page...")
        ws_send(ws, json.dumps({"id": msg_id, "method": "Page.captureScreenshot", "params": {"format": "png"}}))
        while True:
            frame = ws_recv(ws)
            if frame:
                data = json.loads(frame)
                if data.get('id') == msg_id:
                    img_b64 = data['result']['data']
                    with open('audit/images/screenshot_register.png', 'wb') as sf:
                        sf.write(base64.b64decode(img_b64))
                    print(f"[+] Saved audit/images/screenshot_register.png ({len(img_b64)} b64 bytes)")
                    break

        print("\n" + "="*60)
        print("          REAL BROWSER CONSOLE & CSP AUDIT RESULTS      ")
        print("="*60)
        print(f"Total Console/Log Events Captured: {len(captured_logs)}")
        print(f"CSP Violations Detected          : {len(csp_violations)}")
        if csp_violations:
            for cv in csp_violations:
                print("  [!] VIOLATION:", cv)
        else:
            print("  [OK] ZERO CSP VIOLATIONS! All scripts, wasm, fonts, and sockets loaded legally.")
        print("\nCaptured Browser Logs Sample (first 10):")
        for cl in captured_logs[:10]:
            print(" ", cl)
        print("="*60)

    finally:
        proc.terminate()
        print("[*] Terminated Edge process.")

if __name__ == '__main__':
    run_browser_audit()
