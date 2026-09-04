import re, subprocess, struct, sys
BIN="/home/user/animania_build/Animania"

def sections():
    out=subprocess.run(["readelf","-S","-W",BIN],capture_output=True,text=True).stdout
    secs=[]
    for m in re.finditer(r'\[\s*\d+\]\s+(\S+)\s+\S+\s+([0-9a-f]+)\s+([0-9a-f]+)\s+([0-9a-f]+)',out):
        secs.append((m.group(1), int(m.group(2),16), int(m.group(3),16), int(m.group(4),16)))
    return secs
SECS=sections()
DATA=open(BIN,'rb').read()

def read(addr,n):
    for name,va,off,size in SECS:
        if va and va <= addr < va+size:
            fo = off + (addr-va)
            return DATA[fo:fo+n]
    return b''

def as_double(addr):
    b=read(addr,8)
    if len(b)<8: return None
    try: return struct.unpack("<d",b)[0]
    except Exception: return None

def as_str(addr, maxn=90):
    b=read(addr,maxn)
    if not b: return None
    e=b.find(b'\x00')
    s=b[:e if e>=0 else maxn]
    if len(s)>=3 and all(32<=c<127 for c in s): return s.decode('ascii','replace')
    return None

def dis(start,size):
    return subprocess.run(["objdump","-d","--start-address",hex(start),
        "--stop-address",hex(start+size),"-C",BIN],capture_output=True,text=True).stdout

if __name__=="__main__":
    start=int(sys.argv[1],16); size=int(sys.argv[2],16)
    txt=dis(start,size)
    for line in txt.split('\n'):
        m=re.match(r'\s*([0-9a-f]+):\s+(?:[0-9a-f]{2} )+\s*(\S+)\s+(.*)',line)
        if not m: continue
        addr=int(m.group(1),16); op=m.group(2); rest=m.group(3)
        # Haxe source line markers
        ml=re.match(r'\$0x([0-9a-f]+),0x[0-9a-f]+\(%rsp\)',rest)
        if op=="movl" and ml:
            v=int(ml.group(1),16)
            if 1<v<20000: print("        ---- hx line %d ----"%v); continue
        # rip-relative
        r=re.search(r'0x([0-9a-f]+)\(%rip\)',rest)
        if r:
            tgt=None
            c=re.search(r'#\s*([0-9a-f]+)',line)
            if c: tgt=int(c.group(1),16)
            if tgt:
                s=as_str(tgt); d=as_double(tgt)
                note=[]
                if s: note.append('STR "%s"'%s)
                if d is not None and (abs(d)>1e-9 and abs(d)<1e7): note.append("DBL %g"%d)
                if note: print("  %x  %-8s %-42s | %s"%(addr,op,rest[:42]," ; ".join(note)))
                continue
        if op.startswith("call"):
            cm=re.search(r'<(.+)>',rest)
            if cm: print("  %x  call   %s"%(addr,cm.group(1)[:120]))
