"""Unpack a .NET for Android XABA v2 assembly store.

Usage: python3 extract_assembly_store.py libassemblies.arm64-v8a.blob.so OUT_DIR
"""
import sys, struct, os, lz4.block
src, out = sys.argv[1], sys.argv[2]
d = open(src,'rb').read()
base = d.find(b'XABA')
p = base
magic, ver, ec, iec, isz = struct.unpack_from('<5I', d, p); p += 20
print('version', hex(ver), 'entries', ec)
p += isz
descs = []
for i in range(ec):
    descs.append(struct.unpack_from('<7I', d, p)); p += 28
names = []
for i in range(ec):
    (n,) = struct.unpack_from('<I', d, p); p += 4
    names.append(d[p:p+n].decode()); p += n
os.makedirs(out, exist_ok=True)
for i,(mi, off, size, *_ ) in enumerate(descs):
    blob = d[base+off: base+off+size]
    if blob[:4] == b'XALZ':
        _, usz = struct.unpack_from('<II', blob, 4)
        blob = lz4.block.decompress(blob[12:], uncompressed_size=usz)
    name = names[mi] if mi < len(names) else f'asm{i}'
    if not name.endswith('.dll'): name += '.dll'
    open(os.path.join(out, name),'wb').write(blob)
print('\n'.join(sorted(names)))
