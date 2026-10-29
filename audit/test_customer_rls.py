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

def get_profile(supa_url, anon_key, token, user_id):
    url = f"{supa_url}/rest/v1/profiles?id=eq.{user_id}&select=*"
    headers = {
        'apikey': anon_key,
        'Authorization': f'Bearer {token}',
        'Accept': 'application/json',
    }
    req = urllib.request.Request(url, headers=headers, method='GET')
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            rows = json.loads(resp.read().decode('utf-8'))
            return rows[0] if rows else None
    except Exception as e:
        return None

def run_rls_checks(supa_url, anon_key, token_a, id_a, id_b, token_b=None):
    headers_a = {
        'apikey': anon_key,
        'Authorization': f'Bearer {token_a}',
        'Content-Type': 'application/json',
        'Prefer': 'return=representation',
    }

    print("\n" + "="*70)
    print("      SKRIP UJI KEAMANAN ROW LEVEL SECURITY (RLS) MULTI-TENANT    ")
    print("="*70)
    print(f"User A (Attacking Principal) : ID {id_a}")
    print(f"User B (Victim Principal)    : ID {id_b}")
    print("Prinsip: Hanya menggunakan Anon Key + User JWT Token (Zero Service-Role)\n")

    # Ambil kondisi awal profil User A
    initial_profile_a = get_profile(supa_url, anon_key, token_a, id_a)
    initial_role_a = initial_profile_a.get('role', 'customer') if initial_profile_a else 'customer'
    initial_bal_a = initial_profile_a.get('balance', 0) if initial_profile_a else 0
    print(f"[*] Kondisi Awal User A -> Role: '{initial_role_a}', Saldo: Rp {initial_bal_a}")

    # 1. User A tries to SELECT Profile B
    print("\n[1] Uji: User A membaca Profile User B...")
    url = f"{supa_url}/rest/v1/profiles?id=eq.{id_b}&select=*"
    req = urllib.request.Request(url, headers=headers_a, method='GET')
    with urllib.request.urlopen(req) as resp:
        rows = json.loads(resp.read().decode('utf-8'))
        rows_returned = len(rows)
        if rows_returned == 0:
            print(f"    -> PASS: 0 baris dikembalikan (Count: {rows_returned}). Akses diblokir oleh RLS.")
        else:
            print(f"    -> VULNERABLE: Berhasil membaca data profil B! Rows: {rows}")

    # 2. User A tries to UPDATE Profile B
    print("\n[2] Uji: User A mencoba mengubah data pada Profile User B...")
    url = f"{supa_url}/rest/v1/profiles?id=eq.{id_b}"
    payload = json.dumps({'full_name': 'HACKED_BY_A'}).encode('utf-8')
    req = urllib.request.Request(url, data=payload, headers=headers_a, method='PATCH')
    try:
        with urllib.request.urlopen(req) as resp:
            rows = json.loads(resp.read().decode('utf-8'))
            rows_affected = len(rows)
            # Re-read profil B jika token B tersedia
            b_tampered = False
            if token_b:
                prof_b = get_profile(supa_url, anon_key, token_b, id_b)
                if prof_b and prof_b.get('full_name') == 'HACKED_BY_A':
                    b_tampered = True

            if rows_affected == 0 and not b_tampered:
                print(f"    -> PASS: 0 baris dimodifikasi (Count: {rows_affected}). Data profil B tidak berubah.")
            else:
                print(f"    -> VULNERABLE: Profile B berhasil diubah! (Rows affected: {rows_affected})")
    except urllib.error.HTTPError as e:
        print(f"    -> PASS: Permintaan ditolak dengan HTTP {e.code} oleh RLS.")

    # 3. User A tries to SELECT Transactions of B
    print("\n[3] Uji: User A membaca daftar transaksi milik User B...")
    url = f"{supa_url}/rest/v1/transactions?user_id=eq.{id_b}&select=*"
    req = urllib.request.Request(url, headers=headers_a, method='GET')
    with urllib.request.urlopen(req) as resp:
        rows = json.loads(resp.read().decode('utf-8'))
        rows_returned = len(rows)
        if rows_returned == 0:
            print(f"    -> PASS: 0 baris dikembalikan (Count: {rows_returned}). Transaksi B diblokir dari A.")
        else:
            print(f"    -> VULNERABLE: User A dapat melihat {rows_returned} transaksi milik B!")

    # 4. User A tries Privilege Escalation (Ubah role sendiri jadi 'admin')
    print("\n[4] Uji: User A mencoba eskalasi wewenang (mengubah role dirinya ke 'admin')...")
    url = f"{supa_url}/rest/v1/profiles?id=eq.{id_a}"
    payload = json.dumps({'role': 'admin'}).encode('utf-8')
    req = urllib.request.Request(url, data=payload, headers=headers_a, method='PATCH')
    try:
        with urllib.request.urlopen(req) as resp:
            rows = json.loads(resp.read().decode('utf-8'))
            # Baca ulang langsung dari database untuk memverifikasi nilai akhir nyata
            final_prof_a = get_profile(supa_url, anon_key, token_a, id_a)
            final_role = final_prof_a.get('role') if final_prof_a else 'error'
            
            if final_role == 'admin':
                print(f"    -> VULNERABLE: Nilai akhir role berubah menjadi 'admin'! (Eskalasi Berhasil)")
            else:
                print(f"    -> PASS: Role akhir terverifikasi tetap '{final_role}' (Bukan 'admin'). Eskalasi digagalkan.")
    except urllib.error.HTTPError as e:
        print(f"    -> PASS: Ditolak dengan HTTP {e.code} ({e.read().decode('utf-8').strip()}).")

    # 5. User A tries Direct Balance Tampering (Manipulasi saldo sendiri)
    print("\n[5] Uji: User A mencoba manipulasi saldo sendiri secara langsung via REST...")
    url = f"{supa_url}/rest/v1/profiles?id=eq.{id_a}"
    target_fake_balance = 999999999
    payload = json.dumps({'balance': target_fake_balance}).encode('utf-8')
    req = urllib.request.Request(url, data=payload, headers=headers_a, method='PATCH')
    try:
        with urllib.request.urlopen(req) as resp:
            rows = json.loads(resp.read().decode('utf-8'))
            # Baca ulang langsung dari database untuk memverifikasi nilai akhir nyata
            final_prof_a = get_profile(supa_url, anon_key, token_a, id_a)
            final_balance = final_prof_a.get('balance') if final_prof_a else -1
            
            if final_balance == target_fake_balance:
                print(f"    -> VULNERABLE: Nilai akhir saldo berubah menjadi Rp {final_balance}!")
            else:
                print(f"    -> PASS: Saldo akhir terverifikasi tetap Rp {final_balance} (Bukan Rp {target_fake_balance}). Manipulasi digagalkan.")
    except urllib.error.HTTPError as e:
        print(f"    -> PASS: Ditolak dengan HTTP {e.code} ({e.read().decode('utf-8').strip()}).")


    # 6. User A calls update_my_profile with User B's username
    print("\n[6] Uji: User A memanggil update_my_profile dengan username milik User B...")
    prof_b = get_profile(supa_url, anon_key, token_b, id_b) if token_b else None
    target_username = prof_b.get('username') if prof_b else 'darzkine'
    url_rpc = f"{supa_url}/rest/v1/rpc/update_my_profile"
    payload_rpc = json.dumps({
        'p_full_name': 'Attacker Name',
        'p_phone': '081299998888',
        'p_username': target_username
    }).encode('utf-8')
    req_rpc = urllib.request.Request(url_rpc, data=payload_rpc, headers=headers_a, method='POST')
    try:
        with urllib.request.urlopen(req_rpc) as resp:
            body = json.loads(resp.read().decode('utf-8'))
            if body.get('success') is False and body.get('code') == 'username_taken':
                print(f"    -> PASS: Ditolak dengan code '{body.get('code')}': {body.get('message')}")
            else:
                print(f"    -> VULNERABLE: Pembajakan username berhasil! Response: {body}")
    except urllib.error.HTTPError as e:
        print(f"    -> PASS: Request ditolak dengan HTTP {e.code}")

    # 7. User A tries to modify is_2fa_enabled directly via PATCH
    print("\n[7] Uji: User A mencoba mengubah status 2FA langsung via PATCH...")
    url = f"{supa_url}/rest/v1/profiles?id=eq.{id_a}"
    payload = json.dumps({'is_2fa_enabled': not initial_profile_a.get('is_2fa_enabled', False)}).encode('utf-8')
    req = urllib.request.Request(url, data=payload, headers=headers_a, method='PATCH')
    try:
        with urllib.request.urlopen(req) as resp:
            print("    -> VULNERABLE: Direct PATCH status 2FA berhasil lolos!")
    except urllib.error.HTTPError as e:
        print(f"    -> PASS: Direct PATCH 2FA berhasil ditolak oleh trigger dengan HTTP {e.code}.")

    print("\n" + "="*70 + "\n")

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description="Multi-tenant RLS Audit Script (2 Akun Customer)")
    parser.add_argument('--email-a', help="Email Customer A (Penyerang)")
    parser.add_argument('--pass-a', help="Password Customer A")
    parser.add_argument('--email-b', help="Email Customer B (Korban)")
    parser.add_argument('--pass-b', help="Password Customer B")
    parser.add_argument('--token-a', help="JWT Access Token Customer A (jika sudah ada)")
    parser.add_argument('--token-b', help="JWT Access Token Customer B (opsional untuk verifikasi re-read)")
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
    token_b = args.token_b
    id_a = args.id_a
    id_b = args.id_b

    if not token_a and args.email_a and args.pass_a:
        print(f"[*] Melakukan autentikasi User A ({args.email_a})...")
        token_a, id_a = login_user(supa_url, anon_key, args.email_a, args.pass_a)

    if not id_b and args.email_b and args.pass_b:
        print(f"[*] Melakukan autentikasi User B ({args.email_b}) untuk mendapatkan UUID...")
        token_b, id_b = login_user(supa_url, anon_key, args.email_b, args.pass_b)

    if token_a and id_a and id_b:
        run_rls_checks(supa_url, anon_key, token_a, id_a, id_b, token_b)
    else:
        print("""
======================================================================
  PETUNJUK PENGGUNAAN SKRIP UJI RLS 2 AKUN (STANDBY - MENUNGGU AKUN)
======================================================================
Skrip ini TIDAK DIJALANKAN otomatis sebelum Anda menyediakan kredensial
dua akun pengujian (Customer A & Customer B) pada environment staging.

Format Eksekusi:
  python audit/test_customer_rls.py --email-a userA@staging.com --pass-a PassA123! --email-b userB@staging.com --pass-b PassB123!

Karakteristik Verifikasi:
  1. Menilai PASS/VULNERABLE berdasarkan baris aktual yang termodifikasi (count == 0).
  2. Melakukan pembacaan ulang (re-read GET) ke database setelah PATCH
     untuk memastikan nilai role dan balance nyata tidak berubah.
  3. Menggunakan ZERO service_role key (100% anon key + user token).
======================================================================
""")
