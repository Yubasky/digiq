# audit/compare_hashes.py
import hashlib
import urllib.request
import os
import re

files = ['index.html', 'main.dart.js', 'flutter_service_worker.js']
local_dir = os.path.join(os.path.dirname(__file__), '..', 'build', 'web')

def normalize_html(content_bytes: bytes) -> bytes:
    """
    Menghapus TEPAT SATU elemen <script> yang src-nya mengarah ke static.cloudflareinsights.com
    (beserta satu newline trailing jika ada).
    Bila file TIDAK memuat beacon Cloudflare, konten byte dikembalikan 100% utuh tanpa
    mengubah spasi, indentasi, baris kosong, atau line-ending, sehingga hash ternormalisasi
    SAMA PERSIS dengan hash mentah.
    """
    if not content_bytes:
        return b''
    text = content_bytes.decode('utf-8', errors='ignore')
    # Regex tepat menangkap tag script beacon Cloudflare dan newline pengikutnya
    pattern = r'<script[^>]*static\.cloudflareinsights\.com[^>]*>.*?</script>(?:\r?\n)?'
    normalized_text = re.sub(pattern, '', text, count=1)
    return normalized_text.encode('utf-8')

def get_local_bytes(filename):
    p = os.path.join(local_dir, filename)
    if not os.path.exists(p):
        return None
    with open(p, 'rb') as f:
        return f.read()

def get_url_bytes(url):
    try:
        req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
        with urllib.request.urlopen(req, timeout=10) as resp:
            return resp.read()
    except Exception as e:
        return e

def main():
    print(f"{'FILE':<26} | {'LOCAL BUILD (SHA256)':<64} | MATCH")
    print("-" * 115)
    for fn in files:
        local_data = get_local_bytes(fn)
        if local_data is None:
            print(f"{fn:<26} | LOCAL FILE NOT FOUND")
            continue

        local_raw_hash = hashlib.sha256(local_data).hexdigest()
        srv_data = get_url_bytes(f'http://127.0.0.1:9000/{fn}')
        prod_data = get_url_bytes(f'https://enikzrad.web.id/{fn}')

        srv_raw_hash = hashlib.sha256(srv_data).hexdigest() if isinstance(srv_data, bytes) else str(srv_data)
        prod_raw_hash = hashlib.sha256(prod_data).hexdigest() if isinstance(prod_data, bytes) else str(prod_data)

        print(f"{fn:<26} | {local_raw_hash}")
        print(f"  -> Local Server (9000)   : {srv_raw_hash} [{'MATCH' if local_raw_hash == srv_raw_hash else 'MISMATCH'}]")
        print(f"  -> Prod Server (Raw Edge): {prod_raw_hash} [{'MATCH' if local_raw_hash == prod_raw_hash else 'MISMATCH (Cloudflare beacon expected on HTML)'}]")

        if fn == 'index.html':
            local_norm_hash = hashlib.sha256(normalize_html(local_data)).hexdigest()
            prod_norm_hash = hashlib.sha256(normalize_html(prod_data)).hexdigest() if isinstance(prod_data, bytes) else 'N/A'
            srv_norm_hash = hashlib.sha256(normalize_html(srv_data)).hexdigest() if isinstance(srv_data, bytes) else 'N/A'
            print(f"  -> Normalized index.html : {local_norm_hash}")
            print(f"     * Local Raw == Local Norm : {'MATCH (Identik)' if local_raw_hash == local_norm_hash else 'MISMATCH'}")
            print(f"     * Local vs 9000 (Norm)    : {'MATCH' if local_norm_hash == srv_norm_hash else 'MISMATCH'}")
            print(f"     * Local vs Edge (Norm)    : {'MATCH' if local_norm_hash == prod_norm_hash else 'MISMATCH'} (only Cloudflare beacon stripped)")
        print()

if __name__ == '__main__':
    main()
