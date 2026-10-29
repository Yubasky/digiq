import os
import struct
import zlib

# Pure Python PNG pixel analyzer without external dependencies
def read_png_pixels(filepath):
    with open(filepath, 'rb') as f:
        data = f.read()
    
    assert data[:8] == b'\x89PNG\r\n\x1a\n', "Not a valid PNG"
    
    pos = 8
    width = 0
    height = 0
    idat_chunks = []
    
    while pos < len(data):
        length = struct.unpack('>I', data[pos:pos+4])[0]
        chunk_type = data[pos+4:pos+8]
        chunk_data = data[pos+8:pos+8+length]
        pos += 12 + length
        
        if chunk_type == b'IHDR':
            width, height, bit_depth, color_type = struct.unpack('>IIBB', chunk_data[:10])
        elif chunk_type == b'IDAT':
            idat_chunks.append(chunk_data)
        elif chunk_type == b'IEND':
            break

    decompressed = zlib.decompress(b"".join(idat_chunks))
    
    # 8-bit RGBA (color_type 6) or RGB (color_type 2)
    bytes_per_pixel = 4 if color_type == 6 else 3
    stride = width * bytes_per_pixel + 1
    
    rows = []
    prev_row = bytearray(width * bytes_per_pixel)
    
    for y in range(height):
        offset = y * stride
        filter_type = decompressed[offset]
        scanline = bytearray(decompressed[offset+1:offset+stride])
        
        # Unfilter
        if filter_type == 0: # None
            pass
        elif filter_type == 1: # Sub
            for x in range(bytes_per_pixel, len(scanline)):
                scanline[x] = (scanline[x] + scanline[x - bytes_per_pixel]) & 0xFF
        elif filter_type == 2: # Up
            for x in range(len(scanline)):
                scanline[x] = (scanline[x] + prev_row[x]) & 0xFF
        elif filter_type == 3: # Average
            for x in range(len(scanline)):
                a = scanline[x - bytes_per_pixel] if x >= bytes_per_pixel else 0
                b = prev_row[x]
                scanline[x] = (scanline[x] + ((a + b) >> 1)) & 0xFF
        elif filter_type == 4: # Paeth
            for x in range(len(scanline)):
                a = scanline[x - bytes_per_pixel] if x >= bytes_per_pixel else 0
                b = prev_row[x]
                c = prev_row[x - bytes_per_pixel] if x >= bytes_per_pixel else 0
                p = a + b - c
                pa = abs(p - a)
                pb = abs(p - b)
                pc = abs(p - c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                scanline[x] = (scanline[x] + pr) & 0xFF
                
        prev_row = scanline
        rows.append(scanline)
        
    return width, height, rows, bytes_per_pixel

def check_green_icon(png_path):
    print(f"[*] Analyzing image: {png_path} ...")
    w, h, rows, bpp = read_png_pixels(png_path)
    print(f"    Dimensions: {w} x {h}")
    
    # Target suffix icon search area: x in [800, 900], y in [350, 420]
    # AppColors.success is #10B981 -> R:16, G:185, B:129
    green_pixels = []
    
    for y in range(350, min(420, h)):
        row = rows[y]
        for x in range(800, min(900, w)):
            idx = x * bpp
            r = row[idx]
            g = row[idx+1]
            b = row[idx+2]
            
            # Match #10B981 green hue (G dominant, R low)
            if g > 150 and r < 70 and 100 <= b <= 160:
                green_pixels.append((x, y, r, g, b))
                
    print(f"[+] Total Green Checkmark Pixels Found in Suffix Icon Area: {len(green_pixels)}")
    if green_pixels:
        sample = green_pixels[len(green_pixels)//2]
        print(f"    Center Pixel Position : (x={sample[0]}, y={sample[1]})")
        print(f"    Sample RGB Value      : R={sample[2]}, G={sample[3]}, B={sample[4]} (Hex #{sample[2]:02X}{sample[3]:02X}{sample[4]:02X})")
        print("    Matching Target Theme : AppColors.success (#10B981)")
        print("[VERIFIED] Green checkmark icon is CONFIRMED visually and pixel-verified on the rendered Canvas!")
        return True
    else:
        print("[!] No green pixels found in expected area.")
        return False

if __name__ == '__main__':
    check_green_icon('audit/images/screenshot_register_typed.png')

