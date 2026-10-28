import os
import qrcode
from PIL import Image
from pyzbar.pyzbar import decode

os.makedirs('audit/images', exist_ok=True)

def crc16_ccitt(data: str) -> str:
    crc = 0xFFFF
    for ch in data:
        crc ^= (ord(ch) << 8)
        for _ in range(8):
            if crc & 0x8000:
                crc = ((crc << 1) ^ 0x1021) & 0xFFFF
            else:
                crc = (crc << 1) & 0xFFFF
    return f"{crc:04X}"

# 1. Static Payload
static_payload = "00020101021126570011ID.DANA.WWW011893600915302435049402090243504940303UMI51440014ID.CO.QRIS.WWW0215ID10265164220800303UMI5204581353033605802ID5908kopi sat6015Kab. Nanggroe A6105245526304F95A"
img_static = qrcode.make(static_payload)
img_static.save("audit/images/qris_static_sample.png")

# 2. Dynamic Payload (Rp 25.123)
dyn_base = static_payload.replace("010211", "010212")
dyn_base = dyn_base[:dyn_base.rfind("6304")]
idx58 = dyn_base.find("5802ID")
amount_str = "25123"
tag54 = f"54{len(amount_str):02d}{amount_str}"
dyn_base = dyn_base[:idx58] + tag54 + dyn_base[idx58:]
dyn_base += "6304"
dyn_crc = crc16_ccitt(dyn_base)
dynamic_payload = dyn_base + dyn_crc

img_dynamic = qrcode.make(dynamic_payload)
img_dynamic.save("audit/images/qris_dynamic_sample.png")

# 3. Decode & Verify
dec_static = decode(Image.open("audit/images/qris_static_sample.png"))[0].data.decode("utf-8")
dec_dynamic = decode(Image.open("audit/images/qris_dynamic_sample.png"))[0].data.decode("utf-8")

assert dec_static == static_payload, "Static QR decode mismatch"
assert dec_dynamic == dynamic_payload, "Dynamic QR decode mismatch"
assert crc16_ccitt(dec_static[:dec_static.rfind("6304")+4]) == dec_static[-4:], "Static CRC invalid"
assert crc16_ccitt(dec_dynamic[:dec_dynamic.rfind("6304")+4]) == dec_dynamic[-4:], "Dynamic CRC invalid"

print("STATIC DECODE VERIFIED: PASS")
print(f"Decoded Static: {dec_static[:30]}... CRC={dec_static[-4:]}")
print("DYNAMIC DECODE VERIFIED: PASS")
print(f"Decoded Dynamic: {dec_dynamic[:30]}... Tag54={tag54} CRC={dec_dynamic[-4:]}")

# 4. Generate Avatar Sample
img_avatar = Image.new("RGB", (256, 256), color=(6, 172, 220))
img_avatar.save("audit/images/avatar_sample.jpg", "JPEG")
print("Avatar sample saved: audit/images/avatar_sample.jpg")

# 5. Generate Malicious Samples for Upload Security Audit
svg_xss = '<svg xmlns="http://www.w3.org/2000/svg"><script>alert("XSS")</script></svg>'
with open("audit/images/malicious_xss.svg", "w", encoding="utf-8") as f:
    f.write(svg_xss)

with open("audit/images/fake_malware.jpg", "wb") as f:
    f.write(b"MZ\x90\x00\x03\x00\x00\x00This is a fake PE binary header")

with open("audit/images/corrupted_image.jpg", "wb") as f:
    f.write(b"\xFF\xD8\xFF\xE0\x00\x10JFIF\x00\x01\x01\x00\x00\x01\x00\x01")

print("Security audit test files generated in audit/images/")

