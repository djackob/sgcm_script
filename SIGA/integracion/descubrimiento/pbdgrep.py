"""Extrae cadenas ASCII/UTF-16 de los .pbd de SIGA y busca un patron."""
import re, sys, glob, os

pat = re.compile(sys.argv[1].encode('ascii'), re.I)
paths = sorted(glob.glob(sys.argv[2]))
ctx = int(sys.argv[3]) if len(sys.argv) > 3 else 400

STR = re.compile(rb'[\x20-\x7e\r\n\t]{12,}')

for p in paths:
    data = open(p, 'rb').read()
    # ASCII plano
    blobs = [m.group() for m in STR.finditer(data)]
    # UTF-16LE -> colapsar
    try:
        u = data.decode('utf-16-le', 'ignore').encode('ascii', 'ignore')
        blobs += [m.group() for m in STR.finditer(u)]
    except Exception:
        pass
    hits = [b for b in blobs if pat.search(b)]
    if hits:
        print('#' * 70)
        print('#', os.path.basename(p), len(hits), 'coincidencias')
        print('#' * 70)
        for h in hits[:40]:
            print(h.decode('ascii', 'replace')[:ctx])
            print('-' * 60)
