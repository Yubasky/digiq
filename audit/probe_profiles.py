import urllib.request
import json

env = {}
with open('.env', 'r', encoding='utf-8') as f:
    for line in f:
        line = line.strip()
        if line and not line.startswith('#') and '=' in line:
            k, v = line.split('=', 1)
            env[k.strip()] = v.strip().strip('"').strip("'")

supa = env['SUPABASE_URL'].rstrip('/')
anon = env['SUPABASE_ANON_KEY']
masked_anon = anon[:10] + '...[MASKED]...' + anon[-6:]

def test_query(col):
    url = f"{supa}/rest/v1/profiles?select={col}&limit=1"
    headers = {
        'apikey': anon,
        'Authorization': f'Bearer {anon}',
        'Accept': 'application/json'
    }
    req = urllib.request.Request(url, headers=headers)
    try:
        with urllib.request.urlopen(req) as resp:
            body = resp.read().decode('utf-8').strip()
            print(f"[select={col}] HTTP {resp.status} {resp.reason}: {body}")
    except urllib.error.HTTPError as e:
        body = e.read().decode('utf-8').strip()
        print(f"[select={col}] HTTP {e.code} {e.reason}: {body}")

print("==================================================")
print("     PROBE READ-ONLY SCHEMA PROFILES (ANON KEY)   ")
print("==================================================")
print(f"Supabase URL: {supa}")
print(f"Anon Key    : {masked_anon}\n")
test_query('username')
test_query('nonexistent_col_check')
print("==================================================")

