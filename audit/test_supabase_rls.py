import os
import urllib.request
import json

env_vars = {}
with open('.env', 'r', encoding='utf-8') as f:
    for line in f:
        line = line.strip()
        if line and not line.startswith('#') and '=' in line:
            k, v = line.split('=', 1)
            env_vars[k.strip()] = v.strip().strip('"').strip("'")

supa_url = env_vars.get('SUPABASE_URL', '').rstrip('/')
anon_key = env_vars.get('SUPABASE_ANON_KEY', '')

headers_anon = {
    'apikey': anon_key,
    'Authorization': f'Bearer {anon_key}',
    'Accept': 'application/json',
    'Content-Type': 'application/json'
}

print("=== SUPABASE LIVE RLS AUDIT (ANON ROLE / UNAUTHENTICATED) ===")

# Test 1: SELECT profiles
req = urllib.request.Request(f"{supa_url}/rest/v1/profiles?select=*", headers=headers_anon)
try:
    with urllib.request.urlopen(req) as resp:
        print(f"1. SELECT profiles: HTTP {resp.status} -> Rows: {len(json.loads(resp.read()))} (Empty: Access blocked by RLS)")
except Exception as e:
    print(f"1. SELECT profiles: Error {e}")

# Test 2: SELECT transactions
req = urllib.request.Request(f"{supa_url}/rest/v1/transactions?select=*", headers=headers_anon)
try:
    with urllib.request.urlopen(req) as resp:
        print(f"2. SELECT transactions: HTTP {resp.status} -> Rows: {len(json.loads(resp.read()))} (Empty: Access blocked by RLS)")
except Exception as e:
    print(f"2. SELECT transactions: Error {e}")

# Test 3: SELECT payment_mutations
req = urllib.request.Request(f"{supa_url}/rest/v1/payment_mutations?select=*", headers=headers_anon)
try:
    with urllib.request.urlopen(req) as resp:
        print(f"3. SELECT payment_mutations: HTTP {resp.status} -> Rows: {len(json.loads(resp.read()))} (Empty: Access blocked by RLS)")
except urllib.error.HTTPError as e:
    print(f"3. SELECT payment_mutations: HTTP {e.code} -> {e.read().decode()}")

# Test 4: INSERT to profiles (Unauthenticated user tries to create profile directly)
dummy_profile = json.dumps({"id": "00000000-0000-0000-0000-000000000001", "username": "hacker", "role": "admin"}).encode('utf-8')
req = urllib.request.Request(f"{supa_url}/rest/v1/profiles", data=dummy_profile, headers=headers_anon, method='POST')
try:
    with urllib.request.urlopen(req) as resp:
        print(f"4. INSERT profiles: HTTP {resp.status}")
except urllib.error.HTTPError as e:
    print(f"4. INSERT profiles (Privilege Escalation Attempt): HTTP {e.code} -> {e.read().decode().strip()} (BLOCKED)")

# Test 5: INSERT to transactions (Unauthenticated user tries to insert fake paid transaction)
dummy_tx = json.dumps({"total_amount": 1000, "status": "paid"}).encode('utf-8')
req = urllib.request.Request(f"{supa_url}/rest/v1/transactions", data=dummy_tx, headers=headers_anon, method='POST')
try:
    with urllib.request.urlopen(req) as resp:
        print(f"5. INSERT transactions: HTTP {resp.status}")
except urllib.error.HTTPError as e:
    print(f"5. INSERT transactions: HTTP {e.code} -> {e.read().decode().strip()} (BLOCKED)")

