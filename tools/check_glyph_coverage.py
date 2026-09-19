#!/usr/bin/env python3
"""Verifica cobertura de glifos por idioma en las fuentes del proyecto.

Usa fontTools si esta disponible (respeta el glifo 0 / .notdef).
Si no, cae a un parser propio de la tabla cmap.

Uso:
    python3 tools/check_glyph_coverage.py            # pt-BR + muestra hangul
    python3 tools/check_glyph_coverage.py --ko       # hangul completo
"""
import argparse
import glob
import os
import struct
import sys

PT_BR = (
    "AÁÂÃÀBCÇDEÉÊFGHIÍJKLMNOÓÔÕPQRSTUÚVWXYZ"
    "aáâãàbcçdeéêfghiíjklmnoóôõpqrstuúvwxyz"
    "0123456789"
    ".,;:!?()-—'\"·%$#@&*/+=<>[]{}|\\~^`"
)
KO_SAMPLE = "\uac00\uac01\ud55c\uae00"


def coverage_fonttools(path, chars):
    from fontTools.ttLib import TTFont

    font = TTFont(path, fontNumber=0, lazy=True)
    try:
        # getBestCmap respeta el mapeo real a glifos (ignora .notdef)
        cmap = font.getBestCmap()
        return [c for c in chars if ord(c) not in cmap]
    finally:
        font.close()


def read_cmap_manual(path):
    with open(path, "rb") as fh:
        data = fh.read()
    if len(data) < 12:
        raise ValueError("archivo demasiado corto")

    num_tables = struct.unpack(">H", data[4:6])[0]
    cmap_offset = None
    for i in range(num_tables):
        rec = 12 + i * 16
        tag = data[rec:rec + 4]
        off = struct.unpack(">I", data[rec + 8:rec + 12])[0]
        if tag == b"cmap":
            cmap_offset = off
            break
    if cmap_offset is None:
        raise ValueError("sin tabla cmap")

    n_sub = struct.unpack(">H", data[cmap_offset + 2:cmap_offset + 4])[0]
    cps = set()
    for i in range(n_sub):
        rec = cmap_offset + 4 + i * 8
        sub = cmap_offset + struct.unpack(">I", data[rec + 4:rec + 8])[0]
        fmt = struct.unpack(">H", data[sub:sub + 2])[0]
        if fmt == 12:
            n = struct.unpack(">I", data[sub + 12:sub + 16])[0]
            for g in range(n):
                go = sub + 16 + g * 12
                sc, ec, _gi = struct.unpack(">III", data[go:go + 12])
                cps.update(range(sc, ec + 1))
        elif fmt == 4:
            # Formato 4: recorremos el mapeo real a glyph id. Un segmento que abarca
            # un rango amplio puede mapear a .notdef (gid 0) en la mayoria de sus
            # codepoints; sumar el rango entero da falsos positivos.
            seg_x2 = struct.unpack(">H", data[sub + 6:sub + 8])[0]
            seg = seg_x2 // 2
            if seg == 0:
                continue
            ends = struct.unpack(">%dH" % seg, data[sub + 14:sub + 14 + seg_x2])
            base = sub + 14 + seg_x2 + 2
            starts = struct.unpack(">%dH" % seg, data[base:base + seg_x2])
            delta_base = base + seg_x2
            deltas = struct.unpack(">%dh" % seg, data[delta_base:delta_base + seg_x2])
            ro_base = delta_base + seg_x2
            ranges = struct.unpack(">%dH" % seg, data[ro_base:ro_base + seg_x2])
            for i in range(seg):
                s, e = starts[i], ends[i]
                if s > e:
                    continue
                if ranges[i] == 0:
                    d = deltas[i]
                    for c in range(s, e + 1):
                        if c == 0xFFFF:
                            continue
                        if ((c + d) & 0xFFFF) != 0:
                            cps.add(c)
                else:
                    # idRangeOffset apunta dentro de glyphIdArray.
                    for c in range(s, e + 1):
                        if c == 0xFFFF:
                            continue
                        go = ro_base + i * 2 + ranges[i] + (c - s) * 2
                        if go + 2 > len(data):
                            continue
                        gid = struct.unpack(">H", data[go:go + 2])[0]
                        if gid != 0:
                            gid = (gid + deltas[i]) & 0xFFFF
                        if gid != 0:
                            cps.add(c)
    return cps


def coverage_manual(path, chars):
    cps = read_cmap_manual(path)
    return [c for c in chars if ord(c) not in cps]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ko", action="store_true", help="probar Hangul completo")
    args = ap.parse_args()

    try:
        import fontTools  # noqa: F401
        have_ft = True
    except ImportError:
        have_ft = False

    chars = PT_BR
    label = "pt-BR (%d chars)" % len(PT_BR)
    if args.ko:
        chars = "".join(chr(c) for c in range(0xAC00, 0xD7A4))
        label = "Hangul silabario completo (%d chars)" % len(chars)

    print("Backend: %s" % ("fontTools" if have_ft else "parser propio (menos preciso)"))
    print("=== Cobertura %s ===" % label)

    paths = sorted(glob.glob("assets/fonts/*.ttf"))
    if not paths:
        print("No hay fuentes en assets/fonts/*.ttf")
        return 1

    for path in paths:
        name = os.path.basename(path)
        try:
            missing = (coverage_fonttools if have_ft else coverage_manual)(path, chars)
        except Exception as exc:  # noqa: BLE001
            print("ERROR   %-50s %s" % (name, exc))
            continue
        if not missing:
            print("OK      %-50s" % name)
        else:
            sample = " ".join(missing[:60])
            extra = "" if len(missing) <= 60 else " (+%d)" % (len(missing) - 60)
            print("FALTA   %-50s %d: %s%s" % (name, len(missing), sample, extra))
    return 0


if __name__ == "__main__":
    sys.exit(main())
