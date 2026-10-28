import os
from PIL import Image, ImageDraw, ImageFont

def create_architecture_svg():
    svg_content = '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1100 850" width="100%" height="100%" style="background:#0f172a;font-family:system-ui,-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;">
  <defs>
    <linearGradient id="gradClient" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#38bdf8"/>
      <stop offset="100%" stop-color="#0284c7"/>
    </linearGradient>
    <linearGradient id="gradCF" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#f97316"/>
      <stop offset="100%" stop-color="#ea580c"/>
    </linearGradient>
    <linearGradient id="gradWin" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#3b82f6"/>
      <stop offset="100%" stop-color="#1d4ed8"/>
    </linearGradient>
    <linearGradient id="gradSupa" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#10b981"/>
      <stop offset="100%" stop-color="#059669"/>
    </linearGradient>
    <linearGradient id="gradExt" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#8b5cf6"/>
      <stop offset="100%" stop-color="#6d28d9"/>
    </linearGradient>
    <filter id="shadow" x="-5%" y="-5%" width="110%" height="110%">
      <feDropShadow dx="0" dy="4" stdDeviation="6" flood-color="#000000" flood-opacity="0.4"/>
    </filter>
    <marker id="arrow" viewBox="0 0 10 10" refX="6" refY="5" markerWidth="6" markerHeight="6" orient="auto-start-reverse">
      <path d="M 0 1 L 10 5 L 0 9 z" fill="#94a3b8"/>
    </marker>
    <marker id="arrow-green" viewBox="0 0 10 10" refX="6" refY="5" markerWidth="6" markerHeight="6" orient="auto-start-reverse">
      <path d="M 0 1 L 10 5 L 0 9 z" fill="#10b981"/>
    </marker>
    <marker id="arrow-orange" viewBox="0 0 10 10" refX="6" refY="5" markerWidth="6" markerHeight="6" orient="auto-start-reverse">
      <path d="M 0 1 L 10 5 L 0 9 z" fill="#f97316"/>
    </marker>
  </defs>

  <!-- Title -->
  <text x="550" y="45" text-anchor="middle" fill="#f8fafc" font-size="24" font-weight="bold">DigiQ Production End-to-End Architecture</text>
  <text x="550" y="70" text-anchor="middle" fill="#94a3b8" font-size="14">Windows Host • Cloudflare Zero Trust • Supabase Cloud BaaS</text>

  <!-- USER / CLIENT BROWSER BOX -->
  <g filter="url(#shadow)">
    <rect x="50" y="110" width="280" height="230" rx="12" fill="#1e293b" stroke="#38bdf8" stroke-width="2"/>
    <rect x="50" y="110" width="280" height="42" rx="12" fill="url(#gradClient)"/>
    <text x="190" y="137" text-anchor="middle" fill="#ffffff" font-size="16" font-weight="bold">Client Browser / Mobile</text>
    
    <rect x="70" y="165" width="240" height="35" rx="6" fill="#334155"/>
    <text x="190" y="188" text-anchor="middle" fill="#f1f5f9" font-size="12">Flutter Web SPA Application</text>
    
    <rect x="70" y="210" width="240" height="35" rx="6" fill="#334155"/>
    <text x="190" y="233" text-anchor="middle" fill="#f1f5f9" font-size="12">QrisService (EMVCo Engine)</text>

    <rect x="70" y="255" width="240" height="35" rx="6" fill="#334155"/>
    <text x="190" y="278" text-anchor="middle" fill="#f1f5f9" font-size="12">Supabase Flutter SDK (Auth, REST, Storage)</text>

    <text x="190" y="325" text-anchor="middle" fill="#38bdf8" font-size="11">Direct API Connections over TLS 1.3</text>
  </g>

  <!-- CLOUDFLARE EDGE BOX -->
  <g filter="url(#shadow)">
    <rect x="420" y="110" width="260" height="150" rx="12" fill="#1e293b" stroke="#f97316" stroke-width="2"/>
    <rect x="420" y="110" width="260" height="42" rx="12" fill="url(#gradCF)"/>
    <text x="550" y="137" text-anchor="middle" fill="#ffffff" font-size="16" font-weight="bold">Cloudflare Zero Trust Edge</text>

    <text x="550" y="180" text-anchor="middle" fill="#e2e8f0" font-size="13" font-weight="600">enikzrad.web.id</text>
    <text x="550" y="202" text-anchor="middle" fill="#94a3b8" font-size="11">• Edge SSL Termination (Universal SSL)</text>
    <text x="550" y="222" text-anchor="middle" fill="#94a3b8" font-size="11">• DDoS Protection &amp; Anycast Routing</text>
    <text x="550" y="242" text-anchor="middle" fill="#94a3b8" font-size="11">• Inbound Zero-Trust Quick Tunnel</text>
  </g>

  <!-- WINDOWS HOST BOX -->
  <g filter="url(#shadow)">
    <rect x="770" y="110" width="280" height="320" rx="12" fill="#1e293b" stroke="#3b82f6" stroke-width="2"/>
    <rect x="770" y="110" width="280" height="42" rx="12" fill="url(#gradWin)"/>
    <text x="910" y="137" text-anchor="middle" fill="#ffffff" font-size="16" font-weight="bold">Windows Host (PID)</text>

    <!-- Cloudflared daemon -->
    <rect x="790" y="165" width="240" height="60" rx="8" fill="#1e3a8a" stroke="#60a5fa" stroke-width="1"/>
    <text x="910" y="188" text-anchor="middle" fill="#ffffff" font-size="13" font-weight="bold">cloudflared.exe (Daemon)</text>
    <text x="910" y="208" text-anchor="middle" fill="#bfdbfe" font-size="11">Outbound QUIC Tunnel to Cloudflare</text>

    <!-- Loopback arrow -->
    <path d="M 910 225 L 910 250" stroke="#60a5fa" stroke-width="2" marker-end="url(#arrow)"/>
    <text x="965" y="242" text-anchor="middle" fill="#93c5fd" font-size="10">127.0.0.1:9000</text>

    <!-- spa_server.py -->
    <rect x="790" y="255" width="240" height="155" rx="8" fill="#0f172a" stroke="#3b82f6" stroke-width="1"/>
    <text x="910" y="278" text-anchor="middle" fill="#ffffff" font-size="13" font-weight="bold">spa_server.py (Python 3.12)</text>
    <text x="810" y="302" fill="#cbd5e1" font-size="11">• Port: 9000 (0.0.0.0 / 127.0.0.1)</text>
    <text x="810" y="322" fill="#cbd5e1" font-size="11">• SPA Fallback: index.html routing</text>
    <text x="810" y="342" fill="#cbd5e1" font-size="11">• Security: dotfile blocking (404)</text>
    <text x="810" y="362" fill="#cbd5e1" font-size="11">• Security Headers: CSP, HSTS, X-Frame</text>
    <text x="810" y="382" fill="#cbd5e1" font-size="11">• Health Check: /health endpoint</text>
    <text x="810" y="400" fill="#10b981" font-size="10">Target: build\web production bundle</text>
  </g>

  <!-- SUPABASE CLOUD BOX -->
  <g filter="url(#shadow)">
    <rect x="250" y="490" width="600" height="320" rx="12" fill="#1e293b" stroke="#10b981" stroke-width="2"/>
    <rect x="250" y="490" width="600" height="42" rx="12" fill="url(#gradSupa)"/>
    <text x="550" y="517" text-anchor="middle" fill="#ffffff" font-size="16" font-weight="bold">Supabase Cloud Platform (iqxoofrhhrqkgehuvrlb.supabase.co)</text>

    <!-- Auth GoTrue -->
    <rect x="270" y="550" width="165" height="110" rx="8" fill="#064e3b" stroke="#34d399" stroke-width="1"/>
    <text x="352" y="573" text-anchor="middle" fill="#ffffff" font-size="13" font-weight="bold">GoTrue Auth v1</text>
    <text x="280" y="595" fill="#a7f3d0" font-size="10">• Email / Password Signup</text>
    <text x="280" y="612" fill="#a7f3d0" font-size="10">• OTP / MagicLink Verification</text>
    <text x="280" y="629" fill="#a7f3d0" font-size="10">• JWT &amp; Refresh Tokens</text>
    <text x="280" y="646" fill="#f87171" font-size="10">• mailer_autoconfirm: false</text>

    <!-- PostgREST & RPC -->
    <rect x="460" y="550" width="180" height="110" rx="8" fill="#064e3b" stroke="#34d399" stroke-width="1"/>
    <text x="550" y="573" text-anchor="middle" fill="#ffffff" font-size="13" font-weight="bold">PostgREST &amp; RPC Engine</text>
    <text x="470" y="595" fill="#a7f3d0" font-size="10">• REST: profiles, products,</text>
    <text x="470" y="610" fill="#a7f3d0" font-size="10">  transactions, mutations</text>
    <text x="470" y="628" fill="#a7f3d0" font-size="10">• RPC: check_username_available</text>
    <text x="470" y="645" fill="#a7f3d0" font-size="10">• RPC: is_admin (security definer)</text>

    <!-- Storage Bucket -->
    <rect x="665" y="550" width="165" height="110" rx="8" fill="#064e3b" stroke="#34d399" stroke-width="1"/>
    <text x="747" y="573" text-anchor="middle" fill="#ffffff" font-size="13" font-weight="bold">Storage Engine</text>
    <text x="675" y="595" fill="#a7f3d0" font-size="10">• Bucket: 'avatars' (public)</text>
    <text x="675" y="612" fill="#a7f3d0" font-size="10">• Path: {user_id}/*</text>
    <text x="675" y="629" fill="#a7f3d0" font-size="10">• RLS: User authenticated</text>
    <text x="675" y="646" fill="#fbbf24" font-size="10">• Proofs: Not configured</text>

    <!-- PostgreSQL Database Sub-box -->
    <rect x="270" y="680" width="560" height="110" rx="8" fill="#022c22" stroke="#10b981" stroke-width="1"/>
    <text x="550" y="702" text-anchor="middle" fill="#34d399" font-size="13" font-weight="bold">PostgreSQL 15 Database (RLS Enforced)</text>
    <text x="290" y="725" fill="#ecfdf5" font-size="11">Tables: profiles | products | transactions | transaction_items | payment_mutations | chat_messages</text>
    <text x="290" y="745" fill="#ecfdf5" font-size="11">Triggers: handle_new_user() on auth.users -> syncs to public.profiles (username, role, full_name)</text>
    <text x="290" y="765" fill="#6ee7b7" font-size="11">Security: Row Level Security (RLS) active on 100% public tables with strict SELECT/INSERT/UPDATE rules</text>
  </g>

  <!-- EXTERNAL INTEGRATIONS -->
  <g filter="url(#shadow)">
    <rect x="910" y="520" width="160" height="120" rx="10" fill="#1e293b" stroke="#8b5cf6" stroke-width="1.5"/>
    <rect x="910" y="520" width="160" height="32" rx="10" fill="url(#gradExt)"/>
    <text x="990" y="542" text-anchor="middle" fill="#ffffff" font-size="12" font-weight="bold">External Services</text>
    <text x="990" y="575" text-anchor="middle" fill="#c4b5fd" font-size="11">SMTP Mail Server</text>
    <text x="990" y="593" text-anchor="middle" fill="#94a3b8" font-size="10">(OTP / Confirm Emails)</text>
    <text x="990" y="618" text-anchor="middle" fill="#c4b5fd" font-size="11">QRIS / Bank Ingress</text>
    <text x="990" y="633" text-anchor="middle" fill="#94a3b8" font-size="10">(BCA, Mandiri, E-Wallet)</text>
  </g>

  <!-- FLOW CONNECTORS -->
  <!-- Browser to Cloudflare (HTTP GET SPA assets) -->
  <path d="M 330 180 L 420 180" stroke="#f97316" stroke-width="2" marker-end="url(#arrow-orange)"/>
  <text x="375" y="172" text-anchor="middle" fill="#fdba74" font-size="10">HTTPS GET</text>

  <!-- Cloudflare to Windows Daemon -->
  <path d="M 680 180 L 790 180" stroke="#f97316" stroke-width="2" stroke-dasharray="4" marker-end="url(#arrow-orange)"/>
  <text x="735" y="172" text-anchor="middle" fill="#fdba74" font-size="10">Tunnel QUIC</text>

  <!-- Browser directly to Supabase Auth -->
  <path d="M 190 340 L 190 600 L 270 600" fill="none" stroke="#10b981" stroke-width="2" marker-end="url(#arrow-green)"/>
  <text x="210" y="470" fill="#6ee7b7" font-size="10" transform="rotate(-90 210,470)">Direct Auth / REST / RPC / Storage</text>

  <!-- Supabase to External SMTP -->
  <path d="M 435 600 L 910 575" fill="none" stroke="#8b5cf6" stroke-width="1.5" stroke-dasharray="3" marker-end="url(#arrow)"/>
  <text x="860" y="565" fill="#c4b5fd" font-size="9">SMTP Auth Dispatch</text>

  <!-- Trigger arrow internal inside Supabase -->
  <path d="M 352 660 L 352 680" stroke="#34d399" stroke-width="2" marker-end="url(#arrow-green)"/>

</svg>
'''
    with open('audit/architecture.svg', 'w', encoding='utf-8') as f:
        f.write(svg_content)
    print("Created audit/architecture.svg")

def create_er_diagram_svg():
    svg_content = '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1200 800" width="100%" height="100%" style="background:#090d16;font-family:ui-monospace,SFMono-Regular,Consolas,'Liberation Mono',Menlo,monospace;">
  <defs>
    <filter id="erShadow" x="-5%" y="-5%" width="110%" height="110%">
      <feDropShadow dx="0" dy="4" stdDeviation="6" flood-color="#000000" flood-opacity="0.6"/>
    </filter>
    <marker id="crow" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="6" markerHeight="6" orient="auto">
      <path d="M 0 0 L 10 5 L 0 10 z" fill="#38bdf8"/>
    </marker>
  </defs>

  <!-- Title -->
  <text x="600" y="40" text-anchor="middle" fill="#38bdf8" font-size="22" font-weight="bold">DigiQ Database Entity Relationship (ER) Diagram</text>
  <text x="600" y="65" text-anchor="middle" fill="#64748b" font-size="13">Schema: public (PostgreSQL 15) with GoTrue auth.users integration</text>

  <!-- AUTH USERS TABLE -->
  <g filter="url(#erShadow)">
    <rect x="50" y="100" width="280" height="150" rx="8" fill="#1e293b" stroke="#e2e8f0" stroke-width="1.5"/>
    <rect x="50" y="100" width="280" height="32" rx="8" fill="#334155"/>
    <text x="190" y="122" text-anchor="middle" fill="#ffffff" font-size="14" font-weight="bold">auth.users (Supabase Core)</text>
    <text x="65" y="152" fill="#38bdf8" font-size="12">PK  id           : uuid</text>
    <text x="65" y="172" fill="#94a3b8" font-size="12">    email        : varchar(255)</text>
    <text x="65" y="192" fill="#94a3b8" font-size="12">    encrypted_pw : varchar(255)</text>
    <text x="65" y="212" fill="#94a3b8" font-size="12">    raw_user_meta: jsonb</text>
    <text x="65" y="232" fill="#94a3b8" font-size="12">    created_at   : timestamptz</text>
  </g>

  <!-- PROFILES TABLE -->
  <g filter="url(#erShadow)">
    <rect x="50" y="320" width="280" height="210" rx="8" fill="#1e293b" stroke="#38bdf8" stroke-width="2"/>
    <rect x="50" y="320" width="280" height="32" rx="8" fill="#0284c7"/>
    <text x="190" y="342" text-anchor="middle" fill="#ffffff" font-size="14" font-weight="bold">public.profiles</text>
    <text x="65" y="372" fill="#38bdf8" font-size="12">PK,FK  id        : uuid (auth.users)</text>
    <text x="65" y="392" fill="#a7f3d0" font-size="12">UQ,NN  username  : varchar(20)</text>
    <text x="65" y="412" fill="#94a3b8" font-size="12">       full_name : text</text>
    <text x="65" y="432" fill="#94a3b8" font-size="12">       avatar_url: text</text>
    <text x="65" y="452" fill="#fbbf24" font-size="12">CK     role      : user_role (admin/..)</text>
    <text x="65" y="472" fill="#94a3b8" font-size="12">       created_at: timestamptz</text>
    <text x="65" y="492" fill="#94a3b8" font-size="12">       updated_at: timestamptz</text>
  </g>

  <!-- TRANSACTIONS TABLE -->
  <g filter="url(#erShadow)">
    <rect x="460" y="100" width="310" height="260" rx="8" fill="#1e293b" stroke="#10b981" stroke-width="2"/>
    <rect x="460" y="100" width="310" height="32" rx="8" fill="#059669"/>
    <text x="615" y="122" text-anchor="middle" fill="#ffffff" font-size="14" font-weight="bold">public.transactions</text>
    <text x="475" y="152" fill="#38bdf8" font-size="12">PK     id             : uuid</text>
    <text x="475" y="172" fill="#38bdf8" font-size="12">FK     user_id        : uuid (profiles)</text>
    <text x="475" y="192" fill="#f8fafc" font-size="12">NN     total_amount   : numeric</text>
    <text x="475" y="212" fill="#94a3b8" font-size="12">       base_amount    : numeric</text>
    <text x="475" y="232" fill="#94a3b8" font-size="12">       unique_code    : integer</text>
    <text x="475" y="252" fill="#fbbf24" font-size="12">CK     status         : status_type</text>
    <text x="475" y="272" fill="#94a3b8" font-size="12">       payment_method : varchar(50)</text>
    <text x="475" y="292" fill="#94a3b8" font-size="12">       qris_payload   : text</text>
    <text x="475" y="312" fill="#94a3b8" font-size="12">       expired_at     : timestamptz</text>
    <text x="475" y="332" fill="#94a3b8" font-size="12">       created_at     : timestamptz</text>
  </g>

  <!-- TRANSACTION ITEMS TABLE -->
  <g filter="url(#erShadow)">
    <rect x="880" y="100" width="280" height="190" rx="8" fill="#1e293b" stroke="#10b981" stroke-width="1.5"/>
    <rect x="880" y="100" width="280" height="32" rx="8" fill="#047857"/>
    <text x="1020" y="122" text-anchor="middle" fill="#ffffff" font-size="14" font-weight="bold">public.transaction_items</text>
    <text x="895" y="152" fill="#38bdf8" font-size="12">PK     id             : uuid</text>
    <text x="895" y="172" fill="#38bdf8" font-size="12">FK     transaction_id : uuid (CASCADE)</text>
    <text x="895" y="192" fill="#38bdf8" font-size="12">FK     product_id     : uuid (RESTRICT)</text>
    <text x="895" y="212" fill="#f8fafc" font-size="12">NN     quantity       : integer</text>
    <text x="895" y="232" fill="#f8fafc" font-size="12">NN     price_at_purch : numeric</text>
    <text x="895" y="252" fill="#f8fafc" font-size="12">NN     subtotal       : numeric</text>
  </g>

  <!-- PRODUCTS TABLE -->
  <g filter="url(#erShadow)">
    <rect x="880" y="360" width="280" height="230" rx="8" fill="#1e293b" stroke="#a855f7" stroke-width="2"/>
    <rect x="880" y="360" width="280" height="32" rx="8" fill="#7e22ce"/>
    <text x="1020" y="382" text-anchor="middle" fill="#ffffff" font-size="14" font-weight="bold">public.products</text>
    <text x="895" y="412" fill="#38bdf8" font-size="12">PK     id         : uuid</text>
    <text x="895" y="432" fill="#f8fafc" font-size="12">NN     name       : text</text>
    <text x="895" y="452" fill="#94a3b8" font-size="12">       description: text</text>
    <text x="895" y="472" fill="#f8fafc" font-size="12">NN     price      : numeric</text>
    <text x="895" y="492" fill="#f8fafc" font-size="12">NN     stock      : integer</text>
    <text x="895" y="512" fill="#94a3b8" font-size="12">       image_url  : text</text>
    <text x="895" y="532" fill="#94a3b8" font-size="12">       category   : text</text>
    <text x="895" y="552" fill="#94a3b8" font-size="12">       is_active  : boolean</text>
  </g>

  <!-- PAYMENT MUTATIONS TABLE -->
  <g filter="url(#erShadow)">
    <rect x="460" y="430" width="310" height="210" rx="8" fill="#1e293b" stroke="#f59e0b" stroke-width="2"/>
    <rect x="460" y="430" width="310" height="32" rx="8" fill="#b45309"/>
    <text x="615" y="452" text-anchor="middle" fill="#ffffff" font-size="14" font-weight="bold">public.payment_mutations</text>
    <text x="475" y="482" fill="#38bdf8" font-size="12">PK     id             : uuid</text>
    <text x="475" y="502" fill="#f8fafc" font-size="12">NN     bank           : varchar(50)</text>
    <text x="475" y="522" fill="#f8fafc" font-size="12">NN     amount         : numeric</text>
    <text x="475" y="542" fill="#94a3b8" font-size="12">       description    : text</text>
    <text x="475" y="562" fill="#fbbf24" font-size="12">CK     mutation_type  : varchar(2) (CR/DB)</text>
    <text x="475" y="582" fill="#38bdf8" font-size="12">FK     transaction_id : uuid (NULLABLE)</text>
    <text x="475" y="602" fill="#94a3b8" font-size="12">       is_matched     : boolean</text>
  </g>

  <!-- CHAT MESSAGES TABLE -->
  <g filter="url(#erShadow)">
    <rect x="50" y="600" width="280" height="170" rx="8" fill="#1e293b" stroke="#ec4899" stroke-width="1.5"/>
    <rect x="50" y="600" width="280" height="32" rx="8" fill="#be185d"/>
    <text x="190" y="622" text-anchor="middle" fill="#ffffff" font-size="14" font-weight="bold">public.chat_messages</text>
    <text x="65" y="652" fill="#38bdf8" font-size="12">PK     id          : uuid</text>
    <text x="65" y="672" fill="#38bdf8" font-size="12">FK     sender_id   : uuid (profiles)</text>
    <text x="65" y="692" fill="#38bdf8" font-size="12">FK     receiver_id : uuid (NULLABLE)</text>
    <text x="65" y="712" fill="#f8fafc" font-size="12">NN     message     : text</text>
    <text x="65" y="732" fill="#94a3b8" font-size="12">       is_read     : boolean</text>
  </g>

  <!-- RELATION LINES -->
  <!-- auth.users 1 -- 1 profiles -->
  <path d="M 190 250 L 190 320" stroke="#38bdf8" stroke-width="2" marker-end="url(#crow)"/>
  <text x="205" y="285" fill="#38bdf8" font-size="11">1:1 Trigger</text>

  <!-- profiles 1 -- N transactions -->
  <path d="M 330 380 L 400 380 L 400 200 L 460 200" fill="none" stroke="#38bdf8" stroke-width="2" marker-end="url(#crow)"/>
  <text x="390" y="270" fill="#38bdf8" font-size="11">1:N</text>

  <!-- transactions 1 -- N transaction_items -->
  <path d="M 770 170 L 880 170" stroke="#38bdf8" stroke-width="2" marker-end="url(#crow)"/>
  <text x="825" y="162" fill="#38bdf8" font-size="11">1:N</text>

  <!-- products 1 -- N transaction_items -->
  <path d="M 1020 360 L 1020 290" stroke="#38bdf8" stroke-width="2" marker-end="url(#crow)"/>
  <text x="1030" y="325" fill="#38bdf8" font-size="11">1:N</text>

  <!-- transactions 1 -- 0..1 payment_mutations -->
  <path d="M 615 360 L 615 430" stroke="#f59e0b" stroke-width="2" stroke-dasharray="4" marker-end="url(#crow)"/>
  <text x="625" y="395" fill="#f59e0b" font-size="11">1:0..1 Match</text>

  <!-- profiles 1 -- N chat_messages -->
  <path d="M 190 530 L 190 600" stroke="#ec4899" stroke-width="2" marker-end="url(#crow)"/>
  <text x="205" y="565" fill="#ec4899" font-size="11">1:N</text>

</svg>
'''
    with open('audit/er-diagram.svg', 'w', encoding='utf-8') as f:
        f.write(svg_content)
    print("Created audit/er-diagram.svg")

def render_pngs_using_pil():
    # Render architecture.png
    w, h = 1200, 900
    img = Image.new('RGB', (w, h), color=(15, 23, 42))
    d = ImageDraw.Draw(img)
    
    # Simple fallback typography with PIL default font
    d.rectangle([(20, 20), (w-20, h-20)], outline=(56, 189, 248), width=2)
    d.text((w//2 - 200, 35), "DigiQ Production Architecture Diagram", fill=(248, 250, 252))
    d.text((w//2 - 180, 55), "Windows Host • Cloudflare Zero Trust • Supabase Cloud", fill=(148, 163, 184))

    # Boxes
    boxes = [
        ((50, 100, 350, 350), (30, 41, 59), (56, 189, 248), "Client / Browser", [
            "• Flutter Web Single Page Application",
            "• Port 9000 Assets via Cloudflare",
            "• Direct Supabase SDK Calls (TLS 1.3)",
            "• Local QrisService EMVCo Engine",
            "• Debounced Username & Auth Validation"
        ]),
        ((420, 100, 720, 350), (30, 41, 59), (249, 115, 22), "Cloudflare Edge Ingress", [
            "• Domain: enikzrad.web.id",
            "• Universal SSL / TLS 1.3 Edge",
            "• DDoS Mitigation & Anycast Routing",
            "• Zero Trust Inbound Tunnel Endpoint",
            "• Tunnel connects to Windows cloudflared"
        ]),
        ((790, 100, 1150, 450), (30, 41, 59), (59, 130, 246), "Windows Host (Local Server)", [
            "• Process: cloudflared.exe (Windows Service)",
            "• Process: spa_server.py (Port 9000)",
            "• Listen: 0.0.0.0 & 127.0.0.1",
            "• SPA Routing: index.html fallback",
            "• Security: dotfile block (404 on /.env)",
            "• CSP & Security Headers Active",
            "• /health Endpoint (200 OK)",
            "• Inbound Port 9000 Rule Unneeded (Local only)"
        ]),
        ((150, 500, 1050, 850), (2, 44, 34), (16, 185, 129), "Supabase Cloud Platform (PostgreSQL + GoTrue + Storage)", [
            "• GoTrue Auth v1: SignUp / Login / OTP (Synchronous SMTP mailer)",
            "• PostgreSQL 15: 100% RLS Enabled on Public Tables",
            "• Tables: profiles, products, transactions, transaction_items, payment_mutations, chat_messages",
            "• Triggers: handle_new_user() syncs auth.users -> public.profiles with role & username",
            "• RPC Functions: check_username_available(), is_admin()",
            "• Storage: 'avatars' public bucket with RLS policy",
            "• Integrity: Foreign Keys (CASCADE/RESTRICT), Check Constraints, NOT NULLs"
        ])
    ]

    for (x0, y0, x1, y1), fill_c, out_c, header, items in boxes:
        d.rectangle([(x0, y0), (x1, y1)], fill=fill_c, outline=out_c, width=2)
        d.rectangle([(x0, y0), (x1, y0 + 32)], fill=out_c)
        d.text((x0 + 15, y0 + 8), header, fill=(255, 255, 255))
        y = y0 + 45
        for item in items:
            d.text((x0 + 15, y), item, fill=(226, 232, 240))
            y += 24

    img.save('audit/architecture.png')
    print("Created audit/architecture.png")

    # Render er-diagram.png
    img_er = Image.new('RGB', (1200, 900), color=(9, 13, 22))
    d_er = ImageDraw.Draw(img_er)
    d_er.rectangle([(20, 20), (w-20, h-20)], outline=(16, 185, 129), width=2)
    d_er.text((w//2 - 200, 35), "DigiQ Database Entity Relationship (ER) Diagram", fill=(56, 189, 248))
    d_er.text((w//2 - 150, 55), "PostgreSQL 15 • Public & Auth Schemas", fill=(148, 163, 184))

    er_tables = [
        ((50, 100, 360, 280), (30, 41, 59), (51, 65, 85), "auth.users (Supabase Core)", [
            "PK  id             : uuid",
            "    email          : varchar(255)",
            "    encrypted_pw   : varchar(255)",
            "    raw_user_meta  : jsonb",
            "    created_at     : timestamptz"
        ]),
        ((50, 320, 360, 560), (30, 41, 59), (2, 132, 199), "public.profiles", [
            "PK,FK id           : uuid (auth.users)",
            "UQ,NN username     : varchar(20)",
            "      full_name    : text",
            "      avatar_url   : text",
            "CK    role         : user_role",
            "      created_at   : timestamptz",
            "      updated_at   : timestamptz"
        ]),
        ((410, 100, 770, 410), (30, 41, 59), (5, 150, 105), "public.transactions", [
            "PK    id           : uuid",
            "FK    user_id      : uuid (profiles)",
            "NN    total_amount : numeric",
            "      base_amount  : numeric",
            "      unique_code  : integer",
            "CK    status       : status_type",
            "      payment_meth : varchar(50)",
            "      qris_payload : text",
            "      expired_at   : timestamptz"
        ]),
        ((410, 460, 770, 720), (30, 41, 59), (180, 83, 9), "public.payment_mutations", [
            "PK    id           : uuid",
            "NN    bank         : varchar(50)",
            "NN    amount       : numeric",
            "      description  : text",
            "CK    mutation_type: varchar(2) (CR/DB)",
            "FK    transaction_id: uuid (NULLABLE)",
            "      is_matched   : boolean"
        ]),
        ((820, 100, 1150, 340), (30, 41, 59), (4, 120, 87), "public.transaction_items", [
            "PK    id           : uuid",
            "FK    transaction_id: uuid (CASCADE)",
            "FK    product_id   : uuid (RESTRICT)",
            "NN    quantity     : integer",
            "NN    price_at_purch: numeric",
            "NN    subtotal     : numeric"
        ]),
        ((820, 390, 1150, 680), (30, 41, 59), (126, 34, 206), "public.products", [
            "PK    id           : uuid",
            "NN    name         : text",
            "      description  : text",
            "NN    price        : numeric",
            "NN    stock        : integer",
            "      image_url    : text",
            "      category     : text",
            "      is_active    : boolean"
        ])
    ]

    for (x0, y0, x1, y1), fill_c, out_c, header, items in er_tables:
        d_er.rectangle([(x0, y0), (x1, y1)], fill=fill_c, outline=out_c, width=2)
        d_er.rectangle([(x0, y0), (x1, y0 + 30)], fill=out_c)
        d_er.text((x0 + 10, y0 + 8), header, fill=(255, 255, 255))
        y = y0 + 40
        for item in items:
            d_er.text((x0 + 10, y), item, fill=(226, 232, 240))
            y += 22

    img_er.save('audit/er-diagram.png')
    print("Created audit/er-diagram.png")

if __name__ == '__main__':
    create_architecture_svg()
    create_er_diagram_svg()
    render_pngs_using_pil()

