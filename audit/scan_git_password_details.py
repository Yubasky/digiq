import subprocess
import re
import sys

sys.stdout.reconfigure(encoding='utf-8')

cmd = ['git', 'log', '-p', '-S', 'password', '--', ':!build/**', ':!flutter/**', ':!test/**', ':!audit/**']
res = subprocess.run(cmd, capture_output=True, text=True, encoding='utf-8', errors='replace')

lines = res.stdout.splitlines()

# Patterns of variable/identifier/file declarations to exclude
var_filters = [
    r'diff --git',
    r'--- [ab]/',
    r'\+\+\+ [ab]/',
    r'import .*(password|auth)',
    r'class .*Password',
    r'final _passwordController',
    r'final _confirmPasswordController',
    r'final String password',
    r'String password',
    r'bool _obscurePassword',
    r'bool _obscureConfirmPassword',
    r'_passwordController\.dispose\(\)',
    r'_confirmPasswordController\.dispose\(\)',
    r'_passwordController\.text',
    r'_confirmPasswordController\.text',
    r'controller: _passwordController',
    r'controller: _confirmPasswordController',
    r'obscureText: _obscurePassword',
    r'obscureText: _obscureConfirmPassword',
    r'onPressed: \(\) => setState\(\(\) => _obscurePassword',
    r'passwordController',
    r'TextEditingController\(\)',
    r'required this\.password',
    r'this\.password',
    r'isPasswordRecovery',
    r'_isPasswordRecovery',
    r'AuthService\.isPasswordRecovery',
]

def is_var_or_file(line):
    for pat in var_filters:
        if re.search(pat, line, re.IGNORECASE):
            return True
    return False

current_commit = "unknown"
commit_date = ""
meaningful_lines = []

for l in lines:
    if l.startswith('commit '):
        current_commit = l[:18]
    elif l.startswith('Date:'):
        commit_date = l.strip()
    elif (l.startswith('+') and not l.startswith('+++')) or (l.startswith('-') and not l.startswith('---')):
        if 'password' in l.lower():
            if not is_var_or_file(l):
                # Mask any sensitive literals
                masked = re.sub(r'(:[ ]*["\']?[a-zA-Z0-9_-]{8,}["\']?)', r': "***[MASKED_VALUE]***"', l)
                meaningful_lines.append((current_commit, commit_date, masked))

print("================================================================================")
print("     BARIS ASLI DARI GIT SCAN 'PASSWORD' (BUKAN NAMA VARIABEL / FILE)           ")
print("================================================================================")
print(f"Total baris ditemukan setelah eliminasi variabel & nama berkas: {len(meaningful_lines)}\n")

for commit, date, line in meaningful_lines:
    print(f"[{commit}] {line.strip()[:110]}")

print("================================================================================")

