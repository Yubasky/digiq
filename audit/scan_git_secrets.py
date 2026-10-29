import sys
import subprocess
import re

sys.stdout.reconfigure(encoding='utf-8')

patterns = ['service_role', 'sbp_', 'password', 'SECRET_KEY', 'DATABASE_URL']
for pat in patterns:
    cmd = ['git', 'log', '-p', '-S', pat, '--', ':!build/**', ':!flutter/**', ':!test/**']
    res = subprocess.run(cmd, capture_output=True, text=True, encoding='utf-8', errors='replace')
    out = res.stdout
    masked = re.sub(r'(eyJ[a-zA-Z0-9_-]{10})[a-zA-Z0-9_-]+', r'\1...[MASKED]...', out)
    masked = re.sub(r'(sbp_[a-zA-Z0-9]{6})[a-zA-Z0-9]+', r'\1...[MASKED]...', masked)
    lines = masked.splitlines()
    print(f'=== Git log scan: "{pat}" ({len(lines)} diff lines) ===')
    suspicious = [l for l in lines if (l.startswith('+') and not l.startswith('+++') and ('=' in l or ':' in l))]
    print(f'  Suspicious assignment additions: {len(suspicious)}')
    for s in suspicious[:15]:
        print('   ', s.strip()[:100])
    print()

