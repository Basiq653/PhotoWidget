#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Генерирует иконку приложения (1024x1024 PNG) без внешних зависимостей.

Запускать только если хочется перерисовать иконку:
    python3 scripts/make_icon.py App/Assets.xcassets/AppIcon.appiconset/icon-1024.png
"""

import struct
import sys
import zlib

SS = 2          # суперсэмплинг
SIZE = 1024


def lerp(a, b, t):
    return a + (b - a) * t


def in_triangle(px, py, a, b, c):
    def sign(p1, p2, p3):
        return (p1[0] - p3[0]) * (p2[1] - p3[1]) - (p2[0] - p3[0]) * (p1[1] - p3[1])

    d1 = sign((px, py), a, b)
    d2 = sign((px, py), b, c)
    d3 = sign((px, py), c, a)
    neg = (d1 < 0) or (d2 < 0) or (d3 < 0)
    pos = (d1 > 0) or (d2 > 0) or (d3 > 0)
    return not (neg and pos)


def render():
    w = h = SIZE
    big = w * SS
    # цвета в 0..255
    c1 = (46, 78, 148)     # синий
    c2 = (118, 62, 168)    # фиолетовый
    white = (255, 255, 255)

    # фигуры в координатах 0..1
    sun = (0.68, 0.30, 0.105)
    tri_a = ((0.10, 0.84), (0.44, 0.34), (0.78, 0.84))
    tri_b = ((0.46, 0.84), (0.70, 0.52), (0.94, 0.84))
    band = (0.10, 0.84, 0.94, 0.90)   # x1,y1,x2,y2

    acc = [[0, 0, 0] for _ in range(w * h)]
    for by in range(big):
        y = by / big
        row = by // SS
        for bx in range(big):
            x = bx / big
            t = (x * 0.35 + y * 0.65)
            r = lerp(c1[0], c2[0], t)
            g = lerp(c1[1], c2[1], t)
            b = lerp(c1[2], c2[2], t)

            # диагональный блик
            shine = max(0.0, 1.0 - abs((x + y) - 0.55) * 2.2) * 26
            r, g, b = r + shine, g + shine, b + shine

            # солнце
            dx, dy = x - sun[0], y - sun[1]
            if dx * dx + dy * dy <= sun[2] * sun[2]:
                r, g, b = white

            # горы
            if in_triangle(x, y, *tri_a) or in_triangle(x, y, *tri_b):
                r, g, b = white

            # нижняя полоса «подложки»
            if band[0] <= x <= band[2] and band[1] <= y <= band[3]:
                r, g, b = white

            a = acc[row * w + bx // SS]
            a[0] += r
            a[1] += g
            a[2] += b

    px = bytearray()
    n = SS * SS
    for row in range(h):
        px.append(0)
        for col in range(w):
            a = acc[row * w + col]
            px += bytes((int(a[0] / n), int(a[1] / n), int(a[2] / n)))
    return bytes(px)


def png(width, height, rgb):
    def chunk(tag, data):
        return (
            struct.pack(">I", len(data))
            + tag
            + data
            + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
        )

    raw = rgb  # каждая строка уже начинается с байта фильтра 0
    header = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", header)
        + chunk(b"IDAT", zlib.compress(raw, 9))
        + chunk(b"IEND", b"")
    )


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "icon-1024.png"
    with open(out, "wb") as fh:
        fh.write(png(SIZE, SIZE, render()))
    print("written:", out)
