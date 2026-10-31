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
    s.settimeout(5.0)
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
    assert b"101 " in resp
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

def ws_recv_frame(s):
    try:
        head = s.recv(2)
        if not head or len(head) < 2: return None
        b1, b2 = head[0], head[1]
        length = b2 & 0x7F
        if length == 126:
            length = struct.unpack("!H", s.recv(2))[0]
        elif length == 127:
            length = struct.unpack("!Q", s.recv(8))[0]
        buf = bytearray()
        while len(buf) < length:
            chunk = s.recv(min(length - len(buf), 65536))
            if not chunk: break
            buf.extend(chunk)
        return buf.decode('utf-8', errors='replace')
    except socket.timeout:
        return None
    except Exception:
        return None

def check_url(url):
    print(f"\n=== Memeriksa CSP di URL: {url} ===")
    edge = r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
    user_data = os.path.abspath(r"C:\digiq_temp_profile")
    port = 9245

    cmd = [
        edge,
        '--headless=new',
        '--no-sandbox',
        '--disable-gpu',
        f'--remote-debugging-port={port}',
        f'--user-data-dir={user_data}',
        'about:blank'
    ]
    proc = subprocess.Popen(cmd)
    
    # Retry loop menunggu Edge remote debugging port siap
    tabs = None
    for _ in range(15):
        time.sleep(1)
        try:
            tabs = json.loads(urllib.request.urlopen(f"http://127.0.0.1:{port}/json").read().decode('utf-8'))
            if tabs:
                break
        except Exception:
            pass

    if not tabs:
        proc.terminate()
        raise RuntimeError("Gagal terhubung ke Edge remote debugging port setelah 15 detik")

    try:
        ws_url = tabs[0]['webSocketDebuggerUrl']
        parsed_path = "/" + ws_url.split("/", 3)[-1]
        s = make_ws_handshake("127.0.0.1", port, parsed_path)

        msg_id = 0
        def send(method, params=None):
            nonlocal msg_id
            msg_id += 1
            ws_send(s, json.dumps({'id': msg_id, 'method': method, 'params': params or {}}))
            return msg_id

        send('Log.enable')
        send('Runtime.enable')
        send('Security.enable')
        send('Page.navigate', {'url': url})

        violations = []
        errors = []
        t_end = time.time() + 8
        while time.time() < t_end:
            frame = ws_recv_frame(s)
            if not frame:
                continue
            try:
                evt = json.loads(frame)
                method = evt.get('method', '')
                if 'violation' in frame.lower() or 'csp' in frame.lower():
                    violations.append(frame)
                if method == 'Runtime.consoleAPICalled':
                    p = evt.get('params', {})
                    if p.get('type') == 'error':
                        errors.append(p)
                elif method == 'Log.entryAdded':
                    entry = evt.get('params', {}).get('entry', {})
                    if entry.get('level') == 'error':
                        errors.append(entry)
            except Exception:
                pass

        print(f"Total CSP violations terdeteksi: {len(violations)}")
        for v in violations:
            print("  VIOLATION:", v[:200])
        print(f"Total error console terdeteksi: {len(errors)}")
        for e in errors:
            print("  ERROR:", str(e)[:200])
            
        return len(violations) == 0 and len(errors) == 0
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=3)
        except Exception:
            pass

if __name__ == '__main__':
    import sys
    ok1 = check_url("https://enikzrad.web.id/")
    ok2 = check_url("https://enikzrad.web.id/register")
    print(f"\nHASIL AKHIR: Root OK: {ok1}, Register OK: {ok2}")
    if not (ok1 and ok2):
        print("GAGAL: Ditemukan CSP violation atau console error pada edge production.")
        sys.exit(1)
    print("SUKSES: 100% Bebas CSP violation dan console error.")
    sys.exit(0)

