import subprocess
import time
import os
import json
import urllib.request
import socket
import base64
import struct
import shutil

PORT = 9235
PROFILE_DIR = os.path.abspath("temp_edge_direct_register")
EDGE_PATH = r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
SCREENSHOT_PATH = os.path.abspath(r"audit\images\screenshot_direct_register_screen.png")

def make_ws_handshake(host, port, path):
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(10.0)
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

if os.path.exists(PROFILE_DIR):
    shutil.rmtree(PROFILE_DIR, ignore_errors=True)

cmd = [
    EDGE_PATH,
    "--headless=new",
    f"--remote-debugging-port={PORT}",
    f"--user-data-dir={PROFILE_DIR}",
    "--no-first-run",
    "--no-default-browser-check",
    "--disable-gpu",
    "--window-size=1280,1000",
    "https://enikzrad.web.id/register"
]

print("[1] Menjalankan Edge headless menuju https://enikzrad.web.id/register ...")
proc = subprocess.Popen(cmd)

s = None
try:
    time.sleep(3)
    targets_url = f"http://127.0.0.1:{PORT}/json"
    with urllib.request.urlopen(targets_url, timeout=5) as res:
        targets = json.loads(res.read().decode())
    
    page = next(t for t in targets if t.get("type") == "page")
    ws_url = page["webSocketDebuggerUrl"]
    print(f"[2] Target WebSocket ditemukan: {ws_url}")

    parts = ws_url.replace("ws://", "").split("/", 1)
    host, port_str = parts[0].split(":")
    ws_path = "/" + parts[1]
    s = make_ws_handshake(host, int(port_str), ws_path)
    s.settimeout(5.0)

    msg_id = 1
    def send_cmd(method, params=None):
        global msg_id
        mid = msg_id
        msg_id += 1
        ws_send(s, json.dumps({"id": mid, "method": method, "params": params or {}}))
        return mid

    send_cmd("Page.enable")
    send_cmd("DOM.enable")
    send_cmd("Emulation.setDeviceMetricsOverride", {
        "width": 1280,
        "height": 1000,
        "deviceScaleFactor": 1,
        "mobile": False
    })

    print("[3] Menunggu 10 detik inisialisasi render Flutter Web...")
    time.sleep(10)

    # Capture screenshot
    req_id = send_cmd("Page.captureScreenshot", {"format": "png"})
    print("[4] Mengambil screenshot...")

    screenshot_b64 = None
    deadline = time.time() + 10
    while time.time() < deadline:
        frame = ws_recv_frame(s)
        if not frame: continue
        try:
            data = json.loads(frame)
            if data.get("id") == req_id:
                screenshot_b64 = data["result"]["data"]
                break
        except Exception:
            pass

    if screenshot_b64:
        os.makedirs(os.path.dirname(SCREENSHOT_PATH), exist_ok=True)
        img_bytes = base64.b64decode(screenshot_b64)
        with open(SCREENSHOT_PATH, "wb") as f:
            f.write(img_bytes)
        print(f"[SUKSES] Screenshot halaman /register tersimpan di:\n  {SCREENSHOT_PATH}\n  (Ukuran: {len(img_bytes)} bytes)")
    else:
        print("[GAGAL] Tidak dapat menangkap screenshot dari browser.")

finally:
    if s:
        try: s.close()
        except Exception: pass
    proc.terminate()
    try: proc.wait(timeout=5)
    except Exception: proc.kill()
    time.sleep(1)
    if os.path.exists(PROFILE_DIR):
        shutil.rmtree(PROFILE_DIR, ignore_errors=True)
