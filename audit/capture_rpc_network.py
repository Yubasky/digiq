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
    except Exception as e:
        return None

def run():
    edge = r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
    user_data = os.path.abspath("edge_rpc_diag_profile")
    port = 9240

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
    time.sleep(2)

    try:
        v_url = f"http://127.0.0.1:{port}/json"
        with urllib.request.urlopen(v_url, timeout=5) as r:
            targets = json.loads(r.read().decode())
        ws_url = targets[0]['webSocketDebuggerUrl']
        path = ws_url.split(f":{port}")[1]
        ws = make_ws_handshake("127.0.0.1", port, path)
        ws.settimeout(0.5)

        msg_id = 1
        ws_send(ws, json.dumps({"id": msg_id, "method": "Network.enable"}))
        msg_id += 1
        ws_send(ws, json.dumps({"id": msg_id, "method": "Page.enable"}))
        msg_id += 1
        ws_send(ws, json.dumps({
            "id": msg_id,
            "method": "Emulation.setDeviceMetricsOverride",
            "params": {"width": 1280, "height": 1000, "deviceScaleFactor": 1, "mobile": False}
        }))

        print("[*] Navigating to https://enikzrad.web.id/#/register ...")
        msg_id += 1
        ws_send(ws, json.dumps({"id": msg_id, "method": "Page.navigate", "params": {"url": "https://enikzrad.web.id/#/register"}}))

        # Drain initial navigation
        t0 = time.time()
        while time.time() - t0 < 6.0:
            ws_recv_frame(ws)

        # Focus Username field (x=640, y=380)
        print("[*] Focusing Username field at (640, 380)...")
        msg_id += 1
        ws_send(ws, json.dumps({"id": msg_id, "method": "Input.dispatchMouseEvent", "params": {"type": "mouseMoved", "x": 640, "y": 380}}))
        msg_id += 1
        ws_send(ws, json.dumps({"id": msg_id, "method": "Input.dispatchMouseEvent", "params": {"type": "mousePressed", "x": 640, "y": 380, "button": "left", "clickCount": 1}}))
        time.sleep(0.05)
        msg_id += 1
        ws_send(ws, json.dumps({"id": msg_id, "method": "Input.dispatchMouseEvent", "params": {"type": "mouseReleased", "x": 640, "y": 380, "button": "left", "clickCount": 1}}))
        time.sleep(0.2)

        # Type "digiqtester"
        print("[*] Typing username 'digiqtester' character by character...")
        for char in "digiqtester":
            msg_id += 1
            ws_send(ws, json.dumps({"id": msg_id, "method": "Input.dispatchKeyEvent", "params": {"type": "keyDown", "text": char, "unmodifiedText": char}}))
            msg_id += 1
            ws_send(ws, json.dumps({"id": msg_id, "method": "Input.dispatchKeyEvent", "params": {"type": "keyUp"}}))
            time.sleep(0.05)

        captured_rpc = []
        target_request_id = None

        print("[*] Listening for network responses for 5 seconds...")
        t0 = time.time()
        while time.time() - t0 < 5.0:
            f = ws_recv_frame(ws)
            if f:
                try:
                    d = json.loads(f)
                    method = d.get('method')
                    params = d.get('params', {})
                    if method == 'Network.requestWillBeSent':
                        req = params.get('request', {})
                        url = req.get('url', '')
                        if 'check_username_available' in url:
                            r_id = params.get('requestId')
                            target_request_id = r_id
                            captured_rpc.append({
                                'event': 'requestWillBeSent',
                                'requestId': r_id,
                                'method': req.get('method'),
                                'url': url,
                                'postData': req.get('postData'),
                                'headers': {k: ('[MASKED]' if 'key' in k.lower() or 'auth' in k.lower() else v) for k, v in req.get('headers', {}).items()}
                            })
                            print(f"[+] Captured Request: {req.get('method')} {url}")
                    elif method == 'Network.responseReceived':
                        resp = params.get('response', {})
                        url = resp.get('url', '')
                        if 'check_username_available' in url:
                            r_id = params.get('requestId')
                            captured_rpc.append({
                                'event': 'responseReceived',
                                'requestId': r_id,
                                'status': resp.get('status'),
                                'statusText': resp.get('statusText'),
                                'url': url,
                                'headers': resp.get('headers')
                            })
                            print(f"[+] Captured Response: HTTP {resp.get('status')} {resp.get('statusText')} for {url}")
                except Exception as ex:
                    pass

        # If we got response, request the body
        response_body = None
        if target_request_id:
            print(f"[*] Requesting response body for RequestId: {target_request_id}...")
            msg_id += 1
            body_call_id = msg_id
            ws_send(ws, json.dumps({"id": body_call_id, "method": "Network.getResponseBody", "params": {"requestId": target_request_id}}))
            t0 = time.time()
            while time.time() - t0 < 3.0:
                f = ws_recv_frame(ws)
                if f:
                    try:
                        d = json.loads(f)
                        if d.get('id') == body_call_id:
                            response_body = d.get('result', {}).get('body')
                            print(f"[+] Raw Response Body: {response_body}")
                            break
                    except:
                        pass

        print("\n" + "=" * 60)
        print("    REAL BROWSER HEADLESS RPC NETWORK AUDIT REPORT   ")
        print("=" * 60)
        for ev in captured_rpc:
            print(json.dumps(ev, indent=2))
        print(f"\nFinal Response Body: {response_body}")
        print("=" * 60)

    finally:
        proc.terminate()

if __name__ == '__main__':
    run()

