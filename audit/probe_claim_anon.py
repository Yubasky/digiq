#!/usr/bin/env python3
"""
DigiQ Audit Probe: Anon Access to Claim RPCs
File: audit/probe_claim_anon.py

Menguji bahwa RPC `request_claim` dan `admin_mark_delivered` ditolak secara tegas
DI TINGKAT DATABASE ENGINE (permission denied for function), BUKAN dari dalam body fungsi
(seperti pesan 'pengguna belum terautentikasi' atau 'hanya admin').
"""

import os
import sys
import json
import urllib.request
import urllib.error

BANNED_BODY_PHRASES = [
    'belum terautentikasi',
    'hanya admin',
    'terlalu banyak permintaan',
    'pesanan tidak ditemukan',
    'tidak ditemukan',
    'status tidak valid',
    'hanya boleh diubah melalui alur klaim resmi',
]

def evaluate_response(status, body):
    """
    Evaluasi ketat respons anonim:
    - FAIL jika pesan error berasal dari RAISE EXCEPTION di dalam body fungsi.
    - PASS HANYA jika penolakan terjadi di tingkat database permissions ('permission denied for function').
    """
    if not isinstance(body, str):
        body = str(body)

    body_lower = body.lower()

    # 1. Cek apakah ada pesan buatan dari dalam body fungsi
    for phrase in BANNED_BODY_PHRASES:
        if phrase in body_lower:
            return False, f"FAIL: Panggilan menembus ke dalam body fungsi (pesan: '{phrase}')"

    # 2. Cek apakah ada penolakan otorisasi di level database engine
    if status in (401, 403, 404):
        if 'permission denied' in body_lower or 'access denied' in body_lower:
            return True, "PASS: Ditolak tegas di tingkat engine (permission denied for function)"

    # 3. Respons sukses atau status lainnya
    if status == 200:
        return False, "FAIL: RPC berhasil dieksekusi oleh anonim (kritis!)"

    return False, f"FAIL: Status HTTP {status} tanpa pesan permission denied (Respons: {body[:100]})"

def run_parser_unit_tests():
    """Unit test parser evaluasi respons dengan fixtures PASS dan FAIL."""
    print("=== MENJALANKAN UJI UNIT PARSER EVALUASI RESPONS ===")
    fixtures = [
        # (name, status, body, expected_pass)
        (
            "Fixture 1: Body leak 'belum terautentikasi' (Pra-020)",
            401,
            '{"code":"42501","details":null,"hint":null,"message":"Akses ditolak: pengguna belum terautentikasi"}',
            False
        ),
        (
            "Fixture 2: Body leak 'hanya admin' (Pra-020)",
            401,
            '{"code":"42501","details":null,"hint":null,"message":"Akses ditolak: hanya admin yang dapat menandai pesanan terkirim"}',
            False
        ),
        (
            "Fixture 3: Postgres engine 'permission denied for function request_claim' (Pasca-020)",
            401,
            '{"code":"42501","details":null,"hint":null,"message":"permission denied for function request_claim"}',
            True
        ),
        (
            "Fixture 4: PostgREST 403 Forbidden 'permission denied for function admin_mark_delivered'",
            403,
            '{"message":"permission denied for function admin_mark_delivered"}',
            True
        ),
        (
            "Fixture 5: Status 200 Success (Vulnerable)",
            200,
            '{"success":true,"claim_status":"requested"}',
            False
        ),
    ]

    all_passed = True
    for name, status, body, expected_pass in fixtures:
        passed, reason = evaluate_response(status, body)
        match = (passed == expected_pass)
        status_lbl = "OK" if match else "MISMATCH"
        print(f"[{status_lbl}] {name}")
        print(f"       Hasil: {'PASS' if passed else 'FAIL'} | Alasan: {reason}")
        if not match:
            all_passed = False

    print("-" * 60)
    if all_passed:
        print("[PASS] Seluruh 5 fixture unit test parser lolos evaluasi ketat!")
        return 0
    else:
        print("[FAIL] Terdapat kesalahan logika pada parser.")
        return 1

def load_env():
    env_file = os.path.join(os.path.dirname(__file__), '..', '.env')
    env = {}
    if os.path.exists(env_file):
        with open(env_file, 'r', encoding='utf-8') as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith('#') and '=' in line:
                    k, v = line.split('=', 1)
                    env[k.strip()] = v.strip().strip('"').strip("'")
    return env

def probe_rpc(url, anon_key, rpc_name, payload):
    endpoint = f"{url}/rest/v1/rpc/{rpc_name}"
    headers = {
        'apikey': anon_key,
        'Authorization': f"Bearer {anon_key}",
        'Content-Type': 'application/json',
    }
    data = json.dumps(payload).encode('utf-8')
    req = urllib.request.Request(endpoint, data=data, headers=headers, method='POST')

    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            body = resp.read().decode('utf-8')
            return resp.status, body
    except urllib.error.HTTPError as e:
        body = e.read().decode('utf-8')
        return e.code, body
    except Exception as e:
        return None, str(e)

def main():
    if '--unit-test' in sys.argv or '--test' in sys.argv:
        sys.exit(run_parser_unit_tests())

    env = load_env()
    url = env.get('SUPABASE_URL')
    anon_key = env.get('SUPABASE_ANON_KEY')

    if not url or not anon_key:
        print("[ERROR] Konfigurasi SUPABASE_URL atau SUPABASE_ANON_KEY tidak ditemukan di .env")
        sys.exit(1)

    print("=== PROBE AKSES ANONIM KE RPC KLAIM (EVALUASI KETAT TINGKAT ENGINE) ===")
    print(f"Target URL: {url}")
    print("Identitas : Anonymous (tanpa user token)")
    print("-" * 65)

    dummy_trx_id = "00000000-0000-0000-0000-000000000000"

    # 1. Probe request_claim
    status1, body1 = probe_rpc(url, anon_key, 'request_claim', {'p_trx_id': dummy_trx_id})
    pass1, reason1 = evaluate_response(status1, body1)
    print(f"1. RPC request_claim -> HTTP Status: {status1}")
    print(f"   Respons: {body1[:140]}")
    print(f"   Evaluasi: {reason1}")

    # 2. Probe admin_mark_delivered
    status2, body2 = probe_rpc(url, anon_key, 'admin_mark_delivered', {'p_trx_id': dummy_trx_id})
    pass2, reason2 = evaluate_response(status2, body2)
    print(f"2. RPC admin_mark_delivered -> HTTP Status: {status2}")
    print(f"   Respons: {body2[:140]}")
    print(f"   Evaluasi: {reason2}")

    print("-" * 65)
    if pass1 and pass2:
        print("[PASS] Kedua RPC aman: Akses anonim ditolak di level permission database!")
        sys.exit(0)
    else:
        print("[FAIL] RPC masih dapat diakses oleh anon atau menembus ke dalam body fungsi!")
        sys.exit(2)

if __name__ == '__main__':
    main()
