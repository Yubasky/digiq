with open('scripts/spa_server.py', 'r', encoding='utf-8') as f:
    c = f.read()

target = 'https://*.supabase.co wss://*.supabase.co https://cloudflareinsights.com;'
replacement = 'https://*.supabase.co wss://*.supabase.co https://cloudflareinsights.com https://www.gstatic.com https://fonts.gstatic.com https://fonts.googleapis.com;'

if target in c:
    new_c = c.replace(target, replacement, 1)
    with open('scripts/spa_server.py', 'w', encoding='utf-8', newline='') as f:
        f.write(new_c)
    print("Successfully added gstatic and googleapis to connect-src in spa_server.py")
else:
    print("Target string not found in spa_server.py")

