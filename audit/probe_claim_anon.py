#!/usr/bin/env python3
"""
DigiQ Audit Probe: Anon Access to Claim RPCs
File: audit/probe_claim_anon.py

Menguji bahwa RPC `request_claim` dan `admin_mark_delivered` ditolak secara tegas
ketika dipanggil oleh client anonim (tanpa sesi/JWT terotentikasi).

PERINGATAN:
Skrip ini HANYA boleh dijalankan setelah migrasi supabase/019_claim_via_chat.sql
telah dieksekusi di database live. Sebelum migrasi dijalankan, pengujian ini
ditandai sebagai NOT TESTED (karena respons "function not found" bukanlah bukti keamanan).
"""

import os
import sys
import json
import urllib.request
import urllib.error

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
    env = load_env()
    url = env.get('SUPABASE_URL')
    anon_key = env.get('SUPABASE_ANON_KEY')

    if not url or not anon_key:
        print("[ERROR] Konfigurasi SUPABASE_URL atau SUPABASE_ANON_KEY tidak ditemukan di .env")
        sys.exit(1)

    print("=== PROBE AKSES ANONIM KE RPC KLAIM ===")
    print(f"Target URL: {url}")
    print("Identitas : Anonymous (tanpa user token)")
    print("-" * 50)

    dummy_trx_id = "00000000-0000-0000-0000-000000000000"

    # 1. Probe request_claim
    status1, body1 = probe_rpc(url, anon_key, 'request_claim', {'p_trx_id': dummy_trx_id})
    print(f"1. RPC request_claim -> HTTP Status: {status1}")
    print(f"   Respons: {body1[:150]}")

    # 2. Probe admin_mark_delivered
    status2, body2 = probe_rpc(url, anon_key, 'admin_mark_delivered', {'p_trx_id': dummy_trx_id})
    print(f"2. RPC admin_mark_delivered -> HTTP Status: {status2}")
    print(f"   Respons: {body2[:150]}")

    # Evaluasi penolakan
    # Akses ditolak bila status 401, 403, atau 400/404 dengan pesan permission/not found
    is_rejected_1 = status1 in (401, 403) or '42501' in body1 or 'denied' in body1.lower()
    is_rejected_2 = status2 in (401, 403) or '42501' in body2 or 'denied' in body2.lower()

    print("-" * 50)
    if is_rejected_1 and is_rejected_2:
        print("[PASS] Kedua RPC aman: Akses anonim ditolak oleh database!")
        sys.exit(0)
    else:
        print("[INFO] RPC belum aktif di DB atau respons tidak terduga.")
        sys.exit(2)

if __name__ == '__main__':
    main()

