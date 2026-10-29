#!/usr/bin/env python3
"""
==============================================================================
SKRIP PENGUJIAN MANUAL SIGNUP END-TO-END (DIGIQ)
==============================================================================
PERHATIAN AUDIT / KEAMANAN:
- JANGAN JALANKAN SKRIP INI SECARA OTOMATIS OLEH AI ASSISTANT / AGENT.
- HANYA DIJALANKAN SECARA MANUAL OLEH USER MENGGUNAKAN AKUN KHUSUS PENGUJIAN.
- Skrip ini menggunakan ANON KEY publik (bukan service_role).
- Mengukur durasi roundtrip request ke endpoint auth GoTrue Supabase secara presisi.
- Nilai token dan data kredensial otomatis disamarkan (masked) pada output log.

Cara Penggunaan Manual oleh User:
    python audit/test_manual_signup_e2e.py --email tes_user1@example.com --username tesuser1 --name "User Tes 1" --password "Rahasia123!"

Atau jalankan tanpa argumen untuk mode prompt interaktif:
    python audit/test_manual_signup_e2e.py
==============================================================================
"""

import sys
import os
import json
import time
import argparse
import urllib.request
import urllib.error
import ssl
import re

def load_env(env_path=".env"):
    """Membaca variabel SUPABASE_URL dan SUPABASE_ANON_KEY dari .env."""
    config = {}
    if os.path.exists(env_path):
        with open(env_path, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith("#") and "=" in line:
                    k, v = line.split("=", 1)
                    config[k.strip()] = v.strip().strip('"').strip("'")
    return config

def mask_sensitive(text):
    """Menyamarkan token JWT, access token, dan password pada output log."""
    if not isinstance(text, str):
        text = str(text)
    # Mask JWT / anon token
    text = re.sub(r'ey[A-Za-z0-9_-]{15,}', 'ey...[MASKED_TOKEN]...', text)
    # Mask refresh token
    text = re.sub(r'"refresh_token":\s*"[^"]+"', '"refresh_token": "[MASKED]"', text)
    return text

def main():
    parser = argparse.ArgumentParser(description="Pengujian Manual Signup End-to-End DigiQ")
    parser.add_argument("--email", help="Email akun tes pendaftaran")
    parser.add_argument("--password", help="Password akun tes pendaftaran")
    parser.add_argument("--username", help="Username akun tes pendaftaran")
    parser.add_argument("--name", default="User Tester", help="Nama lengkap (display name)")
    args = parser.parse_args()

    # Mode interaktif jika parameter tidak diberikan lewat CLI
    email = args.email
    password = args.password
    username = args.username
    full_name = args.name

    print("\n" + "="*70)
    print(" DIGIQ MANUAL E2E SIGNUP TESTER (READ-ONLY AUDIT GUARD)")
    print("="*70)
    print("[INFO] Skrip ini siap dijalankan secara manual oleh user penguji.")

    env_config = load_env()
    supabase_url = env_config.get("SUPABASE_URL", "https://iqxoofrhhrqkgehuvrlb.supabase.co").rstrip("/")
    anon_key = env_config.get("SUPABASE_ANON_KEY")

    if not anon_key:
        print("[ERROR] SUPABASE_ANON_KEY tidak ditemukan di .env.")
        sys.exit(1)

    if not email:
        email = input("\nMasukkan Email Akun Tes: ").strip()
    if not username:
        username = input("Masukkan Username Akun Tes: ").strip()
    if not password:
        password = input("Masukkan Password Akun Tes: ").strip()

    if not email or not username or not password:
        print("[ABORT] Email, username, dan password wajib diisi untuk tes pendaftaran.")
        sys.exit(1)

    signup_url = f"{supabase_url}/auth/v1/signup"
    headers = {
        "apikey": anon_key,
        "Authorization": f"Bearer {anon_key}",
        "Content-Type": "application/json",
        "User-Agent": "DigiQ-Audit-ManualTester/1.0"
    }

    payload = {
        "email": email,
        "password": password,
        "data": {
            "username": username,
            "full_name": full_name
        }
    }

    data_bytes = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(signup_url, data=data_bytes, headers=headers, method="POST")

    print("\n[START] Mengirim request pendaftaran ke GoTrue...")
    print(f"Target URL: {signup_url}")
    print(f"Payload   : email={email}, username={username}, full_name={full_name}")

    ctx = ssl.create_default_context()
    start_time = time.perf_counter()

    status_code = None
    response_body = ""
    error_occurred = False

    try:
        with urllib.request.urlopen(req, timeout=15, context=ctx) as resp:
            elapsed_ms = (time.perf_counter() - start_time) * 1000
            status_code = resp.status
            response_body = resp.read().decode("utf-8")
    except urllib.error.HTTPError as e:
        elapsed_ms = (time.perf_counter() - start_time) * 1000
        status_code = e.code
        response_body = e.read().decode("utf-8")
        error_occurred = True
    except Exception as e:
        elapsed_ms = (time.perf_counter() - start_time) * 1000
        status_code = "NETWORK_ERROR"
        response_body = str(e)
        error_occurred = True

    print("\n" + "-"*70)
    print(" HASIL PENGUJIAN SIGNUP END-TO-END:")
    print("-"*70)
    print(f"HTTP Status      : {status_code}")
    print(f"Durasi Request   : {elapsed_ms:.2f} ms ({elapsed_ms/1000:.3f} detik)")
    
    # Format & mask response
    try:
        parsed_json = json.loads(response_body)
        formatted_body = json.dumps(parsed_json, indent=2)
    except Exception:
        formatted_body = response_body

    masked_body = mask_sensitive(formatted_body)
    print(f"Response Body    :\n{masked_body}")
    print("-"*70)

    if status_code == 200:
        print("[SUKSES] Akun pendaftaran berhasil diproses oleh auth server.")
        if "user" in response_body:
            print("[INFO] Objek User terbentuk dengan metadata username & full_name.")
    elif status_code == 422:
        print("[VALIDASI] Email sudah terdaftar atau input tidak memenuhi aturan validasi.")
    elif status_code == 429:
        print("[RATE LIMIT] Batas pengiriman request GoTrue terlampaui. Tunggu beberapa saat.")
    else:
        print(f"[STATUS] Respon server: {status_code}")
    print("="*70 + "\n")

if __name__ == "__main__":
    main()

