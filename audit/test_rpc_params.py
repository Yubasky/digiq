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

test_cases = [
    ('p_username', {'p_username': 'user123'}),
    ('username', {'username': 'user123'}),
    ('empty', {}),
    ('taken_test', {'p_username': 'admin'}),
]

for name, payload in test_cases:
    url = f"{supa}/rest/v1/rpc/check_username_available"
    req = urllib.request.Request(
        url,
        data=json.dumps(payload).encode('utf-8'),
        headers={'apikey': anon, 'Authorization': f'Bearer {anon}', 'Content-Type': 'application/json'},
        method='POST'
    )
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            print(f"[{name}] {payload} -> HTTP {resp.status}: {resp.read().decode('utf-8').strip()}")
    except urllib.error.HTTPError as e:
        print(f"[{name}] {payload} -> HTTP {e.code}: {e.read().decode('utf-8').strip()}")
    except Exception as e:
        print(f"[{name}] {payload} -> Error: {e}")

