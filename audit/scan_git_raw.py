import sys
import subprocess
import re

sys.stdout.reconfigure(encoding='utf-8')

patterns = ['service_role', 'eyJ', 'smtp', 'password', 'apikey']

print("=================================================================")
print("          GIT LOG AUDIT SCAN: EXACT RAW DIFF LINES               ")
print("=================================================================")

for pat in patterns:
    print(f"\n>>> PATTERN: '{pat}' <<<")
    cmd = ['git', 'log', '-p', '-S', pat, '--', ':!build/**', ':!flutter/**', ':!test/**', ':!audit/**']
    res = subprocess.run(cmd, capture_output=True, text=True, encoding='utf-8', errors='replace')
    out = res.stdout
    
    # Mask potential token values or credentials
    masked = re.sub(r'(eyJ[a-zA-Z0-9_-]{10})[a-zA-Z0-9_-]+', r'\1...[MASKED]...', out)
    masked = re.sub(r'(:[ ]*["\']?[a-zA-Z0-9_-]{25,}["\']?)', r': "***[MASKED_SECRET]***"', masked)
    
    lines = masked.splitlines()
    print(f"Total diff lines found: {len(lines)}")
    
    # Filter lines that actually add or modify lines containing the pattern
    diff_lines = []
    current_commit = "unknown"
    for l in lines:
        if l.startswith('commit '):
            current_commit = l[:18]
        elif l.startswith('+') and not l.startswith('+++') and pat.lower() in l.lower():
            diff_lines.append(f"  [{current_commit}] {l[:120]}")
            
    print(f"Unique lines adding/modifying '{pat}': {len(diff_lines)}")
    if not diff_lines:
        print("  (Tidak ada baris penambahan kode yang cocok)")
    else:
        for dl in diff_lines[:25]: # Show up to 25 lines
            print(dl)
        if len(diff_lines) > 25:
            print(f"  ... dan {len(diff_lines) - 25} baris lainnya.")

print("\n=================================================================")

