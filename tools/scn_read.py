#!/usr/bin/env python3
"""Minimal reader for Godot 4 binary resources (.scn/.res, "RSRC").

Only what is needed to answer "what did the PC scene actually author on this
sub-resource": the string table, the internal-resource index, and each
internal resource's stored properties. Object references are reported as
references rather than followed.
"""
import struct, sys

class R:
    def __init__(self, b): self.b, self.p = b, 0
    def u32(self):
        v = struct.unpack_from('<I', self.b, self.p)[0]; self.p += 4; return v
    def i32(self):
        v = struct.unpack_from('<i', self.b, self.p)[0]; self.p += 4; return v
    def u64(self):
        v = struct.unpack_from('<Q', self.b, self.p)[0]; self.p += 8; return v
    def f32(self):
        v = struct.unpack_from('<f', self.b, self.p)[0]; self.p += 4; return v
    def f64(self):
        v = struct.unpack_from('<d', self.b, self.p)[0]; self.p += 8; return v
    def s(self):
        n = self.u32()
        v = self.b[self.p:self.p+n].decode('utf-8', 'replace').rstrip('\x00')
        self.p += n
        return v

    def istr(self, strings):
        """_get_string(): indice en la tabla, o string inline si el bit 31
        esta puesto. Tratarlo siempre como indice desincroniza todo."""
        i = self.u32()
        if i & 0x80000000:
            n = i & 0x7FFFFFFF
            v = self.b[self.p:self.p+n].decode('utf-8', 'replace').rstrip('\x00')
            self.p += n
            return v
        return strings[i] if i < len(strings) else f'<idx {i}>' 

# Valores reales del enum VariantBin (core/io/resource_format_binary.cpp).
# NO son los de Variant::Type: aca OBJECT es 24 y ARRAY es 30. Escribirlos de
# memoria fue lo que desincronizo el parser la primera vez.
T = {1:'NIL',2:'BOOL',3:'INT',4:'FLOAT',5:'STRING',10:'VECTOR2',11:'RECT2',
     12:'VECTOR3',13:'PLANE',14:'QUATERNION',15:'AABB',16:'BASIS',
     17:'TRANSFORM3D',18:'TRANSFORM2D',20:'COLOR',21:'IMAGE',22:'NODE_PATH',
     23:'RID',24:'OBJECT',25:'INPUT_EVENT',26:'DICTIONARY',30:'ARRAY',
     31:'PACKED_BYTE_ARRAY',32:'PACKED_INT32_ARRAY',33:'PACKED_FLOAT32_ARRAY',
     34:'PACKED_STRING_ARRAY',35:'PACKED_VECTOR3_ARRAY',36:'PACKED_COLOR_ARRAY',
     37:'PACKED_VECTOR2_ARRAY',40:'INT64',41:'DOUBLE',42:'CALLABLE',43:'SIGNAL',
     44:'STRING_NAME',45:'VECTOR2I',46:'RECT2I',47:'VECTOR3I',
     48:'PACKED_INT64_ARRAY',49:'PACKED_FLOAT64_ARRAY',50:'VECTOR4',51:'VECTOR4I',
     52:'PROJECTION',53:'PACKED_VECTOR4_ARRAY'}

def variant(r, strings, ext, internal):
    t = r.u32()
    n = T.get(t, f'T{t}')
    if n == 'NIL':      return None
    if n == 'BOOL':     return bool(r.u32())
    if n == 'INT':      return r.i32()
    if n == 'INT64':    return r.i64()
    if n == 'FLOAT':    return r.f32()
    if n == 'DOUBLE':   return r.f64()
    if n in ('STRING', 'STRING_NAME'): return r.s()
    if n == 'VECTOR2':  return (r.f32(), r.f32())
    if n == 'VECTOR2I': return (r.i32(), r.i32())
    if n == 'VECTOR3':  return tuple(r.f32() for _ in range(3))
    if n == 'VECTOR3I': return tuple(r.i32() for _ in range(3))
    if n == 'VECTOR4':  return tuple(r.f32() for _ in range(4))
    if n == 'RECT2':    return tuple(r.f32() for _ in range(4))
    if n == 'RECT2I':   return tuple(r.i32() for _ in range(4))
    if n == 'PLANE':    return tuple(r.f32() for _ in range(4))
    if n == 'QUATERNION': return tuple(r.f32() for _ in range(4))
    if n == 'AABB':     return tuple(r.f32() for _ in range(6))
    if n == 'BASIS':    return tuple(r.f32() for _ in range(9))
    if n == 'TRANSFORM3D': return tuple(r.f32() for _ in range(12))
    if n == 'TRANSFORM2D': return tuple(r.f32() for _ in range(6))
    if n == 'PROJECTION':  return tuple(r.f32() for _ in range(16))
    if n == 'COLOR':    return tuple(r.f32() for _ in range(4))
    if n == 'RID':      r.u32(); return '<rid>'
    if n == 'NODE_PATH':
        cnt = r.u32(); sub = r.u32()
        absolute = bool(sub & 0x80000000); sub &= 0x7FFFFFFF
        parts = [r.istr(strings) for _ in range(cnt + sub)]
        return ('/' if absolute else '') + '/'.join(parts)
    if n == 'OBJECT':
        ot = r.u32()
        if ot == 0: return None
        if ot == 1:
            idx = r.u32()
            return f'<interno #{idx}: {internal[idx][0] if idx < len(internal) else "?"}>'
        if ot == 2:
            tn = r.s(); p = r.s(); return f'<externo {tn} {p}>'
        if ot == 3:
            idx = r.u32()
            return f'<externo {ext[idx][1] if idx < len(ext) else idx}>'
        return f'<object {ot}>'
    if n == 'ARRAY':
        cnt = r.u32() & 0x7FFFFFFF
        return [variant(r, strings, ext, internal) for _ in range(cnt)]
    if n == 'DICTIONARY':
        cnt = r.u32() & 0x7FFFFFFF
        return {str(variant(r, strings, ext, internal)): variant(r, strings, ext, internal)
                for _ in range(cnt)}
    if n == 'PACKED_BYTE_ARRAY':
        ln = r.u32(); r.p += ln + ((4 - ln % 4) % 4); return f'<{ln} bytes>'
    if n in ('PACKED_INT32_ARRAY','PACKED_FLOAT32_ARRAY'):
        ln = r.u32(); r.p += ln * 4; return f'<{ln} x 4b>'
    if n in ('PACKED_INT64_ARRAY','PACKED_FLOAT64_ARRAY'):
        ln = r.u32(); r.p += ln * 8; return f'<{ln} x 8b>'
    if n == 'PACKED_STRING_ARRAY':
        ln = r.u32(); return [r.s() for _ in range(ln)]
    if n == 'PACKED_VECTOR2_ARRAY':
        ln = r.u32(); r.p += ln * 8; return f'<{ln} vec2>'
    if n == 'PACKED_VECTOR3_ARRAY':
        ln = r.u32(); r.p += ln * 12; return f'<{ln} vec3>'
    if n == 'PACKED_COLOR_ARRAY':
        ln = r.u32(); r.p += ln * 16; return f'<{ln} colores>'
    if n == 'PACKED_VECTOR4_ARRAY':
        ln = r.u32(); r.p += ln * 16; return f'<{ln} vec4>'
    raise ValueError(f'variante no soportada: {t} ({n}) en offset {r.p}')

def load(path):
    b = open(path, 'rb').read()
    assert b[:4] == b'RSRC', 'no es RSRC (comprimido?)'
    r = R(b); r.p = 4
    big, real64 = r.u32(), r.u32()
    vmaj, vmin, vfmt = r.u32(), r.u32(), r.u32()
    rtype = r.s()
    importmd_ofs = r.u64()
    flags = r.u32()
    uid = r.u64()
    script_class = r.s() if (flags & 8) else ''
    for _ in range(11): r.u32()

    strings = [r.s() for _ in range(r.u32())]
    ext = []
    for _ in range(r.u32()):
        et, ep = r.s(), r.s()
        eu = r.u64() if vfmt >= 3 else 0
        ext.append((et, ep, eu))
    internal = []
    for _ in range(r.u32()):
        ip = r.s(); io = r.u64()
        internal.append((ip, io))

    print(f"tipo={rtype}  formato v{vfmt}  motor {vmaj}.{vmin}  script_class={script_class!r}")
    print(f"strings={len(strings)}  externos={len(ext)}  internos={len(internal)}\n")
    return b, r, strings, ext, internal

def props_at(b, offset, strings, ext, internal):
    r = R(b); r.p = offset
    rtype = r.s()
    pc = r.u32()
    out = []
    for _ in range(pc):
        name = r.istr(strings)
        out.append((name, variant(r, strings, ext, internal)))
    return rtype, out

if __name__ == '__main__':
    path = sys.argv[1]
    want = sys.argv[2] if len(sys.argv) > 2 else None
    b, r, strings, ext, internal = load(path)
    for i, (ip, io) in enumerate(internal):
        try:
            rtype, pr = props_at(b, io, strings, ext, internal)
        except Exception as e:
            print(f"#{i} {ip}  ERROR: {e}"); continue
        names = [n for n, _ in pr]
        if want and want not in names:
            continue
        print(f"#{i} {ip}   tipo={rtype}   {len(pr)} propiedades")
        for n, v in pr:
            print(f"      {n} = {v}")
        print()
