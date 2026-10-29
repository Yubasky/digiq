import urllib.request
import json
import os

env = {}
with open('.env', 'r', encoding='utf-8') as f:
    for line in f:
        line = line.strip()
        if line and not line.startswith('#') and '=' in line:
            k, v = line.split('=', 1)
            env[k.strip()] = v.strip().strip('"').strip("'")

supa = env.get('SUPABASE_URL', '').rstrip('/')
anon = env.get('SUPABASE_ANON_KEY', '')
masked_anon = anon[:10] + '...[MASKED]...' + anon[-6:] if len(anon) > 20 else '***'

url = f'{supa}/rest/v1/rpc/check_username_available'
data = json.dumps({'p_username': 'user123'}).encode('utf-8')
headers = {
    'apikey': anon,
    'Authorization': f'Bearer {anon}',
    'Content-Type': 'application/json',
    'Accept': 'application/json'
}

print("==================================================")
print("     DIAGNOSA ENDPOINT RPC LIVE SUPABASE          ")
print("==================================================")
print(f"Target URL : {url}")
print(f"Anon Key   : {masked_anon}\n")

req = urllib.request.Request(url, data=data, headers=headers, method='POST')
try:
    with urllib.request.urlopen(req, timeout=10) as resp:
        print(f"HTTP Status: {resp.status} {resp.reason}")
        print(f"Response   : {resp.read().decode('utf-8')}")
except urllib.error.HTTPError as e:
    raw_err = e.read().decode('utf-8')
    print(f"HTTP Status: {e.code} {e.reason}")
    print(f"Error Body : {raw_err}")
    try:
        err_json = json.loads(raw_err)
        print(f"  Code     : {err_json.get('code')}")
        print(f"  Message  : {err_json.get('message')}")
        print(f"  Details  : {err_json.get('details')}")
        print(f"  Hint     : {err_json.get('hint')}")
    except:
        pass
except Exception as e:
    print(f"Exception  : {e}")
print("==================================================")

