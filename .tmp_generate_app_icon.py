import math
import os
import struct
import zlib


def main() -> None:
    w = 1024
    h = 1024
    buf = bytearray(w * h * 4)

    def clamp(x: float, a: int = 0, b: int = 255) -> int:
        if x < a:
            return a
        if x > b:
            return b
        return int(x)

    def set_px(x: int, y: int, r: int, g: int, b: int, a: int = 255) -> None:
        if x < 0 or x >= w or y < 0 or y >= h:
            return
        i = (y * w + x) * 4
        buf[i] = r
        buf[i + 1] = g
        buf[i + 2] = b
        buf[i + 3] = a

    def blend_px(x: int, y: int, r: int, g: int, b: int, a: int) -> None:
        if x < 0 or x >= w or y < 0 or y >= h:
            return
        i = (y * w + x) * 4
        da = buf[i + 3]
        sa = a
        if sa == 0:
            return
        if da == 0:
            buf[i] = r
            buf[i + 1] = g
            buf[i + 2] = b
            buf[i + 3] = sa
            return

        sr, sg, sb = r, g, b
        dr, dg, db = buf[i], buf[i + 1], buf[i + 2]
        sa_f = sa / 255.0
        da_f = da / 255.0
        out_a = sa_f + da_f * (1.0 - sa_f)
        if out_a <= 1e-6:
            buf[i] = buf[i + 1] = buf[i + 2] = 0
            buf[i + 3] = 0
            return
        out_r = (sr * sa_f + dr * da_f * (1.0 - sa_f)) / out_a
        out_g = (sg * sa_f + dg * da_f * (1.0 - sa_f)) / out_a
        out_b = (sb * sa_f + db * da_f * (1.0 - sa_f)) / out_a
        buf[i] = clamp(round(out_r))
        buf[i + 1] = clamp(round(out_g))
        buf[i + 2] = clamp(round(out_b))
        buf[i + 3] = clamp(round(out_a * 255.0))

    def lerp(a: float, b: float, t: float) -> float:
        return a + (b - a) * t

    def lerp_c(c1: tuple[int, int, int, int], c2: tuple[int, int, int, int], t: float):
        return (
            clamp(round(lerp(c1[0], c2[0], t))),
            clamp(round(lerp(c1[1], c2[1], t))),
            clamp(round(lerp(c1[2], c2[2], t))),
            clamp(round(lerp(c1[3], c2[3], t))),
        )

    bg_top = (20, 40, 34, 255)
    bg_bot = (30, 58, 48, 255)
    for y in range(h):
        t = y / (h - 1)
        r, g, b, a = lerp_c(bg_top, bg_bot, t)
        for x in range(w):
            dx = (x - (w / 2)) / (w / 2)
            dy = (y - (h / 2)) / (h / 2)
            v = math.sqrt(dx * dx + dy * dy)
            dark = clamp(70 * v)
            set_px(x, y, clamp(r - dark), clamp(g - dark), clamp(b - dark), a)

    cx = w // 2
    cy = int(h * 0.30)
    rx = int(w * 0.42)
    ry = int(h * 0.20)
    roof_col = (225, 244, 235, 180)
    for y in range(int(cy - ry * 0.2), int(cy + ry * 0.9)):
        for x in range(int(cx - rx * 1.05), int(cx + rx * 1.05)):
            ex = (x - cx) / rx
            ey = (y - cy) / ry
            d = ex * ex + ey * ey
            if 0.96 <= d <= 1.02 and y < cy + ry * 0.55:
                alpha = int(roof_col[3] * (1.0 - abs(d - 0.99) / 0.03))
                if alpha > 0:
                    blend_px(x, y, roof_col[0], roof_col[1], roof_col[2], alpha)

    bowl_top = int(h * 0.28)
    bowl_bot = int(h * 0.62)
    for y in range(bowl_top, bowl_bot):
        t = (y - bowl_top) / (bowl_bot - bowl_top)
        col = lerp_c((18, 30, 28, 255), (12, 18, 20, 255), t)
        yy = (y - int(h * 0.52)) / int(h * 0.40)
        half = int(w * (0.44 - 0.12 * yy * yy))
        x0 = cx - half
        x1 = cx + half
        for x in range(max(0, x0), min(w, x1)):
            blend_px(x, y, col[0], col[1], col[2], col[3])

    pitch_y = int(h * 0.62)
    pitch_h = int(h * 0.23)
    px0 = int(w * 0.16)
    px1 = int(w * 0.84)
    py0 = pitch_y
    py1 = pitch_y + pitch_h
    for y in range(py0, py1):
        t = (y - py0) / (py1 - py0)
        base = lerp_c((26, 112, 74, 255), (18, 92, 60, 255), t)
        for x in range(px0, px1):
            stripe = ((x - px0) // 60) % 2
            s = 10 if stripe == 0 else -6
            set_px(x, y, clamp(base[0] + s), clamp(base[1] + s), clamp(base[2] + s), 255)

    ccy = int(py0 + pitch_h * 0.55)
    ccr = int(w * 0.12)
    for y in range(ccy - ccr - 2, ccy + ccr + 2):
        for x in range(cx - ccr - 2, cx + ccr + 2):
            dx = x - cx
            dy = y - ccy
            d = math.hypot(dx, dy)
            if abs(d - ccr) < 1.3:
                blend_px(x, y, 210, 240, 228, 140)

    tr_top = int(h * 0.36)
    tr_bot = int(h * 0.64)
    tr_w = int(w * 0.16)

    for rad in range(int(w * 0.22), int(w * 0.10), -1):
        a = int(90 * (rad / (w * 0.22)) ** 2)
        if a <= 0:
            continue
        for y in range(ccy - rad, ccy + rad):
            if y < 0 or y >= h:
                continue
            dy = y - ccy
            span = int(math.sqrt(max(0, rad * rad - dy * dy)))
            x0 = cx - span
            x1 = cx + span
            for x in range(max(0, x0), min(w, x1)):
                blend_px(x, y, 255, 220, 120, a)

    for y in range(tr_top, tr_bot):
        ty = (y - tr_top) / (tr_bot - tr_top)
        waist = int(tr_w * (0.55 + 0.30 * math.sin(ty * math.pi)))
        x0 = cx - waist
        x1 = cx + waist
        for x in range(x0, x1):
            tx = abs((x - cx) / tr_w)
            if tx > 1.0:
                continue
            cut = (ty < 0.25 and tx > 0.78) or (0.25 <= ty < 0.35 and tx > 0.88)
            if cut:
                continue
            shine = math.exp(-((x - cx) / (tr_w * 0.35)) ** 2) * 0.35
            r = clamp(round(lerp(190, 255, 0.55 + 0.25 * shine)))
            g = clamp(round(lerp(120, 210, 0.55 + 0.25 * shine)))
            b = clamp(round(lerp(35, 90, 0.55 + 0.25 * shine)))
            blend_px(x, y, r, g, b, 255)

    base_y = tr_bot + int(h * 0.02)
    base_h = int(h * 0.04)
    base_w = int(w * 0.22)
    for y in range(base_y, base_y + base_h):
        ty = (y - base_y) / base_h
        col = lerp_c((40, 28, 20, 255), (22, 16, 12, 255), ty)
        for x in range(cx - base_w // 2, cx + base_w // 2):
            blend_px(x, y, col[0], col[1], col[2], 255)

    def draw_player(side: int) -> None:
        px = int(cx + side * w * 0.24)
        py = int(h * 0.50)

        hr = int(w * 0.055)
        hx = px - side * int(w * 0.03)
        hy = py - int(h * 0.11)
        for y in range(hy - hr, hy + hr):
            for x in range(hx - hr, hx + hr):
                dx = x - hx
                dy = y - hy
                if dx * dx + dy * dy <= hr * hr:
                    shade = 22 if side == -1 else 18
                    blend_px(x, y, 220 - shade, 235 - shade, 230 - shade, 255)

        tw = int(w * 0.22)
        th = int(h * 0.22)
        top = py - int(th * 0.25)
        for y in range(top, py + th):
            ty = (y - top) / (th + int(th * 0.25))
            ww = int(tw * (0.95 - 0.35 * ty))
            x0 = px - ww // 2
            x1 = px + ww // 2
            for x in range(x0, x1):
                tx = (x - px) / (ww / 2 + 1e-6)
                if abs(tx) > 1.0:
                    continue
                if side == -1 and x > cx - int(w * 0.10) and y < py + int(h * 0.08):
                    continue
                if side == 1 and x < cx + int(w * 0.10) and y < py + int(h * 0.08):
                    continue

                if side == -1:
                    c1 = (32, 140, 220)
                    c2 = (14, 60, 120)
                else:
                    c1 = (245, 80, 80)
                    c2 = (150, 25, 35)

                hh = math.exp(-((tx + 0.2 * side) / 0.6) ** 2) * 0.25
                rr = clamp(round(lerp(c2[0], c1[0], 0.55 + hh)))
                gg = clamp(round(lerp(c2[1], c1[1], 0.55 + hh)))
                bb = clamp(round(lerp(c2[2], c1[2], 0.55 + hh)))
                blend_px(x, y, rr, gg, bb, 255)

        for y in range(hy + hr - 4, hy + hr + 10):
            for x in range(px - int(w * 0.04), px + int(w * 0.04)):
                blend_px(x, y, 0, 0, 0, 40)

    draw_player(-1)
    draw_player(1)

    rim_y = int(h * 0.62)
    rim_h = int(h * 0.06)
    for y in range(rim_y, rim_y + rim_h):
        t = (y - rim_y) / rim_h
        col = lerp_c((230, 245, 238, 130), (0, 0, 0, 0), t)
        for x in range(int(w * 0.08), int(w * 0.92)):
            blend_px(x, y, col[0], col[1], col[2], col[3])

    rad = int(w * 0.22)
    for y in range(h):
        for x in range(w):
            dx = min(x, w - 1 - x)
            dy = min(y, h - 1 - y)
            if dx >= rad or dy >= rad:
                continue
            ccx = rad if x < rad else w - 1 - rad
            ccy2 = rad if y < rad else h - 1 - rad
            ddx = x - ccx
            ddy = y - ccy2
            if ddx * ddx + ddy * ddy > rad * rad:
                i = (y * w + x) * 4
                buf[i + 3] = 0

    def chunk(tag: bytes, data: bytes) -> bytes:
        return (
            struct.pack('>I', len(data))
            + tag
            + data
            + struct.pack('>I', zlib.crc32(tag + data) & 0xFFFFFFFF)
        )

    raw = bytearray()
    for y in range(h):
        raw.append(0)
        raw.extend(buf[y * w * 4 : (y + 1) * w * 4])
    compressed = zlib.compress(bytes(raw), level=9)

    png = bytearray()
    png.extend(b'\\x89PNG\\r\\n\\x1a\\n')
    png.extend(chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 6, 0, 0, 0)))
    png.extend(chunk(b'IDAT', compressed))
    png.extend(chunk(b'IEND', b''))

    out_path = '/Users/raifkeskin/football_tournament/web/icons/app_icon_custom_1024.png'
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    with open(out_path, 'wb') as f:
        f.write(png)
    print('Wrote', out_path)


if __name__ == '__main__':
    main()
