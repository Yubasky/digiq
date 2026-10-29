import sys
import os
import argparse
import urllib.request
import json

sys.stdout.reconfigure(encoding='utf-8')

def parse_env():
    env = {}
    if os.path.exists('.env'):
        with open('.env', 'r', encoding='utf-8') as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith('#') and '=' in line:
                    k, v = line.split('=', 1)
                    env[k.strip()] = v.strip().strip('"').strip("'")
    return env

def login_user(supa_url, anon_key, email, password):
    url = f"{supa_url}/auth/v1/token?grant_type=password"
    headers = {
        'apikey': anon_key,
        'Content-Type': 'application/json',
    }
    data = json.dumps({'email': email, 'password': password}).encode('utf-8')
    req = urllib.request.Request(url, data=data, headers=headers, method='POST')
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            body = json.loads(resp.read().decode('utf-8'))
            return body.get('access_token'), body.get('user', {}).get('id')
    except urllib.error.HTTPError as e:
        print(f"[-] Login gagal untuk {email}: HTTP {e.code} -> {e.read().decode('utf-8')}")
        return None, None
    except Exception as e:
        print(f"[-] Error koneksi login {email}: {e}")
        return None, None

def run_rls_checks(supa_url, anon_key, token_a, id_a, id_b):
    headers_a = {
        'apikey': anon_key,
        'Authorization': f'Bearer {token_a}',
        'Content-Type': 'application/json',
        'Prefer': 'return=representation',
    }

    print("\n" + "="*65)
    print("      SKRIP UJI KEAMANAN ROW LEVEL SECURITY (RLS) MULTI-TENANT    ")
    print("="*65)
    print(f"User A (Attacking Principal) : ID {id_a}")
    print(f"User B (Victim Principal)    : ID {id_b}")
    print("Prinsip: Hanya menggunakan Anon Key + User Token (Zero Service-Role)\n")

    # 1. User A tries to SELECT Profile B
    print("[1] Uji: User A membaca Profile User B...")
    url = f"{supa_url}/rest/v1/profiles?id=eq.{id_b}&select=*"
    req = urllib.request.Request(url, headers=headers_a, method='GET')
    with urllib.request.urlopen(req) as resp:
        rows = json.loads(resp.read().decode('utf-8'))
        if len(rows) == 0:
            print("    -> PASS: 0 baris dikembalikan. Akses data profil User B DIBLOKIR oleh RLS.")
        else:
            print(f"    -> VULNERABLE: Berhasil membaca data profil B! Rows: {rows}")

    # 2. User A tries to UPDATE Profile B
    print("\n[2] Uji: User A mengubah nama pada Profile User B...")
    url = f"{supa_url}/rest/v1/profiles?id=eq.{id_b}"
    payload = json.dumps({'full_name': 'HACKED_BY_A'}).encode('utf-8')
    req = urllib.request.Request(url, data=payload, headers=headers_a, method='PATCH')
    try:
        with urllib.request.urlopen(req) as resp:
            rows = json.loads(resp.read().decode('utf-8'))
            if len(rows) == 0:
                print("    -> PASS: 0 baris dimodifikasi. Modifikasi lintas tenant DIBLOKIR.")
            else:
                print(f"    -> VULNERABLE: Profile B berhasil diubah! {rows}")
    except urllib.error.HTTPError as e:
        print(f"    -> PASS: Ditolak dengan HTTP {e.code} (RLS Policy Enforcement).")

    # 3. User A tries to SELECT Transactions of B
    print("\n[3] Uji: User A membaca daftar transaksi milik User B...")
    url = f"{supa_url}/rest/v1/transactions?user_id=eq.{id_b}&select=*"
    req = urllib.request.Request(url, headers=headers_a, method='GET')
    with urllib.request.urlopen(req) as resp:
        rows = json.loads(resp.read().decode('utf-8'))
        if len(rows) == 0:
            print("    -> PASS: 0 baris dikembalikan. Transaksi User B DIBLOKIR dari User A.")
        else:
            print(f"    -> VULNERABLE: User A dapat melihat transaksi milik B! {rows}")

    # 4. User A tries Privilege Escalation (Ubah role sendiri jadi 'admin')
    print("\n[4] Uji: User A mencoba eskalasi wewenang (mengubah role dirinya ke 'admin')...")
    url = f"{supa_url}/rest/v1/profiles?id=eq.{id_a}"
    payload = json.dumps({'role': 'admin'}).encode('utf-8')
    req = urllib.request.Request(url, data=payload, headers=headers_a, method='PATCH')
    try:
        with urllib.request.urlopen(req) as resp:
            rows = json.loads(resp.read().decode('utf-8'))
            # Cek apakah role benar-benar berubah
            if rows and rows[0].get('role') == 'admin':
                print("    -> VULNERABLE: User A berhasil mengeskalasi role menjadi 'admin'!")
            else:
                print("    -> PASS: Kolom role tidak berubah (Ditolak / Diproteksi).")
    except urllib.error.HTTPError as e:
        print(f"    -> PASS: Ditolak dengan HTTP {e.code} ({e.read().decode('utf-8').strip()}).")

    # 5. User A tries Direct Balance Tampering (Manipulasi saldo sendiri)
    print("\n[5] Uji: User A mencoba manipulasi saldo sendiri secara langsung via REST...")
    url = f"{supa_url}/rest/v1/profiles?id=eq.{id_a}"
    payload = json.dumps({'balance': 999999999}).encode('utf-8')
    req = urllib.request.Request(url, data=payload, headers=headers_a, method='PATCH')
    try:
        with urllib.request.urlopen(req) as resp:
            rows = json.loads(resp.read().decode('utf-8'))
            if rows and rows[0].get('balance') == 999999999:
                print("    -> VULNERABLE: Saldo berhasil diubah langsung oleh pengguna!")
            else:
                print("    -> PASS: Saldo tidak bertambah (Diproteksi oleh RLS/Triggers).")
    except urllib.error.HTTPError as e:
        print(f"    -> PASS: Ditolak dengan HTTP {e.code} ({e.read().decode('utf-8').strip()}).")

    print("\n" + "="*65 + "\n")

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description="Multi-tenant RLS Audit Script (2 Akun Customer)")
    parser.add_argument('--email-a', help="Email Customer A (Penyerang)")
    parser.add_argument('--pass-a', help="Password Customer A")
    parser.add_argument('--email-b', help="Email Customer B (Korban)")
    parser.add_argument('--pass-b', help="Password Customer B")
    parser.add_argument('--token-a', help="JWT Access Token Customer A (jika sudah ada)")
    parser.add_argument('--id-a', help="UUID User A")
    parser.add_argument('--id-b', help="UUID User B")

    args = parser.parse_args()
    env = parse_env()
    supa_url = env.get('SUPABASE_URL', '').rstrip('/')
    anon_key = env.get('SUPABASE_ANON_KEY', '')

    if not supa_url or not anon_key:
        print("[-] SUPABASE_URL atau SUPABASE_ANON_KEY tidak ditemukan di .env")
        sys.exit(1)

    token_a = args.token_a
    id_a = args.id_a
    id_b = args.id_b

    if not token_a and args.email_a and args.pass_a:
        print(f"[*] Melakukan autentikasi User A ({args.email_a})...")
        token_a, id_a = login_user(supa_url, anon_key, args.email_a, args.pass_a)

    if not id_b and args.email_b and args.pass_b:
        print(f"[*] Melakukan autentikasi User B ({args.email_b}) untuk mendapatkan UUID...")
        _, id_b = login_user(supa_url, anon_key, args.email_b, args.pass_b)

    if token_a and id_a and id_b:
        run_rls_checks(supa_url, anon_key, token_a, id_a, id_b)
    else:
        print("""
[PETUNJUK PENGGUNAAN SKRIP UJI RLS 2 AKUN]:
Skrip ini dirancang khusus untuk menguji isolasi hak akses antara 2 akun Customer
pada project staging atau database uji tanpa menggunakan service_role key.

Contoh Eksekusi:
  python audit/test_customer_rls.py --email-a userA@test.com --pass-a Secret123! --email-b userB@test.com --pass-b Secret123!

Atau jika Anda sudah memiliki JWT Token User A dan UUID User B:
  python audit/test_customer_rls.py --token-a "eyJhbGci..." --id-a "<uuid_a>" --id-b "<uuid_b>"
""")

