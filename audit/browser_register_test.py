import subprocess
import time
import os
import json
import urllib.request
import socket
import base64
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
    try:
        head = s.recv(2)
    except socket.timeout:
        return None
    if not head or len(head) < 2: return None
    b1, b2 = head[0], head[1]
    length = b2 & 0x7F
    if length == 126:
        length = struct.unpack("!H", s.recv(2))[0]
    elif length == 127:
        length = struct.unpack("!Q", s.recv(8))[0]
    payload = b""
    while len(payload) < length:
        try:
            chunk = s.recv(min(length - len(payload), 65536))
            if not chunk: break
            payload += chunk
        except socket.timeout:
            continue
    return payload.decode('utf-8', errors='replace')

def run_test():
    edge = r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
    user_data = os.path.abspath("edge_register_profile")
    port = 9224

    cmd = [
        edge,
        '--headless=new',
        '--no-sandbox',
        '--disable-gpu',
        f'--remote-debugging-port={port}',
        f'--user-data-dir={user_data}',
        '--window-size=1280,900',
        'about:blank'
    ]
    proc = subprocess.Popen(cmd)
    print(f"[*] Launched Edge Headless PID: {proc.pid} on port {port}")
    time.sleep(2)

    try:
        v_url = f"http://127.0.0.1:{port}/json"
        with urllib.request.urlopen(v_url, timeout=5) as r:
            targets = json.loads(r.read().decode())
        ws_url = targets[0]['webSocketDebuggerUrl']
        path = ws_url.split(f":{port}")[1]
        ws = make_ws_handshake("127.0.0.1", port, path)
        print("[+] Connected to CDP.")

        msg_id = 1
        ws_send(ws, json.dumps({"id": msg_id, "method": "Log.enable"}))
        msg_id += 1
        ws_send(ws, json.dumps({"id": msg_id, "method": "Runtime.enable"}))
        msg_id += 1
        ws_send(ws, json.dumps({"id": msg_id, "method": "Page.enable"}))
        msg_id += 1
        ws_send(ws, json.dumps({"id": msg_id, "method": "Network.enable"}))

        captured_logs = []
        csp_violations = []
        rpc_requests = []

        url = "https://enikzrad.web.id/#/register"
        print(f"[*] Navigating to {url} ...")
        msg_id += 1
        ws_send(ws, json.dumps({"id": msg_id, "method": "Page.navigate", "params": {"url": url}}))

        ws.settimeout(0.5)
        start_t = time.time()
        while time.time() - start_t < 7.0:
            frame = ws_recv(ws)
            if frame:
                try:
                    data = json.loads(frame)
                    method = data.get('method')
                    if method == 'Runtime.consoleAPICalled':
                        args = data.get('params', {}).get('args', [])
                        text = " ".join(str(a.get('value', '')) for a in args)
                        captured_logs.append(f"[Console {data['params']['type']}] {text}")
                    elif method == 'Log.entryAdded':
                        entry = data.get('params', {}).get('entry', {})
                        text = entry.get('text', '')
                        captured_logs.append(f"[Log {entry.get('level')}] {text}")
                        if 'content security policy' in text.lower() or 'violates' in text.lower():
                            csp_violations.append(text)
                    elif method == 'Network.requestWillBeSent':
                        req = data.get('params', {}).get('request', {})
                        r_url = req.get('url', '')
                        if 'rpc' in r_url or 'supabase' in r_url:
                            rpc_requests.append(f"REQ {req.get('method')} {r_url}")
                except:
                    pass

        # Capture initial screenshot
        msg_id += 1
        print("[*] Capturing Screenshot: Register Page...")
        ws_send(ws, json.dumps({"id": msg_id, "method": "Page.captureScreenshot", "params": {"format": "png"}}))
        wait_start = time.time()
        while time.time() - wait_start < 5.0:
            frame = ws_recv(ws)
            if frame:
                try:
                    data = json.loads(frame)
                    if data.get('id') == msg_id:
                        with open('audit/images/screenshot_register.png', 'wb') as sf:
                            sf.write(base64.b64decode(data['result']['data']))
                        print(f"[+] Saved audit/images/screenshot_register.png ({len(data['result']['data'])} b64 bytes)")
                        break
                except:
                    pass

        # Dispatch click to focus the username input field (center of screen, y ≈ 380)
        print("[*] Clicking Username field and typing 'digiquser99'...")
        msg_id += 1
        ws_send(ws, json.dumps({"id": msg_id, "method": "Input.dispatchMouseEvent", "params": {"type": "mousePressed", "x": 640, "y": 380, "button": "left", "clickCount": 1}}))
        msg_id += 1
        ws_send(ws, json.dumps({"id": msg_id, "method": "Input.dispatchMouseEvent", "params": {"type": "mouseReleased", "x": 640, "y": 380, "button": "left", "clickCount": 1}}))
        
        # Insert text
        msg_id += 1
        ws_send(ws, json.dumps({"id": msg_id, "method": "Input.insertText", "params": {"text": "digiquser99"}}))

        # Wait 4 seconds for debounce + RPC network execution
        start_t = time.time()
        while time.time() - start_t < 4.0:
            frame = ws_recv(ws)
            if frame:
                try:
                    data = json.loads(frame)
                    method = data.get('method')
                    if method == 'Runtime.consoleAPICalled':
                        args = data.get('params', {}).get('args', [])
                        text = " ".join(str(a.get('value', '')) for a in args)
                        captured_logs.append(f"[Console {data['params']['type']}] {text}")
                    elif method == 'Log.entryAdded':
                        entry = data.get('params', {}).get('entry', {})
                        text = entry.get('text', '')
                        captured_logs.append(f"[Log {entry.get('level')}] {text}")
                        if 'content security policy' in text.lower() or 'violates' in text.lower():
                            csp_violations.append(text)
                    elif method == 'Network.requestWillBeSent':
                        req = data.get('params', {}).get('request', {})
                        r_url = req.get('url', '')
                        if 'rpc' in r_url or 'supabase' in r_url:
                            rpc_requests.append(f"REQ {req.get('method')} {r_url}")
                except:
                    pass

        # Capture screenshot after typing
        msg_id += 1
        print("[*] Capturing Screenshot: Register Page with Typed Username...")
        ws_send(ws, json.dumps({"id": msg_id, "method": "Page.captureScreenshot", "params": {"format": "png"}}))
        wait_start = time.time()
        while time.time() - wait_start < 5.0:
            frame = ws_recv(ws)
            if frame:
                try:
                    data = json.loads(frame)
                    if data.get('id') == msg_id:
                        with open('audit/images/screenshot_register_typed.png', 'wb') as sf:
                            sf.write(base64.b64decode(data['result']['data']))
                        print(f"[+] Saved audit/images/screenshot_register_typed.png ({len(data['result']['data'])} b64 bytes)")
                        break
                except:
                    pass

        print("\n" + "=" * 60)
        print("          REAL BROWSER CONSOLE & CSP AUDIT RESULTS      ")
        print("=" * 60)
        print(f"Total Console/Log Events: {len(captured_logs)}")
        print(f"CSP Violations Detected : {len(csp_violations)}")
        if csp_violations:
            for cv in csp_violations:
                print("  [!] VIOLATION:", cv)
        else:
            print("  [OK] ZERO CSP VIOLATIONS! All scripts, wasm, and sockets loaded legally.")
        
        print(f"\nNetwork Supabase/RPC Requests Captured ({len(rpc_requests)}):")
        for r in rpc_requests:
            print(" ", r)

        print(f"\nCaptured Browser Logs Sample ({len(captured_logs)} total):")
        for cl in captured_logs:
            print(" ", cl)
        print("=" * 60)

    finally:
        proc.terminate()
        print("[*] Terminated Edge process.")

if __name__ == '__main__':
    run_test()

