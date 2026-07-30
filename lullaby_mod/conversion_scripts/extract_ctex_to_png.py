#!/usr/bin/env python3
"""
Script para extraer imágenes PNG de archivos .ctex de Godot 4.
El formato .ctex (Godot Simple Texture 2) contiene la textura comprimida.

Este script intenta extraer datos de textura del formato GST2 de Godot 4.
"""

import struct
import zlib
import os
import sys

def extract_ctex(ctex_path, output_png_path):
    """
    Extrae datos de textura de un archivo .ctex de Godot 4 y los guarda como PNG.
    
    El formato GST2 de Godot 4 es complejo y puede usar diferentes codecs:
    - Raw (sin comprimir)
    - DTX1/DTX5 (compresión de textura)
    - ASTC (compresión de textura móvil)
    - ETC2
    """
    with open(ctex_path, 'rb') as f:
        data = f.read()
    
    # Verificar header GST2
    if data[:4] != b'GST2':
        print(f"Error: No es un archivo GST2 válido: {ctex_path}")
        return False
    
    version = struct.unpack('<I', data[4:8])[0]
    
    # Saltar header principal (8 bytes)
    offset = 8
    
    # En Godot 4, después del header viene:
    # - Flags (4 bytes)
    # - Width (4 bytes)
    # - Height (4 bytes)
    # - Format (4 bytes)
    # - Mipmap count (4 bytes)
    
    if len(data) < offset + 16:
        print(f"Error: Archivo demasiado pequeño: {ctex_path}")
        return False
    
    flags = struct.unpack('<I', data[offset:offset+4])[0]
    width = struct.unpack('<I', data[offset+4:offset+8])[0]
    height = struct.unpack('<I', data[offset+8:offset+12])[0]
    fmt = struct.unpack('<I', data[offset+12:offset+16])[0]
    
    offset += 16
    
    print(f"  Dims: {width}x{height}, Format: {fmt}, Flags: {flags}")
    
    # Los formatos comunes de Godot 4:
    # 0 = FORMAT_L8 (8-bit grayscale)
    # 1 = FORMAT_LA8 (8-bit grayscale + alpha)
    # 2 = FORMAT_R8 (8-bit red)
    # 3 = FORMAT_RG8 (8-bit rg)
    # 4 = FORMAT_RGB8 (24-bit rgb)
    # 5 = FORMAT_RGBA8 (32-bit rgba)
    # 6 = FORMAT_RGBA8 (alias)
    # 7 = FORMAT_RGBA16 (48-bit rgba)
    # 8 = FORMAT_RGBA16F (half float)
    # 9 = FORMAT_RGBA32F (float)
    # 10 = FORMAT_DXT1
    # 11 = FORMAT_DXT3
    # 12 = FORMAT_DXT5
    # 13 = FORMAT_DXT5_RA
    # 14 = FORMAT_ETC
    # 15 = FORMAT_ETC2
    # 16 = FORMAT_ETC2A
    # 17 = FORMAT_ETC2_R11
    # 18 = FORMAT_ETC2_RG11
    # 19 = FORMAT_ETC2_ATCA
    # 20 = FORMAT_ETC2_ATCA1
    # 21 = FORMAT_PVRTC2
    # 22 = FORMAT_PVRTC2A
    # 23 = FORMAT_PVRTC4
    # 24 = FORMAT_PVRTC4A
    # 25 = FORMAT_ASTC4x4
    # 26 = FORMAT_ASTC4x4_HWEBP
    # 27 = FORMAT_ASTC8x8
    # 28 = FORMAT_ASTC8x8_HWEBP
    
    # Intentar extraer como RGBA8 raw si no hay compresión
    if fmt in [5, 6]:
        try:
            # Los datos de textura comienzan después del header de mipmaps
            # Saltar información de mipmaps
            mipmap_count = struct.unpack('<I', data[offset:offset+4])[0] if len(data) > offset else 1
            offset += 4
            
            # Saltar tamaños de mipmaps
            for i in range(mipmap_count):
                if len(data) > offset + 4:
                    mip_size = struct.unpack('<I', data[offset:offset+4])[0]
                    offset += 4 + mip_size
            
            # Ahora debería estar el inicio de los datos de textura
            remaining = len(data) - offset
            expected = width * height * 4
            
            if remaining >= expected:
                # Crear imagen RGBA simple
                create_png(output_png_path, width, height, data[offset:offset+expected])
                return True
        except Exception as e:
            print(f"  Error extrayendo: {e}")
    
    print(f"  Formato no soportado directamente: {fmt}")
    return False

def create_png(output_path, width, height, rgba_data):
    """Crea un archivo PNG simple desde datos RGBA."""
    import struct
    import zlib
    
    def png_chunk(chunk_type, data):
        chunk_len = struct.pack('>I', len(data))
        chunk_crc = struct.pack('>I', zlib.crc32(chunk_type + data) & 0xffffffff)
        return chunk_len + chunk_type + data + chunk_crc
    
    # PNG signature
    signature = b'\x89PNG\r\n\x1a\n'
    
    # IHDR chunk
    ihdr_data = struct.pack('>IIBBBBB', width, height, 8, 6, 0, 0, 0)  # 8-bit RGBA
    ihdr = png_chunk(b'IHDR', ihdr_data)
    
    # IDAT chunk (comprimido)
    raw_data = b''
    for y in range(height):
        raw_data += b'\x00'  # Filter type: None
        row_size = width * 4
        raw_data += rgba_data[y * row_size:(y + 1) * row_size]
    
    compressed = zlib.compress(raw_data, 9)
    idat = png_chunk(b'IDAT', compressed)
    
    # IEND chunk
    iend = png_chunk(b'IEND', b'')
    
    # Guardar PNG
    with open(output_path, 'wb') as f:
        f.write(signature + ihdr + idat + iend)
    
    print(f"  PNG creado: {output_path}")

def process_folder(folder_path, output_folder):
    """Procesa todos los archivos .ctex en una carpeta."""
    os.makedirs(output_folder, exist_ok=True)
    
    count = 0
    for root, dirs, files in os.walk(folder_path):
        for f in files:
            if f.endswith('.ctex'):
                ctex_path = os.path.join(root, f)
                rel_path = os.path.relpath(ctex_path, folder_path)
                output_path = os.path.join(output_folder, rel_path.replace('.ctex', '.png'))
                
                os.makedirs(os.path.dirname(output_path), exist_ok=True)
                
                print(f"Procesando: {rel_path}")
                if extract_ctex(ctex_path, output_path):
                    count += 1
    
    print(f"\n{count} texturas extraídas a {output_folder}")

if __name__ == "__main__":
    if len(sys.argv) > 2:
        input_folder = sys.argv[1]
        output_folder = sys.argv[2]
        process_folder(input_folder, output_folder)
    else:
        print("Uso: python extract_ctex_to_png.py <carpeta_ctex> <carpeta_salida>")
        print("Ejemplo: python extract_ctex_to_png.py ../extracted_sprites ./sprites_png")
