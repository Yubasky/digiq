# audit/test_hash_normalization.py
"""
Unit test untuk normalisasi hash index.html.
Menguji 4 skenario ketat:
(a) File tanpa beacon -> hash ternormalisasi SAMA dengan hash mentah.
(b) File dengan beacon Cloudflare -> hash ternormalisasi SAMA dengan file bersih tanpa beacon.
(c) File dengan injeksi script asing (non-Cloudflare) -> MISMATCH (tidak boleh terhapus).
(d) Perubahan 1 karakter pada body file -> MISMATCH (integritas data terjamin).
"""

import hashlib
import re
import sys

def normalize_html(content_bytes: bytes) -> bytes:
    """
    Menghapus TEPAT SATU elemen <script> yang src-nya mengarah ke static.cloudflareinsights.com
    (beserta satu newline trailing jika ada).
    Bila file TIDAK memuat beacon Cloudflare, konten byte dikembalikan 100% utuh tanpa
    mengubah spasi, indentasi, baris kosong, atau line-ending.
    """
    if not content_bytes:
        return b''
    text = content_bytes.decode('utf-8', errors='ignore')
    pattern = r'<script[^>]*static\.cloudflareinsights\.com[^>]*>.*?</script>(?:\r?\n)?'
    normalized_text = re.sub(pattern, '', text, count=1)
    return normalized_text.encode('utf-8')

def sha256(b: bytes) -> str:
    return hashlib.sha256(b).hexdigest()

def main():
    print("=== UNIT TEST: NORMALISASI HASH INDEX.HTML ===")

    # 1. Base clean HTML (tanpa beacon)
    clean_html = b"""<!DOCTYPE html>
<html>
<head>
  <base href="$FLUTTER_BASE_HREF">
  <meta charset="UTF-8">
  <title>DigiQ - Topup & Produk Digital</title>
</head>
<body>
  <script src="flutter_bootstrap.js" async></script>
</body>
</html>
"""

    clean_raw_hash = sha256(clean_html)
    clean_norm_hash = sha256(normalize_html(clean_html))

    # (a) File tanpa beacon -> hash tidak berubah
    test_a_pass = (clean_raw_hash == clean_norm_hash)
    print(f"(a) File tanpa beacon -> hash tidak berubah:")
    print(f"    Raw : {clean_raw_hash}")
    print(f"    Norm: {clean_norm_hash}")
    print(f"    Status: {'PASS' if test_a_pass else 'FAIL'}")
    assert test_a_pass, "Test (a) failed: file without beacon must preserve exact raw hash"

    # (b) File dengan beacon -> normalized hash sama dengan clean_raw_hash
    beacon_tag = b'<script type="module" src="https://static.cloudflareinsights.com/beacon.min.js/vce701823e78c4301a35b7e07294d87301792088814092" integrity="sha512-UKNk8GbxkABxKcXYuLkO16EleLGUkcvJWtpSNmExE0Too3ZaFAxTscNWEc1OdAv5/BikHawapSCaiD2XCmp+Bw==" data-cf-beacon=\'{"version":"2024.11.0","token":"24194e166c284cc59f3e96dc6fbe99b5","r":1,"spa":2}\' crossorigin="anonymous"></script>\n'
    html_with_beacon = clean_html.replace(b'</body>', beacon_tag + b'</body>')

    beacon_raw_hash = sha256(html_with_beacon)
    beacon_norm_hash = sha256(normalize_html(html_with_beacon))

    test_b_pass = (beacon_raw_hash != clean_raw_hash) and (beacon_norm_hash == clean_raw_hash)
    print(f"\n(b) File dengan beacon Cloudflare -> hash ternormalisasi identik dengan file bersih:")
    print(f"    Beacon Raw : {beacon_raw_hash} (berbeda karena ada beacon)")
    print(f"    Beacon Norm: {beacon_norm_hash} (identik dengan clean raw)")
    print(f"    Clean Raw  : {clean_raw_hash}")
    print(f"    Status: {'PASS' if test_b_pass else 'FAIL'}")
    assert test_b_pass, "Test (b) failed: file with beacon must normalize to exact clean raw hash"

    # (c) File dengan script asing lain yang disuntik -> MISMATCH (tidak boleh terhapus)
    foreign_tag = b'<script src="https://malicious-cdn.com/evil.js"></script>\n'
    html_with_foreign = clean_html.replace(b'</body>', foreign_tag + b'</body>')
    foreign_norm_hash = sha256(normalize_html(html_with_foreign))

    test_c_pass = (foreign_norm_hash != clean_raw_hash)
    print(f"\n(c) File dengan script asing (bukan Cloudflare beacon) -> MISMATCH:")
    print(f"    Foreign Norm: {foreign_norm_hash}")
    print(f"    Clean Raw   : {clean_raw_hash}")
    print(f"    Status: {'PASS' if test_c_pass else 'FAIL'}")
    assert test_c_pass, "Test (c) failed: foreign script must NOT be stripped"

    # (d) Perubahan satu karakter di body -> MISMATCH
    html_tampered = clean_html.replace(b'DigiQ', b'DigiX')
    tampered_norm_hash = sha256(normalize_html(html_tampered))

    test_d_pass = (tampered_norm_hash != clean_raw_hash)
    print(f"\n(d) Perubahan 1 karakter di body ('DigiQ' -> 'DigiX') -> MISMATCH:")
    print(f"    Tampered Norm: {tampered_norm_hash}")
    print(f"    Clean Raw    : {clean_raw_hash}")
    print(f"    Status: {'PASS' if test_d_pass else 'FAIL'}")
    assert test_d_pass, "Test (d) failed: 1-char modification must alter hash"

    print("-" * 65)
    print("SEMUA 4 UJI NORMALISASI HASH SUKSES (PASS)!")
    return 0

if __name__ == '__main__':
    sys.exit(main())
